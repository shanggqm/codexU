use std::collections::{HashMap, HashSet};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::{Duration, UNIX_EPOCH};

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::codex_history_parser::{Fact, ParserState};
use super::codex_state::CodexThreadMetadata;
use super::codex_transcript::CodexTranscriptSummary;
use super::common::{CodexRolloutIndexEntry, MAX_LINE_BYTES, READ_CHUNK_BYTES};
use super::history_integrity::HistoryReadError;
use crate::models::PricedTokenUsage;
use crate::StatisticsTimeZone;

const CHECKPOINT_LINES: usize = 128;
const DATABASE_BYTES: u64 = 256 * 1024 * 1024;
const CACHE_BYTES: u64 = 1024 * 1024 * 1024;
const MAX_FACTS: i64 = 500_000;

#[derive(Default, Debug, Serialize, Deserialize)]
pub struct HistoryIndexMetrics {
    pub parser_read_bytes: u64,
    pub validation_read_bytes: u64,
    pub parsed_files: u64,
    pub checkpoint_commits: u64,
    pub rebuilt_files: u64,
    pub published_generation: i64,
}

struct Source {
    id: i64,
    identity: String,
    size: i64,
    modified: i64,
    offset: i64,
    head: String,
    boundary: String,
    state: ParserState,
    complete: bool,
}

struct Stamp {
    identity: String,
    size: i64,
    modified: i64,
    head: String,
    boundary: String,
}

pub fn database_path(cache: &Path) -> PathBuf {
    cache.join("codex/history-index.sqlite")
}

pub fn clear(cache: &Path) -> anyhow::Result<()> {
    let path = database_path(cache);
    if !path.parent().unwrap().exists() {
        return Ok(());
    }
    let ownership = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path.with_extension("lock"))
        .map_err(|_| HistoryReadError::CacheUnavailable)?;
    ownership
        .try_lock()
        .map_err(|_| HistoryReadError::IndexBusy)?;
    for suffix in ["", "-journal", "-wal", "-shm"] {
        let managed = PathBuf::from(format!("{}{suffix}", path.to_string_lossy()));
        match std::fs::remove_file(managed) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Err(HistoryReadError::CacheUnavailable.into()),
        }
    }
    Ok(())
}

pub(crate) fn load(
    root: &Path,
    cache: &Path,
    index: &[CodexRolloutIndexEntry],
    metadata: &HashMap<String, CodexThreadMetadata>,
    statistics: StatisticsTimeZone,
    now: DateTime<Utc>,
    integrity_scan: bool,
) -> anyhow::Result<Vec<CodexTranscriptSummary>> {
    load_inner(
        root,
        cache,
        index,
        metadata,
        statistics,
        now,
        integrity_scan,
        DATABASE_BYTES,
    )
    .map_err(|error| {
        if let Some(sql) = error.downcast_ref::<rusqlite::Error>() {
            if let rusqlite::Error::SqliteFailure(code, _) = sql {
                return match code.code {
                    rusqlite::ErrorCode::DatabaseBusy | rusqlite::ErrorCode::DatabaseLocked => {
                        HistoryReadError::IndexBusy.into()
                    }
                    rusqlite::ErrorCode::DiskFull => HistoryReadError::CacheFull.into(),
                    _ => HistoryReadError::CacheUnavailable.into(),
                };
            }
            return HistoryReadError::CacheUnavailable.into();
        }
        if error.is::<HistoryReadError>() {
            error
        } else {
            HistoryReadError::CacheUnavailable.into()
        }
    })
}

