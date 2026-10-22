import Foundation

enum UsageStreamParserSelfTest {
    static func run() -> Bool {
        func check(_ value: Bool) throws { if !value { throw UsageIndexError.databaseFailure } }
        do {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 defer { try? FileManager.default.removeItem(at:root) }
 let url=root.appendingPathComponent("fixture.jsonl")
 var data=Data("one\ntwo\ntail".utf8)
 try data.write(to:url)
 var lines:[String]=[]
 let first=try UsageStreamParser.read(url:url,targetEnd:UInt64(data.count),cursor:UsageStreamCursor(),maximumLines:1) { line,_ in lines.append(String(decoding:line,as:UTF8.self)) }
 try check(first.cursor.offset == 4)
 let second=try UsageStreamParser.read(url:url,targetEnd:UInt64(data.count),cursor:first.cursor) { line,_ in lines.append(String(decoding:line,as:UTF8.self)) }
 try check(second.cursor.offset == 8 && second.awaitingNewline && lines == ["one","two"])
 data.append(10);try data.write(to:url)
 let third=try UsageStreamParser.read(url:url,targetEnd:UInt64(data.count),cursor:second.cursor) { line,_ in lines.append(String(decoding:line,as:UTF8.self)) }
 try check(third.reachedTarget && lines == ["one","two","tail"])
 for size in [1_500_000,3_900_000,5_000_000] {
 data=Data(repeating:97,count:size);data.append(contentsOf:[10,122,10]);try data.write(to:url)
 var cursor=UsageStreamCursor();var lengths:[Int]=[];var batches=0
 while cursor.offset < data.count {
 let batch=try UsageStreamParser.read(url:url,targetEnd:UInt64(data.count),cursor:cursor) { line,_ in lengths.append(line.count) }
 try check(batch.cursor.offset>cursor.offset);cursor=batch.cursor;batches+=1;try check(batches<10)
 }
 try check(lengths == (size>UsageStreamParser.maximumLineBytes ? [1] : [size,1]))
 try check(cursor.oversizedLineCount == (size>UsageStreamParser.maximumLineBytes ? 1:0))
 }

            let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("tests/fixtures/history-index/codex-counters.jsonl")
            let fixtureBytes = try Data(contentsOf: fixture).count
            let whole = try UsageStreamParser.readCodex(url: fixture, targetEnd: UInt64(fixtureBytes), checkpoint: CodexIndexCheckpoint())
            var checkpoint = CodexIndexCheckpoint()
            var incremental: [SessionUsageDelta] = []
            repeat {
                let batch = try UsageStreamParser.readCodex(url: fixture, targetEnd: UInt64(fixtureBytes), checkpoint: checkpoint, maximumLines: 1)
                incremental += batch.deltas
                checkpoint = try JSONDecoder().decode(CodexIndexCheckpoint.self, from: JSONEncoder().encode(batch.checkpoint))
            } while checkpoint.cursor.offset < fixtureBytes
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try check(encoder.encode(incremental) == encoder.encode(whole.deltas))
            try check(checkpoint.tokenEventCount == 5 && incremental.count == 4)
            try check(incremental.map(\.totalForTest) == [100, 45, 15, 15])
            for filename in ["codex-counters.jsonl", "codex-inference.jsonl"] {
                let source = fixture.deletingLastPathComponent().appendingPathComponent(filename)
                let size = try Data(contentsOf: source).count
                guard let oracle = CodexUsageReader().historyIndexOracle(url: source) else {
                    throw UsageIndexError.databaseFailure
                }
                var state = CodexIndexCheckpoint()
                var deltas: [SessionUsageDelta] = []
                var samples: [ModelInferenceSample] = []
                var skills: [SkillLoadEvent] = []
                var calls: [String: Int] = [:]
                repeat {
                    let batch = try UsageStreamParser.readCodex(url: source, targetEnd: UInt64(size), checkpoint: state, maximumLines: 1)
                    deltas += batch.deltas; samples += batch.inferenceSamples; skills += batch.skillLoads
                    for (name, count) in batch.toolCalls { calls[name, default: 0] += count }
                    state = try JSONDecoder().decode(CodexIndexCheckpoint.self, from: encoder.encode(batch.checkpoint))
                } while state.cursor.offset < size
                try check(encoder.encode(deltas) == encoder.encode(oracle.deltas))
                try check(encoder.encode(samples) == encoder.encode(oracle.inferenceSamples))
                try check(encoder.encode(skills) == encoder.encode(oracle.skillLoads))
                try check(calls == oracle.toolCalls && state.tokenEventCount == oracle.checkpoint.tokenEventCount)
                try check(state.forkedFromID == oracle.checkpoint.forkedFromID)
                if filename == "codex-inference.jsonl" { try check(samples.count == 3) }
            }
            let helper = UsageParseHelper()
            let request = UsageParseRequest(id: UUID().uuidString, path: fixture.path,
                targetEnd: UInt64(fixtureBytes), checkpoint: CodexIndexCheckpoint(), previousStamp: nil)
            let parsed = try helper.parse(request)
            try check(encoder.encode(parsed.batch.deltas) == encoder.encode(whole.deltas))
            let repeated = try helper.parse(UsageParseRequest(id: UUID().uuidString, path: fixture.path,
                targetEnd: UInt64(fixtureBytes), checkpoint: parsed.batch.checkpoint, previousStamp: parsed.stamp))
            try check(repeated.batch.readBytes == 0 && repeated.batch.deltas.isEmpty)
            if let zstd = UsageCompressedSource.executableURL {
                let plain = root.appendingPathComponent("compressed.jsonl")
                let packed = plain.appendingPathExtension("zst")
                func compress(_ bytes: Data) throws {
                    try bytes.write(to: plain)
                    try? FileManager.default.removeItem(at: packed)
                    guard FileManager.default.createFile(atPath: packed.path, contents: nil,
                        attributes: [.posixPermissions: 0o600]) else { throw UsageIndexError.diskFull }
                    let output = try FileHandle(forWritingTo: packed)
                    defer { try? output.close() }
                    let process = Process()
                    process.executableURL = zstd
                    process.arguments = ["--compress", "--stdout", "--quiet", "--", plain.path]
                    process.standardOutput = output; process.standardError = FileHandle.nullDevice
                    try process.run(); process.waitUntilExit()
                    guard process.terminationStatus == 0 else { throw UsageIndexError.cacheInvalid }
                }
                let original = try Data(contentsOf: fixture)
                var multiple = Data()
                for _ in 0..<60 { multiple.append(original) }
                try compress(multiple)
                try check(!UsageParseHelper.isCompressedSource(path: plain.path))
                var expectedState = CodexIndexCheckpoint(), expectedDeltas: [SessionUsageDelta] = []
                repeat {
                    let value = try UsageStreamParser.readCodex(url: plain, targetEnd: UInt64(multiple.count),
                        checkpoint: expectedState)
                    expectedDeltas += value.deltas; expectedState = value.checkpoint
                } while expectedState.cursor.offset < multiple.count
                try FileManager.default.removeItem(at: plain)
                try check(UsageParseHelper.isCompressedSource(path: plain.path))
                try check(UsageParseHelper.isCompressedSource(path: packed.path))
                let directory = root.appendingPathComponent("mirror")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700])
                let mirror = UsageCompressedSource(directory: directory)
                let physical = try UsageCompressedSource.fingerprint(packed)
                let prepared = try mirror.prepare(packed, physical: physical)
                let preparedStamp = try UsageFileStamp.capture(url: prepared, committedOffset: UInt64(multiple.count))
                try check(try mirror.prepare(packed, physical: physical) == prepared)
                try check(try UsageFileStamp.capture(url: prepared, committedOffset: UInt64(multiple.count)) == preparedStamp)
                try check((try FileManager.default.attributesOfItem(atPath: prepared.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
                mirror.release(ifPlaintextSource: fixture)
                try check(FileManager.default.fileExists(atPath: prepared.path))
                mirror.release(ifPlaintextSource: plain)
                try check(!FileManager.default.fileExists(atPath: prepared.path))
                let restored = try mirror.prepare(packed, physical: physical)
                try check(UsageCompressedSource.stamp(try UsageFileStamp.capture(url: restored,
                    committedOffset: UInt64(multiple.count)), physical: physical)
                    == UsageCompressedSource.stamp(preparedStamp, physical: physical))
                mirror.release()
                var state = CodexIndexCheckpoint(), prior: UsageFileStamp?
                var compressedDeltas: [SessionUsageDelta] = [], batches = 0
                repeat {
                    let value = try helper.parse(UsageParseRequest(id: UUID().uuidString, path: plain.path,
                        targetEnd: UInt64(multiple.count), checkpoint: state, previousStamp: prior))
                    try check(value.stamp.size == multiple.count && !value.requiresRebuild)
                    compressedDeltas += value.batch.deltas; state = value.batch.checkpoint; prior = value.stamp
                    batches += 1; try check(batches < 30)
                    if batches == 1 {
                        let live = try helper.parse(request)
                        try check(encoder.encode(live.batch.deltas) == encoder.encode(whole.deltas))
                    }
                } while state.cursor.offset < multiple.count
                try check(batches > 1 && encoder.encode(compressedDeltas) == encoder.encode(expectedDeltas))
                let restarted = UsageParseHelper()
                let zero = try restarted.parse(UsageParseRequest(id: UUID().uuidString, path: packed.path,
                    targetEnd: UInt64(multiple.count), checkpoint: state, previousStamp: prior))
                try check(zero.batch.readBytes == 0 && zero.batch.deltas.isEmpty && zero.stamp == prior)
                try compress(original)
                try FileManager.default.removeItem(at: plain)
                let replaced = try restarted.parse(UsageParseRequest(id: UUID().uuidString, path: plain.path,
                    targetEnd: UInt64(multiple.count), checkpoint: state, previousStamp: prior))
                try check(replaced.requiresRebuild && replaced.stamp.size == original.count)
                try original.write(to: plain)
                let restoredPlain = try restarted.parse(UsageParseRequest(id: UUID().uuidString, path: plain.path,
                    targetEnd: UInt64(original.count), checkpoint: replaced.batch.checkpoint, previousStamp: replaced.stamp))
                try check(restoredPlain.requiresRebuild && restoredPlain.batch.readBytes == 0 && restoredPlain.batch.deltas.isEmpty)
                let resumedPlain = try restarted.parse(UsageParseRequest(id: UUID().uuidString, path: plain.path,
                    targetEnd: UInt64(original.count), checkpoint: restoredPlain.batch.checkpoint, previousStamp: restoredPlain.stamp))
                try check(!resumedPlain.requiresRebuild && encoder.encode(resumedPlain.batch.deltas) == encoder.encode(whole.deltas))
                let corrupt = root.appendingPathComponent("corrupt.jsonl.zst")
                try Data("invalid compressed source".utf8).write(to: corrupt)
                do {
                    _ = try restarted.parse(UsageParseRequest(id: UUID().uuidString, path: corrupt.path,
                        targetEnd: 0, checkpoint: CodexIndexCheckpoint(), previousStamp: nil))
                    throw UsageIndexError.databaseFailure
                } catch UsageIndexError.cacheInvalid {}
                print("history compressed: path migration, mirror reuse/release, logical checkpoint restart and corrupt source passed")
            } else {
                throw UsageIndexError.resourceLimited
            }
            let frozen = root.appendingPathComponent("frozen.jsonl")
            try Data("first\npart".utf8).write(to: frozen)
            try check(UsageFileStamp.completingBoundary(url: frozen, frozenEnd: 10) == nil)
            try Data("first\npartial\nnewer\n".utf8).write(to: frozen)
            try check(UsageFileStamp.completingBoundary(url: frozen, frozenEnd: 10) == 14)
            print("history stream: complete-line restart, half-line, long/oversized line progress, checkpoint counter parity passed")
            return true
        } catch {
            print("history stream failed: \(error)")
            return false
        }
    }
}

private extension SessionUsageDelta {
    var totalForTest: Int64 { tokens.totalTokens }
}
