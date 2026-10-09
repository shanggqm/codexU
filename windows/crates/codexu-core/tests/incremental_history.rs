use chrono::Utc;
use codexu_core::readers::codex_history_index::{database_path, HistoryIndexMetrics};
use codexu_core::readers::CodexTranscriptReader;
use codexu_core::readers::HistoryReadError;
use codexu_core::StatisticsTimeZone;
use rusqlite::Connection;
use std::io::Write;
use std::path::Path;
use tempfile::tempdir;

fn metrics(cache: &Path) -> HistoryIndexMetrics {
    let db = Connection::open(database_path(cache)).unwrap();
    let json: String = db
        .query_row("SELECT metrics_json FROM index_meta", [], |r| r.get(0))
        .unwrap();
    serde_json::from_str(&json).unwrap()
}

fn meta(id: &str, parent: Option<&str>) -> String {
    serde_json::json!({"timestamp":"2026-10-10T00:00:00Z","type":"session_meta","payload":{"id":id,"cwd":"fixture-project","forked_from_id":parent}}).to_string()+"\n"
}

fn event(turn: &str, last: i64, cumulative: i64) -> String {
    serde_json::json!({"timestamp":"2026-10-10T00:00:00Z","type":"event_msg","payload":{
        "type":"token_count","turn_id":turn,"info":{
            "last_token_usage":{"input_tokens":last,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":last},
            "total_token_usage":{"input_tokens":cumulative,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":cumulative}}}}).to_string()+"\n"
}

fn setup(root: &Path) -> std::path::PathBuf {
    let sessions = root.join("sessions");
    std::fs::create_dir(&sessions).unwrap();
    sessions.join("rollout-a.jsonl")
}

#[tokio::test]
async fn multiple_model_calls_in_one_turn_and_cumulative_only_history_are_counted_as_deltas() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    std::fs::write(
        &file,
        event("same-turn", 100, 100) + &event("same-turn", 200, 300),
    )
    .unwrap();
    let reader = CodexTranscriptReader::new(temp.path().join("cache"));
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        300
    );
    let first = serde_json::json!({"timestamp":"2026-10-10T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"total_tokens":100}}}});
    let second = serde_json::json!({"timestamp":"2026-10-10T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"total_tokens":300}}}});
    std::fs::write(&file, format!("{first}\n{second}\n")).unwrap();
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

#[tokio::test]
async fn sqlite_checkpoint_survives_restart_and_publication_waits_for_complete_input() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    std::fs::write(&file, event("a", 100, 100)).unwrap();
    let cache = temp.path().join("cache");
    let reader = CodexTranscriptReader::new(&cache);
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        100
    );
    let db = Connection::open(cache.join("codex/history-index.sqlite")).unwrap();
    let published: i64 = db
        .query_row("SELECT published_generation FROM index_meta", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert!(published > 0);
    let mut out = std::fs::OpenOptions::new()
        .append(true)
        .open(&file)
        .unwrap();
    out.write_all(event("b", 200, 300).as_bytes()).unwrap();
    out.write_all(b"{unfinished").unwrap();
    drop(out);
    assert!(reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .is_err());
    let after: i64 = db
        .query_row("SELECT published_generation FROM index_meta", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(after, published);
    // A valid complete rewrite must rebuild staging rather than publish the partial cut.
    std::fs::write(&file, event("a", 100, 100) + &event("b", 200, 300)).unwrap();
    let restarted = CodexTranscriptReader::new(&cache);
    assert_eq!(
        restarted
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        300
    );
    let check: String = db
        .query_row("PRAGMA quick_check", [], |row| row.get(0))
        .unwrap();
    assert_eq!(check, "ok");
}

#[tokio::test]
async fn hot_read_and_append_only_parse_new_complete_bytes_then_match_full_integrity_scan() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    let cache = temp.path().join("cache");
    std::fs::write(&file, meta("a", None) + &event("a", 100, 100)).unwrap();
    let reader = CodexTranscriptReader::new(&cache);
    let first = reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        metrics(&cache).parser_read_bytes,
        std::fs::metadata(&file).unwrap().len()
    );
    let hot = reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(hot, first);
    assert_eq!(metrics(&cache).parser_read_bytes, 0);
    assert_eq!(metrics(&cache).parsed_files, 0);
    let added = event("b", 200, 300);
    std::fs::OpenOptions::new()
        .append(true)
        .open(&file)
        .unwrap()
        .write_all(added.as_bytes())
        .unwrap();
    let incremental = reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(metrics(&cache).parser_read_bytes, added.len() as u64);
    let full = CodexTranscriptReader::new(&cache)
        .with_integrity_scan()
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(incremental, full);
    assert_eq!(full.lifetime_tokens, 300);
}

#[tokio::test]
async fn committed_checkpoint_resumes_after_incomplete_tail_without_recounting() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    let cache = temp.path().join("cache");
    std::fs::write(&file, event("start", 1, 1)).unwrap();
    let reader = CodexTranscriptReader::new(&cache);
    reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap();
    let mut out = std::fs::OpenOptions::new()
        .append(true)
        .open(&file)
        .unwrap();
    for n in 2..=260 {
        out.write_all(event(&format!("t-{n}"), 1, n).as_bytes())
            .unwrap();
    }
    let final_line = event("last", 1, 261);
    out.write_all(&final_line.as_bytes()[..20]).unwrap();
    drop(out);
    assert!(reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .is_err());
    let db = Connection::open(database_path(&cache)).unwrap();
    let checkpoint: i64 = db
        .query_row("SELECT checkpoint FROM source", [], |r| r.get(0))
        .unwrap();
    assert!(checkpoint > 1);
    drop(db);
    std::fs::OpenOptions::new()
        .append(true)
        .open(&file)
        .unwrap()
        .write_all(&final_line.as_bytes()[20..])
        .unwrap();
    let recovered = CodexTranscriptReader::new(&cache)
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered.lifetime_tokens, 261);
    assert!(metrics(&cache).parser_read_bytes < std::fs::metadata(&file).unwrap().len());
}

#[tokio::test]
async fn valid_unterminated_eof_is_stable_on_hot_read_and_safe_on_append() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    let cache = temp.path().join("cache");
    std::fs::write(&file, meta("actual-id", None).trim_end()).unwrap();
    let reader = CodexTranscriptReader::new(&cache);
    let first = reader
        .load_local_summaries(temp.path())
        .await
        .unwrap()
        .unwrap();
    let hot = reader
        .load_local_summaries(temp.path())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(first, hot);
    assert_eq!(first[0].session_id, "actual-id");
    std::fs::OpenOptions::new()
        .append(true)
        .open(&file)
        .unwrap()
        .write_all(("\n".to_owned() + &event("a", 100, 100)).as_bytes())
        .unwrap();
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        100
    );
}

#[tokio::test]
async fn duplicate_live_archive_and_forked_token_prefix_are_not_billed_twice() {
    let temp = tempdir().unwrap();
    let parent = setup(temp.path());
    let cache = temp.path().join("cache");
    let contents = meta("parent", None) + &event("one", 100, 100) + &event("two", 200, 300);
    std::fs::write(&parent, &contents).unwrap();
    let archived = temp.path().join("archived_sessions");
    std::fs::create_dir(&archived).unwrap();
    std::fs::write(archived.join("rollout-copy.jsonl"), &contents).unwrap();
    let child = temp.path().join("sessions/rollout-child.jsonl");
    std::fs::write(
        &child,
        meta("child", Some("parent"))
            + &event("one", 100, 100)
            + &event("two", 200, 300)
            + &event("new", 50, 350),
    )
    .unwrap();
    let usage = CodexTranscriptReader::new(&cache)
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(usage.lifetime_tokens, 350);
    assert_eq!(usage.thread_count, 2);
    assert_eq!(usage.detailed_usage.unwrap().token_event_count, 3);
}

#[tokio::test]
async fn cached_input_is_a_subset_and_counter_reset_or_echo_does_not_inflate_total() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    let cache = temp.path().join("cache");
    let first = serde_json::json!({"timestamp":"2026-10-10T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":10,"total_tokens":120},"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":10,"total_tokens":120}}}});
    std::fs::write(&file, format!("{first}\n{first}\n")).unwrap();
    let reader = CodexTranscriptReader::new(&cache);
    let usage = reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap()
        .unwrap();
    let tokens = &usage.detailed_usage.as_ref().unwrap().lifetime.tokens;
    assert_eq!(usage.lifetime_tokens, 120);
    assert_eq!(tokens.input_tokens, 100);
    assert_eq!(tokens.cached_input_tokens, 40);
    assert_eq!(tokens.output_tokens, 20);
    std::fs::OpenOptions::new()
        .append(true)
        .open(&file)
        .unwrap()
        .write_all(event("reset", 10, 10).as_bytes())
        .unwrap();
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        130
    );
}

