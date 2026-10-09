use chrono::{Duration, TimeZone, Utc};
use codexu_core::{
    readers::{CodexDashboardProvider, InferencePerformanceReader},
    InferencePerformanceArchive, InferencePerformanceBuilder, InferencePerformancePeriod,
    InferencePerformanceSample, StatisticsTimeZone,
};
use std::fs::{FileTimes, OpenOptions};
use std::io::Write;
use std::time::{Duration as StdDuration, Instant};
use tempfile::tempdir;

fn write_session(path: &std::path::Path, lines: Vec<String>) {
    std::fs::write(path, lines.join("\n")).unwrap();
}

fn line(
    timestamp: chrono::DateTime<Utc>,
    envelope_type: &str,
    payload: serde_json::Value,
) -> String {
    let timestamp = timestamp.to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    line_with_raw_timestamp(Some(&timestamp), envelope_type, payload)
}

fn line_with_raw_timestamp(
    timestamp: Option<&str>,
    envelope_type: &str,
    payload: serde_json::Value,
) -> String {
    let mut object = serde_json::json!({
        "type": envelope_type,
        "payload": payload,
    });
    if let Some(timestamp) = timestamp {
        object["timestamp"] = serde_json::json!(timestamp);
    }
    object.to_string()
}

fn turn_context(
    timestamp: chrono::DateTime<Utc>,
    turn_id: &str,
    model: &str,
    effort: Option<&str>,
) -> String {
    let mut payload = serde_json::json!({
        "turn_id": turn_id,
        "cwd": "C:\\Projects\\Inference",
        "model": model,
    });
    if let Some(effort) = effort {
        payload["effort"] = serde_json::json!(effort);
    }
    line(timestamp, "turn_context", payload)
}

fn assistant_output(timestamp: chrono::DateTime<Utc>) -> String {
    line(
        timestamp,
        "response_item",
        serde_json::json!({
            "type": "agent_message",
            "role": "assistant"
        }),
    )
}

fn tool_output_boundary(timestamp: chrono::DateTime<Utc>) -> String {
    line(
        timestamp,
        "response_item",
        serde_json::json!({
            "type": "function_call_output",
        }),
    )
}

fn token_count(
    timestamp: chrono::DateTime<Utc>,
    turn_id: &str,
    output_tokens: i64,
    reasoning_output_tokens: i64,
) -> String {
    line(
        timestamp,
        "event_msg",
        token_count_payload(turn_id, output_tokens, reasoning_output_tokens),
    )
}

fn token_count_payload(
    turn_id: &str,
    output_tokens: i64,
    reasoning_output_tokens: i64,
) -> serde_json::Value {
    serde_json::json!({
        "type": "token_count",
        "turn_id": turn_id,
        "info": {
            "last_token_usage": {
                "input_tokens": 100,
                "cached_input_tokens": 0,
                "output_tokens": output_tokens,
                "reasoning_output_tokens": reasoning_output_tokens,
                "total_tokens": 100 + output_tokens
            },
            "total_token_usage": {
                "input_tokens": 100,
                "cached_input_tokens": 0,
                "output_tokens": output_tokens,
                "reasoning_output_tokens": reasoning_output_tokens,
                "total_tokens": 100 + output_tokens
            }
        }
    })
}

fn token_count_with_info(
    timestamp: chrono::DateTime<Utc>,
    turn_id: &str,
    info: serde_json::Value,
) -> String {
    line(
        timestamp,
        "event_msg",
        serde_json::json!({
            "type": "token_count",
            "turn_id": turn_id,
            "info": info,
        }),
    )
}

fn inference_history(
    snapshot: &codexu_core::CodexDashboardSnapshot,
) -> &codexu_core::InferencePerformanceHistory {
    snapshot
        .codex
        .snapshot
        .local
        .as_ref()
        .expect("local usage remains present")
        .inference_performance
        .as_ref()
        .expect("inference performance is an independent local branch")
}

fn cached_sample(
    sample_id: &str,
    completed_at: chrono::DateTime<Utc>,
    output_tokens: i64,
) -> serde_json::Value {
    serde_json::json!({
        "sample_id": sample_id,
        "completed_at": completed_at.timestamp_millis(),
        "duration_seconds": 2.0,
        "output_tokens": output_tokens,
        "reasoning_output_tokens": 0,
        "model": "gpt-5",
        "effort": "high",
    })
}

fn write_cached_samples(
    cache: &std::path::Path,
    recording_started_at: chrono::DateTime<Utc>,
    samples: Vec<serde_json::Value>,
) -> std::path::PathBuf {
    let cache_file = cache.join("codex").join("inference-performance-v1.json");
    std::fs::create_dir_all(cache_file.parent().unwrap()).unwrap();
    let envelope = serde_json::json!({
        "version": 2,
        "archive": {
            "recording_started_at": recording_started_at.timestamp_millis(),
            "samples_by_source_id": {
                "timezone-fixture": samples,
            }
        },
        "entries": {}
    });
    std::fs::write(&cache_file, serde_json::to_vec(&envelope).unwrap()).unwrap();
    cache_file
}

