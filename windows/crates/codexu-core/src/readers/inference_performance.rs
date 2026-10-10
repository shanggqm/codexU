use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, BufReader};

use super::common::{
    index_codex_rollout_files, CodexRolloutIndexEntry, FileFingerprint, MAX_LINE_BYTES,
    READ_CHUNK_BYTES,
};
use super::history_integrity::{
    ensure_history_unchanged, write_cache_atomically, HistoryReadError,
};
use crate::models::{
    InferencePerformanceArchive, InferencePerformanceBuilder, InferencePerformanceHistory,
    InferencePerformanceSample, TokenBreakdown, INFERENCE_MINIMUM_CALL_DURATION_SECONDS,
};
use crate::StatisticsTimeZone;

const INFERENCE_CACHE_VERSION: i32 = 2;
const INFERENCE_PARSER_VERSION: i32 = 3;
const MAXIMUM_ARCHIVE_BYTES: u64 = 32 * 1024 * 1024;
const MAXIMUM_SAMPLE_COUNT: usize = 50_000;

const MODEL_OUTPUT_PAYLOAD_TYPES: &[&str] = &[
    "reasoning",
    "agent_reasoning",
    "agent_message",
    "function_call",
    "custom_tool_call",
    "tool_search_call",
    "web_search_call",
];

const INPUT_BOUNDARY_PAYLOAD_TYPES: &[&str] = &[
    "function_call_output",
    "custom_tool_call_output",
    "tool_search_output",
    "mcp_tool_call_end",
    "web_search_end",
    "patch_apply_end",
    "image_generation_end",
];

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
struct DiskEnvelope {
    version: i32,
    archive: InferencePerformanceArchive,
    entries: HashMap<String, InferenceFileCacheEntry>,
}

