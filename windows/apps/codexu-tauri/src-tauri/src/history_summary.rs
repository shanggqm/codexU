//! Bounded startup summary. It is derived local data, never an official quota cache.
use chrono::{Local, Offset};
use codexu_core::models::{CodexDashboardSnapshot, LocalUsage};
use codexu_core::readers::codex_dashboard::empty_dashboard;
use serde::{Deserialize, Serialize};
use std::io::Read;
use std::path::{Path, PathBuf};

const MAX_BYTES: u64 = 256 * 1024;
const NAME: &str = "history-summary.json";

#[derive(Serialize, Deserialize)]
struct Summary {
    version: u8,
    root: PathBuf,
    cache: PathBuf,
    calendar: i32,
    dashboard: CodexDashboardSnapshot,
}

fn calendar() -> i32 {
    Local::now().offset().fix().local_minus_utc()
}

pub fn load(directory: &Path, root: &Path, cache: &Path) -> Option<CodexDashboardSnapshot> {
    let file = std::fs::File::open(directory.join(NAME)).ok()?;
    if file.metadata().ok()?.len() > MAX_BYTES {
        return None;
    }
    let mut bytes = Vec::new();
    file.take(MAX_BYTES + 1).read_to_end(&mut bytes).ok()?;
    if bytes.len() as u64 > MAX_BYTES {
        return None;
    }
    let saved: Summary = serde_json::from_slice(&bytes).ok()?;
    (saved.version == 1
        && saved.root == root
        && saved.cache == cache
        && saved.calendar == calendar())
    .then_some(saved.dashboard)
}

pub async fn save(
    directory: &Path,
    root: &Path,
    cache: &Path,
    full: &CodexDashboardSnapshot,
) -> anyhow::Result<()> {
    let mut dashboard = empty_dashboard(full.refreshed_at);
    // Construct only fixed headline data instead of cloning the full detail vectors.
    dashboard.codex.snapshot.local = full.codex.snapshot.local.as_ref().map(|local| LocalUsage {
        lifetime_tokens: local.lifetime_tokens,
        today_tokens: local.today_tokens,
        seven_day_tokens: local.seven_day_tokens,
        thread_count: local.thread_count,
        last_updated_at: local.last_updated_at,
        detailed_usage: local.detailed_usage.clone(),
        daily_buckets: vec![],
        recent_threads: vec![],
        usage_trend: None,
        inference_performance: None,
        project_board: None,
        tool_usages: vec![],
        skill_usages: vec![],
    });
    dashboard.leadership = full.leadership.clone();
    if let Some(report) = dashboard.leadership.report.as_mut() {
        for period in &mut report.reports {
            period.daily_points.clear();
            period.projects.clear();
        }
    }
    let bytes = serde_json::to_vec(&Summary {
        version: 1,
        root: root.into(),
        cache: cache.into(),
        calendar: calendar(),
        dashboard,
    })?;
    anyhow::ensure!(
        bytes.len() as u64 <= MAX_BYTES,
        "Startup summary exceeds its budget"
    );
    codexu_core::readers::history_integrity::write_cache_atomically(&directory.join(NAME), &bytes)
        .await?;
    Ok(())
}

pub fn clear(directory: &Path) -> anyhow::Result<()> {
    for name in [NAME] {
        match std::fs::remove_file(directory.join(name)) {
            Ok(()) => (),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
            Err(e) => return Err(e.into()),
        }
    }
    Ok(())
}