#[tokio::test]
async fn today_uses_utc_calendar_boundary() {
    let temp = tempdir().unwrap();
    let cache = temp.path().join("cache");
    let day_start = Utc.with_ymd_and_hms(2026, 8, 5, 0, 0, 0).unwrap();
    let now = day_start + Duration::minutes(30);
    write_cached_samples(
        &cache,
        day_start - Duration::milliseconds(1),
        vec![
            cached_sample("before", day_start - Duration::milliseconds(1), 20),
            cached_sample("at-start", day_start, 10),
        ],
    );

    let history = InferencePerformanceReader::new_with_timezone(
        &cache,
        StatisticsTimeZone::Named(chrono_tz::UTC),
    )
    .load(temp.path(), now)
    .await
    .unwrap()
    .expect("history");
    let today = history.today.expect("today");

    assert_eq!(today.total_call_count, 1);
    assert_eq!(today.groups[0].output_tokens, 10);
}

#[tokio::test]
async fn today_uses_positive_offset_calendar_boundary() {
    let temp = tempdir().unwrap();
    let cache = temp.path().join("cache");
    let local_day_start = Utc.with_ymd_and_hms(2026, 8, 4, 16, 0, 0).unwrap();
    let now = local_day_start + Duration::minutes(30);
    write_cached_samples(
        &cache,
        local_day_start - Duration::milliseconds(1),
        vec![
            cached_sample(
                "previous-local-day",
                local_day_start - Duration::milliseconds(1),
                20,
            ),
            cached_sample("local-midnight", local_day_start, 10),
        ],
    );

    let history = InferencePerformanceReader::new_with_timezone(
        &cache,
        StatisticsTimeZone::Named(chrono_tz::Asia::Shanghai),
    )
    .load(temp.path(), now)
    .await
    .unwrap()
    .expect("history");
    let today = history.today.expect("today");

    assert_eq!(today.total_call_count, 1);
    assert_eq!(today.groups[0].output_tokens, 10);
}

#[tokio::test]
async fn today_uses_negative_offset_calendar_boundary() {
    let temp = tempdir().unwrap();
    let cache = temp.path().join("cache");
    let local_day_start = Utc.with_ymd_and_hms(2026, 8, 5, 7, 0, 0).unwrap();
    let now = local_day_start + Duration::minutes(30);
    write_cached_samples(
        &cache,
        local_day_start - Duration::milliseconds(1),
        vec![
            cached_sample(
                "previous-local-day",
                local_day_start - Duration::milliseconds(1),
                20,
            ),
            cached_sample("local-midnight", local_day_start, 10),
        ],
    );

    let history = InferencePerformanceReader::new_with_timezone(
        &cache,
        StatisticsTimeZone::Named(chrono_tz::America::Los_Angeles),
    )
    .load(temp.path(), now)
    .await
    .unwrap()
    .expect("history");
    let today = history.today.expect("today");

    assert_eq!(today.total_call_count, 1);
    assert_eq!(today.groups[0].output_tokens, 10);
}

#[tokio::test]
async fn spring_forward_today_stops_at_the_next_local_midnight() {
    let temp = tempdir().unwrap();
    let cache = temp.path().join("cache");
    let local_day_start = Utc.with_ymd_and_hms(2026, 3, 8, 5, 0, 0).unwrap();
    let next_local_day_start = Utc.with_ymd_and_hms(2026, 3, 9, 4, 0, 0).unwrap();
    let now = next_local_day_start - Duration::minutes(15);
    write_cached_samples(
        &cache,
        local_day_start,
        vec![
            cached_sample("local-midnight", local_day_start, 10),
            cached_sample(
                "late-spring-day",
                next_local_day_start - Duration::minutes(30),
                20,
            ),
            cached_sample(
                "next-local-day",
                next_local_day_start + Duration::minutes(15),
                40,
            ),
        ],
    );

    let history = InferencePerformanceReader::new_with_timezone(
        &cache,
        StatisticsTimeZone::Named(chrono_tz::America::New_York),
    )
    .load(temp.path(), now)
    .await
    .unwrap()
    .expect("history");
    let today = history.today.expect("today");

    assert_eq!(today.total_call_count, 2);
    assert_eq!(today.groups[0].output_tokens, 30);
}

#[tokio::test]
async fn fall_back_today_includes_the_full_twenty_five_hour_local_day() {
    let temp = tempdir().unwrap();
    let cache = temp.path().join("cache");
    let local_day_start = Utc.with_ymd_and_hms(2026, 11, 1, 4, 0, 0).unwrap();
    let next_local_day_start = Utc.with_ymd_and_hms(2026, 11, 2, 5, 0, 0).unwrap();
    let now = next_local_day_start - Duration::minutes(15);
    write_cached_samples(
        &cache,
        local_day_start,
        vec![
            cached_sample("local-midnight", local_day_start, 10),
            cached_sample(
                "first-one-thirty",
                Utc.with_ymd_and_hms(2026, 11, 1, 5, 30, 0).unwrap(),
                20,
            ),
            cached_sample(
                "second-one-thirty",
                Utc.with_ymd_and_hms(2026, 11, 1, 6, 30, 0).unwrap(),
                40,
            ),
            cached_sample(
                "late-fall-day",
                next_local_day_start - Duration::minutes(30),
                80,
            ),
        ],
    );

    let history = InferencePerformanceReader::new_with_timezone(
        &cache,
        StatisticsTimeZone::Named(chrono_tz::America::New_York),
    )
    .load(temp.path(), now)
    .await
    .unwrap()
    .expect("history");
    let today = history.today.expect("today");

    assert_eq!(today.total_call_count, 4);
    assert_eq!(today.groups[0].output_tokens, 150);
}

