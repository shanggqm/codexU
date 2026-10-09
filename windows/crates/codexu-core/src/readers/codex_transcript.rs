//! Codex transcript reader.
//!
//! Reads Codex archived session JSONL files and produces `LocalUsage`.
//!
//! Codex JSONL format (Windows, 2026-07) has only three top-level fields:
//! `timestamp`, `type`, `payload`. All event-specific data lives inside
//! `payload`, so this reader maps the macOS-expected fields from the payload
//! object rather than the top-level line.
//!
//! Usage events appear as:
//! ```json
//! {
//!   "timestamp": "2026-03-26T12:53:47.164Z",
//!   "type": "event_msg",
//!   "payload": {
//!     "type": "token_count",
//!     "info": {
//!       "total_token_usage": {
//!         "input_tokens": 16545,
//!         "cached_input_tokens": 9728,
//!         "output_tokens": 710,
//!         "reasoning_output_tokens": 368,
//!         "total_tokens": 17255
//!       }
//!     }
//!   }
//! }
//! ```

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::codex_state::CodexThreadMetadata;
use super::common::*;
use super::history_integrity::ensure_history_unchanged;
use crate::models::*;
use crate::StatisticsTimeZone;

/// Summary of a single Codex transcript file.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CodexTranscriptSummary {
    pub file_path: String,
    pub session_id: String,
    pub project_path: String,
    pub model: Option<String>,
    #[serde(with = "chrono::serde::ts_milliseconds_option")]
    pub last_active_at: Option<DateTime<Utc>>,
    pub deltas: Vec<CodexUsageDelta>,
    pub tool_calls: HashMap<String, i64>,
    /// Safe summaries of `SKILL.md` references observed in local tool calls.
    /// The original path and tool argument are discarded during parsing.
    #[serde(default)]
    pub skill_loads: Vec<CodexSkillLoad>,
    #[serde(default)]
    pub task_intervals: Vec<CodexTaskInterval>,
}

/// A privacy-preserving local skill-read observation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CodexSkillLoad {
    pub name: String,
    pub source_label: String,
    #[serde(with = "chrono::serde::ts_milliseconds_option")]
    pub observed_at: Option<DateTime<Utc>>,
}

/// A single usage delta extracted from a Codex transcript.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CodexUsageDelta {
    pub turn_id: Option<String>,
    #[serde(with = "chrono::serde::ts_milliseconds")]
    pub date: DateTime<Utc>,
    pub tokens: TokenBreakdown,
    pub model: Option<String>,
    pub project_path: String,
    pub session_id: String,
}

/// Reads Codex transcripts and produces `LocalUsage`.
pub struct CodexTranscriptReader {
    cache_dir: PathBuf,
    statistics_time_zone: StatisticsTimeZone,
    integrity_scan: bool,
}

impl CodexTranscriptReader {
    pub fn new(cache_dir: impl AsRef<Path>) -> Self {
        Self::new_with_timezone(cache_dir, StatisticsTimeZone::Local)
    }

    pub fn new_with_timezone(
        cache_dir: impl AsRef<Path>,
        statistics_time_zone: StatisticsTimeZone,
    ) -> Self {
        Self {
            cache_dir: cache_dir.as_ref().to_path_buf(),
            statistics_time_zone,
            integrity_scan: false,
        }
    }

    /// Explicit full-source verification detects arbitrary interior rewrites,
    /// including edits outside the bounded append-validation blocks.
    pub fn with_integrity_scan(mut self) -> Self {
        self.integrity_scan = true;
        self
    }

    /// Loads parsed transcript summaries without resolving them into `LocalUsage`.
    pub async fn load_local_summaries(
        &self,
        data_root: impl AsRef<Path>,
    ) -> anyhow::Result<Option<Vec<CodexTranscriptSummary>>> {
        self.load_local_summaries_internal(data_root).await
    }

    /// Loads parsed session summaries including optional thread metadata.
    pub async fn load_local_session_summaries(
        &self,
        data_root: impl AsRef<Path>,
        metadata: HashMap<String, CodexThreadMetadata>,
    ) -> anyhow::Result<Option<Vec<SessionSummary>>> {
        let root = data_root.as_ref();
        let index = index_codex_rollout_files(root).await?;
        let summaries = self
            .load_local_summaries_from_index(root, &index, &metadata, Utc::now())
            .await?;
        Ok(summaries.map(|summaries| combine_session_metadata(summaries, metadata)))
    }