fn load_inner(
    root: &Path,
    cache: &Path,
    index: &[CodexRolloutIndexEntry],
    metadata: &HashMap<String, CodexThreadMetadata>,
    statistics: StatisticsTimeZone,
    now: DateTime<Utc>,
    integrity_scan: bool,
    database_bytes: u64,
) -> anyhow::Result<Vec<CodexTranscriptSummary>> {
    let path = database_path(cache);
    std::fs::create_dir_all(path.parent().unwrap())
        .map_err(|_| HistoryReadError::CacheUnavailable)?;
    let ownership = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path.with_extension("lock"))
        .map_err(|_| HistoryReadError::CacheUnavailable)?;
    ownership
        .try_lock()
        .map_err(|_| HistoryReadError::IndexBusy)?;
    check_budget(&path)?;
    let mut db = Connection::open(&path)?;
    db.busy_timeout(Duration::ZERO)?;
    db.execute_batch("PRAGMA foreign_keys=ON; PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA cache_size=-8192; PRAGMA temp_store=FILE; PRAGMA journal_size_limit=16777216;")?;
    let schema: i64 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if schema != 0 && schema != 1 {
        return Err(HistoryReadError::CacheUnavailable.into());
    }
    db.execute_batch(SCHEMA)?;
    let page_size: i64 = db.query_row("PRAGMA page_size", [], |r| r.get(0))?;
    db.pragma_update(
        None,
        "max_page_count",
        (database_bytes / page_size as u64) as i64,
    )?;
    let root_id = hex(root.to_string_lossy().as_bytes());
    let scan: i64 = db.query_row(
        "UPDATE index_meta SET scan_serial=scan_serial+1 RETURNING scan_serial",
        [],
        |r| r.get(0),
    )?;
    let mut metrics = HistoryIndexMetrics::default();
    for entry in index {
        refresh_source(
            &mut db,
            &root_id,
            scan,
            entry,
            metadata,
            &mut metrics,
            integrity_scan,
        )?;
        let facts: i64 = db.query_row("SELECT fact_count FROM index_meta", [], |r| r.get(0))?;
        if facts > MAX_FACTS {
            return Err(HistoryReadError::ResourceLimited.into());
        }
        check_budget(&path)?;
    }
    // Verify every path again before selecting the staged facts for publication.
    for entry in index {
        verify_source(&db, &root_id, entry)?;
    }
    let summaries = materialize(&db, &root_id, scan)?;
    publish_days(
        &mut db,
        &summaries,
        &root_id,
        scan,
        statistics,
        now,
        &mut metrics,
    )?;
    reclaim(&mut db)?;
    // The obsolete JSON summary has no readers or migration path.
    match std::fs::remove_file(cache.join("codex/session-usage-v1.json")) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(_) => return Err(HistoryReadError::CacheUnavailable.into()),
    }
    Ok(summaries)
}