#[tokio::test]
async fn retention_coverage_and_daily_averages_use_calendar_days_across_dst() {
    let temp = tempdir().unwrap();
    let cache = temp.path().join("cache");
    let now = Utc.with_ymd_and_hms(2026, 3, 20, 16, 0, 0).unwrap();
    let retention_start = Utc.with_ymd_and_hms(2026, 2, 21, 5, 0, 0).unwrap();
    let cache_file = write_cached_samples(
        &cache,
        retention_start - Duration::milliseconds(1),
        vec![
            cached_sample(
                "outside-retention",
                retention_start - Duration::milliseconds(1),
                40,
            ),
            cached_sample("retention-boundary", retention_start, 20),
            cached_sample("current-local-day", now - Duration::minutes(1), 10),
        ],
    );

    let history = InferencePerformanceReader::new_with_timezone(
        &cache,
        StatisticsTimeZone::Named(chrono_tz::America::New_York),
    )
    .load(temp.path(), now)
    .await
    .unwrap()
    .expect("history");

    let seven_days = history.seven_days.expect("seven days");
    assert_eq!(seven_days.coverage_day_count, 7);
    assert_eq!(seven_days.total_call_count, 1);
    assert!((seven_days.groups[0].average_daily_call_count - (1.0 / 7.0)).abs() < 0.000_1);

    let twenty_eight_days = history.twenty_eight_days.expect("twenty eight days");
    assert_eq!(twenty_eight_days.coverage_day_count, 28);
    assert_eq!(twenty_eight_days.total_call_count, 2);
    assert!((twenty_eight_days.groups[0].average_daily_call_count - (2.0 / 28.0)).abs() < 0.000_1);

    let saved: serde_json::Value =
        serde_json::from_slice(&std::fs::read(cache_file).unwrap()).unwrap();
    let saved_samples = saved["archive"]["samples_by_source_id"]["timezone-fixture"]
        .as_array()
        .unwrap();
    assert_eq!(saved_samples.len(), 2, "pre-boundary sample is removed");
    assert!(saved_samples.iter().any(|sample| {
        sample["sample_id"] == "retention-boundary"
            && sample["completed_at"] == retention_start.timestamp_millis()
    }));
}

fn rewrite_session_at(path: &std::path::Path, lines: Vec<String>, modified: std::time::SystemTime) {
    let mut file = OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(path)
        .unwrap();
    file.write_all(lines.join("\n").as_bytes()).unwrap();
    file.set_times(FileTimes::new().set_modified(modified))
        .unwrap();
}

fn single_call_lines(
    now: chrono::DateTime<Utc>,
    source_id: &str,
    output_tokens: i64,
) -> Vec<String> {
    vec![
        line(
            now - Duration::seconds(10),
            "session_meta",
            serde_json::json!({"id": source_id, "cwd": "C:\\Projects\\Inference"}),
        ),
        turn_context(now, "turn-cache", "gpt-5", Some("high")),
        assistant_output(now + Duration::seconds(1)),
        token_count(now + Duration::seconds(4), "turn-cache", output_tokens, 10),
    ]
}

fn single_group_output_tokens(history: &codexu_core::InferencePerformanceHistory) -> i64 {
    history
        .today
        .as_ref()
        .expect("today")
        .groups
        .first()
        .expect("group")
        .output_tokens
}

#[tokio::test]
async fn rollout_cache_hits_and_invalidates_by_size_mtime_and_parser_schema() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    let cache = temp.path().join("cache");
    std::fs::create_dir_all(&archived).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 14, 0, 0).unwrap();
    let session = archived.join("rollout-cache.jsonl");
    write_session(&session, single_call_lines(now, "cache-thread", 40));
    let original_metadata = std::fs::metadata(&session).unwrap();
    let original_size = original_metadata.len();
    let original_modified = original_metadata.modified().unwrap();

    let reader = InferencePerformanceReader::new(&cache);
    let first_started = Instant::now();
    let first = reader.load(temp.path(), now).await.unwrap().expect("first");
    let first_elapsed = first_started.elapsed();
    assert_eq!(single_group_output_tokens(&first), 40);

    rewrite_session_at(
        &session,
        single_call_lines(now, "cache-thread", 90),
        original_modified,
    );
    assert_eq!(std::fs::metadata(&session).unwrap().len(), original_size);
    let cached_started = Instant::now();
    let cached = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("cached");
    let cached_elapsed = cached_started.elapsed();
    assert_eq!(
        single_group_output_tokens(&cached),
        40,
        "unchanged path, size, and mtime must reuse the cached parse"
    );

    let cache_file = cache.join("codex").join("inference-performance-v1.json");
    let cache_bytes = std::fs::read(&cache_file).unwrap();
    let cache_json: serde_json::Value = serde_json::from_slice(&cache_bytes).unwrap();
    let entries = cache_json["entries"].as_object().expect("cache entries");
    assert_eq!(entries.len(), 1);
    let (cache_key, entry) = entries.iter().next().expect("cache entry");
    assert!(cache_key.starts_with("rollout-"));
    assert!(
        !String::from_utf8_lossy(&cache_bytes).contains(session.to_string_lossy().as_ref()),
        "the persisted cache must not contain the rollout path"
    );
    assert_eq!(entry["file_size"], original_size);
    assert!(entry["modification_time_ns"].as_i64().is_some());
    assert_eq!(entry["parser_version"], 3);

    rewrite_session_at(
        &session,
        single_call_lines(now, "cache-thread", 100),
        original_modified,
    );
    let size_changed = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("size changed");
    assert_eq!(single_group_output_tokens(&size_changed), 100);

    let newer_modified = original_modified + StdDuration::from_secs(60);
    rewrite_session_at(
        &session,
        single_call_lines(now, "cache-thread", 200),
        newer_modified,
    );
    let mtime_changed = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("mtime changed");
    assert_eq!(single_group_output_tokens(&mtime_changed), 200);

    let mut cache_json: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&cache_file).unwrap()).unwrap();
    cache_json["entries"][cache_key]["parser_version"] = serde_json::json!(0);
    std::fs::write(&cache_file, serde_json::to_vec(&cache_json).unwrap()).unwrap();
    rewrite_session_at(
        &session,
        single_call_lines(now, "cache-thread", 300),
        newer_modified,
    );
    let schema_changed = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("schema changed");
    assert_eq!(single_group_output_tokens(&schema_changed), 300);

    eprintln!(
        "representative_cache_fixture first_ms={} cached_ms={}",
        first_elapsed.as_millis(),
        cached_elapsed.as_millis()
    );
}

