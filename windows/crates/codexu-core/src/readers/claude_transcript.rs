//! Claude Code transcript reader.
//!
//! Translates the Swift `ClaudeCodeRuntimeProvider` logic to Rust.
//! Reads `~/.claude/projects/**/*.jsonl` on any platform and produces `LocalUsage`.
//!
//! NOTE: This provider is currently **deferred** on Windows because Claude Code
//! does not yet write project transcripts to `%USERPROFILE%\.claude\projects`.
//! The implementation is kept intact for macOS parity and future activation once
//! the data path appears.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use chrono::{DateTime, TimeZone, Utc};
use serde::{Deserialize, Serialize};

use super::common::*;
use crate::models::*;

const CLAUDE_CACHE_VERSION: i32 = 2;

/// On-disk cache for Claude transcript summaries.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClaudeSessionDiskCache {
    pub version: i32,
    pub entries: HashMap<String, ClaudeSessionCacheEntry>,
}

/// A cached summary for a single transcript file.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClaudeSessionCacheEntry {
    pub file_size: i64,
    pub modification_time_ns: Option<i64>,
    pub summary: ClaudeTranscriptSummary,
}

impl ClaudeSessionCacheEntry {
    pub fn matches(&self, fingerprint: &FileFingerprint) -> bool {
        self.file_size == fingerprint.file_size
            && self.modification_time_ns == fingerprint.modification_time_ns
    }
}

/// A single usage delta extracted from a Claude transcript.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClaudeUsageDelta {
    pub message_id: Option<String>,
    #[serde(with = "chrono::serde::ts_milliseconds")]
    pub date: DateTime<Utc>,
    pub tokens: TokenBreakdown,
    pub model: Option<String>,
    pub project_path: String,
    pub session_id: String,
}

/// A skill load event.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClaudeSkillLoad {
    pub name: String,
    pub path: Option<String>,
    #[serde(with = "chrono::serde::ts_milliseconds_option")]
    pub date: Option<DateTime<Utc>>,
}

/// Summary of a single Claude transcript file.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClaudeTranscriptSummary {
    pub file_path: String,
    pub session_id: String,
    pub project_path: String,
    pub model: Option<String>,
    #[serde(with = "chrono::serde::ts_milliseconds_option")]
    pub last_active_at: Option<DateTime<Utc>>,
    pub deltas: Vec<ClaudeUsageDelta>,
    pub tool_calls: HashMap<String, i64>,
    pub skill_loads: Vec<ClaudeSkillLoad>,
}

/// Reads Claude Code transcripts and produces `LocalUsage`.
pub struct ClaudeCodeTranscriptReader {
    cache_dir: PathBuf,
}

impl ClaudeCodeTranscriptReader {
    pub fn new(cache_dir: impl AsRef<Path>) -> Self {
        Self {
            cache_dir: cache_dir.as_ref().to_path_buf(),
        }
    }