fn refresh_source(
    db: &mut Connection,
    root: &str,
    scan: i64,
    entry: &CodexRolloutIndexEntry,
    metadata: &HashMap<String, CodexThreadMetadata>,
    metrics: &mut HistoryIndexMetrics,
    integrity_scan: bool,
) -> anyhow::Result<()> {
    let path = entry.path.to_string_lossy().to_string();
    let mut file = File::open(&entry.path).map_err(|_| HistoryReadError::Unavailable)?;
    check_fingerprint(&file, entry)?;
    let identity = file_identity(&file)?;
    let fingerprint = entry
        .fingerprint
        .as_ref()
        .ok_or(HistoryReadError::Unavailable)?;
    let modified = fingerprint
        .modification_time_ns
        .ok_or(HistoryReadError::Unavailable)?;
    let stored=db.query_row("SELECT id,identity,file_size,modified_ns,checkpoint,head_digest,boundary_digest,state_json,complete FROM source WHERE root_id=?1 AND path=?2",params![root,path],|r| {
        Ok((r.get::<_,i64>(0)?,r.get::<_,String>(1)?,r.get::<_,i64>(2)?,r.get::<_,i64>(3)?,r.get::<_,i64>(4)?,r.get::<_,String>(5)?,r.get::<_,String>(6)?,r.get::<_,String>(7)?,r.get::<_,bool>(8)?))
    }).optional()?;
    let mut source =
        if let Some((id, identity, size, modified, offset, head, boundary, state, complete)) =
            stored
        {
            Source {
                id,
                identity,
                size,
                modified,
                offset,
                head,
                boundary,
                state: serde_json::from_str(&state)?,
                complete,
            }
        } else {
            let fallback = entry
                .path
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();
            let state = ParserState::new(&path, fallback);
            db.execute(
                "INSERT INTO source(root_id,path,identity,state_json) VALUES(?1,?2,?3,?4)",
                params![root, path, identity, serde_json::to_string(&state)?],
            )?;
            Source {
                id: db.last_insert_rowid(),
                identity: identity.clone(),
                size: 0,
                modified: 0,
                offset: 0,
                head: hex(b""),
                boundary: hex(b""),
                state,
                complete: false,
            }
        };
    let unchanged = source.complete
        && source.identity == identity
        && source.size == fingerprint.file_size
        && source.modified == modified;
    if unchanged && !integrity_scan {
        db.execute(
            "UPDATE source SET active_scan=?2 WHERE id=?1",
            params![source.id, scan],
        )?;
        if let Some(meta) = metadata.get(
            entry
                .path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .as_ref(),
        ) {
            db.execute(
                "UPDATE source SET logical_id=?2,parent_id=COALESCE(?3,parent_id) WHERE id=?1",
                params![source.id, meta.thread_id, source.state.parent_id.as_deref()],
            )?;
        }
        return Ok(());
    }
    metrics.parsed_files += 1;
    let prefix = if source.offset <= fingerprint.file_size {
        Some(stamp(&mut file, source.offset, metrics)?)
    } else {
        None
    };
    let append = prefix.as_ref().is_some_and(|s| {
        s.identity == source.identity && s.head == source.head && s.boundary == source.boundary
    }) && !integrity_scan
        && (!source.complete || fingerprint.file_size > source.size);
    if !append {
        metrics.rebuilt_files += 1;
        source.offset = 0;
        source.state = ParserState::new(
            &path,
            entry
                .path
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string(),
        );
    }
    source.identity = identity;
    let transaction = db.transaction()?;
    transaction.execute(
        "DELETE FROM fact WHERE source=?1 AND byte_offset>=?2",
        params![source.id, source.offset],
    )?;
    transaction.execute(
        "DELETE FROM turn_model WHERE source=?1 AND byte_offset>=?2",
        params![source.id, source.offset],
    )?;
    transaction.execute("UPDATE source SET complete=0 WHERE id=?1", [source.id])?;
    transaction.commit()?;
    file.seek(SeekFrom::Start(source.offset as u64))?;
    let mut reader = BufReader::with_capacity(READ_CHUNK_BYTES, file);
    let mut line = Vec::with_capacity(READ_CHUNK_BYTES);
    let mut offset = source.offset;
    let mut line_offset = offset;
    let mut checkpoint_state = source.state.clone();
    let mut checkpoint_offset = source.offset;
    let mut lines = 0usize;
    db.execute_batch("BEGIN IMMEDIATE")?;
    let parsing = (|| -> anyhow::Result<()> {
        loop {
            let buffer = reader
                .fill_buf()
                .map_err(|_| HistoryReadError::Unavailable)?;
            if buffer.is_empty() {
                break;
            }
            let newline = buffer.iter().position(|b| *b == b'\n');
            let bytes = newline.map_or(buffer.len(), |n| n + 1);
            let contents = newline.unwrap_or(buffer.len());
            if line.len().saturating_add(contents) > MAX_LINE_BYTES {
                return Err(HistoryReadError::ResourceLimited.into());
            }
            line.extend_from_slice(&buffer[..contents]);
            reader.consume(bytes);
            offset += bytes as i64;
            metrics.parser_read_bytes += bytes as u64;
            if newline.is_some() {
                source.state.consume(db, source.id, line_offset, &line)?;
                line.clear();
                line_offset = offset;
                checkpoint_offset = offset;
                checkpoint_state = source.state.clone();
                lines += 1;
                if lines >= CHECKPOINT_LINES {
                    commit_checkpoint(
                        db,
                        &mut reader,
                        source.id,
                        checkpoint_offset,
                        &checkpoint_state,
                        metrics,
                    )?;
                    db.execute_batch("BEGIN IMMEDIATE")?;
                    lines = 0;
                }
            }
        }
        // A complete JSON record at EOF is usable even without a newline. Its
        // facts are re-read on growth from the preceding newline checkpoint.
        if !line.iter().all(u8::is_ascii_whitespace) {
            source.state.consume(db, source.id, line_offset, &line)?;
        }
        let mut file = reader.get_mut();
        let final_stamp = stamp(&mut file, checkpoint_offset, metrics)?;
        check_fingerprint(&file, entry)?;
        db.execute("UPDATE source SET identity=?2,file_size=?3,modified_ns=?4,checkpoint=?5,head_digest=?6,boundary_digest=?7,state_json=?8,complete=1 WHERE id=?1",params![source.id,final_stamp.identity,final_stamp.size,final_stamp.modified,checkpoint_offset,final_stamp.head,final_stamp.boundary,serde_json::to_string(&checkpoint_state)?])?;
        db.execute_batch("COMMIT")?;
        metrics.checkpoint_commits += 1;
        // The complete observed header includes a valid unterminated EOF record;
        // checkpoint_state remains before it for safe append recovery.
        update_annotation(db, &source, entry, metadata, scan)?;
        Ok(())
    })();
    if parsing.is_err() {
        let _ = db.execute_batch("ROLLBACK");
    }
    parsing
}