    pub async fn load_local_usage(
        &self,
        data_root: impl AsRef<Path>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<LocalUsage>> {
        self.load_local_usage_with_metadata(data_root, HashMap::new(), now)
            .await
    }

    /// Loads usage and enriches each session with metadata from `state_5.sqlite`.
    pub async fn load_local_usage_with_metadata(
        &self,
        data_root: impl AsRef<Path>,
        metadata: HashMap<String, CodexThreadMetadata>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<LocalUsage>> {
        let root = data_root.as_ref();
        let index = index_codex_rollout_files(root).await?;
        let summaries = self
            .load_local_summaries_from_index(root, &index, &metadata, now)
            .await?;
        Ok(summaries.and_then(|summaries| {
            let skill_usages = make_skill_usages(&summaries);
            let sessions = combine_session_metadata(summaries, metadata);
            let mut usage =
                make_local_usage_with_timezone(sessions, now, self.statistics_time_zone)?;
            usage.skill_usages = skill_usages;
            Some(usage)
        }))
    }

    pub(crate) async fn load_dashboard_inputs_from_index(
        &self,
        root: &Path,
        index: &[CodexRolloutIndexEntry],
        metadata: HashMap<String, CodexThreadMetadata>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<(Option<LocalUsage>, Option<Vec<SessionSummary>>)> {
        let Some(summaries) = self
            .load_local_summaries_from_index(root, index, &metadata, now)
            .await?
        else {
            return Ok((None, None));
        };
        let skill_usages = make_skill_usages(&summaries);
        let sessions = combine_session_metadata(summaries, metadata);
        let local_usage =
            make_local_usage_with_timezone(sessions.clone(), now, self.statistics_time_zone).map(
                |mut usage| {
                    usage.skill_usages = skill_usages;
                    usage
                },
            );
        Ok((local_usage, Some(sessions)))
    }

    async fn load_local_summaries_internal(
        &self,
        data_root: impl AsRef<Path>,
    ) -> anyhow::Result<Option<Vec<CodexTranscriptSummary>>> {
        let index = index_codex_rollout_files(data_root.as_ref()).await?;
        self.load_local_summaries_from_index(
            data_root.as_ref(),
            &index,
            &HashMap::new(),
            Utc::now(),
        )
        .await
    }

    async fn load_local_summaries_from_index(
        &self,
        root: &Path,
        index: &[CodexRolloutIndexEntry],
        metadata: &HashMap<String, CodexThreadMetadata>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<Vec<CodexTranscriptSummary>>> {
        let root = root.to_path_buf();
        let cache = self.cache_dir.clone();
        let entries = index.to_vec();
        let metadata = metadata.clone();
        let statistics = self.statistics_time_zone;
        let integrity_scan = self.integrity_scan;
        let summaries = tokio::task::spawn_blocking(move || {
            super::codex_history_index::load(
                &root,
                &cache,
                &entries,
                &metadata,
                statistics,
                now,
                integrity_scan,
            )
        })
        .await??;
        ensure_history_unchanged(index).await?;
        Ok((!summaries.is_empty()).then_some(summaries))
    }
}

fn combine_session_metadata(
    summaries: Vec<CodexTranscriptSummary>,
    metadata: HashMap<String, CodexThreadMetadata>,
) -> Vec<SessionSummary> {
    summaries
        .into_iter()
        .map(|s| {
            let key = Path::new(&s.file_path)
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| s.session_id.clone());
            let meta = metadata.get(&key);

            let project_path = meta
                .and_then(|m| m.cwd.as_ref())
                .filter(|p| !p.is_empty())
                .cloned()
                .unwrap_or(s.project_path);
            let model = s.model.or_else(|| meta.and_then(|m| m.model.clone()));
            let last_active_at = match (s.last_active_at, meta.and_then(|m| m.updated_at)) {
                (Some(a), Some(b)) => Some(a.max(b)),
                (Some(a), None) => Some(a),
                (None, Some(b)) => Some(b),
                (None, None) => None,
            };

            SessionSummary {
                file_path: s.file_path,
                session_id: s.session_id,
                project_path: project_path.clone(),
                model,
                last_active_at,
                deltas: s
                    .deltas
                    .into_iter()
                    .map(|d| UsageDelta {
                        message_id: d.turn_id,
                        date: d.date,
                        tokens: d.tokens,
                        model: d.model,
                        project_path: project_path.clone(),
                        session_id: d.session_id,
                    })
                    .collect(),
                tool_calls: s.tool_calls,
                title: meta.and_then(|m| m.title.clone()),
                archived: meta.map(|m| m.archived).unwrap_or(false),
                created_at: meta.and_then(|m| m.created_at),
                thread_source: meta.and_then(|m| m.thread_source.clone()),
                parent_thread_id: meta.and_then(|m| m.parent_thread_id.clone()),
                task_intervals: s.task_intervals,
                git_branch: meta.and_then(|m| m.git_branch.clone()),
                git_origin_url: meta.and_then(|m| m.git_origin_url.clone()),
            }
        })
        .collect()
}

#[derive(Debug)]
struct SkillUsageAccumulator {
    name: String,
    source_label: String,
    load_count: i64,
    thread_ids: HashSet<String>,
    last_loaded_at: Option<DateTime<Utc>>,
}

impl SkillUsageAccumulator {
    fn new(name: String, source_label: String) -> Self {
        Self {
            name,
            source_label,
            load_count: 0,
            thread_ids: HashSet::new(),
            last_loaded_at: None,
        }
    }

    fn record(&mut self, session_id: &str, observed_at: Option<DateTime<Utc>>) {
        self.load_count += 1;
        self.thread_ids.insert(session_id.to_string());
        if observed_at.is_some() && observed_at > self.last_loaded_at {
            self.last_loaded_at = observed_at;
        }
    }

    fn into_usage(self) -> SkillUsage {
        let id = format!(
            "{}:{}",
            self.source_label.to_ascii_lowercase().replace(' ', "-"),
            self.name
        );
        SkillUsage {
            id,
            name: self.name,
            source_label: self.source_label,
            load_count: self.load_count,
            thread_count: self.thread_ids.len() as i64,
            last_loaded_at: self.last_loaded_at,
        }
    }
}

fn make_skill_usages(summaries: &[CodexTranscriptSummary]) -> Vec<SkillUsage> {
    let mut accumulated: HashMap<(String, String), SkillUsageAccumulator> = HashMap::new();

    for summary in summaries {
        for load in &summary.skill_loads {
            let key = (load.source_label.clone(), load.name.clone());
            let accumulator = accumulated.entry(key).or_insert_with(|| {
                SkillUsageAccumulator::new(load.name.clone(), load.source_label.clone())
            });
            accumulator.record(&summary.session_id, load.observed_at);
        }
    }

    let mut usages: Vec<SkillUsage> = accumulated
        .into_values()
        .map(SkillUsageAccumulator::into_usage)
        .collect();
    usages.sort_by(|left, right| {
        right
            .load_count
            .cmp(&left.load_count)
            .then_with(|| left.name.cmp(&right.name))
            .then_with(|| left.source_label.cmp(&right.source_label))
    });
    usages
}

pub(super) fn safe_skill_loads_from_tool_payload(
    payload: &serde_json::Value,
    observed_at: Option<DateTime<Utc>>,
) -> Vec<CodexSkillLoad> {
    let mut loads = Vec::new();
    let mut seen = HashSet::new();

    for key in ["arguments", "input", "cmd", "command"] {
        let Some(argument_text) = payload.get(key).and_then(serialized_skill_argument) else {
            continue;
        };
        for load in extract_safe_skill_loads(&argument_text, observed_at) {
            if seen.insert((load.source_label.clone(), load.name.clone())) {
                loads.push(load);
            }
        }
    }

    loads
}

/// Matches the macOS reader's handling of tool arguments: plain strings are
/// scanned directly, while object/array arguments are serialized briefly for
/// safe `SKILL.md` identity extraction. The serialized payload is not stored.
fn serialized_skill_argument(value: &serde_json::Value) -> Option<String> {
    if let Some(text) = value.as_str() {
        return Some(text.to_string());
    }

    if value.is_object() || value.is_array() {
        return serde_json::to_string(value).ok();
    }

    None
}

fn extract_safe_skill_loads(text: &str, observed_at: Option<DateTime<Utc>>) -> Vec<CodexSkillLoad> {
    const SKILL_FILENAME: &str = "skill.md";
    let lowercase = text.to_ascii_lowercase();
    let mut loads = Vec::new();
    let mut seen = HashSet::new();
    let mut offset = 0;

    while offset < lowercase.len() {
        let Some(relative_match) = lowercase[offset..].find(SKILL_FILENAME) else {
            break;
        };
        let end = offset + relative_match + SKILL_FILENAME.len();
        let candidate_start = text[..end - SKILL_FILENAME.len()]
            .rfind(is_skill_path_boundary)
            .map(|index| index + 1)
            .unwrap_or(0);
        let candidate = &text[candidate_start..end];

        if let Some((name, source_label)) = safe_skill_identity(candidate) {
            let key = (source_label.clone(), name.clone());
            if seen.insert(key) {
                loads.push(CodexSkillLoad {
                    name,
                    source_label,
                    observed_at,
                });
            }
        }
        offset = end;
    }

    loads
}

fn is_skill_path_boundary(character: char) -> bool {
    character.is_whitespace()
        || matches!(
            character,
            '\"' | '\'' | '`' | '<' | '>' | ',' | ';' | '(' | ')' | '[' | ']' | '{' | '}'
        )
}

fn safe_skill_identity(candidate: &str) -> Option<(String, String)> {
    let normalized = candidate
        .trim_matches(|character: char| {
            character.is_whitespace() || "\"'`<>,;.()[]{}".contains(character)
        })
        .replace('\\', "/");
    let lowercase = normalized.to_ascii_lowercase();
    if !lowercase.ends_with("/skill.md") {
        return None;
    }

    let components: Vec<&str> = normalized
        .split('/')
        .filter(|component| !component.is_empty())
        .collect();
    let name = components.get(components.len().checked_sub(2)?).copied()?;
    if !is_safe_skill_name(name) {
        return None;
    }

    let lowercase_components: Vec<String> = components
        .iter()
        .map(|component| component.to_ascii_lowercase())
        .collect();
    let source_label = if lowercase_components
        .windows(2)
        .any(|components| components == ["plugins", "cache"])
    {
        "Bundled Codex skill"
    } else if lowercase_components
        .windows(2)
        .any(|components| components == [".codex", "skills"])
    {
        "Personal Codex skill"
    } else if lowercase_components
        .windows(2)
        .any(|components| components == [".agents", "skills"])
    {
        "Project skill"
    } else {
        "Local skill reference"
    };

    Some((name.to_string(), source_label.to_string()))
}

fn is_safe_skill_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 80
        && name.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.')
        })
}

