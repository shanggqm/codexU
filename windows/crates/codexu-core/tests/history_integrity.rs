use chrono::Utc;
use codexu_core::readers::{
    CodexDashboardProvider, CodexTranscriptReader, InferencePerformanceReader,
};
use std::path::Path;
use tempfile::tempdir;

fn published_generation(cache: &Path) -> i64 {
    rusqlite::Connection::open(cache.join("codex/history-index.sqlite"))
        .unwrap()
        .query_row("SELECT published_generation FROM index_meta", [], |row| {
            row.get(0)
        })
        .unwrap()
}

fn write_usage(path: &Path, turn: &str, tokens: i64) {
    let event = serde_json::json!({
        "timestamp": "2026-10-10T00:00:00Z", "type": "event_msg",
        "payload": {"type": "token_count", "turn_id": turn,
            "info": {"last_token_usage": {"input_tokens": tokens,
                "cached_input_tokens": 0, "output_tokens": 0,
                "reasoning_output_tokens": 0, "total_tokens": tokens}}}
    });
    std::fs::write(path, format!("{event}\n")).unwrap();
}

#[tokio::test]
async fn malformed_line_cannot_publish_or_cache_partial_history() {
    let temp = tempdir().unwrap();
    let sessions = temp.path().join("sessions");
    std::fs::create_dir(&sessions).unwrap();
    let file = sessions.join("rollout-a.jsonl");
    let cache = temp.path().join("cache");
    let reader = CodexTranscriptReader::new(&cache);
    write_usage(&file, "a", 300);
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        300
    );
    let complete_generation = published_generation(&cache);
    write_usage(&file, "a", 100);
    use std::io::Write;
    writeln!(
        std::fs::OpenOptions::new()
            .append(true)
            .open(&file)
            .unwrap(),
        "{{broken"
    )
    .unwrap();
    assert!(reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .is_err());
    assert_eq!(published_generation(&cache), complete_generation);
    write_usage(&file, "a", 50);
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        50
    );
}

#[tokio::test]
async fn unavailable_root_and_failed_directory_scan_are_not_empty_history() {
    let temp = tempdir().unwrap();
    let provider =
        CodexDashboardProvider::new(temp.path().join("missing"), temp.path().join("cache"));
    assert!(provider.load_dashboard_snapshot(Utc::now()).await.is_err());
    let provider = CodexDashboardProvider::new(temp.path(), temp.path().join("cache"));
    assert!(provider
        .load_dashboard_snapshot(Utc::now())
        .await
        .unwrap()
        .is_none());
    std::fs::write(temp.path().join("sessions"), b"not a directory").unwrap();
    assert!(provider.load_dashboard_snapshot(Utc::now()).await.is_err());
}

#[tokio::test]
async fn source_change_is_rejected_before_publication() {
    use codexu_core::readers::history_integrity::{ensure_history_unchanged, HistoryReadError};
    use codexu_core::readers::index_codex_rollout_files;
    let temp = tempdir().unwrap();
    let sessions = temp.path().join("sessions");
    std::fs::create_dir(&sessions).unwrap();
    let file = sessions.join("rollout-a.jsonl");
    write_usage(&file, "a", 300);
    let index = index_codex_rollout_files(temp.path()).await.unwrap();
    write_usage(&file, "a", 10000);
    assert!(matches!(
        ensure_history_unchanged(&index).await,
        Err(HistoryReadError::SourceChanged)
    ));
}

#[cfg(windows)]
#[tokio::test]
async fn failed_atomic_cache_replacement_preserves_complete_bytes_and_cleans_temporary_file() {
    use codexu_core::readers::history_integrity::write_cache_atomically;
    use std::os::windows::fs::OpenOptionsExt;
    let temp = tempdir().unwrap();
    let cache_file = temp.path().join("cache.json");
    std::fs::write(&cache_file, b"previous complete cache").unwrap();
    let locked = std::fs::OpenOptions::new()
        .read(true)
        .share_mode(0)
        .open(&cache_file)
        .unwrap();
    assert!(write_cache_atomically(&cache_file, b"replacement")
        .await
        .is_err());
    drop(locked);
    assert_eq!(
        std::fs::read(&cache_file).unwrap(),
        b"previous complete cache"
    );
    assert_eq!(std::fs::read_dir(temp.path()).unwrap().count(), 1);
    write_cache_atomically(&cache_file, b"replacement")
        .await
        .unwrap();
    assert_eq!(std::fs::read(&cache_file).unwrap(), b"replacement");
}

#[cfg(windows)]
#[tokio::test]
async fn locked_changed_file_recovers_without_a_second_change() {
    use std::io::Write;
    use std::os::windows::fs::OpenOptionsExt;
    let temp = tempdir().unwrap();
    let sessions = temp.path().join("sessions");
    std::fs::create_dir(&sessions).unwrap();
    let a = sessions.join("rollout-a.jsonl");
    let b = sessions.join("rollout-b.jsonl");
    write_usage(&a, "a", 100);
    write_usage(&b, "b", 200);
    let cache = temp.path().join("cache");
    let reader = CodexTranscriptReader::new(&cache);
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        300
    );
    let complete_generation = published_generation(&cache);
    writeln!(std::fs::OpenOptions::new().append(true).open(&b).unwrap()).unwrap();
    let locked = std::fs::OpenOptions::new()
        .read(true)
        .share_mode(0)
        .open(&b)
        .unwrap();
    assert!(reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .is_err());
    assert_eq!(published_generation(&cache), complete_generation);
    drop(locked);
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        300
    );
}

#[cfg(windows)]
#[tokio::test]
async fn inference_read_failure_does_not_replace_completed_samples() {
    use std::io::Write;
    use std::os::windows::fs::OpenOptionsExt;
    let temp = tempdir().unwrap();
    let sessions = temp.path().join("sessions");
    std::fs::create_dir(&sessions).unwrap();
    let file = sessions.join("rollout-a.jsonl");
    std::fs::write(&file, concat!(
        "{\"timestamp\":\"2026-10-10T00:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"a\"}}\n",
        "{\"timestamp\":\"2026-10-10T00:00:00Z\",\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"a\",\"model\":\"gpt-5\",\"effort\":\"high\"}}\n",
        "{\"timestamp\":\"2026-10-10T00:00:01Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"agent_message\",\"role\":\"assistant\"}}\n",
        "{\"timestamp\":\"2026-10-10T00:00:04Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":0,\"output_tokens\":40,\"reasoning_output_tokens\":10,\"total_tokens\":140}}}}\n"
    )).unwrap();
    let reader = InferencePerformanceReader::new(temp.path().join("cache"));
    let now = chrono::DateTime::parse_from_rfc3339("2026-10-10T00:00:10Z")
        .unwrap()
        .with_timezone(&Utc);
    let first = reader.load(temp.path(), now).await.unwrap().unwrap();
    writeln!(std::fs::OpenOptions::new()
        .append(true)
        .open(&file)
        .unwrap())
    .unwrap();
    let locked = std::fs::OpenOptions::new()
        .read(true)
        .share_mode(0)
        .open(&file)
        .unwrap();
    assert!(reader.load(temp.path(), now).await.is_err());
    drop(locked);
    let restored = reader.load(temp.path(), now).await.unwrap().unwrap();
    assert_eq!(restored.today, first.today);
}