fn update_annotation(
    db: &Connection,
    source: &Source,
    entry: &CodexRolloutIndexEntry,
    metadata: &HashMap<String, CodexThreadMetadata>,
    scan: i64,
) -> anyhow::Result<()> {
    let name = entry.path.file_name().unwrap_or_default().to_string_lossy();
    let meta = metadata.get(name.as_ref());
    let logical = meta
        .map(|m| m.thread_id.as_str())
        .unwrap_or(&source.state.summary.session_id);
    // Runtime spawn edges are not proof of copied history. Only the transcript's
    // explicit fork identity participates in usage-prefix deduplication.
    let parent = source.state.parent_id.as_deref();
    db.execute(
        "UPDATE source SET logical_id=?2,parent_id=?3,active_scan=?4,header_json=?5 WHERE id=?1",
        params![
            source.id,
            logical,
            parent,
            scan,
            serde_json::to_string(&source.state.summary)?
        ],
    )?;
    Ok(())
}

fn commit_checkpoint(
    db: &Connection,
    reader: &mut BufReader<File>,
    source: i64,
    offset: i64,
    state: &ParserState,
    metrics: &mut HistoryIndexMetrics,
) -> anyhow::Result<()> {
    // Seeking the underlying handle must not disturb BufReader's unread bytes.
    let position = reader.get_mut().stream_position()?;
    let current = stamp(reader.get_mut(), offset, metrics)?;
    reader.get_mut().seek(SeekFrom::Start(position))?;
    db.execute("UPDATE source SET identity=?2,checkpoint=?3,head_digest=?4,boundary_digest=?5,state_json=?6 WHERE id=?1",params![source,current.identity,offset,current.head,current.boundary,serde_json::to_string(state)?])?;
    db.execute_batch("COMMIT")?;
    metrics.checkpoint_commits += 1;
    let facts: i64 = db.query_row("SELECT fact_count FROM index_meta", [], |r| r.get(0))?;
    if facts > MAX_FACTS {
        return Err(HistoryReadError::ResourceLimited.into());
    }
    Ok(())
}

fn check_fingerprint(file: &File, entry: &CodexRolloutIndexEntry) -> anyhow::Result<()> {
    let metadata = file.metadata().map_err(|_| HistoryReadError::Unavailable)?;
    let modified = metadata
        .modified()
        .map_err(|_| HistoryReadError::Unavailable)?
        .duration_since(UNIX_EPOCH)
        .map_err(|_| HistoryReadError::Unavailable)?
        .as_nanos() as i64;
    let fp = entry
        .fingerprint
        .as_ref()
        .ok_or(HistoryReadError::Unavailable)?;
    if metadata.len() as i64 != fp.file_size || Some(modified) != fp.modification_time_ns {
        return Err(HistoryReadError::SourceChanged.into());
    }
    Ok(())
}

fn verify_source(
    db: &Connection,
    root: &str,
    entry: &CodexRolloutIndexEntry,
) -> anyhow::Result<()> {
    let file = File::open(&entry.path).map_err(|_| HistoryReadError::Unavailable)?;
    check_fingerprint(&file, entry)?;
    let stored: String = db.query_row(
        "SELECT identity FROM source WHERE root_id=?1 AND path=?2",
        params![root, entry.path.to_string_lossy()],
        |r| r.get(0),
    )?;
    if file_identity(&file)? != stored {
        return Err(HistoryReadError::SourceChanged.into());
    }
    Ok(())
}