#[tokio::test]
async fn live_and_archive_rollout_caches_invalidate_independently() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    let sessions = temp.path().join("sessions");
    let cache = temp.path().join("cache");
    std::fs::create_dir_all(&archived).unwrap();
    std::fs::create_dir_all(&sessions).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 14, 30, 0).unwrap();
    let archive_rollout = archived.join("rollout-archive-cache.jsonl");
    let live_rollout = sessions.join("rollout-live-cache.jsonl");
    write_session(
        &archive_rollout,
        single_call_lines(now, "archive-thread", 40),
    );
    write_session(&live_rollout, single_call_lines(now, "live-thread", 60));
    let archive_modified = std::fs::metadata(&archive_rollout)
        .unwrap()
        .modified()
        .unwrap();
    let live_modified = std::fs::metadata(&live_rollout)
        .unwrap()
        .modified()
        .unwrap();

    let reader = InferencePerformanceReader::new(&cache);
    let first = reader.load(temp.path(), now).await.unwrap().expect("first");
    assert_eq!(single_group_output_tokens(&first), 100);
    assert_eq!(first.today.as_ref().unwrap().total_call_count, 2);

    rewrite_session_at(
        &archive_rollout,
        single_call_lines(now, "archive-thread", 70),
        archive_modified,
    );
    rewrite_session_at(
        &live_rollout,
        single_call_lines(now, "live-thread", 80),
        live_modified,
    );
    let both_cached = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("both cached");
    assert_eq!(
        single_group_output_tokens(&both_cached),
        100,
        "unchanged live and archive fingerprints must both hit cache"
    );

    rewrite_session_at(
        &live_rollout,
        single_call_lines(now, "live-thread", 80),
        live_modified + StdDuration::from_secs(60),
    );
    let live_changed = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("live changed");
    assert_eq!(
        single_group_output_tokens(&live_changed),
        120,
        "only the changed live rollout should be reparsed"
    );

    rewrite_session_at(
        &archive_rollout,
        single_call_lines(now, "archive-thread", 70),
        archive_modified + StdDuration::from_secs(60),
    );
    let archive_changed = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("archive changed");
    assert_eq!(
        single_group_output_tokens(&archive_changed),
        150,
        "only the changed archive rollout should be reparsed"
    );
}

