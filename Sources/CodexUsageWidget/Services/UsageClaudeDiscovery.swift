import Foundation

extension UsageSourceDiscovery {
    static func claude(root: URL, page: ([UsageDiscoveredSource]) throws -> Void) throws -> UsageDiscoveryResult {
        let started = ProcessInfo.processInfo.systemUptime
        var complete = true
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in complete = false; return true }) else {
            throw UsageIndexError.cacheInvalid
        }
        var pending: [UsageDiscoveredSource] = []
        var count = 0, bytes = 0
        for case let url as URL in enumerator {
            if ProcessInfo.processInfo.systemUptime - started > 10 { complete = false; break }
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            if properties.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard url.pathExtension == "jsonl", properties.isRegularFile == true else { continue }
            guard url.path.utf8.count <= 16384 else { complete = false; continue }
            let source = UsageDiscoveredSource(runtime: "claude-code", logicalID: url.path, locator: url.path,
                model: nil, project: "", updatedAt: Int64((properties.contentModificationDate ?? .distantPast).timeIntervalSince1970))
            let size = try JSONEncoder().encode(source).count
            guard bytes + size <= 128 * 1024 * 1024 else { complete = false; break }
            bytes += size; count += 1; pending.append(source)
            if pending.count == 256 { try page(pending); pending.removeAll(keepingCapacity: true) }
        }
        if !pending.isEmpty { try page(pending) }
        return UsageDiscoveryResult(sources: count, complete: complete, metadataBytes: bytes)
    }
}
