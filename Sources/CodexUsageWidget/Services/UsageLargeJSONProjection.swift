import Foundation

/// Validates a large JSON object incrementally while retaining only allowlisted statistical
/// scalars. Unknown subtrees (including tool output and message text) never enter checkpoints.
struct UsageLargeJSONProjection: Codable, Equatable {
    private struct Frame: Codable, Equatable {
        var object: Bool
        var path: String?
        var state: Int = 0 // object: key/end, colon, value, comma/end, key; array: value/end, comma/end, value
        var key: String?
    }
    private var stack: [Frame] = []
    private var mode = 0 // none, string, primitive
    private var keyToken = false
    private var keyCandidates: [String] = []
    private var capture = false
    private var token: [UInt8] = []
    private var tokenPath: String?
    private var escaped = false
    private var unicodeRemaining = 0
    private var utf8Remaining = 0
    private var utf8Lower: UInt8 = 128
    private var utf8Upper: UInt8 = 191
    private var rootStarted = false
    private var rootComplete = false
    private(set) var invalid = false
    private var values: [String: String] = [:]

    private static let paths: Set<String> = {
        var paths: Set<String> = ["type","timestamp","payload.type","payload.role","payload.model","payload.effort",
            "payload.service_tier","payload.forked_from_id","payload.turn_id","payload.started_at","payload.completed_at",
            "payload.duration_ms","payload.thread_settings.service_tier"]
        for container in ["total_token_usage","last_token_usage"] {
            for key in ["input_tokens","cached_input_tokens","cache_write_input_tokens","output_tokens","reasoning_output_tokens","total_tokens"] {
                paths.insert("payload.info."+container+"."+key)
            }
        }
        return paths
    }()

    mutating func feed(_ data: Data) {
        guard !invalid else { return }
        for byte in data {
            process(byte)
            if invalid { break }
        }
    }

    private mutating func process(_ byte: UInt8) {
        if mode == 1 {
            if utf8Remaining>0 {
                guard byte>=utf8Lower,byte<=utf8Upper else { invalid=true;return }
                utf8Remaining-=1;utf8Lower=128;utf8Upper=191;append(byte);return
            }
            if byte>=128 {
                guard !escaped,unicodeRemaining==0,byte>=194,byte<=244 else { invalid=true;return }
                utf8Remaining = byte<224 ? 1 : (byte<240 ? 2 : 3)
                utf8Lower = byte==224 ? 160 : (byte==240 ? 144 : 128)
                utf8Upper = byte==237 ? 159 : (byte==244 ? 143 : 191)
                append(byte);return
            }
            if unicodeRemaining > 0 {
                guard (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) else { invalid=true;return }
                unicodeRemaining-=1
                append(byte);return
            }
            if escaped {
                escaped=false
                guard [34,92,47,98,102,110,114,116,117].contains(byte) else { invalid=true;return }
                if byte == 117 { unicodeRemaining=4 }
                append(byte);return
            }
            if byte == 92 {
                // Escaped keys at a statistical path are uncommon; without retaining arbitrary
                // key bytes we cannot prove their meaning, so refuse completeness conservatively.
                if keyToken,stack.last?.path != nil { invalid=true;return }
                escaped=true;append(byte);return
            }
            if byte == 34 {
                append(byte)
                if capture {
                    guard let value=try? JSONSerialization.jsonObject(with:Data(token),options:.fragmentsAllowed) else { invalid=true;return }
                    if keyToken {
                        guard let key=value as? String, let index=stack.indices.last else { invalid=true;return }
                        let path=stack[index].path.map { $0.isEmpty ? key : $0+"."+key }
                        stack[index].key = !key.contains(".") && path.map { candidate in Self.paths.contains(candidate) || Self.paths.contains(where:{$0.hasPrefix(candidate+".")}) } == true ? key : nil
                        if stack[index].key != nil,let path {
                            // JSONSerialization uses the last duplicate member. Replacing a whole
                            // object must also remove every statistic retained from its predecessor.
                            for previous in Array(values.keys) where previous == path || previous.hasPrefix(path+".") { values.removeValue(forKey:previous) }
                        }
                    } else if let path=tokenPath { values[path]=String(decoding:token,as:UTF8.self) }
                }
                mode=0;token=[];tokenPath=nil
                if keyToken { stack[stack.count-1].state=1 } else { finishValue() }
                return
            }
            guard byte>=32 else { invalid=true;return }
            append(byte);return
        }
        if mode == 2 {
            if byte == 44 || byte == 93 || byte == 125 || Self.space(byte) {
                finishPrimitive()
                if !invalid { process(byte) }
            } else {
                guard token.count < 128 else { invalid=true;return }
                token.append(byte)
            }
            return
        }
        if Self.space(byte) { return }
        guard !rootComplete else { invalid=true;return }
        if let index=stack.indices.last {
            let frame=stack[index]
            if frame.object {
                if frame.state == 0 || frame.state == 4 {
                    if byte == 125,frame.state == 0 { close(object:true);return }
                    guard byte == 34 else { invalid=true;return }
                    keyToken=true;capture=frame.path != nil;token=capture ? [34] : [];mode=1
                    let prefix=frame.path.map { $0.isEmpty ? "" : $0+"." } ?? ""
                    keyCandidates=capture ? Array(Set(Self.paths.filter{$0.hasPrefix(prefix)}.map{String($0.dropFirst(prefix.count).split(separator:".")[0])})) : []
                    return
                }
                if frame.state == 1 {
                    guard byte == 58 else { invalid=true;return }
                    stack[index].state=2;return
                }
                if frame.state == 3 {
                    if byte == 125 { close(object:true);return }
                    guard byte == 44 else { invalid=true;return }
                    stack[index].state=4;stack[index].key=nil;return
                }
            } else {
                if frame.state == 0,byte == 93 { close(object:false);return }
                if frame.state == 1 {
                    if byte == 93 { close(object:false);return }
                    guard byte == 44 else { invalid=true;return }
                    stack[index].state=2;return
                }
            }
        } else {
            guard !rootStarted,byte == 123 else { invalid=true;return }
        }
        let path: String?
        if let frame=stack.last,frame.object,let parent=frame.path,let key=frame.key { path=parent.isEmpty ? key : parent+"."+key }
        else { path = stack.isEmpty ? "" : nil }
        if byte == 123 || byte == 91 {
            guard stack.count < 64 else { invalid=true;return }
            rootStarted=true
            stack.append(Frame(object:byte == 123,path:byte == 123 ? path : nil));return
        }
        keyToken=false;tokenPath=path.flatMap { Self.paths.contains($0) ? $0 : nil };capture=tokenPath != nil
        if byte == 34 { mode=1;token=capture ? [34] : [];return }
        guard byte == 45 || (48...57).contains(byte) || [116,102,110].contains(byte) else { invalid=true;return }
        mode=2;token=[byte]
    }