    pub async fn load_local_usage(
        &self,
        projects_root: impl AsRef<Path>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<LocalUsage>> {
        let projects_root = projects_root.as_ref();
        if !tokio::fs::try_exists(projects_root).await.unwrap_or(false) {
            return Ok(None);
        }

        let files = enumerate_jsonl_files(projects_root).await?;
        if files.is_empty() {
            return Ok(None);
        }

        let mut cache = self.read_cache().await;
        let live_paths: HashSet<String> = files
            .iter()
            .map(|f| f.to_string_lossy().to_string())
            .collect();
        cache.entries.retain(|k, _| live_paths.contains(k));

        let mut summaries = Vec::new();
        for file in files {
            let fingerprint = fingerprint_for(&file).await;
            let key = file.to_string_lossy().to_string();

            if let Some(entry) = cache.entries.get(&key) {
                if let Some(ref fp) = fingerprint {
                    if entry.matches(fp) {
                        summaries.push(entry.summary.clone());
                        continue;
                    }
                }
            }

            let summary = parse_transcript(&file, fingerprint.as_ref()).await;
            if let Some(fp) = fingerprint {
                cache.entries.insert(
                    key,
                    ClaudeSessionCacheEntry {
                        file_size: fp.file_size,
                        modification_time_ns: fp.modification_time_ns,
                        summary: summary.clone(),
                    },
                );
            }
            summaries.push(summary);
        }

        self.write_cache(&cache).await;
        Ok(make_local_usage_from_claude(summaries, now))
    }

    async fn read_cache(&self) -> ClaudeSessionDiskCache {
        let path = self
            .cache_dir
            .join("claude-code")
            .join("session-usage-v1.json");
        match tokio::fs::metadata(&path).await {
            Ok(meta) if meta.len() <= MAX_CACHE_BYTES => {}
            _ => {
                return ClaudeSessionDiskCache {
                    version: CLAUDE_CACHE_VERSION,
                    entries: HashMap::new(),
                }
            }
        }
        match tokio::fs::read(&path).await {
            Ok(data) => match serde_json::from_slice::<ClaudeSessionDiskCache>(&data) {
                Ok(cache) if cache.version == CLAUDE_CACHE_VERSION => cache,
                _ => ClaudeSessionDiskCache {
                    version: CLAUDE_CACHE_VERSION,
                    entries: HashMap::new(),
                },
            },
            _ => ClaudeSessionDiskCache {
                version: CLAUDE_CACHE_VERSION,
                entries: HashMap::new(),
            },
        }
    }

    async fn write_cache(&self, cache: &ClaudeSessionDiskCache) {
        let path = self
            .cache_dir
            .join("claude-code")
            .join("session-usage-v1.json");
        if let Ok(data) = serde_json::to_vec(cache) {
            if data.len() as u64 <= MAX_CACHE_BYTES {
                let _ = tokio::fs::create_dir_all(path.parent().unwrap()).await;
                let _ = tokio::fs::write(&path, data).await;
            }
        }
    }
}

async fn parse_transcript(
    file: &Path,
    fingerprint: Option<&FileFingerprint>,
) -> ClaudeTranscriptSummary {
    let session_id = file
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let modification_date =
        fingerprint.and_then(|fp| fp.modification_time_ns.map(|ns| Utc.timestamp_nanos(ns)));

    let mut summary = ClaudeTranscriptSummary {
        file_path: file.to_string_lossy().to_string(),
        session_id,
        project_path: infer_claude_project_path(file),
        model: None,
        last_active_at: modification_date,
        deltas: Vec::new(),
        tool_calls: HashMap::new(),
        skill_loads: Vec::new(),
    };

    let data = match tokio::fs::read(file).await {
        Ok(data) => data,
        Err(_) => return summary,
    };

    let mut seen_message_ids = HashSet::new();

    for line in data.split(|b| *b == b'\n') {
        if line.is_empty() || line.len() > MAX_LINE_BYTES {
            continue;
        }
        let text = match std::str::from_utf8(line) {
            Ok(text) => text,
            Err(_) => continue,
        };
        if !text.contains("\"usage\"")
            && !text.contains("\"tool_use\"")
            && !text.contains("attribution")
        {
            continue;
        }
        let object: serde_json::Value = match serde_json::from_str(text) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let message = object.get("message");
        let timestamp = claude_date_value(object.get("timestamp"))
            .or(modification_date)
            .unwrap_or_else(Utc::now);
        let project_path = claude_string_value(object.get("cwd"))
            .or_else(|| claude_string_value(object.get("projectPath")))
            .unwrap_or_else(|| summary.project_path.clone());
        let model = claude_string_value(message.and_then(|m| m.get("model")))
            .or_else(|| claude_string_value(object.get("model")))
            .or_else(|| summary.model.clone());

        summary.project_path = project_path.clone();
        summary.model = model.clone();
        summary.last_active_at = summary
            .last_active_at
            .map(|d| d.max(timestamp))
            .or(Some(timestamp));

        if let Some(skill_name) = claude_string_value(object.get("attributionSkill"))
            .or_else(|| claude_string_value(object.get("attribution_skill")))
            .or_else(|| claude_string_value(message.and_then(|m| m.get("attributionSkill"))))
            .or_else(|| claude_string_value(message.and_then(|m| m.get("attribution_skill"))))
        {
            summary.skill_loads.push(ClaudeSkillLoad {
                name: skill_name,
                path: None,
                date: Some(timestamp),
            });
        }

        parse_tool_calls(
            message.and_then(|m| m.get("content")),
            timestamp,
            &mut summary,
        );

        let usage = match message.and_then(|m| m.get("usage")) {
            Some(u) => u,
            None => continue,
        };
        let tokens = match parse_usage(usage) {
            Some(t) if !t.is_zero() => t,
            _ => continue,
        };

        let message_id = claude_string_value(message.and_then(|m| m.get("id")))
            .or_else(|| claude_string_value(object.get("uuid")))
            .or_else(|| claude_string_value(object.get("id")));
        if let Some(ref id) = message_id {
            if seen_message_ids.contains(id) {
                continue;
            }
            seen_message_ids.insert(id.clone());
        }

        summary.deltas.push(ClaudeUsageDelta {
            message_id,
            date: timestamp,
            tokens,
            model,
            project_path,
            session_id: summary.session_id.clone(),
        });
    }

    summary
}

fn parse_tool_calls(
    content: Option<&serde_json::Value>,
    date: DateTime<Utc>,
    summary: &mut ClaudeTranscriptSummary,
) {
    let items = match content.and_then(|c| c.as_array()) {
        Some(items) => items,
        None => return,
    };
    for item in items {
        let item_object = match item.as_object() {
            Some(o) => o,
            None => continue,
        };
        if claude_string_value(item_object.get("type")).as_deref() != Some("tool_use") {
            continue;
        }
        let name = match claude_string_value(item_object.get("name")) {
            Some(n) if !n.is_empty() => n,
            _ => continue,
        };
        *summary.tool_calls.entry(name.clone()).or_insert(0) += 1;
        if name.to_lowercase().contains("skill") {
            summary.skill_loads.push(ClaudeSkillLoad {
                name,
                path: None,
                date: Some(date),
            });
        }
    }
}

fn parse_usage(usage: &serde_json::Value) -> Option<TokenBreakdown> {
    let input = claude_i64_value(usage.get("input_tokens")).unwrap_or(0);
    let cache_creation = claude_i64_value(usage.get("cache_creation_input_tokens")).unwrap_or(0);
    let cache_read = claude_i64_value(usage.get("cache_read_input_tokens")).unwrap_or(0);
    let output = claude_i64_value(usage.get("output_tokens")).unwrap_or(0);
    let reasoning = claude_i64_value(usage.get("reasoning_output_tokens")).unwrap_or(0);
    let total = claude_i64_value(usage.get("total_tokens"))
        .unwrap_or(input + cache_creation + cache_read + output + reasoning);

    Some(TokenBreakdown {
        input_tokens: input + cache_creation + cache_read,
        cached_input_tokens: cache_creation + cache_read,
        output_tokens: output,
        reasoning_output_tokens: reasoning,
        total_tokens: total,
    })
}

fn infer_claude_project_path(file: &Path) -> String {
    let encoded = file
        .parent()
        .and_then(|p| p.file_name())
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    if encoded.starts_with('-') {
        encoded.replacen('-', "/", 1)
    } else {
        encoded
    }
}

fn claude_string_value(value: Option<&serde_json::Value>) -> Option<String> {
    value.and_then(|v| {
        if let Some(s) = v.as_str() {
            if !s.is_empty() {
                Some(s.to_string())
            } else {
                None
            }
        } else {
            v.as_number().map(|n| n.to_string())
        }
    })
}

fn claude_i64_value(value: Option<&serde_json::Value>) -> Option<i64> {
    value.and_then(|v| {
        if let Some(n) = v.as_i64() {
            Some(n)
        } else if let Some(s) = v.as_str() {
            s.parse().ok()
        } else {
            None
        }
    })
}

fn claude_date_value(value: Option<&serde_json::Value>) -> Option<DateTime<Utc>> {
    value.and_then(|v| {
        if let Some(n) = v.as_f64() {
            let seconds = if n > 10_000_000_000.0 { n / 1000.0 } else { n };
            Some(DateTime::from_timestamp(seconds as i64, 0).unwrap_or_else(Utc::now))
        } else if let Some(s) = v.as_str() {
            s.parse::<DateTime<Utc>>().ok()
        } else {
            None
        }
    })
}

fn make_local_usage_from_claude(
    summaries: Vec<ClaudeTranscriptSummary>,
    now: DateTime<Utc>,
) -> Option<LocalUsage> {
    let common_summaries: Vec<SessionSummary> = summaries
        .into_iter()
        .map(|s| SessionSummary {
            file_path: s.file_path,
            session_id: s.session_id,
            project_path: s.project_path,
            model: s.model,
            last_active_at: s.last_active_at,
            deltas: s
                .deltas
                .into_iter()
                .map(|d| UsageDelta {
                    message_id: d.message_id,
                    date: d.date,
                    tokens: d.tokens,
                    model: d.model,
                    project_path: d.project_path,
                    session_id: d.session_id,
                })
                .collect(),
            tool_calls: s.tool_calls,
            title: None,
            archived: false,
            thread_source: None,
            parent_thread_id: None,
            created_at: None,
            task_intervals: Vec::new(),
            git_branch: None,
            git_origin_url: None,
        })
        .collect();
    make_local_usage(common_summaries, now)
}