fn stamp(file: &mut File, offset: i64, metrics: &mut HistoryIndexMetrics) -> anyhow::Result<Stamp> {
    let before = file.metadata().map_err(|_| HistoryReadError::Unavailable)?;
    if offset < 0 || before.len() < offset as u64 {
        return Err(HistoryReadError::SourceChanged.into());
    }
    let count = (offset as usize).min(4096);
    let mut data = vec![0; count];
    file.seek(SeekFrom::Start(0))?;
    file.read_exact(&mut data)
        .map_err(|_| HistoryReadError::SourceChanged)?;
    let head = hex(&data);
    file.seek(SeekFrom::Start(offset as u64 - count as u64))?;
    file.read_exact(&mut data)
        .map_err(|_| HistoryReadError::SourceChanged)?;
    metrics.validation_read_bytes += 2 * count as u64;
    let after = file.metadata().map_err(|_| HistoryReadError::Unavailable)?;
    if before.len() != after.len() || before.modified()? != after.modified()? {
        return Err(HistoryReadError::SourceChanged.into());
    }
    Ok(Stamp {
        identity: file_identity(file)?,
        size: after.len() as i64,
        modified: after.modified()?.duration_since(UNIX_EPOCH)?.as_nanos() as i64,
        head,
        boundary: hex(&data),
    })
}

#[cfg(windows)]
fn file_identity(file: &File) -> anyhow::Result<String> {
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::Storage::FileSystem::{
        GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION,
    };
    let mut info = std::mem::MaybeUninit::<BY_HANDLE_FILE_INFORMATION>::zeroed();
    if unsafe { GetFileInformationByHandle(file.as_raw_handle() as _, info.as_mut_ptr()) } == 0 {
        return Err(HistoryReadError::Unavailable.into());
    }
    let info = unsafe { info.assume_init() };
    Ok(format!(
        "{}:{}:{}:{}:{}",
        info.dwVolumeSerialNumber,
        info.nFileIndexHigh,
        info.nFileIndexLow,
        info.ftCreationTime.dwHighDateTime,
        info.ftCreationTime.dwLowDateTime
    ))
}

#[cfg(unix)]
fn file_identity(file: &File) -> anyhow::Result<String> {
    use std::os::unix::fs::MetadataExt;
    let m = file.metadata()?;
    Ok(format!("{}:{}", m.dev(), m.ino()))
}

fn hex(data: &[u8]) -> String {
    format!("{:x}", Sha256::digest(data))
}

fn check_budget(path: &Path) -> anyhow::Result<()> {
    let parent = path.parent().unwrap();
    let mut bytes = 0u64;
    for entry in std::fs::read_dir(parent).map_err(|_| HistoryReadError::CacheUnavailable)? {
        let entry = entry?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with("history-index.sqlite") || name == "history-index.lock" {
            bytes = bytes.saturating_add(entry.metadata()?.len());
        }
    }
    if bytes > CACHE_BYTES {
        Err(HistoryReadError::CacheFull.into())
    } else {
        Ok(())
    }
}

const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS index_meta(id INTEGER PRIMARY KEY CHECK(id=1),scan_serial INTEGER NOT NULL DEFAULT 0,published_generation INTEGER NOT NULL DEFAULT 0,previous_generation INTEGER NOT NULL DEFAULT 0,published_root TEXT NOT NULL DEFAULT '',statistics_id TEXT NOT NULL DEFAULT '',metrics_json TEXT NOT NULL DEFAULT '{}',fact_count INTEGER NOT NULL DEFAULT 0);
INSERT OR IGNORE INTO index_meta(id) VALUES(1);
CREATE TABLE IF NOT EXISTS source(id INTEGER PRIMARY KEY,root_id TEXT NOT NULL,path TEXT NOT NULL,identity TEXT NOT NULL,file_size INTEGER NOT NULL DEFAULT 0,modified_ns INTEGER NOT NULL DEFAULT 0,checkpoint INTEGER NOT NULL DEFAULT 0,head_digest TEXT NOT NULL DEFAULT '',boundary_digest TEXT NOT NULL DEFAULT '',state_json TEXT NOT NULL,header_json TEXT NOT NULL DEFAULT '{}',logical_id TEXT NOT NULL DEFAULT '',parent_id TEXT,active_scan INTEGER NOT NULL DEFAULT 0,complete INTEGER NOT NULL DEFAULT 0,UNIQUE(root_id,path));
CREATE TABLE IF NOT EXISTS fact(source INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,byte_offset INTEGER NOT NULL,kind TEXT NOT NULL,event_key TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(source,byte_offset,kind),UNIQUE(source,event_key));
CREATE TRIGGER IF NOT EXISTS fact_insert AFTER INSERT ON fact BEGIN UPDATE index_meta SET fact_count=fact_count+1; END;
CREATE TRIGGER IF NOT EXISTS fact_delete AFTER DELETE ON fact BEGIN UPDATE index_meta SET fact_count=fact_count-1; END;
CREATE TABLE IF NOT EXISTS turn_model(source INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,byte_offset INTEGER NOT NULL,turn_id TEXT NOT NULL,model TEXT NOT NULL,PRIMARY KEY(source,byte_offset));
CREATE INDEX IF NOT EXISTS turn_lookup ON turn_model(source,turn_id,byte_offset);
CREATE TABLE IF NOT EXISTS day_archive(generation INTEGER NOT NULL,day TEXT NOT NULL,root_id TEXT NOT NULL,usage_json TEXT NOT NULL,PRIMARY KEY(generation,day));
PRAGMA user_version=1;
"#;

