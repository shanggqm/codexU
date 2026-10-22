import Darwin
import Foundation

/// One disposable plaintext mirror per parser slot; persistent checkpoints use the compressed source identity.
final class UsageCompressedSource {
    static let maximumMirrorBytes: Int64 = 32 * 1024 * 1024 * 1024
    static var executableURL: URL? {
        ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }).map { URL(fileURLWithPath: $0) }
    }
    private let directory: URL?
    private var source: URL?
    private var physical: UsageFileStamp?
    private var mirror: URL?

    init(directory: URL?) { self.directory = directory }
    deinit { release() }

    static func resolve(path: String, runtime: String) -> URL {
        let url = URL(fileURLWithPath: path)
        if runtime == "codex", url.pathExtension == "jsonl",
           !FileManager.default.fileExists(atPath: url.path) {
            let compressed = url.appendingPathExtension("zst")
            if FileManager.default.fileExists(atPath: compressed.path) { return compressed }
        }
        return url
    }

    static func fingerprint(_ url: URL) throws -> UsageFileStamp {
        let first = try UsageFileStamp.capture(url: url, committedOffset: 0)
        let full = try UsageFileStamp.capture(url: url, committedOffset: first.size)
        guard first.identity == full.identity, first.size == full.size,
              first.modifiedSeconds == full.modifiedSeconds,
              first.modifiedNanoseconds == full.modifiedNanoseconds else { throw UsageIndexError.sourceChanged }
        return full
    }

    static func identity(_ physical: UsageFileStamp) -> String {
        "zstd:\(physical.identity):\(physical.size):\(physical.modifiedSeconds):\(physical.modifiedNanoseconds):\(physical.headDigest):\(physical.boundaryDigest)"
    }

    static func stamp(_ logical: UsageFileStamp, physical: UsageFileStamp) -> UsageFileStamp {
        UsageFileStamp(identity: identity(physical), size: logical.size,
            modifiedSeconds: physical.modifiedSeconds, modifiedNanoseconds: physical.modifiedNanoseconds,
            committedOffset: logical.committedOffset, headDigest: logical.headDigest, boundaryDigest: logical.boundaryDigest)
    }

    func prepare(_ url: URL, physical expected: UsageFileStamp) throws -> URL {
        if source == url, physical == expected, let mirror,
           FileManager.default.fileExists(atPath: mirror.path) { return mirror }
        release()
        guard let directory, let executable = Self.executableURL else { throw UsageIndexError.resourceLimited }
        let outputURL = directory.appendingPathComponent("source.jsonl")
        let outputFD = open(outputURL.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard outputFD >= 0 else { throw UsageIndexError.diskFull }
        mirror = outputURL
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? output.close() }
        let inputFD = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard inputFD >= 0 else { release(); throw UsageIndexError.sourceChanged }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        defer { try? input.close() }
        var inputInformation = stat()
        guard fstat(inputFD, &inputInformation) == 0, inputInformation.st_mode & S_IFMT == S_IFREG else {
            release(); throw UsageIndexError.sourceChanged
        }
        let child = Process()
        child.executableURL = executable
        child.arguments = ["--decompress", "--stdout", "--quiet"]
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        do {
            try child.run()
            let deadline = ProcessInfo.processInfo.systemUptime + 55
            while child.isRunning {
                var information = stat()
                guard fstat(outputFD, &information) == 0 else { throw UsageIndexError.cacheInvalid }
                guard information.st_size <= Self.maximumMirrorBytes else { throw UsageIndexError.resourceLimited }
                let free = try FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber
                guard (free?.int64Value ?? 0) > 1024 * 1024 * 1024 else { throw UsageIndexError.diskFull }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw UsageIndexError.cancelled }
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard child.terminationStatus == 0 else { throw UsageIndexError.cacheInvalid }
            var information = stat()
            guard fstat(outputFD, &information) == 0, information.st_size <= Self.maximumMirrorBytes else {
                throw UsageIndexError.resourceLimited
            }
            guard try Self.fingerprint(url) == expected else { throw UsageIndexError.sourceChanged }
            source = url; physical = expected
            return outputURL
        } catch {
            if child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL); child.waitUntilExit() }
            release()
            throw error
        }
    }

    func release(ifPlaintextSource url: URL) {
        if source == url.appendingPathExtension("zst") { release() }
    }

    func release() {
        if let mirror { try? FileManager.default.removeItem(at: mirror) }
        mirror = nil; source = nil; physical = nil
    }
}
