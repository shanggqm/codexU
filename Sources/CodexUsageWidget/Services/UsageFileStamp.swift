import CryptoKit
import Darwin
import Foundation

/// Checks bounded head/committed-boundary blocks. Interior rewrites require the separate integrity scan.
struct UsageFileStamp: Codable, Equatable {
    let identity: String
    let size: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let committedOffset: UInt64
    let headDigest: String
    let boundaryDigest: String

    static func capture(url: URL, committedOffset: UInt64) throws -> UsageFileStamp {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw UsageIndexError.sourceChanged }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0, UInt64(before.st_size) >= committedOffset else { throw UsageIndexError.sourceChanged }
        func digest(start: UInt64, count: Int) throws -> String {
            try handle.seek(toOffset: start)
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { throw UsageIndexError.sourceChanged }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let count = Int(min(committedOffset, 4096))
        let head = try digest(start: 0, count: count)
        let boundary = try digest(start: committedOffset - UInt64(count), count: count)
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw UsageIndexError.sourceChanged }
        let identity = "\(before.st_dev):\(before.st_ino):\(before.st_birthtimespec.tv_sec):\(before.st_birthtimespec.tv_nsec)"
        return UsageFileStamp(identity: identity, size: UInt64(before.st_size),
            modifiedSeconds: Int64(before.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(before.st_mtimespec.tv_nsec),
            committedOffset: committedOffset, headDigest: head, boundaryDigest: boundary)
    }

    func validatesPrefix(of candidate: UsageFileStamp) -> Bool {
        identity == candidate.identity && committedOffset == candidate.committedOffset
            && candidate.size >= committedOffset && headDigest == candidate.headDigest
            && boundaryDigest == candidate.boundaryDigest
    }

    /// A frozen target that split a line can extend only to its first subsequent newline.
    /// nil means wait for source growth, not EOF and not a complete generation.
    static func completingBoundary(url: URL, frozenEnd: UInt64) throws -> UInt64? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw UsageIndexError.sourceChanged }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0, UInt64(before.st_size) >= frozenEnd else { throw UsageIndexError.sourceChanged }
        try handle.seek(toOffset: frozenEnd)
        var position = frozenEnd
        let maximum = UInt64(UsageStreamParser.maximumLineBytes + UsageStreamParser.chunkBytes)
        while position < UInt64(before.st_size), position - frozenEnd < maximum {
            let count = Int(min(UInt64(UsageStreamParser.chunkBytes), UInt64(before.st_size) - position, maximum - (position - frozenEnd)))
            guard let data = try handle.read(upToCount: count), !data.isEmpty else { throw UsageIndexError.sourceChanged }
            if let newline = data.firstIndex(of: 10) {
                var after = stat()
                guard fstat(descriptor, &after) == 0, before.st_size == after.st_size,
                      before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw UsageIndexError.sourceChanged }
                return position + UInt64(data.distance(from: data.startIndex, to: newline)) + 1
            }
            position += UInt64(data.count)
        }
        if position - frozenEnd >= maximum { throw UsageIndexError.resourceLimited }
        return nil
    }
}