#[tokio::test]
async fn dashboard_builds_privacy_safe_inference_performance_branch() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    std::fs::create_dir_all(&archived).unwrap();

    let today = Utc.with_ymd_and_hms(2026, 8, 5, 12, 0, 0).unwrap();
    let prior_day = today - Duration::days(1);
    let session = archived.join("rollout-inference.jsonl");

    write_session(
        &session,
        vec![
            line(
                prior_day - Duration::seconds(10),
                "session_meta",
                serde_json::json!({"id": "thread-inference", "cwd": "C:\\Projects\\Inference"}),
            ),
            turn_context(prior_day, "turn-prior", "gpt-5", Some("High")),
            assistant_output(prior_day + Duration::seconds(1)),
            token_count(prior_day + Duration::seconds(8), "turn-prior", 80, 20),
            turn_context(today, "turn-1", "gpt-5", Some("High")),
            assistant_output(today + Duration::seconds(1)),
            token_count(today + Duration::seconds(2), "turn-1", 20, 5),
            tool_output_boundary(today + Duration::seconds(10)),
            assistant_output(today + Duration::seconds(13)),
            token_count(today + Duration::seconds(14), "turn-2", 40, 60),
            token_count(today + Duration::milliseconds(14_500), "turn-2", 40, 60),
            turn_context(
                today + Duration::seconds(20),
                "turn-missing-effort",
                "gpt-5",
                None,
            ),
            assistant_output(today + Duration::seconds(21)),
            token_count(today + Duration::seconds(22), "turn-missing-effort", 10, 2),
            turn_context(
                today + Duration::seconds(30),
                "turn-noise",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(today + Duration::milliseconds(30_020)),
            token_count(today + Duration::milliseconds(30_050), "turn-noise", 10, 2),
            turn_context(
                today + Duration::seconds(40),
                "turn-no-output",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(today + Duration::seconds(41)),
            token_count(today + Duration::seconds(42), "turn-no-output", 0, 0),
            turn_context(
                today + Duration::seconds(50),
                "turn-no-model-output",
                "gpt-5",
                Some("high"),
            ),
            token_count(today + Duration::seconds(52), "turn-no-model-output", 10, 2),
        ],
    );

    let provider = CodexDashboardProvider::new(temp.path(), temp.path().join("cache"));
    let snapshot = provider
        .load_dashboard_snapshot(today)
        .await
        .unwrap()
        .expect("snapshot");

    let local = snapshot
        .codex
        .snapshot
        .local
        .as_ref()
        .expect("local usage remains present");
    let inference = local
        .inference_performance
        .as_ref()
        .expect("inference performance is an independent local branch");
    assert!(
        local.detailed_usage.is_some(),
        "existing detailed usage remains usable"
    );

    let today_period = inference.today.as_ref().expect("today period");
    assert_eq!(today_period.period, InferencePerformancePeriod::Today);
    assert_eq!(today_period.total_call_count, 2);
    let today_group = today_period.groups.first().expect("today group");
    assert_eq!(today_group.model, "gpt-5");
    assert_eq!(today_group.effort, "high");
    assert_eq!(today_group.call_count, 2);
    assert_eq!(today_group.output_tokens, 60);
    assert_eq!(
        today_group.reasoning_output_tokens, 45,
        "reasoning tokens are clamped to output-token bounds"
    );
    assert!(
        (today_group.average_duration_seconds - 3.0).abs() < 0.000_1,
        "tool-output boundary excludes tool execution time"
    );

    let seven_days = inference.seven_days.as_ref().expect("seven-day period");
    assert_eq!(seven_days.coverage_day_count, 2);
    assert_eq!(
        seven_days.total_call_count, 3,
        "duplicate and invalid samples are excluded"
    );
    let group = seven_days.groups.first().expect("seven-day group");
    assert!((group.average_daily_call_count - 1.5).abs() < 0.000_1);
    assert!((group.p50_duration_seconds - 4.0).abs() < 0.000_1);
    assert!((group.p90_duration_seconds - 7.2).abs() < 0.000_1);
    assert!(
        (group.effective_output_tokens_per_second - 10.0).abs() < 0.000_1,
        "effective throughput is total output tokens over full call duration"
    );

    let json = serde_json::to_value(&snapshot).unwrap();
    assert!(json["codex"]["snapshot"]["local"]["inference_performance"].is_object());
    assert!(
        json["codex"]["snapshot"]["local"]["detailed_usage"]["inference_performance"].is_null(),
        "inference fields must not be overloaded into DetailedUsage"
    );
}

#[tokio::test]
async fn keeps_multiple_valid_model_calls_inside_one_turn() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    std::fs::create_dir_all(&archived).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 15, 0, 0).unwrap();
    let session = archived.join("rollout-multi-call.jsonl");
    write_session(
        &session,
        vec![
            line(
                now - Duration::seconds(10),
                "session_meta",
                serde_json::json!({"id": "thread-multi-call", "cwd": "C:\\Projects\\Inference"}),
            ),
            turn_context(now, "turn-shared", "gpt-5", Some("medium")),
            assistant_output(now + Duration::seconds(1)),
            token_count(now + Duration::seconds(3), "turn-shared", 30, 3),
            tool_output_boundary(now + Duration::seconds(10)),
            assistant_output(now + Duration::seconds(11)),
            token_count(now + Duration::seconds(15), "turn-shared", 80, 20),
        ],
    );

    let provider = CodexDashboardProvider::new(temp.path(), temp.path().join("cache"));
    let snapshot = provider
        .load_dashboard_snapshot(now)
        .await
        .unwrap()
        .expect("snapshot");

    let today = inference_history(&snapshot).today.as_ref().expect("today");
    assert_eq!(
        today.total_call_count, 2,
        "two valid model calls in one turn must not collapse to one sample"
    );
    let group = today.groups.first().expect("group");
    assert_eq!(group.call_count, 2);
    assert_eq!(group.output_tokens, 110);
    assert!((group.average_duration_seconds - 4.0).abs() < 0.000_1);
    assert!((group.p50_duration_seconds - 4.0).abs() < 0.000_1);
    assert!((group.effective_output_tokens_per_second - (110.0 / 8.0)).abs() < 0.000_1);
}

#[tokio::test]
async fn copied_rollout_between_live_and_archive_dirs_is_reconciled_once() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    let sessions = temp.path().join("sessions");
    std::fs::create_dir_all(&archived).unwrap();
    std::fs::create_dir_all(&sessions).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 16, 0, 0).unwrap();
    let lines = vec![
        line(
            now - Duration::seconds(10),
            "session_meta",
            serde_json::json!({"id": "stable-thread-id", "cwd": "C:\\Projects\\Inference"}),
        ),
        turn_context(now, "turn-copy", "gpt-5", Some("high")),
        assistant_output(now + Duration::seconds(1)),
        token_count(now + Duration::seconds(4), "turn-copy", 40, 10),
    ];
    write_session(&archived.join("rollout-copy.jsonl"), lines.clone());
    write_session(&sessions.join("rollout-copy.jsonl"), lines);

    let provider = CodexDashboardProvider::new(temp.path(), temp.path().join("cache"));
    let snapshot = provider
        .load_dashboard_snapshot(now)
        .await
        .unwrap()
        .expect("snapshot");

    let today = inference_history(&snapshot).today.as_ref().expect("today");
    assert_eq!(
        today.total_call_count, 1,
        "the same rollout observed in sessions and archived_sessions should not double-count"
    );
}

