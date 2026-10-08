import Darwin
import Foundation
import SQLite3

enum UsageIndexError: String, Error {
    case indexBusy, unsupportedSchema, cacheInvalid, diskFull, resourceLimited
    case sourceChanged, revisionExpired, cancelled, databaseFailure
}

enum UsageSQLValue: Equatable {
    case null, integer(Int64), text(String), real(Double)
    var integer: Int64? { if case .integer(let value) = self { return value }; return nil }
    var text: String? { if case .text(let value) = self { return value }; return nil }
}

/// Owned by one serial worker. Never create this object on the home rendering path.
final class UsageIndexStore {
    static let schemaVersion: Int64 = 2
    static let maximumPayloadBytes = 256 * 1024
    private var database: OpaquePointer?
    private var lockFD: Int32 = -1
    private let directory: URL
    private var deadline: UInt64 = .max
    private var inTransaction = false

    init(directory: URL) throws {
        self.directory = directory
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        // Do not follow a substituted cache directory or database symlink.
        for url in [directory, directory.appendingPathComponent("index.sqlite"),
                    directory.appendingPathComponent("writer.lock"),
                    directory.appendingPathComponent("index.sqlite-wal"),
                    directory.appendingPathComponent("index.sqlite-shm")] {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                throw UsageIndexError.cacheInvalid
            }
        }
        guard chmod(directory.path, 0o700) == 0 else { throw UsageIndexError.cacheInvalid }
        lockFD = open(directory.appendingPathComponent("writer.lock").path,
                      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw UsageIndexError.indexBusy }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD); lockFD = -1
            throw UsageIndexError.indexBusy
        }
        do {
            let path = directory.appendingPathComponent("index.sqlite").path
            // Precreate with restrictive mode; SQLite must not create a world-readable file.
            let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw UsageIndexError.cacheInvalid }
            let protected = fchmod(fd, 0o600) == 0
            close(fd)
            guard protected else { throw UsageIndexError.cacheInvalid }
            guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
                throw UsageIndexError.cacheInvalid
            }
            sqlite3_busy_timeout(database, 100)
            let version = try scalar("PRAGMA user_version") ?? 0
            guard version <= Self.schemaVersion else { throw UsageIndexError.unsupportedSchema }
            if version == 0 {
                guard try scalar("SELECT count(*) FROM sqlite_master WHERE type='table'") == 0 else {
                    throw UsageIndexError.cacheInvalid
                }
            }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA temp_store=FILE")
            try execute("PRAGMA cache_size=-32768")
            try execute("PRAGMA wal_autocheckpoint=1000")
            if version == 0 {
                try transaction {
                    guard sqlite3_exec(database, Self.schema, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
                    try execute("PRAGMA user_version=1")
                }
            }
            if version < 2 {
                try transaction {
                    for statement in Self.ownershipSchema { try execute(statement) }
                    try execute("PRAGMA user_version=2")
                }
            }
            try execute("CREATE INDEX IF NOT EXISTS job_materialize_queue ON job(kind,context_id,status,updated_at_ms,id)")
            try execute("CREATE INDEX IF NOT EXISTS source_runtime ON source(runtime,id)")
            try execute("CREATE INDEX IF NOT EXISTS archive_day_revision ON archive_day(context_id,revision_id,day_key)")
            try configureStorageBudget()
            try protectFiles()
            sqlite3_progress_handler(database, 1000, { pointer in
                guard let pointer else { return 1 }
                let store = Unmanaged<UsageIndexStore>.fromOpaque(pointer).takeUnretainedValue()
                return DispatchTime.now().uptimeNanoseconds >= store.deadline ? 1 : 0
            }, Unmanaged.passUnretained(self).toOpaque())
        } catch {
            if let database { sqlite3_close(database); self.database = nil }
            flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1
            throw error
        }
    }

    deinit {
        if let database { sqlite3_progress_handler(database, 0, nil, nil); sqlite3_close(database) }
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) }
    }

    func withDeadline<T>(milliseconds: UInt64 = 100, _ operation: () throws -> T) throws -> T {
        let old = deadline
        deadline = min(old, DispatchTime.now().uptimeNanoseconds &+ milliseconds * 1_000_000)
        defer { deadline = old }
        return try operation()
    }

    func transaction<T>(_ operation: () throws -> T) throws -> T {
        if inTransaction {
            let savepoint = "nested_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            try execute("SAVEPOINT " + savepoint)
            do {
                let result = try operation()
                try execute("RELEASE " + savepoint)
                return result
            } catch {
                let old = deadline; deadline = .max
                try? execute("ROLLBACK TO " + savepoint)
                try? execute("RELEASE " + savepoint)
                deadline = old
                throw error
            }
        }
        try execute("BEGIN IMMEDIATE")
        inTransaction = true
        defer { inTransaction = false }
        do {
            let result = try operation()
            try execute("COMMIT")
            return result
        } catch {
            // A cancelled statement must not also cancel rollback.
            let old = deadline; deadline = .max
            try? execute("ROLLBACK")
            deadline = old
            throw error
        }
    }

    func execute(_ sql: String, _ values: [UsageSQLValue] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW else { throw databaseError() }
        }
    }

    /// Query callers use keyset pagination. The cap is also enforced on returned bytes.
    func rows(_ sql: String, _ values: [UsageSQLValue] = [], limit: Int = 256,
              maximumBytes: Int = 4 * 1024 * 1024) throws -> [[UsageSQLValue]] {
        guard limit > 0, limit <= 1000 else { throw UsageIndexError.resourceLimited }
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [[UsageSQLValue]] = []
        var bytes = 0
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw databaseError() }
            guard result.count < limit else { throw UsageIndexError.resourceLimited }
            var row: [UsageSQLValue] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_NULL: row.append(.null); bytes += 1
                case SQLITE_INTEGER: row.append(.integer(sqlite3_column_int64(statement, column))); bytes += 8
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(statement, column))); bytes += 8
                case SQLITE_TEXT:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    guard count <= maximumBytes - bytes else { throw UsageIndexError.resourceLimited }
                    bytes += count
                    guard let text = sqlite3_column_text(statement, column) else { throw UsageIndexError.cacheInvalid }
                    row.append(.text(String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)))
                default: throw UsageIndexError.cacheInvalid
                }
                guard bytes <= maximumBytes else { throw UsageIndexError.resourceLimited }
            }
            result.append(row)
        }
    }

    func scalar(_ sql: String, _ values: [UsageSQLValue] = []) throws -> Int64? {
        try rows(sql, values, limit: 1).first?.first?.integer
    }

    func allocateRevision(now: Date) throws -> Int64 {
        guard inTransaction else { throw UsageIndexError.databaseFailure }
        try execute("INSERT INTO revision(committed_at_ms) VALUES (?)", [.integer(try usageIndexMilliseconds(now))])
        return sqlite3_last_insert_rowid(database)
    }

    func checkpointWAL() throws {
        guard !inTransaction else { throw UsageIndexError.databaseFailure }
        guard sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil) == SQLITE_OK else {
            throw databaseError()
        }
        try protectFiles()
    }

    private func prepare(_ sql: String, _ values: [UsageSQLValue]) throws -> OpaquePointer {
        guard DispatchTime.now().uptimeNanoseconds < deadline else { throw UsageIndexError.cancelled }
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw databaseError()
        }
        do {
            guard sqlite3_bind_parameter_count(pointer) == values.count else { throw UsageIndexError.databaseFailure }
            for (index, value) in values.enumerated() {
                let column = Int32(index + 1)
                let result: Int32
                switch value {
                case .null: result = sqlite3_bind_null(pointer, column)
                case .integer(let number): result = sqlite3_bind_int64(pointer, column, number)
                case .real(let number): result = sqlite3_bind_double(pointer, column, number)
                case .text(let text):
                    guard text.utf8.count <= 4 * 1024 * 1024 else { throw UsageIndexError.resourceLimited }
                    result = text.withCString { sqlite3_bind_text(pointer, column, $0, Int32(text.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                }
                guard result == SQLITE_OK else { throw databaseError() }
            }
            return pointer
        } catch { sqlite3_finalize(pointer); throw error }
    }

    private func protectFiles() throws {
        for name in ["index.sqlite", "index.sqlite-wal", "index.sqlite-shm", "writer.lock"] {
            let path = directory.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: path), chmod(path, 0o600) != 0 { throw UsageIndexError.cacheInvalid }
        }
    }

    private func databaseError() -> UsageIndexError {
        switch sqlite3_errcode(database) {
        case SQLITE_BUSY, SQLITE_LOCKED: return .indexBusy
        case SQLITE_FULL: return .diskFull
        case SQLITE_INTERRUPT: return .cancelled
        case SQLITE_CORRUPT, SQLITE_NOTADB: return .cacheInvalid
        default: return .databaseFailure
        }
    }
}

