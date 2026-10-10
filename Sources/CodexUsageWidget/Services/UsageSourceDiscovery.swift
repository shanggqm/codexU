import Foundation
import SQLite3

struct UsageDiscoveredSource: Codable {
    let runtime: String
    let logicalID: String
    let locator: String
    let model: String?
    let project: String
    let updatedAt: Int64
    var createdAt: Int64? = nil
    var sourceKind: String? = nil
    var workerParentID: String? = nil
    var automationID: String? = nil
}

struct UsageDiscoveryResult {
    let sources: Int
    let complete: Bool
    let metadataBytes: Int
}

/// The caller owns discovery jobs/scan epochs; pages are hints until `complete` is true.
/// Run inside the discovery worker, never the home coordinator or its I/O queue.
enum UsageSourceDiscovery {
    static func codex(databaseURL: URL, deadlineSeconds: Double = 10,
                      page: ([UsageDiscoveredSource]) throws -> Void) throws -> UsageDiscoveryResult {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw UsageIndexError.cacheInvalid
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        let deadline = Deadline(seconds: deadlineSeconds)
        sqlite3_progress_handler(database, 1000, { pointer in
            guard let pointer else { return 1 }
            return Unmanaged<Deadline>.fromOpaque(pointer).takeUnretainedValue().expired ? 1 : 0
        }, Unmanaged.passUnretained(deadline).toOpaque())
        defer { sqlite3_progress_handler(database, 0, nil, nil) }
        guard sqlite3_exec(database, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw UsageIndexError.indexBusy }
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
        // ORDER BY stable id within one read snapshot: updated_at can move backwards.
        var columns = Set<String>()
        var schemaStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(threads)", -1, &schemaStatement, nil) == SQLITE_OK,
              let schemaStatement else { throw UsageIndexError.cacheInvalid }
        while sqlite3_step(schemaStatement) == SQLITE_ROW {
            if let name = sqlite3_column_text(schemaStatement, 1) { columns.insert(String(cString: name)) }
        }
        sqlite3_finalize(schemaStatement)
        let created = columns.contains("created_at") ? "created_at" : "NULL"
        let kind = columns.contains("thread_source") ? "thread_source" : "NULL"
        let automation = columns.contains("title") && columns.contains("thread_source") ? """
            CASE WHEN thread_source='automation' AND instr(title,'Automation ID: ')>0
            THEN substr(substr(title,instr(title,'Automation ID: ')+15),1,instr(substr(title,instr(title,'Automation ID: ')+15),char(10))-1)
            ELSE NULL END
            """ : "NULL"
        let sql = """
            SELECT id,rollout_path,model,cwd,updated_at,\(created),\(kind),\(automation) FROM threads
            WHERE rollout_path IS NOT NULL AND rollout_path<>'' ORDER BY id
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw UsageIndexError.cacheInvalid
        }
        defer { sqlite3_finalize(statement) }
        var pending: [UsageDiscoveredSource] = []
        var total = 0
        var metadataBytes = 0
        func text(_ column: Int32) throws -> String? {
            if sqlite3_column_type(statement, column) == SQLITE_NULL { return nil }
            let size = Int(sqlite3_column_bytes(statement, column))
            guard size <= 16384 else { throw UsageIndexError.resourceLimited }
            guard let bytes = sqlite3_column_text(statement, column) else { return nil }
            return String(decoding: UnsafeBufferPointer(start: bytes, count: size), as: UTF8.self)
        }
        while !deadline.expired {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                if !pending.isEmpty { try page(pending) }
                return UsageDiscoveryResult(sources: total, complete: true, metadataBytes: metadataBytes)
            }
            if status == SQLITE_INTERRUPT { break }
            guard status == SQLITE_ROW else { throw UsageIndexError.databaseFailure }
            guard let id = try text(0), let locator = try text(1), !id.isEmpty else { throw UsageIndexError.cacheInvalid }
            let source = try UsageDiscoveredSource(runtime: "codex", logicalID: id, locator: locator,
                model: text(2), project: text(3) ?? "", updatedAt: sqlite3_column_int64(statement, 4),
                createdAt: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 5),
                sourceKind: text(6), automationID: text(7))
            let size = try JSONEncoder().encode(source).count
            guard metadataBytes + size <= 128 * 1024 * 1024 else {
                if !pending.isEmpty { try page(pending) }
                return UsageDiscoveryResult(sources: total, complete: false, metadataBytes: metadataBytes)
            }
            metadataBytes += size
            total += 1
            pending.append(source)
            if pending.count == 256 { try page(pending); pending.removeAll(keepingCapacity: true) }
        }
        if !pending.isEmpty { try page(pending) }
        return UsageDiscoveryResult(sources: total, complete: false, metadataBytes: metadataBytes)
    }

    private final class Deadline {
        let end: UInt64
        init(seconds: Double) {
            let bounded = seconds.isFinite ? min(max(seconds, 0), 10) : 0
            end = DispatchTime.now().uptimeNanoseconds + UInt64(bounded * 1_000_000_000)
        }
        var expired: Bool { DispatchTime.now().uptimeNanoseconds >= end }
    }
}