    private mutating func append(_ byte: UInt8) {
        guard capture else { return }
        if keyToken,byte != 34 {
            let prefix=String(decoding:token.dropFirst()+[byte],as:UTF8.self)
            keyCandidates=keyCandidates.filter{$0.hasPrefix(prefix)}
            if keyCandidates.isEmpty { capture=false;token=[];return }
        }
        guard token.count<32768 else { invalid=true;return }
        token.append(byte)
    }
    private mutating func finishPrimitive() {
        guard (try? JSONSerialization.jsonObject(with:Data(token),options:.fragmentsAllowed)) != nil else { invalid=true;return }
        if capture,let path=tokenPath { values[path]=String(decoding:token,as:UTF8.self) }
        token=[];tokenPath=nil;mode=0;finishValue()
    }
    private mutating func finishValue() {
        if let index=stack.indices.last { stack[index].state=stack[index].object ? 3 : 1;stack[index].key=nil }
        else { rootComplete=true }
    }
    private mutating func close(object: Bool) {
        guard stack.last?.object == object else { invalid=true;return }
        stack.removeLast();finishValue()
    }
    private static func space(_ byte: UInt8) -> Bool { [9,10,13,32].contains(byte) }

    mutating func finish() -> Data? {
        if mode == 2 { finishPrimitive() }
        guard !invalid,rootComplete,stack.isEmpty,mode == 0 else { return nil }
        func string(_ path:String)->String? {
            values[path].flatMap { try? JSONSerialization.jsonObject(with:Data($0.utf8),options:.fragmentsAllowed) as? String }
        }
        let rootType=string("type"),payloadType=string("payload.type")
        // Large call arguments can contain skill loads; they cannot be silently discarded.
        guard payloadType != "function_call",payloadType != "custom_tool_call" else { return nil }
        guard ["response_item","event_msg","turn_context","session_meta","compacted"].contains(rootType ?? "") else { return nil }
        func object(prefix:String)->String {
            var fields:[String]=[]
            let children=Set(values.keys.filter{$0.hasPrefix(prefix)}.map { String($0.dropFirst(prefix.count).split(separator:".")[0]) })
            for child in children.sorted() {
                let path=prefix+child
                if let value=values[path] { fields.append("\""+child+"\":"+value) }
                else { fields.append("\""+child+"\":"+object(prefix:path+".")) }
            }
            return "{"+fields.joined(separator:",")+"}"
        }
        let data=Data(object(prefix:"").utf8)
        return data.count<=65536 ? data : nil
    }
}