extension UsageIndexStore {
    private static let schema = #"""
-- v1.1 proposal; all writes owned by one worker. Event payload is a validated whitelist DTO.
PRAGMA foreign_keys=ON;
CREATE TABLE index_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE revision (id INTEGER PRIMARY KEY, committed_at_ms INTEGER NOT NULL);
CREATE TABLE source (
 id TEXT PRIMARY KEY, root_id TEXT NOT NULL, runtime TEXT NOT NULL CHECK(runtime IN ('codex','claude-code')),
 logical_id TEXT NOT NULL, instance_id TEXT NOT NULL, locator TEXT NOT NULL,
 discovered_epoch INTEGER NOT NULL, created_revision INTEGER NOT NULL REFERENCES revision(id),
 status TEXT NOT NULL, updated_at_ms INTEGER NOT NULL,
 UNIQUE(root_id,runtime,logical_id,instance_id)
);
CREATE TABLE source_generation (
 source_id TEXT NOT NULL REFERENCES source(id), generation INTEGER NOT NULL,
 parser_version INTEGER NOT NULL, file_identity TEXT NOT NULL,
 checkpoint_offset INTEGER NOT NULL CHECK(checkpoint_offset>=0), observed_end INTEGER NOT NULL,
 checkpoint_state TEXT NOT NULL, fingerprint TEXT NOT NULL,
 valid_from INTEGER REFERENCES revision(id), valid_to INTEGER REFERENCES revision(id),
 created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL,
 PRIMARY KEY(source_id,generation), CHECK(valid_to IS NULL OR valid_to>valid_from)
);
CREATE UNIQUE INDEX source_active ON source_generation(source_id) WHERE valid_from IS NOT NULL AND valid_to IS NULL;
CREATE TABLE fact (
 source_id TEXT NOT NULL, generation INTEGER NOT NULL, sequence INTEGER NOT NULL,
 kind TEXT NOT NULL, logical_key TEXT NOT NULL, operation TEXT NOT NULL CHECK(operation IN ('upsert','delete')),
 occurred_at_ms INTEGER NOT NULL, event_identity TEXT,
 payload TEXT NOT NULL, commit_revision INTEGER NOT NULL REFERENCES revision(id),
 PRIMARY KEY(source_id,generation,sequence),
 FOREIGN KEY(source_id,generation) REFERENCES source_generation(source_id,generation)
);
CREATE INDEX fact_time ON fact(occurred_at_ms,kind,source_id,generation,sequence);
CREATE INDEX fact_revision ON fact(commit_revision);
CREATE INDEX fact_logical_version ON fact(source_id,generation,kind,logical_key,commit_revision DESC,sequence DESC);
CREATE TABLE dependency_version (
 child_source_id TEXT NOT NULL, child_generation INTEGER NOT NULL,
 parent_logical_id TEXT NOT NULL, parent_source_id TEXT, parent_generation INTEGER,
 valid_from INTEGER NOT NULL REFERENCES revision(id), valid_to INTEGER REFERENCES revision(id),
 token_prefix INTEGER, inference_prefix INTEGER, status TEXT NOT NULL, updated_at_ms INTEGER NOT NULL,
 child_checkpoint_revision INTEGER REFERENCES revision(id), parent_checkpoint_revision INTEGER REFERENCES revision(id),
 child_metadata_revision INTEGER REFERENCES revision(id), parent_metadata_revision INTEGER REFERENCES revision(id),
 PRIMARY KEY(child_source_id,child_generation,valid_from),
 CHECK(status<>'resolved' OR (parent_source_id IS NOT NULL AND parent_generation IS NOT NULL
   AND token_prefix IS NOT NULL AND token_prefix>=0 AND inference_prefix IS NOT NULL AND inference_prefix>=0
   AND child_checkpoint_revision IS NOT NULL AND parent_checkpoint_revision IS NOT NULL
   AND child_metadata_revision IS NOT NULL AND parent_metadata_revision IS NOT NULL)),
 FOREIGN KEY(child_source_id,child_generation) REFERENCES source_generation(source_id,generation),
 FOREIGN KEY(parent_source_id,parent_generation) REFERENCES source_generation(source_id,generation),
 CHECK(valid_to IS NULL OR valid_to>valid_from)
);
CREATE INDEX dependency_parent ON dependency_version(parent_source_id,valid_from,valid_to);
CREATE UNIQUE INDEX dependency_current ON dependency_version(child_source_id,child_generation) WHERE valid_to IS NULL;
CREATE TABLE source_metadata_version (
 source_id TEXT NOT NULL REFERENCES source(id), valid_from INTEGER NOT NULL REFERENCES revision(id),
 valid_to INTEGER REFERENCES revision(id), payload TEXT NOT NULL,
 PRIMARY KEY(source_id,valid_from), CHECK(valid_to IS NULL OR valid_to>valid_from)
);
CREATE TABLE discovery_scan (
 id INTEGER PRIMARY KEY, root_id TEXT NOT NULL, runtime TEXT NOT NULL,
 started_at_ms INTEGER NOT NULL, completed_at_ms INTEGER, method TEXT NOT NULL,
 revision_id INTEGER REFERENCES revision(id), status TEXT NOT NULL, inventory_digest TEXT
);
CREATE TABLE source_observation (
 source_id TEXT NOT NULL REFERENCES source(id), revision_id INTEGER NOT NULL REFERENCES revision(id),
 scan_id INTEGER REFERENCES discovery_scan(id), file_identity TEXT NOT NULL,
 target_end INTEGER NOT NULL CHECK(target_end>=0), status TEXT NOT NULL, observed_at_ms INTEGER NOT NULL,
 PRIMARY KEY(source_id,revision_id)
);
CREATE TABLE checkpoint_version (
 source_id TEXT NOT NULL, generation INTEGER NOT NULL, revision_id INTEGER NOT NULL REFERENCES revision(id),
 complete_offset INTEGER NOT NULL CHECK(complete_offset>=0), observed_end INTEGER NOT NULL,
 PRIMARY KEY(source_id,generation,revision_id),
 FOREIGN KEY(source_id,generation) REFERENCES source_generation(source_id,generation)
);
CREATE TABLE projection_context (
 id TEXT PRIMARY KEY, root_id TEXT NOT NULL, timezone_id TEXT NOT NULL,
 formula_version INTEGER NOT NULL, price_version INTEGER NOT NULL, created_at_ms INTEGER NOT NULL
);
CREATE TABLE source_projection (
 id TEXT PRIMARY KEY, context_id TEXT NOT NULL REFERENCES projection_context(id), source_id TEXT NOT NULL,
 generation INTEGER NOT NULL, input_revision INTEGER NOT NULL REFERENCES revision(id),
 dependency_revision INTEGER REFERENCES revision(id), state TEXT NOT NULL CHECK(state IN ('building','ready','partial','retired')),
 created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL,
 UNIQUE(context_id,source_id,generation,input_revision),
 FOREIGN KEY(source_id,generation) REFERENCES source_generation(source_id,generation)
);
CREATE TABLE source_day (
 projection_id TEXT NOT NULL REFERENCES source_projection(id), day_key TEXT NOT NULL,
 dimension_key TEXT NOT NULL, payload TEXT NOT NULL,
 PRIMARY KEY(projection_id,day_key,dimension_key)
);
CREATE TABLE report_build (
 id TEXT PRIMARY KEY, context_id TEXT NOT NULL REFERENCES projection_context(id),
 cut_revision INTEGER NOT NULL REFERENCES revision(id), scan_id INTEGER REFERENCES discovery_scan(id),
 day_key TEXT NOT NULL, domain TEXT NOT NULL, runtime TEXT NOT NULL, state TEXT NOT NULL,
 cursor TEXT NOT NULL, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL
);
CREATE TABLE build_member (
 build_id TEXT NOT NULL REFERENCES report_build(id), source_id TEXT NOT NULL REFERENCES source(id),
 projection_id TEXT NOT NULL REFERENCES source_projection(id), PRIMARY KEY(build_id,source_id)
);
CREATE TABLE job (
 id TEXT PRIMARY KEY, dedup_key TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, priority INTEGER NOT NULL,
 source_id TEXT REFERENCES source(id), context_id TEXT REFERENCES projection_context(id),
 status TEXT NOT NULL, cursor TEXT NOT NULL, cut_revision INTEGER REFERENCES revision(id),
 retry_at_ms INTEGER, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL
);
CREATE TABLE archive_day (
 context_id TEXT NOT NULL REFERENCES projection_context(id), day_key TEXT NOT NULL,
 revision_id INTEGER NOT NULL REFERENCES revision(id), coverage TEXT NOT NULL,
 payload TEXT NOT NULL, updated_at_ms INTEGER NOT NULL,
 PRIMARY KEY(context_id,day_key,revision_id)
);
CREATE TABLE published_slice (
 build_id TEXT NOT NULL REFERENCES report_build(id), day_key TEXT NOT NULL,
 context_id TEXT NOT NULL REFERENCES projection_context(id), domain TEXT NOT NULL, runtime TEXT NOT NULL,
 revision_id INTEGER NOT NULL REFERENCES revision(id), coverage TEXT NOT NULL,
 observed_at_ms INTEGER, payload TEXT NOT NULL, updated_at_ms INTEGER NOT NULL,
 PRIMARY KEY(context_id,domain,runtime), CHECK(length(CAST(payload AS BLOB))<=262144)
);
CREATE TABLE revision_pin (
 owner_id TEXT PRIMARY KEY, revision_id INTEGER NOT NULL REFERENCES revision(id),
 expires_at_ms INTEGER, updated_at_ms INTEGER NOT NULL
);

CREATE TABLE build_interval (
 build_id TEXT NOT NULL REFERENCES report_build(id), interval_id TEXT NOT NULL,
 worker_id TEXT NOT NULL, project_id TEXT NOT NULL, start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL,
 quality TEXT NOT NULL, autonomous INTEGER NOT NULL CHECK(autonomous IN (0,1)),
 PRIMARY KEY(build_id,interval_id), CHECK(end_ms>start_ms)
);
CREATE INDEX interval_sweep ON build_interval(build_id,worker_id,start_ms,end_ms);
CREATE TABLE build_boundary (
 build_id TEXT NOT NULL REFERENCES report_build(id), scope_key TEXT NOT NULL,
 time_ms INTEGER NOT NULL, event_order INTEGER NOT NULL, interval_id TEXT NOT NULL, delta INTEGER NOT NULL,
 PRIMARY KEY(build_id,scope_key,time_ms,event_order,interval_id)
);
CREATE TABLE build_metric (
 build_id TEXT NOT NULL REFERENCES report_build(id), scope_key TEXT NOT NULL, metric_key TEXT NOT NULL,
 payload TEXT NOT NULL, PRIMARY KEY(build_id,scope_key,metric_key)
);
CREATE TABLE build_sample (
 build_id TEXT NOT NULL REFERENCES report_build(id), sample_id TEXT NOT NULL,
 model TEXT NOT NULL, effort TEXT NOT NULL, duration_ns INTEGER NOT NULL, payload TEXT NOT NULL,
 PRIMARY KEY(build_id,sample_id)
);
CREATE INDEX sample_rank ON build_sample(build_id,model,effort,duration_ns,sample_id);

"""#
}

func usageIndexMilliseconds(_ date: Date) throws -> Int64 {
    let value = date.timeIntervalSince1970 * 1000
    guard value.isFinite, value >= Double(Int64.min), value < Double(Int64.max) else {
        throw UsageIndexError.resourceLimited
    }
    return Int64(value)
}