impl DiskEnvelope {
    fn empty(now: DateTime<Utc>) -> Self {
        Self {
            version: INFERENCE_CACHE_VERSION,
            archive: InferencePerformanceArchive::new(now),
            entries: HashMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
struct InferenceFileCacheEntry {
    file_size: i64,
    modification_time_ns: Option<i64>,
    parser_version: i32,
    parsed: ParsedInferenceFile,
}

impl InferenceFileCacheEntry {
    fn matches(&self, fingerprint: &FileFingerprint) -> bool {
        self.file_size == fingerprint.file_size
            && self.modification_time_ns == fingerprint.modification_time_ns
            && self.parser_version == INFERENCE_PARSER_VERSION
    }
}

pub struct InferencePerformanceReader {
    cache_dir: PathBuf,
    statistics_time_zone: StatisticsTimeZone,
}

impl InferencePerformanceReader {
    pub fn new(cache_dir: impl AsRef<Path>) -> Self {
        Self {
            cache_dir: cache_dir.as_ref().to_path_buf(),
            statistics_time_zone: StatisticsTimeZone::Local,
        }
    }

    pub fn new_with_timezone(
        cache_dir: impl AsRef<Path>,
        statistics_time_zone: StatisticsTimeZone,
    ) -> Self {
        Self {
            cache_dir: cache_dir.as_ref().to_path_buf(),
            statistics_time_zone,
        }
    }

    pub async fn load(
        &self,
        codex_root: impl AsRef<Path>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<InferencePerformanceHistory>> {
        let index = index_codex_rollout_files(codex_root.as_ref()).await?;
        self.load_from_index(&index, now).await
    }

    pub(crate) async fn load_from_index(
        &self,
        index: &[CodexRolloutIndexEntry],
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<InferencePerformanceHistory>> {
        let retention_start = self.statistics_time_zone.days_before_start(now, 27);
        let mut cache = self.load_cache(now).await;

        let live_paths: HashSet<String> = index
            .iter()
            .map(|entry| source_identifier(&entry.path))
            .collect();
        cache.entries.retain(|path, _| live_paths.contains(path));

        let mut samples_by_source_id: HashMap<String, Vec<InferencePerformanceSample>> =
            HashMap::new();
        for indexed in index {
            let file = &indexed.path;
            let key = source_identifier(file);
            let cached = indexed.fingerprint.as_ref().and_then(|fingerprint| {
                cache
                    .entries
                    .get(&key)
                    .filter(|entry| entry.matches(fingerprint))
                    .map(|entry| entry.parsed.clone())
            });
            let parsed = if let Some(parsed) = cached {
                parsed
            } else {
                let parsed = parse_inference_samples(file).await?;
                if let Some(fingerprint) = indexed.fingerprint {
                    cache.entries.insert(
                        key,
                        InferenceFileCacheEntry {
                            file_size: fingerprint.file_size,
                            modification_time_ns: fingerprint.modification_time_ns,
                            parser_version: INFERENCE_PARSER_VERSION,
                            parsed: parsed.clone(),
                        },
                    );
                }
                parsed
            };
            samples_by_source_id
                .entry(parsed.source_id.unwrap_or_else(|| source_identifier(file)))
                .or_default()
                .extend(parsed.samples);
        }
        ensure_history_unchanged(index).await?;
        for (source_id, samples) in samples_by_source_id {
            cache
                .archive
                .replace_samples(source_id, samples, retention_start);
        }
        cache.archive.compact(retention_start, MAXIMUM_SAMPLE_COUNT);
        let _ = self.save_cache(&cache).await;

        Ok(InferencePerformanceBuilder::make_history(
            &cache.archive.samples(),
            cache.archive.recording_started_at,
            now,
            self.statistics_time_zone,
        ))
    }

    async fn load_cache(&self, now: DateTime<Utc>) -> DiskEnvelope {
        let path = self.archive_path();
        match tokio::fs::metadata(&path).await {
            Ok(meta) if meta.len() <= MAXIMUM_ARCHIVE_BYTES => {}
            _ => return DiskEnvelope::empty(now),
        }
        match tokio::fs::read(&path).await {
            Ok(data) => match serde_json::from_slice::<DiskEnvelope>(&data) {
                Ok(envelope) if envelope.version == INFERENCE_CACHE_VERSION => envelope,
                _ => DiskEnvelope::empty(now),
            },
            _ => DiskEnvelope::empty(now),
        }
    }

    async fn save_cache(&self, envelope: &DiskEnvelope) -> bool {
        let path = self.archive_path();
        let Ok(data) = serde_json::to_vec(&envelope) else {
            return false;
        };
        if data.len() as u64 > MAXIMUM_ARCHIVE_BYTES {
            return false;
        }
        write_cache_atomically(&path, &data).await.is_ok()
    }

    fn archive_path(&self) -> PathBuf {
        self.cache_dir
            .join("codex")
            .join("inference-performance-v1.json")
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
struct ParsedInferenceFile {
    source_id: Option<String>,
    samples: Vec<InferencePerformanceSample>,
}

async fn parse_inference_samples(path: &Path) -> Result<ParsedInferenceFile, HistoryReadError> {
    let mut parsed = ParsedInferenceFile::default();
    let file = tokio::fs::File::open(path)
        .await
        .map_err(|_| HistoryReadError::Unavailable)?;

    let mut tracker = InferenceCallTracker::default();
    let mut seen_sample_ids = HashSet::new();
    let mut reader = BufReader::with_capacity(READ_CHUNK_BYTES, file);
    let mut line = Vec::with_capacity(READ_CHUNK_BYTES);
    let mut oversized = false;

    loop {
        let buffer = reader
            .fill_buf()
            .await
            .map_err(|_| HistoryReadError::Unavailable)?;
        if buffer.is_empty() {
            break;
        }

        let newline = buffer.iter().position(|byte| *byte == b'\n');
        let consumed = newline.map(|index| index + 1).unwrap_or(buffer.len());
        let content_len = newline.unwrap_or(buffer.len());

        if !oversized {
            if line.len().saturating_add(content_len) > MAX_LINE_BYTES {
                line.clear();
                oversized = true;
            } else {
                line.extend_from_slice(&buffer[..content_len]);
            }
        }
        reader.consume(consumed);

        if newline.is_some() {
            if !oversized {
                apply_inference_line(&line, &mut parsed, &mut tracker, &mut seen_sample_ids);
            }
            line.clear();
            oversized = false;
        }
    }

    if !oversized {
        apply_inference_line(&line, &mut parsed, &mut tracker, &mut seen_sample_ids);
    }

    Ok(parsed)
}

fn apply_inference_line(
    line: &[u8],
    parsed: &mut ParsedInferenceFile,
    tracker: &mut InferenceCallTracker,
    seen_sample_ids: &mut HashSet<String>,
) {
    if line.is_empty() {
        return;
    }
    let Ok(text) = std::str::from_utf8(line) else {
        return;
    };
    let Ok(object) = serde_json::from_str::<serde_json::Value>(text) else {
        return;
    };
    let Some(payload) = object.get("payload") else {
        return;
    };
    if payload.is_null() {
        return;
    }

    let object_type = object.get("type").and_then(|value| value.as_str());
    if object_type == Some("session_meta") {
        if parsed.source_id.is_none() {
            parsed.source_id = string_value(payload.get("id"))
                .and_then(|id| normalize(Some(id)))
                .map(|id| format!("session-{id}"));
        }
        return;
    }

    let payload_type = string_value(payload.get("type"));
    let payload_type = payload_type.as_deref();
    let is_turn_context = object_type == Some("turn_context");
    let is_model_output = payload_type
        .map(|value| MODEL_OUTPUT_PAYLOAD_TYPES.contains(&value))
        .unwrap_or(false)
        || string_value(payload.get("role")).as_deref() == Some("assistant");
    let is_input_boundary = payload_type
        .map(|value| INPUT_BOUNDARY_PAYLOAD_TYPES.contains(&value))
        .unwrap_or(false);
    let is_token_count = payload_type == Some("token_count");

    if !is_turn_context && !is_model_output && !is_input_boundary && !is_token_count {
        return;
    }

    let Some(timestamp) = date_value(object.get("timestamp")) else {
        tracker.discard_active_call();
        return;
    };

    if is_turn_context {
        tracker.apply_turn_context(
            string_value(payload.get("model")),
            string_value(payload.get("effort")),
            timestamp,
        );
        return;
    }

    if is_model_output {
        tracker.observe_model_output();
    }

    if is_input_boundary {
        tracker.apply_input_boundary(timestamp);
        return;
    }

    if !is_token_count {
        return;
    }

    let turn_id = string_value(payload.get("turn_id"));
    let sample_id = token_event_sample_id(turn_id.as_deref(), timestamp);

    let info = payload.get("info");
    let cumulative_usage = info
        .and_then(|info| info.get("total_token_usage"))
        .and_then(parse_usage);
    let last_usage = info
        .and_then(|info| info.get("last_token_usage"))
        .and_then(parse_usage);

    if cumulative_usage.is_none() && last_usage.is_none() {
        return;
    }

    if let Some(sample) = tracker.consume_token_event(timestamp, sample_id, last_usage.as_ref()) {
        if seen_sample_ids.insert(sample.sample_id.clone()) {
            parsed.samples.push(sample);
        }
    }
}

#[derive(Debug, Default)]
struct InferenceCallTracker {
    active_model: Option<String>,
    active_effort: Option<String>,
    call_started_at: Option<DateTime<Utc>>,
    observed_model_output: bool,
}

impl InferenceCallTracker {
    fn discard_active_call(&mut self) {
        *self = Self::default();
    }

    fn apply_turn_context(
        &mut self,
        model: Option<String>,
        effort: Option<String>,
        at: DateTime<Utc>,
    ) {
        self.active_model = normalize(model);
        self.active_effort = normalize(effort).map(|effort| effort.to_lowercase());
        self.call_started_at = Some(at);
        self.observed_model_output = false;
    }

    fn apply_input_boundary(&mut self, at: DateTime<Utc>) {
        if self
            .call_started_at
            .map(|started| at > started)
            .unwrap_or(true)
        {
            self.call_started_at = Some(at);
        }
        self.observed_model_output = false;
    }

    fn observe_model_output(&mut self) {
        self.observed_model_output = true;
    }

    fn consume_token_event(
        &mut self,
        completed_at: DateTime<Utc>,
        sample_id: String,
        last_usage: Option<&TokenBreakdown>,
    ) -> Option<InferencePerformanceSample> {
        let result = self.consume_token_event_inner(completed_at, sample_id, last_usage);
        self.call_started_at = Some(completed_at);
        self.observed_model_output = false;
        result
    }

    fn consume_token_event_inner(
        &self,
        completed_at: DateTime<Utc>,
        sample_id: String,
        last_usage: Option<&TokenBreakdown>,
    ) -> Option<InferencePerformanceSample> {
        let last_usage = last_usage?;
        let model = self.active_model.as_ref()?;
        let effort = self.active_effort.as_ref()?;
        let started_at = self.call_started_at?;
        let duration_seconds = completed_at
            .signed_duration_since(started_at)
            .num_milliseconds() as f64
            / 1000.0;
        if !self.observed_model_output
            || duration_seconds < INFERENCE_MINIMUM_CALL_DURATION_SECONDS
            || last_usage.output_tokens <= 0
            || last_usage.input_tokens < 0
            || last_usage.cached_input_tokens < 0
            || last_usage.output_tokens < 0
            || last_usage.reasoning_output_tokens < 0
            || last_usage.total_tokens < 0
        {
            return None;
        }

        Some(InferencePerformanceSample {
            sample_id,
            completed_at,
            duration_seconds,
            output_tokens: last_usage.output_tokens,
            reasoning_output_tokens: last_usage
                .reasoning_output_tokens
                .clamp(0, last_usage.output_tokens),
            model: model.clone(),
            effort: effort.clone(),
        })
    }
}

fn normalize(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn parse_usage(value: &serde_json::Value) -> Option<TokenBreakdown> {
    Some(TokenBreakdown {
        input_tokens: i64_value(value.get("input_tokens"))?,
        cached_input_tokens: i64_value(value.get("cached_input_tokens")).unwrap_or(0),
        output_tokens: i64_value(value.get("output_tokens"))?,
        reasoning_output_tokens: i64_value(value.get("reasoning_output_tokens")).unwrap_or(0),
        total_tokens: i64_value(value.get("total_tokens")).unwrap_or(0),
    })
}

fn string_value(value: Option<&serde_json::Value>) -> Option<String> {
    match value {
        Some(serde_json::Value::String(value)) => Some(value.clone()),
        _ => None,
    }
}

fn i64_value(value: Option<&serde_json::Value>) -> Option<i64> {
    match value {
        Some(serde_json::Value::Number(number)) => number.as_i64(),
        _ => None,
    }
}

fn date_value(value: Option<&serde_json::Value>) -> Option<DateTime<Utc>> {
    let value = string_value(value)?;
    DateTime::parse_from_rfc3339(&value)
        .ok()
        .map(|date| date.with_timezone(&Utc))
}

fn source_identifier(path: &Path) -> String {
    let mut hash: u64 = 14_695_981_039_346_656_037;
    for byte in path.to_string_lossy().as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(1_099_511_628_211);
    }
    format!("rollout-{hash:x}")
}

fn token_event_sample_id(turn_id: Option<&str>, timestamp: DateTime<Utc>) -> String {
    let event_time = timestamp.timestamp_millis();
    match turn_id.and_then(|value| normalize(Some(value.to_string()))) {
        Some(turn_id) => format!("{turn_id}:{event_time}"),
        None => format!("token-count:{event_time}"),
    }
}