#[tokio::test]
async fn merges_partial_live_and_archive_files_for_same_session() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    let sessions = temp.path().join("sessions");
    std::fs::create_dir_all(&archived).unwrap();
    std::fs::create_dir_all(&sessions).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 16, 30, 0).unwrap();
    let session_meta = line(
        now - Duration::seconds(10),
        "session_meta",
        serde_json::json!({"id": "stable-merge-thread", "cwd": "C:\\Projects\\Inference"}),
    );
    let archive_sample = vec![
        turn_context(now, "turn-archive", "gpt-5", Some("high")),
        assistant_output(now + Duration::seconds(1)),
        token_count(now + Duration::seconds(4), "turn-archive", 40, 10),
    ];
    let shared_live_sample = vec![
        turn_context(
            now + Duration::seconds(5),
            "turn-live",
            "gpt-5",
            Some("high"),
        ),
        assistant_output(now + Duration::seconds(6)),
        token_count(now + Duration::seconds(9), "turn-live", 60, 20),
    ];

    let mut archive_lines = vec![session_meta.clone()];
    archive_lines.extend(archive_sample);
    archive_lines.extend(shared_live_sample.clone());
    write_session(&archived.join("rollout-merge.jsonl"), archive_lines);

    let mut live_lines = vec![session_meta];
    live_lines.extend(shared_live_sample);
    write_session(&sessions.join("rollout-merge.jsonl"), live_lines);

    let provider = CodexDashboardProvider::new(temp.path(), temp.path().join("cache"));
    let snapshot = provider
        .load_dashboard_snapshot(now)
        .await
        .unwrap()
        .expect("snapshot");

    let today = inference_history(&snapshot).today.as_ref().expect("today");
    assert_eq!(
        today.total_call_count, 2,
        "partial live data must merge with archive data without dropping or duplicating samples"
    );
    let group = today.groups.first().expect("group");
    assert_eq!(group.call_count, 2);
    assert_eq!(group.output_tokens, 100);
}

#[tokio::test]
async fn archive_disk_load_save_and_safe_degradation() {
    let temp = tempdir().unwrap();
    let cache = temp.path().join("cache");
    let cache_file = cache.join("codex").join("inference-performance-v1.json");
    std::fs::create_dir_all(cache_file.parent().unwrap()).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 17, 0, 0).unwrap();
    let sample = serde_json::json!({
        "sample_id": "disk-sample",
        "completed_at": (now + Duration::seconds(2)).timestamp_millis(),
        "duration_seconds": 2.0,
        "output_tokens": 20,
        "reasoning_output_tokens": 5,
        "model": "gpt-5",
        "effort": "high",
    });
    let valid_cache = serde_json::json!({
        "version": 2,
        "archive": {
            "recording_started_at": now.timestamp_millis(),
            "samples_by_source_id": {
                "stable-thread-id": [sample],
            }
        },
        "entries": {}
    });
    std::fs::write(&cache_file, serde_json::to_vec(&valid_cache).unwrap()).unwrap();

    let reader = InferencePerformanceReader::new(&cache);
    let loaded = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("loaded history");
    assert_eq!(loaded.today.as_ref().unwrap().total_call_count, 1);
    let saved: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&cache_file).unwrap()).unwrap();
    assert_eq!(saved["version"], 2);

    std::fs::write(&cache_file, b"not-json").unwrap();
    assert!(
        reader.load(temp.path(), now).await.unwrap().is_none(),
        "corrupt archive must safely degrade to empty data"
    );

    let version_mismatch = serde_json::json!({
        "version": 999,
        "archive": {
            "recording_started_at": now.timestamp_millis(),
            "samples_by_source_id": {
                "stable-thread-id": [sample],
            }
        },
        "entries": {}
    });
    std::fs::write(&cache_file, serde_json::to_vec(&version_mismatch).unwrap()).unwrap();
    assert!(
        reader.load(temp.path(), now).await.unwrap().is_none(),
        "version mismatch must safely degrade to empty data"
    );

    std::fs::write(&cache_file, vec![b'x'; 33 * 1024 * 1024]).unwrap();
    assert!(
        reader.load(temp.path(), now).await.unwrap().is_none(),
        "oversized archive must safely degrade to empty data"
    );
}

