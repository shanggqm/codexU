use std::path::PathBuf;

use anyhow::Context;
use chrono::Utc;
use clap::Parser;
use codexu_core::readers::{
    ClaudeCodeTranscriptReader, CodexDashboardProvider, CodexStateReader, CodexTranscriptReader,
};
use tracing::{info, warn};

#[derive(Parser, Debug)]
#[command(name = "codexu-probe")]
#[command(about = "codexU Windows port - data probe CLI")]
struct Args {
    /// Data provider to read from.
    #[arg(long, value_enum, default_value = "codex")]
    provider: Provider,

    /// Path to Codex data root (e.g. ~/.codex)
    #[arg(long, value_name = "PATH")]
    codex_root: Option<PathBuf>,

    /// Path to Claude Code projects root (e.g. ~/.claude/projects)
    #[arg(long, value_name = "PATH")]
    claude_projects: Option<PathBuf>,

    /// Cache directory for codexU
    #[arg(long, value_name = "PATH")]
    cache_dir: Option<PathBuf>,

    /// Output file for JSON dump
    #[arg(short, long, value_name = "PATH", default_value = "codexu-probe.json")]
    output: PathBuf,

    /// Only print summary, skip writing JSON
    #[arg(long)]
    summary: bool,

    /// Write the full local Codex dashboard snapshot for the Web visual harness.
    #[arg(long)]
    dashboard: bool,

    /// Rebuild and verify derived usage against full source files, including interior edits.
    #[arg(long, conflicts_with = "dashboard")]
    verify_history_index: bool,
}

#[derive(Debug, Clone, Copy, Default, clap::ValueEnum)]
enum Provider {
    #[default]
    Codex,
    ClaudeCode,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    let home = dirs::home_dir().context("Could not determine home directory")?;
    let cache_dir = args.cache_dir.unwrap_or_else(|| {
        dirs::cache_dir()
            .unwrap_or_else(|| home.join(".cache"))
            .join("codexU")
    });

    match args.provider {
        Provider::Codex => {
            let codex_root = args.codex_root.unwrap_or_else(|| home.join(".codex"));

            if args.dashboard {
                let provider = CodexDashboardProvider::new(&codex_root, &cache_dir);
                if let Some(snapshot) = provider.load_dashboard_snapshot(Utc::now()).await? {
                    let json = serde_json::to_string_pretty(&snapshot)?;
                    tokio::fs::write(&args.output, json).await?;
                    info!("Wrote dashboard JSON to {}", args.output.display());
                } else {
                    warn!(
                        "No Codex dashboard data found at {}; no JSON was written",
                        codex_root.display()
                    );
                }
                return Ok(());
            }

            let state_db_path = codex_root.join("state_5.sqlite");
            info!("Codex data root: {}", codex_root.display());
            info!("Codex state DB: {}", state_db_path.display());
            info!("Cache directory: {}", cache_dir.display());

            let reader = CodexTranscriptReader::new(&cache_dir);
            let reader = if args.verify_history_index {
                reader.with_integrity_scan()
            } else {
                reader
            };
            let now = Utc::now();

            let metadata = if tokio::fs::try_exists(&state_db_path).await.unwrap_or(false) {
                match CodexStateReader::new(&state_db_path).load_metadata().await {
                    Ok(m) => {
                        info!("Loaded metadata for {} threads from state DB", m.len());
                        m
                    }
                    Err(e) => {
                        warn!(
                            "Failed to load Codex state metadata ({}); continuing without it",
                            e
                        );
                        std::collections::HashMap::new()
                    }
                }
            } else {
                info!("Codex state DB not found; continuing without metadata enrichment");
                std::collections::HashMap::new()
            };

            match reader
                .load_local_usage_with_metadata(&codex_root, metadata, now)
                .await
            {
                Ok(Some(local_usage)) => {
                    info!(
                        "Parsed {} files, {} unique usage events",
                        local_usage
                            .detailed_usage
                            .as_ref()
                            .map(|d| d.parsed_file_count)
                            .unwrap_or(0),
                        local_usage
                            .detailed_usage
                            .as_ref()
                            .map(|d| d.token_event_count)
                            .unwrap_or(0)
                    );
                    info!(
                        "Today: {} tokens, 7-day: {} tokens, lifetime: {} tokens",
                        local_usage.today_tokens,
                        local_usage.seven_day_tokens,
                        local_usage.lifetime_tokens
                    );
                    info!(
                        "Projects: {}",
                        local_usage
                            .project_board
                            .as_ref()
                            .map(|b| b.all_projects.len())
                            .unwrap_or(0)
                    );
                    info!("Tools: {}", local_usage.tool_usages.len());

                    if !args.summary {
                        let json = serde_json::to_string_pretty(&local_usage)?;
                        tokio::fs::write(&args.output, json).await?;
                        info!("Wrote JSON to {}", args.output.display());
                    }
                }
                Ok(None) => {
                    warn!("No Codex usage data found at {}", codex_root.display());
                }
                Err(e) => {
                    return Err(e).context("Failed to load Codex local usage");
                }
            }
        }
        Provider::ClaudeCode => {
            let claude_projects = args
                .claude_projects
                .unwrap_or_else(|| home.join(".claude").join("projects"));
            warn!("Claude Code provider is deferred on Windows; data path may not exist yet");
            info!("Claude projects root: {}", claude_projects.display());
            info!("Cache directory: {}", cache_dir.display());

            let reader = ClaudeCodeTranscriptReader::new(&cache_dir);
            let now = Utc::now();

            match reader.load_local_usage(&claude_projects, now).await {
                Ok(Some(local_usage)) => {
                    info!(
                        "Parsed {} files, {} unique usage events",
                        local_usage
                            .detailed_usage
                            .as_ref()
                            .map(|d| d.parsed_file_count)
                            .unwrap_or(0),
                        local_usage
                            .detailed_usage
                            .as_ref()
                            .map(|d| d.token_event_count)
                            .unwrap_or(0)
                    );
                    info!(
                        "Today: {} tokens, 7-day: {} tokens, lifetime: {} tokens",
                        local_usage.today_tokens,
                        local_usage.seven_day_tokens,
                        local_usage.lifetime_tokens
                    );
                    info!(
                        "Projects: {}",
                        local_usage
                            .project_board
                            .as_ref()
                            .map(|b| b.all_projects.len())
                            .unwrap_or(0)
                    );
                    info!("Tools: {}", local_usage.tool_usages.len());

                    if !args.summary {
                        let json = serde_json::to_string_pretty(&local_usage)?;
                        tokio::fs::write(&args.output, json).await?;
                        info!("Wrote JSON to {}", args.output.display());
                    }
                }
                Ok(None) => {
                    warn!(
                        "No Claude Code usage data found at {}",
                        claude_projects.display()
                    );
                }
                Err(e) => {
                    return Err(e).context("Failed to load Claude Code local usage");
                }
            }
        }
    }

    Ok(())
}
