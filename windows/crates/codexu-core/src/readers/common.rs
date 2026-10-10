//! Shared helpers for transcript readers.
//!
//! Both Codex and Claude Code transcripts eventually produce the same `LocalUsage`
//! aggregation. The functions here are provider-agnostic: file enumeration,
//! fingerprinting, aggregation into macOS-compatible models, and cost estimation.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use chrono::{DateTime, Datelike, Utc};
use serde::{Deserialize, Serialize};

use super::history_integrity::HistoryReadError;
use crate::models::*;

#[cfg(test)]
thread_local! {
    static JSONL_ENUMERATION_COUNT: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    static FINGERPRINT_COUNT: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

#[cfg(test)]
pub(crate) fn reset_rollout_io_counts() {
    JSONL_ENUMERATION_COUNT.with(|count| count.set(0));
    FINGERPRINT_COUNT.with(|count| count.set(0));
}

#[cfg(test)]
pub(crate) fn rollout_io_counts() -> (usize, usize) {
    (
        JSONL_ENUMERATION_COUNT.with(std::cell::Cell::get),
        FINGERPRINT_COUNT.with(std::cell::Cell::get),
    )
}

pub const MAX_CACHE_BYTES: u64 = 128 * 1024 * 1024;
pub const MAX_LINE_BYTES: usize = 4 * 1024 * 1024;
pub const READ_CHUNK_BYTES: usize = 64 * 1024;
pub const CACHE_VERSION: i32 = 2;

/// A fingerprint for a transcript file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FileFingerprint {
    pub file_size: i64,
    pub modification_time_ns: Option<i64>,
}

/// One rollout path and the filesystem identity captured for a single refresh.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CodexRolloutIndexEntry {
    pub path: PathBuf,
    pub fingerprint: Option<FileFingerprint>,
}