#[tokio::test]
async fn local_calendar_archives_and_dst_windows_agree_with_displayed_totals() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    let cache = temp.path().join("cache");
    let mut before: serde_json::Value =
        serde_json::from_str(event("before", 100, 100).trim()).unwrap();
    before["timestamp"] = serde_json::json!("2026-10-09T15:59:59Z");
    let mut after: serde_json::Value =
        serde_json::from_str(event("after", 200, 300).trim()).unwrap();
    after["timestamp"] = serde_json::json!("2026-10-09T16:00:01Z");
    std::fs::write(&file, format!("{before}\n{after}\n")).unwrap();
    let now = chrono::DateTime::parse_from_rfc3339("2026-10-10T02:00:00+08:00")
        .unwrap()
        .with_timezone(&Utc);
    let reader = CodexTranscriptReader::new_with_timezone(
        &cache,
        StatisticsTimeZone::Named(chrono_tz::Asia::Shanghai),
    );
    let usage = reader
        .load_local_usage(temp.path(), now)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(usage.today_tokens, 200);
    assert_eq!(usage.lifetime_tokens, 300);
    let db = Connection::open(database_path(&cache)).unwrap();
    let rows:i64=db.query_row("SELECT count(*) FROM day_archive WHERE generation=(SELECT published_generation FROM index_meta)",[],|r|r.get(0)).unwrap();
    assert_eq!(rows, 2);
    drop(db);
    let mut a: serde_json::Value = serde_json::from_str(event("a", 100, 100).trim()).unwrap();
    a["timestamp"] = serde_json::json!("2026-11-01T04:30:00Z");
    let mut b: serde_json::Value = serde_json::from_str(event("b", 200, 300).trim()).unwrap();
    b["timestamp"] = serde_json::json!("2026-11-02T04:30:00Z");
    std::fs::write(&file, format!("{a}\n{b}\n")).unwrap();
    let now = chrono::DateTime::parse_from_rfc3339("2026-11-01T23:45:00-05:00")
        .unwrap()
        .with_timezone(&Utc);
    let ny = CodexTranscriptReader::new_with_timezone(
        &cache,
        StatisticsTimeZone::Named(chrono_tz::America::New_York),
    );
    assert_eq!(
        ny.load_local_usage(temp.path(), now)
            .await
            .unwrap()
            .unwrap()
            .today_tokens,
        300
    );
}