fn materialize(
    db: &Connection,
    root: &str,
    scan: i64,
) -> anyhow::Result<Vec<CodexTranscriptSummary>> {
    let mut summaries: HashMap<String, CodexTranscriptSummary> = HashMap::new();
    let mut parents: HashMap<String, String> = HashMap::new();
    let mut header_query=db.prepare("SELECT logical_id,parent_id,header_json FROM source WHERE root_id=?1 AND active_scan=?2 AND complete=1 ORDER BY path")?;
    let rows = header_query.query_map(params![root, scan], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, Option<String>>(1)?,
            r.get::<_, String>(2)?,
        ))
    })?;
    for row in rows {
        let (logical, parent, json) = row?;
        let mut summary: CodexTranscriptSummary = serde_json::from_str(&json)?;
        summary.session_id = logical.clone();
        if let Some(parent) = parent {
            parents.insert(logical.clone(), parent);
        }
        summaries
            .entry(logical)
            .and_modify(|old| {
                if summary.last_active_at > old.last_active_at {
                    old.last_active_at = summary.last_active_at;
                    old.model = summary.model.clone();
                }
            })
            .or_insert(summary);
    }
    // Deduplicate physical live/archive copies before comparing raw token prefixes.
    let mut query=db.prepare("SELECT logical_id,event_key,payload FROM source JOIN fact ON source.id=fact.source WHERE root_id=?1 AND active_scan=?2 AND complete=1 ORDER BY logical_id,byte_offset,path")?;
    let rows = query.query_map(params![root, scan], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
        ))
    })?;
    let mut seen = HashSet::new();
    let mut ancillary = vec![];
    let mut usage: HashMap<String, Vec<(String, super::codex_transcript::CodexUsageDelta)>> =
        HashMap::new();
    for row in rows {
        let (logical, key, json) = row?;
        if !seen.insert((logical.clone(), key.clone())) {
            continue;
        }
        if !summaries.contains_key(&logical) {
            return Err(HistoryReadError::CacheUnavailable.into());
        }
        match serde_json::from_str::<Fact>(&json)? {
            Fact::Usage {
                mut delta,
                signature,
            } => {
                delta.session_id = logical.clone();
                usage.entry(logical).or_default().push((signature, delta));
            }
            Fact::Tool { name, skills } => {
                ancillary.push((logical, key, Fact::Tool { name, skills }));
            }
            Fact::Interval(interval) => ancillary.push((logical, key, Fact::Interval(interval))),
        }
    }
    for events in usage.values_mut() {
        events.sort_by(|a, b| a.1.date.cmp(&b.1.date));
    }
    let mut inherited = HashMap::new();
    for (child, parent) in &parents {
        if let (Some(child_events), Some(parent_events)) = (usage.get(child), usage.get(parent)) {
            let count = child_events
                .iter()
                .zip(parent_events)
                .take_while(|(c, p)| c.0 == p.0)
                .count();
            inherited.insert(child.clone(), count);
        }
    }
    for (logical, key, fact) in ancillary {
        if inherited.get(&logical).is_some_and(|n| *n > 0)
            && parents
                .get(&logical)
                .is_some_and(|p| seen.contains(&(p.clone(), key.clone())))
        {
            continue;
        }
        let summary = summaries.get_mut(&logical).unwrap();
        match fact {
            Fact::Tool { name, skills } => {
                if !name.is_empty() {
                    *summary.tool_calls.entry(name).or_default() += 1;
                }
                summary.skill_loads.extend(skills);
            }
            Fact::Interval(interval) => summary.task_intervals.push(interval),
            _ => unreachable!(),
        }
    }
    for (logical, events) in usage {
        let summary = summaries.get_mut(&logical).unwrap();
        for (_, mut delta) in events
            .into_iter()
            .skip(*inherited.get(&logical).unwrap_or(&0))
        {
            delta.turn_id = Some(format!(
                "{logical}:{}",
                delta.turn_id.as_deref().unwrap_or("")
            ));
            summary.deltas.push(delta);
        }
    }
    // The current DTO consumers still need per-session facts; the fact ceiling
    // bounds this materialization. Daily archives are independently persisted.
    let mut result: Vec<_> = summaries.into_values().collect();
    result.sort_by(|a, b| a.file_path.cmp(&b.file_path));
    Ok(result)
}

