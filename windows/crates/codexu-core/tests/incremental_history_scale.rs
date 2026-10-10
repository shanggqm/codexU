use chrono::Utc;
use codexu_core::readers::{
    codex_history_index::{database_path, HistoryIndexMetrics},
    CodexTranscriptReader,
};
use std::alloc::{GlobalAlloc, Layout, System};
use std::io::Write;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

struct TrackingAllocator;
static CURRENT: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
unsafe impl GlobalAlloc for TrackingAllocator {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        let p = System.alloc(l);
        if !p.is_null() {
            let n = CURRENT.fetch_add(l.size(), Ordering::Relaxed) + l.size();
            PEAK.fetch_max(n, Ordering::Relaxed);
        }
        p
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        CURRENT.fetch_sub(l.size(), Ordering::Relaxed);
        System.dealloc(p, l)
    }
    unsafe fn realloc(&self, p: *mut u8, l: Layout, n: usize) -> *mut u8 {
        let next = System.realloc(p, l, n);
        if !next.is_null() {
            if n >= l.size() {
                let v = CURRENT.fetch_add(n - l.size(), Ordering::Relaxed) + n - l.size();
                PEAK.fetch_max(v, Ordering::Relaxed);
            } else {
                CURRENT.fetch_sub(l.size() - n, Ordering::Relaxed);
            }
        }
        next
    }
}
#[global_allocator]
static ALLOCATOR: TrackingAllocator = TrackingAllocator;

#[cfg(windows)]
fn process_peak_working_set() -> Option<u64> {
    use windows_sys::Win32::System::{
        ProcessStatus::{GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS},
        Threading::GetCurrentProcess,
    };
    let mut counters = unsafe { std::mem::zeroed::<PROCESS_MEMORY_COUNTERS>() };
    counters.cb = std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
    if unsafe { GetProcessMemoryInfo(GetCurrentProcess(), &mut counters, counters.cb) } == 0 {
        None
    } else {
        Some(counters.PeakWorkingSetSize as u64)
    }
}
#[cfg(not(windows))]
fn process_peak_working_set() -> Option<u64> {
    None
}

#[tokio::test]
#[ignore = "bounded scale probe; run explicitly and preserve its measurements"]
async fn fifty_thousand_event_whole_entry_probe() {
    let temp = tempfile::tempdir().unwrap();
    let sessions = temp.path().join("sessions");
    std::fs::create_dir(&sessions).unwrap();
    let cache = temp.path().join("cache");
    let event = |n: i64| {
        serde_json::json!({"timestamp":"2026-10-09T16:00:00Z","type":"event_msg","payload":{"type":"token_count","turn_id":format!("t-{n}"),"info":{"last_token_usage":{"input_tokens":1,"total_tokens":1},"total_token_usage":{"input_tokens":n,"total_tokens":n}}}}).to_string()+"\n"
    };
    for id in 0..500 {
        let mut file =
            std::fs::File::create(sessions.join(format!("rollout-{id:03}.jsonl"))).unwrap();
        writeln!(file,"{}",serde_json::json!({"timestamp":"2026-10-09T16:00:00Z","type":"session_meta","payload":{"id":format!("fixture-{id}"),"cwd":"fixture-project"}})).unwrap();
        for n in 1..=100 {
            file.write_all(event(n).as_bytes()).unwrap();
        }
    }
    let reader = CodexTranscriptReader::new(&cache);
    let now = Utc::now();
    let mut records = vec![];
    for (phase, expected) in [("cold", 50000), ("hot", 50000), ("append", 50001)] {
        if phase == "append" {
            std::fs::OpenOptions::new()
                .append(true)
                .open(sessions.join("rollout-000.jsonl"))
                .unwrap()
                .write_all(event(101).as_bytes())
                .unwrap();
        }
        let baseline = CURRENT.load(Ordering::Relaxed);
        PEAK.store(baseline, Ordering::Relaxed);
        let start = Instant::now();
        let result = reader
            .load_local_usage(temp.path(), now)
            .await
            .unwrap()
            .unwrap();
        let elapsed = start.elapsed();
        assert_eq!(result.lifetime_tokens, expected);
        let db = rusqlite::Connection::open(database_path(&cache)).unwrap();
        let json: String = db
            .query_row("SELECT metrics_json FROM index_meta", [], |r| r.get(0))
            .unwrap();
        let metrics: HistoryIndexMetrics = serde_json::from_str(&json).unwrap();
        if phase == "hot" {
            assert_eq!(metrics.parser_read_bytes, 0);
            assert_eq!(metrics.parsed_files, 0);
        }
        if phase == "append" {
            assert_eq!(metrics.parser_read_bytes, event(101).len() as u64);
            assert_eq!(metrics.parsed_files, 1);
        }
        let check: String = db
            .query_row("PRAGMA quick_check", [], |r| r.get(0))
            .unwrap();
        assert_eq!(check, "ok");
        let foreign_keys: i64 = db
            .query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| {
                r.get(0)
            })
            .unwrap();
        assert_eq!(foreign_keys, 0);
        let growth = PEAK.load(Ordering::Relaxed).saturating_sub(baseline);
        assert!(
            growth < 256 * 1024 * 1024,
            "50k fixture Rust allocation growth must remain below 256 MiB"
        );
        records.push(serde_json::json!({"phase":phase,"whole_entry_ms":elapsed.as_secs_f64()*1000.0,"peak_rust_allocation_growth_bytes":growth,"process_cumulative_peak_working_set_bytes":process_peak_working_set(),"metrics":metrics,"lifetime_tokens":expected}));
        drop(result);
    }
    let record = serde_json::json!({"profile":if cfg!(debug_assertions){"debug"}else{"release"},"sources":500,"initial_token_events":50000,"sqlite_bytes":std::fs::metadata(database_path(&cache)).unwrap().len(),"rows":records});
    println!("scale_probe={record}");
    if let Ok(path) = std::env::var("CODEXU_INDEX_SCALE_OUTPUT") {
        std::fs::write(path, serde_json::to_vec_pretty(&record).unwrap()).unwrap();
    }
}
