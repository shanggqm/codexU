import Darwin
import Foundation

/// Numeric continuation only: incomplete/raw lines never enter a checkpoint.
struct UsageStreamCursor: Codable, Equatable {
    var offset: UInt64 = 0
    var lastCompleteOffset: UInt64? = nil
    var skippingOversizedLine = false
    var oversizedLineCount: UInt64 = 0
    var largeProjection: UsageLargeJSONProjection? = nil
}

struct UsageStreamBatch {
    let cursor: UsageStreamCursor
    let readBytes: Int
    let lineCount: Int
    let reachedTarget: Bool
    let awaitingNewline: Bool
}

/// Caller runs this only in an isolated parser helper, since even local disk reads can block.
/// A complete line is the minimum commit unit; the 1 MiB batch budget is soft for one long line.
enum UsageStreamParser {
    static let chunkBytes = 64 * 1024
    static let maximumLineBytes = 4 * 1024 * 1024
    static let batchBytes = 1024 * 1024

    static func read(url: URL, targetEnd: UInt64, cursor: UsageStreamCursor,
                     maximumLines: Int = 1000, projectLargeJSON: Bool = false, consume: (Data, UInt64) throws -> Void) throws -> UsageStreamBatch {
        guard maximumLines > 0, maximumLines <= 1000, cursor.offset <= targetEnd else {
            throw UsageIndexError.sourceChanged
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw UsageIndexError.sourceChanged }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_size >= 0, UInt64(attributes.st_size) >= targetEnd else {
            throw UsageIndexError.sourceChanged
        }
        try handle.seek(toOffset: cursor.offset)
        var next = cursor
        var position = cursor.offset
        var lineStart = position
        var buffer = Data()
        var readBytes = 0
        var lines = 0
        let started = DispatchTime.now().uptimeNanoseconds
        func result(_ awaiting: Bool = false) -> UsageStreamBatch {
            UsageStreamBatch(cursor: next, readBytes: readBytes, lineCount: lines,
                             reachedTarget: next.offset == targetEnd && !next.skippingOversizedLine, awaitingNewline: awaiting)
        }
        while position < targetEnd {
            let count = Int(min(UInt64(chunkBytes), targetEnd - position))
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                throw UsageIndexError.sourceChanged
            }
            readBytes += chunk.count
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 10)
                let end = newline ?? chunk.endIndex
                let segmentCount = chunk.distance(from: start, to: end)
                if !next.skippingOversizedLine {
                    if buffer.count + segmentCount > maximumLineBytes {
                        if projectLargeJSON {
                            next.largeProjection = UsageLargeJSONProjection()
                            next.largeProjection?.feed(buffer)
                            next.largeProjection?.feed(Data(chunk[start..<end]))
                        }
                        buffer.removeAll(keepingCapacity: false)
                        next.skippingOversizedLine = true
                        next.oversizedLineCount += 1
                    } else {
                        buffer.append(contentsOf: chunk[start..<end])
                    }
                } else { next.largeProjection?.feed(Data(chunk[start..<end])) }
                position += UInt64(segmentCount)
                if let newline {
                    if !next.skippingOversizedLine { try consume(buffer, lineStart) }
                    else if let projected = next.largeProjection?.finish() {
                        try consume(projected,lineStart)
                        next.oversizedLineCount -= 1
                    }
                    next.largeProjection = nil
                    position += 1
                    next.offset = position
                    next.lastCompleteOffset = position
                    next.skippingOversizedLine = false
                    buffer.removeAll(keepingCapacity: true)
                    lineStart = position
                    lines += 1
                    let elapsed = DispatchTime.now().uptimeNanoseconds - started
                    if lines >= maximumLines || readBytes >= batchBytes || elapsed >= 50_000_000 {
                        return result()
                    }
                    start = chunk.index(after: newline)
                } else {
                    // While discarding an oversized line, preserve forward progress without its bytes.
                    if next.skippingOversizedLine { next.offset = position }
                    start = end
                }
            }
            if next.skippingOversizedLine, readBytes >= batchBytes { return result() }
        }
        // Do not parse an unterminated tail: its content may still be appended or replaced.
        return result(!buffer.isEmpty || next.skippingOversizedLine)
    }
}