fn publish_days(
    db: &mut Connection,
    summaries: &[CodexTranscriptSummary],
    root: &str,
    scan: i64,
    statistics: StatisticsTimeZone,
    _now: DateTime<Utc>,
    metrics: &mut HistoryIndexMetrics,
) -> anyhow::Result<()> {
    let mut days: HashMap<String, PricedTokenUsage> = HashMap::new();
    for delta in summaries.iter().flat_map(|s| &s.deltas) {
        let day = statistics.day_key(delta.date);
        days.entry(day).or_default().add_tokens(
            &delta.tokens,
            super::common::estimated_cost_usd(&delta.tokens, delta.model.as_deref()),
        );
    }
    metrics.published_generation = scan;
    let tx = db.transaction()?;
    for (day, usage) in days {
        tx.execute(
            "INSERT INTO day_archive(generation,day,root_id,usage_json) VALUES(?1,?2,?3,?4)",
            params![scan, day, root, serde_json::to_string(&usage)?],
        )?;
    }
    tx.execute("UPDATE index_meta SET previous_generation=published_generation,published_generation=?1,published_root=?2,statistics_id=?3,metrics_json=?4",params![scan,root,statistics.identity(),serde_json::to_string(metrics)?])?;
    tx.execute(
        "DELETE FROM source WHERE root_id!=?1 OR active_scan!=?2",
        params![root, scan],
    )?;
    tx.commit()?;
    Ok(())
}