#[tokio::test]
async fn same_size_rewrite_and_atomic_replacement_rebuild_correctly() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    let cache = temp.path().join("cache");
    std::fs::write(&file, event("a", 100, 100)).unwrap();
    let reader = CodexTranscriptReader::new(&cache);
    reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap();
    std::fs::write(&file, event("a", 200, 200)).unwrap();
    assert_eq!(
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap()
            .lifetime_tokens,
        200
    );
    let replacement = temp.path().join("replacement.jsonl");
    std::fs::write(&replacement, event("a", 50, 50)).unwrap();
    std::fs::remove_file(&file).unwrap();
    std::fs::rename(&replacement, &file).unwrap();
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
async fn writer_lock_blocks_refresh_and_clear_without_changing_published_generation() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    let cache = temp.path().join("cache");
    std::fs::write(&file, event("a", 100, 100)).unwrap();
    let reader = CodexTranscriptReader::new(&cache);
    reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap();
    let generation = metrics(&cache).published_generation;
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(database_path(&cache).with_extension("lock"))
        .unwrap();
    lock.try_lock().unwrap();
    let error = reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap_err();
    assert!(matches!(
        error.downcast_ref::<HistoryReadError>(),
        Some(HistoryReadError::IndexBusy)
    ));
    assert!(codexu_core::readers::codex_history_index::clear(&cache).is_err());
    assert_eq!(metrics(&cache).published_generation, generation);
    drop(lock);
    codexu_core::readers::codex_history_index::clear(&cache).unwrap();
    assert!(!database_path(&cache).exists());
}

#[tokio::test]
async fn runtime_spawn_parent_is_not_mistaken_for_a_copied_fork_prefix() {
    use codexu_core::readers::CodexThreadMetadata;
    use std::collections::HashMap;
    let temp = tempdir().unwrap();
    let parent = setup(temp.path());
    let cache = temp.path().join("cache");
    std::fs::write(&parent, meta("parent", None) + &event("a", 100, 100)).unwrap();
    let child = temp.path().join("sessions/rollout-child.jsonl");
    std::fs::write(&child, meta("child", None) + &event("b", 100, 100)).unwrap();
    let metadata = HashMap::from([(
        "rollout-child.jsonl".to_owned(),
        CodexThreadMetadata {
            thread_id: "child".to_owned(),
            rollout_path: "rollout-child.jsonl".to_owned(),
            title: None,
            cwd: None,
            model: None,
            archived: false,
            created_at: None,
            updated_at: None,
            thread_source: Some("subagent".to_owned()),
            parent_thread_id: Some("parent".to_owned()),
            git_branch: None,
            git_origin_url: None,
        },
    )]);
    let usage = CodexTranscriptReader::new(&cache)
        .load_local_usage_with_metadata(temp.path(), metadata, Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(usage.lifetime_tokens, 200);
}

#[tokio::test]
async fn explicit_integrity_scan_detects_growing_rewrite_outside_prefix_validation_blocks() {
    let temp = tempdir().unwrap();
    let file = setup(temp.path());
    let cache = temp.path().join("cache");
    let mut contents = meta("a", None);
    for n in 1..=150 {
        contents.push_str(&event(&format!("t-{n}"), 1, n));
    }
    std::fs::write(&file, &contents).unwrap();
    let reader = CodexTranscriptReader::new(&cache);
    reader
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap();
    let changed =
        contents.replace(&event("t-70", 1, 70), &event("t-70", 2, 70)) + &event("new", 1, 151);
    std::fs::write(&file, changed).unwrap();
    let verified = reader
        .with_integrity_scan()
        .load_local_usage(temp.path(), Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(verified.lifetime_tokens, 152);
    let stat = metrics(&cache);
    assert_eq!(stat.rebuilt_files, 1);
    assert_eq!(
        stat.parser_read_bytes,
        std::fs::metadata(&file).unwrap().len()
    );
}
