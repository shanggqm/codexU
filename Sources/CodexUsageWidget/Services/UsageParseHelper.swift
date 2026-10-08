import Darwin
import Foundation

struct UsageParseRequest: Codable {
    let id: String
    let path: String
    let targetEnd: UInt64
    let checkpoint: CodexIndexCheckpoint
    let previousStamp: UsageFileStamp?
    var finishFrozenTail: Bool = false
    var runtime: String = "codex"
    var claudeCheckpoint: ClaudeIndexCheckpoint? = nil
    var forceRebuild = false
}

struct UsageParseResponse: Codable {
    let batch: CodexIndexBatch
    let stamp: UsageFileStamp
    var claude: ClaudeIndexBatch? = nil
    var requiresRebuild: Bool = false
    var completedBoundary: UInt64? = nil
}

private struct UsageParseFrame: Codable {
    let id: String
    let chunk: Data?
    let end: Bool
    let error: String?
}

/// One persistent process slot, owned by one helper queue. Never invoke on the index writer queue.
final class UsageParseHelper {
    static let maximumFrame = 256 * 1024
    static let maximumResponse = 4 * 1024 * 1024
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var ownsGroup = false

    deinit { terminate() }

    func parse(_ request: UsageParseRequest, timeout: Double = 5) throws -> UsageParseResponse {
        let encoded = try JSONEncoder().encode(request)
        guard encoded.count + 1 <= Self.maximumFrame else { throw UsageIndexError.resourceLimited }
        let deadline = ProcessInfo.processInfo.systemUptime + min(max(timeout, 0), 5)
        do {
            try start()
            guard let input, let output, let process else { throw UsageIndexError.resourceLimited }
            var packet = encoded; packet.append(10)
            var sent = 0
            var pending = Data()
            var response = Data()
            var bytes = [UInt8](repeating: 0, count: 32 * 1024)
            while ProcessInfo.processInfo.systemUptime < deadline {
                if getpgid(process.processIdentifier) == process.processIdentifier { ownsGroup = true }
                if sent < packet.count {
                    let count = packet.withUnsafeBytes { buffer in
                        Darwin.write(input.fileDescriptor, buffer.baseAddress!.advanced(by: sent), packet.count - sent)
                    }
                    if count > 0 { sent += count }
                    else if count < 0, errno != EINTR, errno != EAGAIN, errno != EWOULDBLOCK { throw UsageIndexError.sourceChanged }
                }
                let count = bytes.withUnsafeMutableBytes { Darwin.read(output.fileDescriptor, $0.baseAddress!, $0.count) }
                if count > 0 {
                    pending.append(contentsOf: bytes.prefix(count))
                    while let newline = pending.firstIndex(of: 10) {
                        let length = pending.distance(from: pending.startIndex, to: newline)
                        guard length <= Self.maximumFrame else { throw UsageIndexError.resourceLimited }
                        let frame = try JSONDecoder().decode(UsageParseFrame.self, from: pending.prefix(length))
                        pending.removeSubrange(pending.startIndex...newline)
                        guard frame.id == request.id else { throw UsageIndexError.sourceChanged }
                        if let error = frame.error { throw UsageIndexError(rawValue: error) ?? .databaseFailure }
                        if let chunk = frame.chunk {
                            guard chunk.count <= Self.maximumResponse - response.count else { throw UsageIndexError.resourceLimited }
                            response.append(chunk)
                        }
                        if frame.end { return try JSONDecoder().decode(UsageParseResponse.self, from: response) }
                    }
                    guard pending.count <= Self.maximumFrame else { throw UsageIndexError.resourceLimited }
                } else if count == 0 { throw UsageIndexError.sourceChanged }
                else if errno != EINTR, errno != EAGAIN, errno != EWOULDBLOCK { throw UsageIndexError.sourceChanged }
                var descriptors = [pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0),
                                   pollfd(fd: input.fileDescriptor, events: sent < packet.count ? Int16(POLLOUT) : 0, revents: 0)]
                _ = Darwin.poll(&descriptors, 2, 10)
            }
            throw UsageIndexError.cancelled
        } catch {
            terminate()
            throw error
        }
    }

    private func start() throws {
        if let process {
            if process.isRunning {
                guard input != nil, output != nil else { throw UsageIndexError.resourceLimited }
                return
            }
            self.process = nil
        }
        guard let executable = Bundle.main.executableURL else { throw UsageIndexError.resourceLimited }
        let child = Process()
        child.executableURL = executable
        child.arguments = ["--usage-parse-helper"]
        let incoming = Pipe(), outgoing = Pipe()
        child.standardInput = incoming; child.standardOutput = outgoing; child.standardError = FileHandle.nullDevice
        try child.run()
        try? incoming.fileHandleForReading.close(); try? outgoing.fileHandleForWriting.close()
        process = child; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading; ownsGroup = false
        guard fcntl(incoming.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            terminate(); throw UsageIndexError.resourceLimited
        }
        for handle in [input, output].compactMap({ $0 }) {
            let descriptor = handle.fileDescriptor
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                terminate(); throw UsageIndexError.resourceLimited
            }
        }
    }

    private func terminate() {
        if let process, process.isRunning {
            let pid = process.processIdentifier
            if getpgid(pid) == pid { ownsGroup = true }
            if ownsGroup { _ = Darwin.kill(-pid, SIGKILL) }
            else { _ = Darwin.kill(pid, SIGKILL) }
        }
        try? input?.close(); try? output?.close(); input = nil; output = nil
        // Retain a still-running process in this slot. It must not trigger unlimited respawns.
        if process?.isRunning == false { process = nil }
    }

    static func runChild() -> Int32 {
        guard setpgid(0, 0) == 0 || getpgrp() == getpid() else { return 2 }
        var pending = Data()
        do {
            var incoming = [UInt8](repeating: 0, count: 32 * 1024)
            while true {
                let count = Darwin.read(STDIN_FILENO, &incoming, incoming.count)
                if count == 0 { break }
                if count < 0 { if errno == EINTR { continue }; return 1 }
                pending.append(contentsOf: incoming.prefix(count))
                while let newline = pending.firstIndex(of: 10) {
                    let length = pending.distance(from: pending.startIndex, to: newline)
                    guard length <= maximumFrame else { return 2 }
                    // Persistent helpers must release Foundation temporaries after every batch.
                    try autoreleasepool {
                    let request = try JSONDecoder().decode(UsageParseRequest.self, from: pending.prefix(length))
                    pending.removeSubrange(pending.startIndex...newline)
                    do {
                        guard request.path.utf8.count <= 16384, request.id.utf8.count <= 128 else { throw UsageIndexError.resourceLimited }
                        let url = URL(fileURLWithPath: request.path)
                        let metadata = try UsageFileStamp.capture(url: url, committedOffset: 0)
                        var before = metadata
                        var rebuild = request.forceRebuild || request.targetEnd > metadata.size
                            || (request.previousStamp.map { $0.size > metadata.size } ?? false)
                        if !rebuild {
                            before = try UsageFileStamp.capture(url: url, committedOffset: request.checkpoint.cursor.offset)
                            if let previous = request.previousStamp {
                                rebuild = !previous.validatesPrefix(of: before)
                                    || (previous.size == before.size && (previous.modifiedSeconds != before.modifiedSeconds
                                        || previous.modifiedNanoseconds != before.modifiedNanoseconds))
                            }
                        }
                        if request.claudeCheckpoint?.usedFallbackTimestamp == true, let previous = request.previousStamp,
                           previous.modifiedSeconds != metadata.modifiedSeconds || previous.modifiedNanoseconds != metadata.modifiedNanoseconds {
                            rebuild = true
                        }
                        var boundary: UInt64?
                        if request.finishFrozenTail, !rebuild {
                            if request.checkpoint.cursor.largeProjection != nil,metadata.size>request.targetEnd {
                                // A streamed oversized tail can advance in bounded pieces even when
                                // its closing newline has not yet arrived.
                                do { boundary = try UsageFileStamp.completingBoundary(url:url,frozenEnd:request.targetEnd) }
                                catch UsageIndexError.resourceLimited { boundary = nil }
                                if boundary == nil { boundary = min(metadata.size,request.targetEnd+UInt64(UsageStreamParser.batchBytes)) }
                            } else {
                                boundary = try UsageFileStamp.completingBoundary(url: url, frozenEnd: request.targetEnd)
                            }
                        }
                        let parser = rebuild ? CodexIndexCheckpoint() : request.checkpoint
                        let target = rebuild ? 0 : request.targetEnd
                        guard target <= metadata.size else { throw UsageIndexError.sourceChanged }
                        let frozenStamp = try UsageFileStamp.capture(url: url, committedOffset: target)
                        let batch: CodexIndexBatch
                        var claude: ClaudeIndexBatch?
                        if request.runtime == "codex" {
                            batch = try UsageStreamParser.readCodex(url: url, targetEnd: target, checkpoint: parser, maximumLines: 200)
                        } else if request.runtime == "claude-code" {
                            let state = rebuild ? ClaudeIndexCheckpoint() : (request.claudeCheckpoint ?? ClaudeIndexCheckpoint())
                            let parsed = try ClaudeIncrementalAdapter.read(url: url, targetEnd: target, checkpoint: state,
                                modificationDate: Date(timeIntervalSince1970: Double(metadata.modifiedSeconds) + Double(metadata.modifiedNanoseconds) / 1_000_000_000))
                            claude = parsed
                            var common = CodexIndexCheckpoint(); common.cursor = parsed.checkpoint.cursor
                            batch = CodexIndexBatch(checkpoint: common, deltas: [], inferenceSamples: [], toolCalls: [:], skillLoads: [],
                                readBytes: parsed.readBytes, reachedTarget: parsed.reachedTarget, awaitingNewline: parsed.awaitingNewline)
                        } else { throw UsageIndexError.cacheInvalid }
                        let stamp = try UsageFileStamp.capture(url: url, committedOffset: batch.checkpoint.cursor.offset)
                        let verifiedTarget = try UsageFileStamp.capture(url: url, committedOffset: target)
                        guard frozenStamp.validatesPrefix(of: verifiedTarget), metadata.identity == stamp.identity,
                              stamp.size >= metadata.size,
                              stamp.size > metadata.size || (metadata.modifiedSeconds == stamp.modifiedSeconds
                                && metadata.modifiedNanoseconds == stamp.modifiedNanoseconds) else { throw UsageIndexError.sourceChanged }
                        let data = try JSONEncoder().encode(UsageParseResponse(batch: batch, stamp: stamp, claude: claude,
                            requiresRebuild: rebuild, completedBoundary: boundary))
                        guard data.count <= maximumResponse else { throw UsageIndexError.resourceLimited }
                        var offset = 0
                        while offset < data.count {
                            let end = min(offset + 128 * 1024, data.count)
                            try send(UsageParseFrame(id: request.id, chunk: data.subdata(in: offset..<end), end: end == data.count, error: nil))
                            offset = end
                        }
                    } catch {
                        try send(UsageParseFrame(id: request.id, chunk: nil, end: true,
                                                 error: (error as? UsageIndexError)?.rawValue ?? UsageIndexError.cacheInvalid.rawValue))
                    }
                    }
                }
                guard pending.count <= maximumFrame else { return 2 }
            }
            return 0
        } catch { return 1 }
    }

    private static func send(_ frame: UsageParseFrame) throws {
        var data = try JSONEncoder().encode(frame)
        guard data.count <= maximumFrame else { throw UsageIndexError.resourceLimited }
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