fn reclaim(db: &mut Connection) -> anyhow::Result<()> {
    loop {
        let tx = db.transaction()?;
        let deleted=tx.execute("DELETE FROM day_archive WHERE rowid IN(SELECT rowid FROM day_archive WHERE generation NOT IN(SELECT published_generation FROM index_meta UNION ALL SELECT previous_generation FROM index_meta) LIMIT 256)",[])?;
        tx.commit()?;
        if deleted == 0 {
            break;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn event(n: i64) -> String {
        serde_json::json!({"timestamp":"2026-10-10T00:00:00Z","type":"event_msg","payload":{"type":"token_count","turn_id":format!("t-{n}"),"info":{"last_token_usage":{"input_tokens":1,"total_tokens":1},"total_token_usage":{"input_tokens":n,"total_tokens":n}}}}).to_string()+"\n"
    }

    #[tokio::test]
    async fn sqlite_page_budget_failure_preserves_publication_and_recovers_after_budget_is_available(
    ) {
        let temp = tempfile::tempdir().unwrap();
        let cache = temp.path().join("cache");
        std::fs::create_dir(temp.path().join("sessions")).unwrap();
        let file = temp.path().join("sessions/rollout-a.jsonl");
        std::fs::write(&file, event(1)).unwrap();
        let reader = super::super::CodexTranscriptReader::new(&cache);
        reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap();
        let db = Connection::open(database_path(&cache)).unwrap();
        let published: i64 = db
            .query_row("SELECT published_generation FROM index_meta", [], |r| {
                r.get(0)
            })
            .unwrap();
        let pages: i64 = db.query_row("PRAGMA page_count", [], |r| r.get(0)).unwrap();
        let page_size: i64 = db.query_row("PRAGMA page_size", [], |r| r.get(0)).unwrap();
        drop(db);
        let mut out = OpenOptions::new().append(true).open(&file).unwrap();
        for n in 2..=1000 {
            out.write_all(event(n).as_bytes()).unwrap();
        }
        drop(out);
        let index = super::super::index_codex_rollout_files(temp.path())
            .await
            .unwrap();
        let error = load_inner(
            temp.path(),
            &cache,
            &index,
            &HashMap::new(),
            StatisticsTimeZone::Local,
            Utc::now(),
            false,
            (pages * page_size) as u64,
        )
        .unwrap_err();
        assert!(
            matches!(error.downcast_ref::<rusqlite::Error>(),Some(rusqlite::Error::SqliteFailure(code,_)) if code.code==rusqlite::ErrorCode::DiskFull)
        );
        let db = Connection::open(database_path(&cache)).unwrap();
        let after: i64 = db
            .query_row("SELECT published_generation FROM index_meta", [], |r| {
                r.get(0)
            })
            .unwrap();
        assert_eq!(after, published);
        drop(db);
        let recovered = reader
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(recovered.lifetime_tokens, 1000);
    }

    #[test]
    fn archive_reclamation_is_batched_and_preserves_current_previous_and_reader_snapshot() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("index.sqlite");
        let mut db = Connection::open(&path).unwrap();
        db.execute_batch(SCHEMA).unwrap();
        db.execute(
            "UPDATE index_meta SET published_generation=1000,previous_generation=999",
            [],
        )
        .unwrap();
        for n in 1..=1000 {
            db.execute(
                "INSERT INTO day_archive VALUES(?1,'2026-10-10','fixture','{}')",
                [n],
            )
            .unwrap();
        }
        let reader = Connection::open(&path).unwrap();
        reader.execute_batch("BEGIN").unwrap();
        let before: i64 = reader
            .query_row("SELECT count(*) FROM day_archive", [], |r| r.get(0))
            .unwrap();
        assert_eq!(before, 1000);
        db.busy_timeout(Duration::ZERO).unwrap();
        assert!(reclaim(&mut db).is_err());
        let pinned: i64 = reader
            .query_row("SELECT count(*) FROM day_archive", [], |r| r.get(0))
            .unwrap();
        assert_eq!(pinned, 1000);
        reader.execute_batch("COMMIT").unwrap();
        drop(reader);
        reclaim(&mut db).unwrap();
        let remaining: i64 = db
            .query_row("SELECT count(*) FROM day_archive", [], |r| r.get(0))
            .unwrap();
        assert_eq!(remaining, 2);
        for retained in [999, 1000] {
            assert_eq!(
                db.query_row(
                    "SELECT count(*) FROM day_archive WHERE generation=?1",
                    [retained],
                    |r| r.get::<_, i64>(0)
                )
                .unwrap(),
                1
            );
        }
    }

    #[tokio::test]
    async fn final_source_check_rejects_replacement_with_matching_size_and_mtime() {
        let temp = tempfile::tempdir().unwrap();
        let cache = temp.path().join("cache");
        std::fs::create_dir(temp.path().join("sessions")).unwrap();
        let path = temp.path().join("sessions/rollout-a.jsonl");
        let contents = event(1);
        std::fs::write(&path, &contents).unwrap();
        super::super::CodexTranscriptReader::new(&cache)
            .load_local_usage(temp.path(), Utc::now())
            .await
            .unwrap();
        let index = super::super::index_codex_rollout_files(temp.path())
            .await
            .unwrap();
        let modified = std::fs::metadata(&path).unwrap().modified().unwrap();
        let replacement = temp.path().join("new.jsonl");
        std::fs::write(&replacement, &contents).unwrap();
        OpenOptions::new()
            .write(true)
            .open(&replacement)
            .unwrap()
            .set_times(std::fs::FileTimes::new().set_modified(modified))
            .unwrap();
        std::fs::remove_file(&path).unwrap();
        std::fs::rename(replacement, &path).unwrap();
        let db = Connection::open(database_path(&cache)).unwrap();
        let error = verify_source(
            &db,
            &hex(temp.path().to_string_lossy().as_bytes()),
            &index[0],
        )
        .unwrap_err();
        assert!(matches!(
            error.downcast_ref::<HistoryReadError>(),
            Some(HistoryReadError::SourceChanged)
        ));
    }
}