struct CodexIndexCheckpoint: Codable {
    var cursor = UsageStreamCursor()
    var forkedFromID: String?
    var activeModel: String?
    var activeServiceTier: String?
    var inferenceTracker = ModelInferenceCallTracker()
    var counterState = CodexTokenCounterState()
    var sawTokenEvent = false
    var tokenEventCount = 0
}

struct CodexIndexBatch: Codable {
    let checkpoint: CodexIndexCheckpoint
    let deltas: [SessionUsageDelta]
    let inferenceSamples: [ModelInferenceSample]
    let toolCalls: [String: Int]
    let skillLoads: [SkillLoadEvent]
    let readBytes: Int
    let reachedTarget: Bool
    let awaitingNewline: Bool
    var turnEvents: [UsageCodexTurnEvent] = []
}

extension UsageStreamParser {
    static func readCodex(url: URL, targetEnd: UInt64, checkpoint: CodexIndexCheckpoint,
                          maximumLines: Int = 1000) throws -> CodexIndexBatch {
        var next = checkpoint
        var deltas: [SessionUsageDelta] = []
        var inferenceSamples: [ModelInferenceSample] = []
        var tools: [String: Int] = [:]
        var skills: [SkillLoadEvent] = []
        var turns: [UsageCodexTurnEvent] = []
        let reader = CodexUsageReader()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func needle(_ type: String) -> Data { Data(("\"type\":\"" + type + "\"").utf8) }
        let boundaries = ["function_call_output", "custom_tool_call_output", "tool_search_output",
                          "mcp_tool_call_end", "web_search_end", "patch_apply_end", "image_generation_end"].map(needle)
        let outputs = ["reasoning", "agent_reasoning", "agent_message", "function_call", "custom_tool_call",
                       "tool_search_call", "web_search_call"].map(needle) + [Data(#""role":"assistant""#.utf8)]
        let batch = try read(url: url, targetEnd: targetEnd, cursor: checkpoint.cursor,
                             maximumLines: maximumLines, projectLargeJSON: true) { line, _ in
            if let turn = UsageLeadershipAdapter.event(line) { turns.append(turn) }
            reader.processSessionLine(line,
                sessionMetaNeedle: needle("session_meta"), turnContextNeedle: needle("turn_context"),
                threadSettingsNeedle: needle("thread_settings_applied"), tokenCountNeedle: needle("token_count"),
                functionCallNeedle: needle("function_call"), customToolCallNeedle: needle("custom_tool_call"),
                inferenceBoundaryNeedles: boundaries, modelOutputNeedles: outputs,
                fractionalFormatter: fractional, plainFormatter: plain,
                forkedFromId: &next.forkedFromID, activeModel: &next.activeModel,
                activeServiceTier: &next.activeServiceTier, inferenceTracker: &next.inferenceTracker,
                counterState: &next.counterState, sawTokenEvent: &next.sawTokenEvent,
                tokenEventCount: &next.tokenEventCount, deltas: &deltas, inferenceSamples: &inferenceSamples,
                toolCalls: &tools, skillLoads: &skills)
        }
        next.cursor = batch.cursor
        guard try JSONEncoder().encode(next).count <= 256 * 1024 else { throw UsageIndexError.resourceLimited }
        let result = CodexIndexBatch(checkpoint: next, deltas: deltas, inferenceSamples: inferenceSamples,
                                    toolCalls: tools, skillLoads: skills, readBytes: batch.readBytes,
                                    reachedTarget: batch.reachedTarget, awaitingNewline: batch.awaitingNewline, turnEvents: turns)
        guard try JSONEncoder().encode(result).count <= 4 * 1024 * 1024 else { throw UsageIndexError.resourceLimited }
        return result
    }
}