/// A single usage delta extracted from a transcript.
#[derive(Debug, Clone, PartialEq)]
pub struct UsageDelta {
    pub message_id: Option<String>,
    pub date: DateTime<Utc>,
    pub tokens: TokenBreakdown,
    pub model: Option<String>,
    pub project_path: String,
    pub session_id: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CodexTaskInterval {
    pub turn_id: Option<String>,
    #[serde(with = "chrono::serde::ts_milliseconds")]
    pub started_at: DateTime<Utc>,
    #[serde(with = "chrono::serde::ts_milliseconds")]
    pub ended_at: DateTime<Utc>,
    pub quality: LeadershipEvidenceQuality,
}

/// Per-session metadata and deltas extracted from one transcript file.
#[derive(Debug, Clone, PartialEq)]
pub struct SessionSummary {
    pub file_path: String,
    pub session_id: String,
    pub project_path: String,
    pub model: Option<String>,
    pub last_active_at: Option<DateTime<Utc>>,
    /// Factual creation time from state metadata.
    pub created_at: Option<DateTime<Utc>>,
    pub deltas: Vec<UsageDelta>,
    pub tool_calls: HashMap<String, i64>,
    /// Thread title from the Codex state database, if available.
    pub title: Option<String>,
    /// Whether this thread has been archived according to the state database.
    pub archived: bool,
    /// Git branch captured when the thread was created.
    pub git_branch: Option<String>,
    /// Git origin URL captured when the thread was created.
    pub git_origin_url: Option<String>,
    /// Worker kind source from the state DB, if available (`main`, `subagent`, `automation`).
    pub thread_source: Option<String>,
    /// Parent thread id from optional runtime edges table, if available.
    pub parent_thread_id: Option<String>,
    /// Task timing evidence extracted from transcript events.
    pub task_intervals: Vec<CodexTaskInterval>,
}

/// Enumerates all `.jsonl` files under `root`, sorted.
pub async fn enumerate_jsonl_files(root: &Path) -> Result<Vec<PathBuf>, HistoryReadError> {
    #[cfg(test)]
    JSONL_ENUMERATION_COUNT.with(|count| count.set(count.get() + 1));

    let mut files = Vec::new();
    let mut dirs = vec![root.to_path_buf()];
    while let Some(dir) = dirs.pop() {
        let mut entries = tokio::fs::read_dir(&dir)
            .await
            .map_err(|_| HistoryReadError::Unavailable)?;
        while let Some(entry) = entries
            .next_entry()
            .await
            .map_err(|_| HistoryReadError::Unavailable)?
        {
            let path = entry.path();
            let file_type = entry
                .file_type()
                .await
                .map_err(|_| HistoryReadError::Unavailable)?;
            if file_type.is_dir() {
                if !path
                    .file_name()
                    .map(|n| n.to_string_lossy().starts_with('.'))
                    .unwrap_or(false)
                {
                    dirs.push(path);
                }
            } else if file_type.is_file()
                && path.extension().and_then(|e| e.to_str()) == Some("jsonl")
            {
                files.push(path);
            }
        }
    }
    files.sort();
    Ok(files)
}

/// Builds a file fingerprint from filesystem metadata.
pub async fn fingerprint_for(path: &Path) -> Option<FileFingerprint> {
    #[cfg(test)]
    FINGERPRINT_COUNT.with(|count| count.set(count.get() + 1));

    let meta = tokio::fs::metadata(path).await.ok()?;
    let modified = meta.modified().ok()?;
    let duration = modified.duration_since(std::time::UNIX_EPOCH).ok()?;
    Some(FileFingerprint {
        file_size: meta.len() as i64,
        modification_time_ns: Some(duration.as_nanos() as i64),
    })
}

/// Enumerates and fingerprints the live and archived Codex rollouts once.
pub async fn index_codex_rollout_files(
    codex_root: &Path,
) -> Result<Vec<CodexRolloutIndexEntry>, HistoryReadError> {
    let root_metadata = tokio::fs::metadata(codex_root)
        .await
        .map_err(|_| HistoryReadError::Unavailable)?;
    if !root_metadata.is_dir() {
        return Err(HistoryReadError::Unavailable);
    }
    let mut paths = Vec::new();
    for root in [
        codex_root.join("archived_sessions"),
        codex_root.join("sessions"),
    ] {
        if tokio::fs::try_exists(&root)
            .await
            .map_err(|_| HistoryReadError::Unavailable)?
        {
            paths.extend(enumerate_jsonl_files(&root).await?);
        }
    }
    paths.sort();
    paths.dedup();

    let mut entries = Vec::with_capacity(paths.len());
    for path in paths {
        let fingerprint = Some(
            fingerprint_for(&path)
                .await
                .ok_or(HistoryReadError::Unavailable)?,
        );
        entries.push(CodexRolloutIndexEntry { path, fingerprint });
    }
    Ok(entries)
}

/// Aggregates a collection of session summaries into `LocalUsage`.
pub fn make_local_usage(summaries: Vec<SessionSummary>, now: DateTime<Utc>) -> Option<LocalUsage> {
    make_local_usage_with_timezone(summaries, now, crate::StatisticsTimeZone::Local)
}

pub fn make_local_usage_with_timezone(
    summaries: Vec<SessionSummary>,
    now: DateTime<Utc>,
    statistics: crate::StatisticsTimeZone,
) -> Option<LocalUsage> {
    let mut unique_deltas: Vec<UsageDelta> = Vec::new();
    let mut seen_message_ids = HashSet::new();
    for delta in summaries.iter().flat_map(|s| s.deltas.iter()) {
        if let Some(ref id) = delta.message_id {
            if seen_message_ids.contains(id) {
                continue;
            }
            seen_message_ids.insert(id.clone());
        }
        unique_deltas.push(delta.clone());
    }

    if unique_deltas.is_empty() {
        return None;
    }

    unique_deltas.sort_by_key(|a| a.date);

    let day_start = statistics.day_start(now);
    let seven_day_start = statistics.days_before_start(now, 6);
    let previous_seven_day_start = statistics.days_before_start(now, 13);
    let month_start = statistics.month_start(now);

    let mut today = PricedTokenUsage::ZERO;
    let mut seven_day = PricedTokenUsage::ZERO;
    let mut previous_seven_day = PricedTokenUsage::ZERO;
    let mut month = PricedTokenUsage::ZERO;
    let mut lifetime = PricedTokenUsage::ZERO;
    let mut daily_usage: HashMap<String, (DateTime<Utc>, PricedTokenUsage)> = HashMap::new();
    let mut projects: HashMap<String, ProjectAccumulator> = HashMap::new();

    for delta in &unique_deltas {
        let cost = estimated_cost_usd(&delta.tokens, delta.model.as_deref());
        lifetime.add_tokens(&delta.tokens, cost);
        if delta.date >= month_start {
            month.add_tokens(&delta.tokens, cost);
        }
        if delta.date >= seven_day_start {
            seven_day.add_tokens(&delta.tokens, cost);
        }
        if delta.date >= previous_seven_day_start && delta.date < seven_day_start {
            previous_seven_day.add_tokens(&delta.tokens, cost);
        }
        if delta.date >= day_start {
            today.add_tokens(&delta.tokens, cost);
        }

        let bucket_date = statistics.day_start(delta.date);
        let key = statistics.day_key(delta.date);
        let entry = daily_usage
            .entry(key)
            .or_insert_with(|| (bucket_date, PricedTokenUsage::ZERO));
        entry.1.add_tokens(&delta.tokens, cost);

        let project_path = if delta.project_path.is_empty() {
            "Codex".to_string()
        } else {
            delta.project_path.clone()
        };
        let acc = projects
            .entry(project_path.clone())
            .or_insert_with(|| ProjectAccumulator {
                path: project_path.clone(),
                ..Default::default()
            });
        acc.add(delta, cost);
    }

    let daily_buckets = make_seven_day_buckets(&daily_usage, now, statistics);
    let usage_trend = make_usage_trend(
        &daily_usage,
        &seven_day,
        &previous_seven_day,
        &month,
        now,
        statistics,
    );

    let detailed = DetailedUsage {
        today: today.clone(),
        seven_day: seven_day.clone(),
        month: month.clone(),
        lifetime: lifetime.clone(),
        parsed_file_count: summaries.len() as i64,
        token_event_count: unique_deltas.len() as i64,
    };

    let mut project_usages: Vec<ProjectUsage> =
        projects.values().map(|p| p.make_project()).collect();
    project_usages.sort_by(|a, b| {
        if a.tokens != b.tokens {
            b.tokens.cmp(&a.tokens)
        } else {
            b.last_active_at.cmp(&a.last_active_at)
        }
    });

    let recent_threads: Vec<LocalThread> = summaries
        .iter()
        .map(|s| {
            let tokens = s
                .deltas
                .iter()
                .map(|d| d.tokens.visible_total_tokens())
                .sum();
            let title = s
                .title
                .as_ref()
                .map(|t| truncate_title(t))
                .unwrap_or_else(|| short_workspace_name(&s.project_path));
            LocalThread {
                id: s.session_id.clone(),
                title,
                tokens,
                updated_at: s.last_active_at,
                model: s.model.clone(),
                cwd: s.project_path.clone(),
                archived: s.archived,
            }
        })
        .collect();

    let tool_usages = make_tool_usages(&summaries, &lifetime);

    let usage = LocalUsage {
        lifetime_tokens: lifetime.tokens.visible_total_tokens(),
        today_tokens: today.tokens.visible_total_tokens(),
        seven_day_tokens: seven_day.tokens.visible_total_tokens(),
        thread_count: summaries.len().max(1) as i64,
        last_updated_at: summaries.iter().filter_map(|s| s.last_active_at).max(),
        daily_buckets,
        recent_threads,
        detailed_usage: Some(detailed),
        usage_trend: Some(usage_trend),
        inference_performance: None,
        project_board: Some(ProjectBoard {
            recent_projects: project_usages.iter().take(8).cloned().collect(),
            all_projects: project_usages,
        }),
        tool_usages,
        skill_usages: Vec::new(), // TODO: implement skill resolver
    };

    Some(usage)
}

fn make_seven_day_buckets(
    daily_usage: &HashMap<String, (DateTime<Utc>, PricedTokenUsage)>,
    now: DateTime<Utc>,
    statistics: crate::StatisticsTimeZone,
) -> Vec<DailyTokenBucket> {
    (0..7)
        .map(|offset| {
            let date = statistics.days_before_start(now, 6 - offset);
            let key = statistics.day_key(date);
            DailyTokenBucket {
                id: key.clone(),
                label: statistics.date(date).format("%a").to_string(),
                tokens: daily_usage
                    .get(&key)
                    .map(|(_, u)| u.tokens.visible_total_tokens())
                    .unwrap_or(0),
            }
        })
        .collect()
}

fn make_usage_trend(
    daily_usage: &HashMap<String, (DateTime<Utc>, PricedTokenUsage)>,
    seven_day: &PricedTokenUsage,
    previous_seven_day: &PricedTokenUsage,
    month: &PricedTokenUsage,
    now: DateTime<Utc>,
    statistics: crate::StatisticsTimeZone,
) -> UsageTrend {
    let mut buckets = Vec::new();
    let mut heatmap_days = Vec::new();

    for offset in 0..180 {
        let date = statistics.days_before_start(now, 179 - offset);
        let key = statistics.day_key(date);
        let usage = daily_usage
            .get(&key)
            .map(|(_, u)| u.clone())
            .unwrap_or_default();
        buckets.push(UsageDayBucket {
            id: key,
            date,
            usage: usage.clone(),
            source_quality: UsageSourceQuality::Detailed,
        });
        heatmap_days.push(UsageHeatmapDay {
            id: statistics.day_key(date),
            date,
            usage: if usage.tokens.visible_total_tokens() > 0 {
                Some(usage)
            } else {
                None
            },
            is_future: date > now,
        });
    }

    let active_buckets: Vec<UsageDayBucket> =
        buckets.iter().filter(|b| b.tokens() > 0).cloned().collect();
    let peak = active_buckets.iter().max_by_key(|b| b.tokens()).cloned();
    let active_day_count = active_buckets.len() as i64;
    let previous_tokens = previous_seven_day.tokens.visible_total_tokens();
    let current_tokens = seven_day.tokens.visible_total_tokens();
    let change_percent = if previous_tokens > 0 {
        Some(((current_tokens - previous_tokens) as f64 / previous_tokens as f64) * 100.0)
    } else {
        None
    };

    let summary = UsageTrendSummary {
        seven_day: seven_day.clone(),
        daily_average_tokens: current_tokens / 7,
        peak_day: peak,
        change_percent,
        is_new_activity: previous_tokens == 0 && current_tokens > 0,
    };

    let mut thresholds =
        make_heatmap_thresholds(active_buckets.iter().map(|b| b.tokens()).collect());
    if thresholds.is_empty() {
        thresholds = vec![1, 10, 100, 1000];
    }

    let heatmap_weeks: Vec<Vec<_>> = heatmap_days.chunks(7).map(|c| c.to_vec()).collect();

    UsageTrend {
        day_buckets: buckets,
        heatmap_weeks,
        heatmap_thresholds: thresholds,
        summary,
        model_trends: None,
        month: month.clone(),
        projected_month_cost_usd: projected_month_cost(
            month.estimated_cost_usd,
            statistics.date(now),
        ),
        active_day_count,
        source_quality: UsageSourceQuality::Detailed,
    }
}

fn make_heatmap_thresholds(tokens: Vec<i64>) -> Vec<i64> {
    let mut sorted: Vec<i64> = tokens.into_iter().filter(|t| *t > 0).collect();
    if sorted.is_empty() {
        return Vec::new();
    }
    sorted.sort();

    vec![
        sorted[(sorted.len() - 1) * 25 / 100].max(1),
        sorted[(sorted.len() - 1) * 50 / 100].max(1),
        sorted[(sorted.len() - 1) * 75 / 100].max(1),
        sorted[(sorted.len() - 1) * 95 / 100].max(1),
    ]
}

fn projected_month_cost(month_cost: f64, now: chrono::NaiveDate) -> Option<f64> {
    let day = now.day();
    let days_in_month = match now.month() {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        2 => {
            if now.year() % 4 == 0 && (now.year() % 100 != 0 || now.year() % 400 == 0) {
                29
            } else {
                28
            }
        }
        _ => 30,
    };
    if day == 0 || day > days_in_month as u32 {
        return None;
    }
    Some(month_cost / day as f64 * days_in_month as f64)
}

fn make_tool_usages(summaries: &[SessionSummary], lifetime: &PricedTokenUsage) -> Vec<ToolUsage> {
    let mut calls: HashMap<String, i64> = HashMap::new();
    for summary in summaries {
        for (name, count) in &summary.tool_calls {
            *calls.entry(name.clone()).or_insert(0) += count;
        }
    }

    let total_calls: i64 = calls.values().sum();
    let total_calls = total_calls.max(1);
    let tokens_per_call = lifetime.tokens.visible_total_tokens() / total_calls;
    let cost_per_call = lifetime.estimated_cost_usd / total_calls as f64;

    let mut usages: Vec<ToolUsage> = calls
        .into_iter()
        .map(|(name, count)| ToolUsage {
            id: name.clone(),
            name: name.clone(),
            category: tool_category(&name),
            call_count: count,
            estimated_tokens: if tokens_per_call > 0 {
                Some(tokens_per_call * count)
            } else {
                None
            },
            estimated_cost_usd: if cost_per_call > 0.0 {
                Some(cost_per_call * count as f64)
            } else {
                None
            },
        })
        .collect();
    usages.sort_by_key(|b| std::cmp::Reverse(b.call_count));
    usages
}

pub fn tool_category(name: &str) -> String {
    let normalized = name.to_lowercase();
    if normalized.contains("bash")
        || normalized.contains("shell")
        || normalized.contains("terminal")
    {
        "terminal".to_string()
    } else if normalized.contains("edit")
        || normalized.contains("write")
        || normalized.contains("patch")
    {
        "edit".to_string()
    } else if normalized.contains("read")
        || normalized.contains("grep")
        || normalized.contains("glob")
    {
        "docs".to_string()
    } else if normalized.contains("web")
        || normalized.contains("browser")
        || normalized.contains("fetch")
    {
        "browser".to_string()
    } else if normalized.contains("task")
        || normalized.contains("agent")
        || normalized.contains("todo")
    {
        "planning".to_string()
    } else if normalized.contains("mcp") {
        "mcp".to_string()
    } else {
        "tool".to_string()
    }
}

pub fn short_workspace_name(path: &str) -> String {
    let trimmed = path.trim_matches(|c| c == '/' || c == '\\');
    trimmed
        .split(|c| c == '/' || c == '\\')
        .next_back()
        .unwrap_or(path)
        .to_string()
}

const MAX_TITLE_CHARS: usize = 200;

/// Truncates a thread title to a display-safe length.
///
/// Codex stores the first user message (or a generated summary) in the `title`
/// column, which can be very long. We keep enough for the UI while avoiding
/// storing full prompts in memory.
pub fn truncate_title(title: &str) -> String {
    if title.chars().count() <= MAX_TITLE_CHARS {
        title.to_string()
    } else {
        let mut result: String = title.chars().take(MAX_TITLE_CHARS).collect();
        result.push('…');
        result
    }
}

/// Estimates USD cost from a token breakdown and an optional model name.
///
/// Supports Claude and OpenAI/Codex model families with approximate list prices.
/// Prices are per-million-tokens and are best-effort; update them when official
/// pricing changes. When the model is unknown the cost is zero.
pub fn estimated_cost_usd(tokens: &TokenBreakdown, model: Option<&str>) -> f64 {
    let model_lower = model.map(|m| m.to_lowercase());
    let m = model_lower.as_deref();
    let price = if m == Some("claude-opus") || m.map(|s| s.contains("opus")).unwrap_or(false) {
        Some((15.0, 1.5, 75.0))
    } else if m == Some("claude-sonnet") || m.map(|s| s.contains("sonnet")).unwrap_or(false) {
        Some((3.0, 0.3, 15.0))
    } else if m == Some("claude-haiku") || m.map(|s| s.contains("haiku")).unwrap_or(false) {
        Some((0.8, 0.08, 4.0))
    } else if m.map(|s| s.contains("gpt-5.5")).unwrap_or(false) {
        // Approximate higher-tier GPT-5.5 pricing.
        Some((5.0, 1.25, 20.0))
    } else if m.map(|s| s.contains("gpt-5")).unwrap_or(false) {
        // Approximate GPT-5.4 / base GPT-5 pricing.
        Some((2.5, 0.625, 10.0))
    } else if m.map(|s| s.contains("gpt-4o")).unwrap_or(false) {
        Some((2.5, 1.25, 10.0))
    } else if m.map(|s| s.contains("gpt-4")).unwrap_or(false) {
        Some((10.0, 5.0, 30.0))
    } else if m
        .map(|s| s.contains("gpt-3.5") || s.contains("gpt-35"))
        .unwrap_or(false)
    {
        Some((0.5, 0.25, 1.5))
    } else {
        None
    };
    let Some((input_price, cached_price, output_price)) = price else {
        return 0.0;
    };
    let uncached_cost = tokens.uncached_input_tokens() as f64 / 1_000_000.0 * input_price;
    let cached_cost = tokens.billable_cached_input_tokens() as f64 / 1_000_000.0 * cached_price;
    let output_cost = tokens.output_tokens.max(0) as f64 / 1_000_000.0 * output_price;
    uncached_cost + cached_cost + output_cost
}

#[derive(Debug, Default)]
struct ProjectAccumulator {
    path: String,
    tokens: TokenBreakdown,
    estimated_cost_usd: f64,
    session_ids: HashSet<String>,
    last_active_at: Option<DateTime<Utc>>,
}

impl ProjectAccumulator {
    fn add(&mut self, delta: &UsageDelta, cost_usd: f64) {
        self.tokens.add(&delta.tokens);
        self.estimated_cost_usd += cost_usd;
        self.session_ids.insert(delta.session_id.clone());
        self.last_active_at = self
            .last_active_at
            .map(|d| d.max(delta.date))
            .or(Some(delta.date));
    }

    fn make_project(&self) -> ProjectUsage {
        ProjectUsage {
            id: self.path.clone(),
            name: short_workspace_name(&self.path),
            full_path: self.path.clone(),
            tokens: self.tokens.visible_total_tokens(),
            estimated_cost_usd: if self.estimated_cost_usd > 0.0 {
                Some(self.estimated_cost_usd)
            } else {
                None
            },
            thread_count: self.session_ids.len().max(1) as i64,
            last_active_at: self.last_active_at,
            source_quality: UsageSourceQuality::Detailed,
        }
    }
}

impl UsageDayBucket {
    fn tokens(&self) -> i64 {
        self.usage.tokens.visible_total_tokens()
    }
}
