import Foundation

enum UsageLargeJSONSelfTest {
    static func run() -> Bool {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let fixture=directory.appendingPathComponent("large.jsonl")
            let original=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/history-index/codex-inference.jsonl")
            let object:[String:Any] = ["type":"response_item","timestamp":"2026-09-18T10:00:00Z",
                "payload":["type":"function_call_output","output":String(repeating:"private-body-sentinel",count:800000)]]
            var data=try JSONSerialization.data(withJSONObject:object,options:.sortedKeys);data.append(10)
            data.append(try Data(contentsOf:original));try data.write(to:fixture)
            guard let oracle=CodexUsageReader().historyIndexOracle(url:fixture) else { throw UsageIndexError.cacheInvalid }
            var state=CodexIndexCheckpoint(), deltas:[SessionUsageDelta]=[], samples:[ModelInferenceSample]=[]
            var batches=0
            while state.cursor.offset<UInt64(data.count) {
                let batch=try UsageStreamParser.readCodex(url:fixture,targetEnd:UInt64(data.count),checkpoint:state)
                deltas+=batch.deltas;samples+=batch.inferenceSamples
                let checkpoint=try JSONEncoder().encode(batch.checkpoint)
                guard checkpoint.count<65536,!String(decoding:checkpoint,as:UTF8.self).contains("private-body-sentinel") else { throw UsageIndexError.resourceLimited }
                state=try JSONDecoder().decode(CodexIndexCheckpoint.self,from:checkpoint)
                batches+=1;guard batches<100 else { throw UsageIndexError.resourceLimited }
            }
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            guard state.cursor.oversizedLineCount==0,try encoder.encode(deltas)==encoder.encode(oracle.deltas),samples==oracle.inferenceSamples else { throw UsageIndexError.databaseFailure }
            for malformed in [#"{"type":"compacted",}"#,#"{"type":"compacted","payload":[1,]}"#,#"{"type":"compacted","payload":"\x"}"#] {
                var parser=UsageLargeJSONProjection();parser.feed(Data(malformed.utf8))
                guard parser.finish()==nil else { throw UsageIndexError.databaseFailure }
            }
            for tricky in [
                #"{"type":"event_msg","payload.type":"token_count","payload.info":{"total_token_usage":{"total_tokens":100}}}"#,
                #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}},"payload":{}}"#
            ] {
                var parser=UsageLargeJSONProjection();parser.feed(Data(tricky.utf8))
                guard let projected=parser.finish(),!String(decoding:projected,as:UTF8.self).contains("token_count") else { throw UsageIndexError.databaseFailure }
            }
            var counter=UsageLargeJSONProjection()
            counter.feed(Data(#"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"cache_write_input_tokens":15,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":130}}}}"#.utf8))
            guard let counterData=counter.finish(),String(decoding:counterData,as:UTF8.self).contains("cache_write_input_tokens") else { throw UsageIndexError.databaseFailure }
            var privateKey=UsageLargeJSONProjection()
            privateKey.feed(Data(#"{"type":"compacted","SECRET_BODY_USED_AS_UNKNOWN_KEY"#.utf8))
            let saved=try JSONSerialization.jsonObject(with:JSONEncoder().encode(privateKey)) as! [String:Any]
            let storedBytes=(saved["token"] as? [NSNumber] ?? []).map{$0.uint8Value}
            guard !String(decoding:storedBytes,as:UTF8.self).contains("SECRET_BODY") else { throw UsageIndexError.databaseFailure }
            print("history large JSON: 16 MB body streamed across checkpoints, no body persisted, old-reader token/inference parity and malformed rejection passed")
            return true
        } catch {
            print("history large JSON failed: \(error)")
            return false
        }
    }
}
