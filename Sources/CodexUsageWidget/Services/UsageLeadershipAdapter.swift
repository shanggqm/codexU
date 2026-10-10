import Foundation

struct UsageCodexTurnEvent: Codable {
    let turnID: String
    let date: Date
    let isStart: Bool
    let durationSeconds: Double?
}

enum UsageLeadershipAdapter {
    static func event(_ line: Data) -> UsageCodexTurnEvent? {
        guard line.range(of: Data(#""type":"event_msg""#.utf8)) != nil,
              line.range(of: Data(#""type":"task_started""#.utf8)) != nil || line.range(of: Data(#""type":"task_complete""#.utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              let turnID = payload["turn_id"] as? String, !turnID.isEmpty, turnID.utf8.count <= 1024,
              let type = payload["type"] as? String else { return nil }
        let isStart = type == "task_started"
        guard let time = payload[isStart ? "started_at" : "completed_at"] as? NSNumber,
              time.doubleValue.isFinite else { return nil }
        let duration = (payload["duration_ms"] as? NSNumber).map { $0.doubleValue / 1000 }
        return UsageCodexTurnEvent(turnID: turnID, date: Date(timeIntervalSince1970: time.doubleValue),
                                  isStart: isStart, durationSeconds: duration?.isFinite == true ? duration : nil)
    }

    static func interval(event: UsageCodexTurnEvent, start: Date?, logicalID: String,
                         metadata: UsageSourceMetadata, now: Date) -> LeadershipInterval? {
        guard !event.isStart,
              let start = start ?? event.durationSeconds.map({ event.date.addingTimeInterval(-$0) }),
              start >= Date(timeIntervalSince1970: Double(metadata.createdAt ?? 0)).addingTimeInterval(-2),
              event.date <= now.addingTimeInterval(5), event.date > start else { return nil }
        let kind: LeadershipWorkerKind
        switch metadata.sourceKind?.lowercased() {
        case "subagent": kind = .subagent
        case "automation": kind = .automation
        default: kind = .main
        }
        let worker = kind == .automation && metadata.automationID != nil
            ? "codex:automation:\(metadata.automationID!)" : "codex:\(kind.rawValue):\(logicalID)"
        return LeadershipInterval(id: "codex:\(logicalID):\(event.turnID)", workerID: worker, runtime: .codex,
            workerKind: kind, projectID: projectID(runtime: "codex", path: metadata.project),
            startAt: start, endAt: event.date, quality: kind == .automation && metadata.automationID == nil ? .derived : .fact,
            isAutonomous: kind == .automation || kind == .subagent)
    }

    static func projectID(runtime: String, path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return runtime + ":uncategorized" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in trimmed.utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return runtime + ":" + String(hash, radix: 16)
    }
}