#[tokio::test]
async fn ignores_inference_events_with_missing_invalid_or_payload_only_timestamps() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    std::fs::create_dir_all(&archived).unwrap();

    let now = Utc::now();
    let session = archived.join("rollout-invalid-inference-timestamps.jsonl");
    let mut payload_timestamp_only = token_count_payload("turn-payload-time", 30, 3);
    payload_timestamp_only["timestamp"] = serde_json::json!(
        (now - Duration::seconds(28)).to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
    );

    write_session(
        &session,
        vec![
            line_with_raw_timestamp(
                None,
                "session_meta",
                serde_json::json!({"id": "thread-invalid-inference-timestamps"}),
            ),
            turn_context(
                now - Duration::seconds(50),
                "turn-missing-time",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(now - Duration::seconds(49)),
            line_with_raw_timestamp(
                None,
                "event_msg",
                token_count_payload("turn-missing-time", 10, 1),
            ),
            turn_context(
                now - Duration::seconds(40),
                "turn-invalid-time",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(now - Duration::seconds(39)),
            line_with_raw_timestamp(
                Some("not-a-timestamp"),
                "event_msg",
                token_count_payload("turn-invalid-time", 20, 2),
            ),
            turn_context(
                now - Duration::seconds(30),
                "turn-payload-time",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(now - Duration::seconds(29)),
            line_with_raw_timestamp(None, "event_msg", payload_timestamp_only),
            turn_context(
                now - Duration::seconds(20),
                "turn-missing-output-time",
                "gpt-5",
                Some("high"),
            ),
            line_with_raw_timestamp(
                None,
                "response_item",
                serde_json::json!({"type": "agent_message", "role": "assistant"}),
            ),
            token_count(
                now - Duration::seconds(17),
                "turn-missing-output-time",
                40,
                4,
            ),
            turn_context(
                now - Duration::seconds(12),
                "turn-invalid-boundary-time",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(now - Duration::seconds(11)),
            line_with_raw_timestamp(
                Some("still-not-a-timestamp"),
                "response_item",
                serde_json::json!({"type": "function_call_output"}),
            ),
            assistant_output(now - Duration::seconds(9)),
            token_count(
                now - Duration::seconds(8),
                "turn-invalid-boundary-time",
                50,
                5,
            ),
            turn_context(
                now - Duration::seconds(4),
                "turn-valid",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(now - Duration::seconds(3)),
            token_count(now - Duration::seconds(1), "turn-valid", 60, 6),
        ],
    );

    let reader = InferencePerformanceReader::new(temp.path().join("cache"));
    let history = reader
        .load(temp.path(), now)
        .await
        .unwrap()
        .expect("the final valid inference call should remain");
    let today = history.today.as_ref().expect("today");
    assert_eq!(today.total_call_count, 1);
    assert_eq!(today.groups.first().unwrap().output_tokens, 60);
}

#[tokio::test]
async fn ignores_token_events_with_missing_info_last_usage_or_required_numeric_fields() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    std::fs::create_dir_all(&archived).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 18, 0, 0).unwrap();
    let session = archived.join("rollout-invalid-token-events.jsonl");
    write_session(
        &session,
        vec![
            line(
                now - Duration::seconds(10),
                "session_meta",
                serde_json::json!({"id": "thread-invalid-token-events", "cwd": "C:\\Projects\\Inference"}),
            ),
            turn_context(now, "turn-missing-info", "gpt-5", Some("high")),
            assistant_output(now + Duration::seconds(1)),
            line(
                now + Duration::seconds(3),
                "event_msg",
                serde_json::json!({"type": "token_count", "turn_id": "turn-missing-info"}),
            ),
            turn_context(
                now + Duration::seconds(10),
                "turn-missing-last",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(now + Duration::seconds(11)),
            token_count_with_info(
                now + Duration::seconds(13),
                "turn-missing-last",
                serde_json::json!({
                    "total_token_usage": {
                        "input_tokens": 100,
                        "cached_input_tokens": 0,
                        "output_tokens": 20,
                        "reasoning_output_tokens": 5,
                        "total_tokens": 120
                    }
                }),
            ),
            turn_context(
                now + Duration::seconds(20),
                "turn-missing-output",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(now + Duration::seconds(21)),
            token_count_with_info(
                now + Duration::seconds(23),
                "turn-missing-output",
                serde_json::json!({
                    "last_token_usage": {
                        "input_tokens": 100,
                        "cached_input_tokens": 0,
                        "reasoning_output_tokens": 5,
                        "total_tokens": 120
                    }
                }),
            ),
            turn_context(
                now + Duration::seconds(30),
                "turn-valid",
                "gpt-5",
                Some("high"),
            ),
            assistant_output(now + Duration::seconds(31)),
            token_count(now + Duration::seconds(34), "turn-valid", 40, 10),
        ],
    );

    let provider = CodexDashboardProvider::new(temp.path(), temp.path().join("cache"));
    let snapshot = provider
        .load_dashboard_snapshot(now)
        .await
        .unwrap()
        .expect("snapshot");

    let today = inference_history(&snapshot).today.as_ref().expect("today");
    assert_eq!(
        today.total_call_count, 1,
        "only the event with info.last_token_usage and required numeric token fields should be retained"
    );
    assert_eq!(today.groups.first().unwrap().output_tokens, 40);
}

#[tokio::test]
async fn cumulative_only_token_event_advances_boundary_before_a_followup_response() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    std::fs::create_dir_all(&archived).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 18, 0, 0).unwrap();
    let session = archived.join("rollout-invalid-boundary.jsonl");
    write_session(
        &session,
        vec![
            line(
                now - Duration::seconds(10),
                "session_meta",
                serde_json::json!({"id": "thread-invalid-boundary", "cwd": "C:\\Projects\\Inference"}),
            ),
            turn_context(now, "turn-invalid-boundary", "gpt-5", Some("high")),
            assistant_output(now + Duration::seconds(1)),
            token_count_with_info(
                now + Duration::seconds(3),
                "turn-invalid-boundary",
                serde_json::json!({
                    "total_token_usage": {
                        "input_tokens": 100,
                        "cached_input_tokens": 0,
                        "output_tokens": 20,
                        "reasoning_output_tokens": 5,
                        "total_tokens": 120
                    }
                }),
            ),
            assistant_output(now + Duration::milliseconds(3_010)),
            token_count(
                now + Duration::milliseconds(3_050),
                "turn-invalid-boundary",
                40,
                10,
            ),
        ],
    );

    let provider = CodexDashboardProvider::new(temp.path(), temp.path().join("cache"));
    let snapshot = provider
        .load_dashboard_snapshot(now + Duration::minutes(1))
        .await
        .unwrap()
        .expect("snapshot");
    let local = snapshot.codex.snapshot.local.as_ref().expect("local usage");

    assert!(
        local.inference_performance.is_none(),
        "the cumulative-only token event must advance the boundary so a 40ms followup cannot inherit the earlier call duration"
    );
}

#[tokio::test]
async fn data_less_token_event_does_not_shift_the_next_call_start() {
    let temp = tempdir().unwrap();
    let archived = temp.path().join("archived_sessions");
    std::fs::create_dir_all(&archived).unwrap();

    let now = Utc.with_ymd_and_hms(2026, 8, 5, 18, 0, 0).unwrap();
    let session = archived.join("rollout-data-less-boundary.jsonl");
    write_session(
        &session,
        vec![
            line(
                now - Duration::seconds(10),
                "session_meta",
                serde_json::json!({"id": "thread-data-less-boundary", "cwd": "C:\\Projects\\Inference"}),
            ),
            turn_context(now, "turn-data-less-boundary", "gpt-5", Some("high")),
            token_count_with_info(
                now + Duration::seconds(2),
                "turn-data-less-boundary",
                serde_json::Value::Null,
            ),
            assistant_output(now + Duration::seconds(3)),
            token_count(
                now + Duration::seconds(5),
                "turn-data-less-boundary",
                40,
                10,
            ),
        ],
    );

    let provider = CodexDashboardProvider::new(temp.path(), temp.path().join("cache"));
    let snapshot = provider
        .load_dashboard_snapshot(now + Duration::minutes(1))
        .await
        .unwrap()
        .expect("snapshot");
    let today = inference_history(&snapshot).today.as_ref().expect("today");

    assert_eq!(today.total_call_count, 1);
    let group = today.groups.first().expect("inference group");
    assert!(
        (group.average_duration_seconds - 5.0).abs() < 0.000_1,
        "a token event without valid usage data must not reset the active call boundary"
    );
}

#[test]
fn inference_archive_deduplicates_and_bounds_retention() {
    let base = Utc.with_ymd_and_hms(2026, 8, 5, 12, 0, 0).unwrap();
    let retention_start = base - Duration::days(28);
    let mut archive = InferencePerformanceArchive::new(base);
    let sample = |id: &str, completed_at: chrono::DateTime<Utc>, duration_seconds: f64| {
        InferencePerformanceSample {
            sample_id: id.to_string(),
            completed_at,
            duration_seconds,
            output_tokens: 10,
            reasoning_output_tokens: 2,
            model: "gpt-5".to_string(),
            effort: "high".to_string(),
        }
    };

    archive.replace_samples(
        "rollout-a",
        vec![
            sample("old", retention_start - Duration::seconds(1), 2.0),
            sample("noise", base, 0.05),
            sample("a", base - Duration::seconds(3), 2.0),
            sample("a", base - Duration::seconds(2), 2.0),
            sample("b", base - Duration::seconds(1), 3.0),
        ],
        retention_start,
    );

    assert_eq!(
        archive.samples().len(),
        2,
        "old, noisy, and duplicate samples are discarded"
    );
    archive.compact(retention_start, 1);
    assert_eq!(
        archive.samples().len(),
        1,
        "archive enforces maximum sample count"
    );
    assert_eq!(
        archive.samples()[0].sample_id,
        "b",
        "newest sample is retained first"
    );
}

#[test]
fn inference_archive_compaction_preserves_recording_coverage_across_idle_days() {
    let now = Utc.with_ymd_and_hms(2026, 8, 29, 12, 0, 0).unwrap();
    let recording_started_at = Utc.with_ymd_and_hms(2026, 8, 1, 12, 0, 0).unwrap();
    let retention_start = Utc.with_ymd_and_hms(2026, 8, 2, 0, 0, 0).unwrap();
    let mut archive = InferencePerformanceArchive::new(recording_started_at);
    archive.replace_samples(
        "rollout-idle-gap",
        vec![InferencePerformanceSample {
            sample_id: "idle-gap-sample".to_string(),
            completed_at: Utc.with_ymd_and_hms(2026, 8, 20, 12, 0, 0).unwrap(),
            duration_seconds: 3.0,
            output_tokens: 30,
            reasoning_output_tokens: 5,
            model: "gpt-5".to_string(),
            effort: "high".to_string(),
        }],
        retention_start,
    );

    archive.compact(retention_start, 50_000);

    assert_eq!(archive.recording_started_at, recording_started_at);
    let history = InferencePerformanceBuilder::make_history(
        &archive.samples(),
        archive.recording_started_at,
        now,
        StatisticsTimeZone::Named(chrono_tz::UTC),
    )
    .expect("history");
    let period = history.twenty_eight_days.expect("twenty-eight days");
    assert_eq!(period.coverage_day_count, 28);
    assert!((period.groups[0].average_daily_call_count - (1.0 / 28.0)).abs() < 1e-12);
}