pub(super) fn parse_derived_task_started_at(
    completed_at: DateTime<Utc>,
    duration_ms: Option<f64>,
) -> Option<DateTime<Utc>> {
    let duration_ms = duration_ms?;
    if !duration_ms.is_finite() || duration_ms <= 0.0 {
        return None;
    }
    if duration_ms > i64::MAX as f64 {
        return None;
    }

    let duration_ms = duration_ms.trunc() as i64;
    let duration = chrono::Duration::milliseconds(duration_ms);
    completed_at.checked_sub_signed(duration)
}

pub(super) fn codex_string_value(value: Option<&serde_json::Value>) -> Option<String> {
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

pub(super) fn codex_f64_value(value: Option<&serde_json::Value>) -> Option<f64> {
    value.and_then(|v| {
        if let Some(n) = v.as_f64() {
            Some(n)
        } else if let Some(s) = v.as_str() {
            s.parse().ok()
        } else if let Some(n) = v.as_i64() {
            Some(n as f64)
        } else if let Some(n) = v.as_u64() {
            Some(n as f64)
        } else {
            None
        }
    })
}

pub(super) fn codex_date_value(value: Option<&serde_json::Value>) -> Option<DateTime<Utc>> {
    value.and_then(|v| {
        if let Some(s) = v.as_str() {
            s.parse::<DateTime<Utc>>().ok()
        } else if let Some(n) = v.as_f64() {
            let seconds = if n > 10_000_000_000.0 { n / 1000.0 } else { n };
            DateTime::from_timestamp(seconds as i64, 0)
        } else {
            None
        }
    })
}

pub(super) fn codex_task_timestamp_value(
    value: Option<&serde_json::Value>,
) -> Option<DateTime<Utc>> {
    value.and_then(|v| match v {
        serde_json::Value::String(s) => s.parse::<DateTime<Utc>>().ok(),
        serde_json::Value::Number(n) => n
            .as_i64()
            .or_else(|| n.as_u64().and_then(|v| i64::try_from(v).ok()))
            .and_then(|n| {
                let abs_secs = n.unsigned_abs();
                let secs = if abs_secs > 10_000_000_000 {
                    n / 1000
                } else {
                    n
                };
                DateTime::from_timestamp(secs, 0)
            }),
        _ => None,
    })
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, TimeZone};

    use super::*;
    use crate::readers::CodexStateReader;

    #[tokio::test]
    async fn reduces_skill_reads_to_safe_local_usage_without_paths_or_arguments() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();

        let session = archived.join("rollout-skill.jsonl");
        let private_path = r"C:\\Users\\private-user\\.codex\\skills\\review\\SKILL.md";
        let raw_argument = format!("Get-Content -Raw '{private_path}'");
        let lines = vec![
            r#"{"timestamp":"2026-03-26T12:53:47.026Z","type":"session_meta","payload":{"id":"session-s","cwd":"C:\\workspace"}}"#.to_string(),
            format!(
                r#"{{"timestamp":"2026-03-26T12:53:48.000Z","type":"response_item","payload":{{"type":"function_call","name":"exec_command","arguments":{}}}}}"#,
                serde_json::to_string(&raw_argument).unwrap()
            ),
            r#"{"timestamp":"2026-03-26T12:53:49.000Z","type":"event_msg","payload":{"type":"token_count","turn_id":"turn-1","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}"#.to_string(),
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let usage = reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .expect("should produce LocalUsage");

        assert_eq!(usage.skill_usages.len(), 1);
        let skill = &usage.skill_usages[0];
        assert_eq!(skill.name, "review");
        assert_eq!(skill.source_label, "Personal Codex skill");
        assert_eq!(skill.load_count, 1);
        assert_eq!(skill.thread_count, 1);

        let dashboard_json = serde_json::to_string(&usage).unwrap();
        assert!(!dashboard_json.contains(private_path));
        assert!(!dashboard_json.contains(&raw_argument));
    }

    #[test]
    fn extracts_blueprint_from_object_arguments_like_macos_reader() {
        let payload = serde_json::json!({
            "arguments": {
                "cmd": r#"Get-Content -Raw 'C:\Users\private-user\.codex\skills\blueprint\SKILL.md'"#
            }
        });

        let loads = safe_skill_loads_from_tool_payload(&payload, None);

        assert_eq!(loads.len(), 1);
        assert_eq!(loads[0].name, "blueprint");
        assert_eq!(loads[0].source_label, "Personal Codex skill");
    }

    #[tokio::test]
    async fn parses_codex_session_jsonl() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();

        let session = archived.join("rollout-test.jsonl");
        let lines = vec![
            r#"{"timestamp":"2026-03-26T12:53:47.026Z","type":"session_meta","payload":{"id":"session-1","timestamp":"2026-03-26T12:53:36.076Z","cwd":"h:\\project\\demo","model_provider":"openai"}}"#,
            r#"{"timestamp":"2026-03-26T12:53:47.028Z","type":"turn_context","payload":{"turn_id":"turn-1","cwd":"h:\\project\\demo","model":"gpt-5.4"}}"#,
            r#"{"timestamp":"2026-03-26T12:53:47.164Z","type":"event_msg","payload":{"type":"token_count","turn_id":"turn-1","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":190}}}}"#,
            r#"{"timestamp":"2026-03-26T12:54:00.000Z","type":"response_item","payload":{"type":"custom_tool_call","status":"completed","call_id":"call-1","name":"apply_patch","input":""}}"#,
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let usage = reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .expect("should produce LocalUsage");

        assert_eq!(usage.thread_count, 1);
        assert_eq!(usage.lifetime_tokens, 190);
        assert_eq!(usage.project_board.as_ref().unwrap().all_projects.len(), 1);
        assert_eq!(usage.tool_usages.len(), 1);
        assert_eq!(usage.tool_usages[0].name, "apply_patch");
        assert_eq!(usage.tool_usages[0].call_count, 1);

        let detailed = usage.detailed_usage.unwrap();
        assert_eq!(detailed.parsed_file_count, 1);
        assert_eq!(detailed.token_event_count, 1);
    }

    #[tokio::test]
    async fn aggregates_function_and_custom_tool_calls_without_exposing_arguments() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();

        let session = archived.join("rollout-mixed-tools.jsonl");
        let private_argument = r#"{"cmd":"Get-Content 'C:\\Users\\private-user\\secret.txt'"}"#;
        let lines = [
            r#"{"timestamp":"2026-03-26T12:53:47.026Z","type":"session_meta","payload":{"id":"session-mixed","cwd":"h:\\project\\demo","model_provider":"openai"}}"#.to_string(),
            r#"{"timestamp":"2026-03-26T12:53:47.164Z","type":"event_msg","payload":{"type":"token_count","turn_id":"turn-1","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}"#.to_string(),
            format!(
                r#"{{"timestamp":"2026-03-26T12:53:48.000Z","type":"response_item","payload":{{"type":"function_call","name":"read_file","arguments":{}}}}}"#,
                serde_json::to_string(private_argument).unwrap()
            ),
            r#"{"timestamp":"2026-03-26T12:53:49.000Z","type":"response_item","payload":{"type":"custom_tool_call","status":"completed","call_id":"call-2","name":"apply_patch","input":"replace private content"}}"#.to_string(),
            r#"{"timestamp":"2026-03-26T12:53:50.000Z","type":"response_item","payload":{"type":"function_call","name":"read_file","arguments":"same tool, second event"}}"#.to_string(),
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let usage = reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .expect("should produce LocalUsage");

        assert_eq!(usage.tool_usages.len(), 2);
        assert_eq!(
            usage
                .tool_usages
                .iter()
                .find(|tool| tool.name == "read_file")
                .map(|tool| tool.call_count),
            Some(2)
        );
        assert_eq!(
            usage
                .tool_usages
                .iter()
                .find(|tool| tool.name == "apply_patch")
                .map(|tool| tool.call_count),
            Some(1)
        );

        let dashboard_json = serde_json::to_string(&usage).unwrap();
        assert!(!dashboard_json.contains(private_argument));
        assert!(!dashboard_json.contains("replace private content"));
    }

    #[tokio::test]
    async fn uses_last_token_usage_not_cumulative_total() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();

        let session = archived.join("rollout-cumulative.jsonl");
        let lines = vec![
            r#"{"timestamp":"2026-03-26T12:53:47.026Z","type":"session_meta","payload":{"id":"session-c","cwd":"/tmp","model_provider":"openai"}}"#,
            r#"{"timestamp":"2026-03-26T12:53:48.000Z","type":"event_msg","payload":{"type":"token_count","turn_id":"turn-1","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150},"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}"#,
            r#"{"timestamp":"2026-03-26T12:53:49.000Z","type":"event_msg","payload":{"type":"token_count","turn_id":"turn-2","info":{"last_token_usage":{"input_tokens":50,"cached_input_tokens":0,"output_tokens":25,"reasoning_output_tokens":0,"total_tokens":75},"total_token_usage":{"input_tokens":150,"cached_input_tokens":0,"output_tokens":75,"reasoning_output_tokens":0,"total_tokens":225}}}}"#,
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let usage = reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .expect("should produce LocalUsage");

        // Should sum last_token_usage deltas (150 + 75 = 225), not total_token_usage totals.
        assert_eq!(usage.lifetime_tokens, 225);
    }

    #[tokio::test]
    async fn parse_task_started_and_task_complete_as_fact_interval() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();
        let started = Utc.with_ymd_and_hms(2026, 3, 26, 12, 0, 0).unwrap();
        let completed = Utc.with_ymd_and_hms(2026, 3, 26, 12, 30, 0).unwrap();

        let session = archived.join("rollout-task.jsonl");
        let lines = vec![
            format!(
                r#"{{"timestamp":"{}","type":"event_msg","payload":{{"type":"task_started","turn_id":"turn-1","started_at":"{}"}}}}"#,
                started.to_rfc3339(),
                started.to_rfc3339()
            ),
            format!(
                r#"{{"timestamp":"{}","type":"event_msg","payload":{{"type":"task_complete","turn_id":"turn-1","completed_at":"{}"}}}}"#,
                completed.to_rfc3339(),
                completed.to_rfc3339()
            ),
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let summaries = reader
            .load_local_summaries(temp.path())
            .await
            .unwrap()
            .expect("should parse summaries");

        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].task_intervals.len(), 1);
        let interval = &summaries[0].task_intervals[0];
        assert_eq!(interval.turn_id.as_deref(), Some("turn-1"));
        assert_eq!(interval.quality, LeadershipEvidenceQuality::Fact);
        assert_eq!(interval.started_at, started);
        assert_eq!(interval.ended_at, completed);
    }

    #[tokio::test]
    async fn parse_task_complete_with_duration_as_derived_interval() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();
        let completed = Utc.with_ymd_and_hms(2026, 3, 26, 12, 10, 0).unwrap();

        let session = archived.join("rollout-task-derived.jsonl");
        let lines = vec![format!(
            r#"{{"timestamp":"{}","type":"event_msg","payload":{{"type":"task_complete","turn_id":"turn-1","completed_at":"{}","duration_ms":5000}}}}"#,
            completed.to_rfc3339(),
            completed.to_rfc3339()
        )];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let summaries = reader
            .load_local_summaries(temp.path())
            .await
            .unwrap()
            .expect("should parse summaries");

        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].task_intervals.len(), 1);
        let interval = &summaries[0].task_intervals[0];
        assert_eq!(interval.turn_id.as_deref(), Some("turn-1"));
        assert_eq!(interval.quality, LeadershipEvidenceQuality::Derived);
        let started = completed - Duration::seconds(5);
        assert_eq!(interval.started_at, started);
        assert_eq!(interval.ended_at, completed);
    }

    #[tokio::test]
    async fn parse_task_complete_with_nonnumeric_duration_ms_is_ignored() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();
        let completed = Utc.with_ymd_and_hms(2026, 3, 26, 12, 10, 0).unwrap();

        let session = archived.join("rollout-task-derived-nonnumeric.jsonl");
        let lines = vec![format!(
            r#"{{"timestamp":"{}","type":"event_msg","payload":{{"type":"task_complete","turn_id":"turn-1","completed_at":"{}","duration_ms":"NaN"}}}}"#,
            completed.to_rfc3339(),
            completed.to_rfc3339()
        )];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let summaries = reader
            .load_local_summaries(temp.path())
            .await
            .unwrap()
            .expect("should parse summaries");

        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].task_intervals.len(), 0);
    }

    #[tokio::test]
    async fn parse_task_complete_with_long_duration_is_accepted() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();
        let completed = Utc.with_ymd_and_hms(2026, 3, 26, 12, 10, 0).unwrap();

        let session = archived.join("rollout-task-derived-just-above-24h.jsonl");
        let long_ms: i64 = 29 * 24 * 60 * 60 * 1000;
        let line = serde_json::json!({
            "timestamp": completed.to_rfc3339(),
            "type": "event_msg",
            "payload": {
                "type": "task_complete",
                "turn_id": "turn-1",
                "completed_at": completed.to_rfc3339(),
                "duration_ms": long_ms,
            }
        });
        let lines = vec![line.to_string()];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let summaries = reader
            .load_local_summaries(temp.path())
            .await
            .unwrap()
            .expect("should parse summaries");

        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].task_intervals.len(), 1);
        assert_eq!(
            summaries[0].task_intervals[0].quality,
            LeadershipEvidenceQuality::Derived
        );
        assert_eq!(
            summaries[0].task_intervals[0].started_at,
            completed - Duration::milliseconds(long_ms)
        );
    }

    #[tokio::test]
    async fn parse_task_complete_with_excessive_duration_is_ignored() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();
        let completed = Utc.with_ymd_and_hms(2026, 3, 26, 12, 10, 0).unwrap();

        let session = archived.join("rollout-task-derived-excessive.jsonl");
        let too_long_ms: i64 = i64::MAX - 1;
        let line = serde_json::json!({
            "timestamp": completed.to_rfc3339(),
            "type": "event_msg",
            "payload": {
                "type": "task_complete",
                "turn_id": "turn-1",
                "completed_at": completed.to_rfc3339(),
                "duration_ms": too_long_ms,
            }
        });
        let lines = vec![line.to_string()];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let summaries = reader
            .load_local_summaries(temp.path())
            .await
            .unwrap()
            .expect("should parse summaries");

        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].task_intervals.len(), 0);
    }

    #[test]
    fn parse_task_timestamp_min_i64_does_not_overflow() {
        let value = serde_json::json!(-9223372036854775808_i64);
        assert_eq!(codex_task_timestamp_value(Some(&value)), None);
    }

    #[test]
    fn parse_task_complete_with_derive_duration_that_underflows_is_ignored() {
        let complete_at = chrono::Utc.from_utc_datetime(&chrono::NaiveDateTime::MIN);
        assert_eq!(
            parse_derived_task_started_at(complete_at, Some(1_000.0)),
            None
        );
    }

    #[tokio::test]
    async fn parse_task_events_require_completed_timestamp() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();

        let session = archived.join("rollout-task-missing-complete.jsonl");
        let lines = vec![
            r#"{"timestamp":"2026-03-26T12:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1","started_at":"2026-03-26T12:00:00.000Z"}}"#,
            r#"{"timestamp":"2026-03-26T12:01:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#,
            r#"{"timestamp":"2026-03-26T12:02:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","duration_ms":1000}}"#,
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let summaries = reader
            .load_local_summaries(temp.path())
            .await
            .unwrap()
            .expect("should parse summaries");

        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].task_intervals.len(), 0);
    }

    #[tokio::test]
    async fn parse_task_started_missing_timestamp_is_ignored() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();

        let session = archived.join("rollout-task-missing-start.jsonl");
        let lines = vec![
            r#"{"timestamp":"2026-03-26T12:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            r#"{"timestamp":"2026-03-26T12:01:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","completed_at":"2026-03-26T12:01:00.000Z"}}"#,
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let summaries = reader
            .load_local_summaries(temp.path())
            .await
            .unwrap()
            .expect("should parse summaries");

        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].task_intervals.len(), 0);
    }

    #[tokio::test]
    async fn enriches_session_with_state_metadata() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();

        let session = archived.join("rollout-test.jsonl");
        let lines = vec![
            r#"{"timestamp":"2026-03-26T12:53:47.164Z","type":"event_msg","payload":{"type":"token_count","turn_id":"turn-1","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":150}}}}"#,
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let db_path = temp.path().join("state_5.sqlite");
        create_test_state_db(
            &db_path,
            "rollout-test.jsonl",
            "Test Thread Title",
            "h:\\project\\demo",
            "gpt-5.4",
            true,
        );

        let metadata = CodexStateReader::new(&db_path)
            .load_metadata()
            .await
            .unwrap();
        assert_eq!(metadata.len(), 1);

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let usage = reader
            .load_local_usage_with_metadata(temp.path(), metadata, Utc::now())
            .await
            .unwrap()
            .expect("should produce LocalUsage");

        assert_eq!(usage.recent_threads.len(), 1);
        let thread = &usage.recent_threads[0];
        assert_eq!(thread.title, "Test Thread Title");
        assert_eq!(thread.cwd, "h:\\project\\demo");
        assert_eq!(thread.model.as_deref(), Some("gpt-5.4"));
        assert!(thread.archived);

        let projects = &usage.project_board.as_ref().unwrap().all_projects;
        assert_eq!(projects[0].full_path, "h:\\project\\demo");
    }

    #[tokio::test]
    async fn falls_back_to_short_path_when_title_missing() {
        let temp = tempfile::tempdir().unwrap();
        let archived = temp.path().join("archived_sessions");
        tokio::fs::create_dir_all(&archived).await.unwrap();

        let session = archived.join("rollout-test.jsonl");
        let lines = vec![
            r#"{"timestamp":"2026-03-26T12:53:47.164Z","type":"event_msg","payload":{"type":"token_count","turn_id":"turn-1","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15}}}}"#,
        ];
        tokio::fs::write(&session, lines.join("\n")).await.unwrap();

        let db_path = temp.path().join("state_5.sqlite");
        create_test_state_db(
            &db_path,
            "rollout-test.jsonl",
            "",
            "h:\\project\\demo",
            "",
            false,
        );

        let metadata = CodexStateReader::new(&db_path)
            .load_metadata()
            .await
            .unwrap();

        let cache = temp.path().join("cache");
        let reader = CodexTranscriptReader::new(&cache);
        let usage = reader
            .load_local_usage_with_metadata(temp.path(), metadata, Utc::now())
            .await
            .unwrap()
            .expect("should produce LocalUsage");

        assert_eq!(usage.recent_threads[0].title, "demo");
    }

    fn create_test_state_db(
        path: &std::path::Path,
        rollout_filename: &str,
        title: &str,
        cwd: &str,
        model: &str,
        archived: bool,
    ) {
        use rusqlite::Connection;
        let conn = Connection::open(path).unwrap();
        conn.execute(
            "CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                rollout_path TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                source TEXT NOT NULL,
                model_provider TEXT NOT NULL,
                cwd TEXT NOT NULL,
                title TEXT NOT NULL,
                sandbox_policy TEXT NOT NULL,
                approval_mode TEXT NOT NULL,
                tokens_used INTEGER NOT NULL DEFAULT 0,
                has_user_event INTEGER NOT NULL DEFAULT 0,
                archived INTEGER NOT NULL DEFAULT 0,
                archived_at INTEGER,
                git_sha TEXT,
                git_branch TEXT,
                git_origin_url TEXT,
                cli_version TEXT NOT NULL DEFAULT '',
                first_user_message TEXT NOT NULL DEFAULT '',
                agent_nickname TEXT,
                agent_role TEXT,
                memory_mode TEXT NOT NULL DEFAULT 'enabled',
                model TEXT,
                reasoning_effort TEXT,
                agent_path TEXT,
                created_at_ms INTEGER,
                updated_at_ms INTEGER,
                thread_source TEXT,
                preview TEXT NOT NULL DEFAULT '',
                recency_at INTEGER NOT NULL DEFAULT 0,
                recency_at_ms INTEGER NOT NULL DEFAULT 0,
                history_mode TEXT NOT NULL DEFAULT 'legacy',
                name TEXT
            )",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO threads (
                id, rollout_path, created_at, updated_at, source, model_provider,
                cwd, title, sandbox_policy, approval_mode, archived,
                model, created_at_ms, updated_at_ms
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)",
            rusqlite::params![
                "thread-1",
                rollout_filename,
                0i64,
                0i64,
                "source",
                "openai",
                cwd,
                title,
                "sandbox",
                "approval",
                archived as i64,
                if model.is_empty() {
                    None::<String>
                } else {
                    Some(model.to_string())
                },
                1711434827000i64,
                1711434827000i64,
            ],
        )
        .unwrap();
    }
}
