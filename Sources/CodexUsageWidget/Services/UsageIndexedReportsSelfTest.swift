import Foundation

enum UsageIndexedReportsSelfTest {
    static func run() -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var phase = "setup"
        do {
            func check(_ condition: Bool) throws { if !condition { throw UsageIndexError.databaseFailure } }
            let now = ISO8601DateFormatter().date(from: "2026-09-19T18:00:00Z")!
            let statistics = StatisticsContext(preference: .init(selection: .utc, fixedIdentifier: "UTC"), now: now)
            let store = try UsageIndexStore(directory: directory)
            let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/history-index/codex-inference.jsonl")
            guard let parsed = CodexUsageReader().historyIndexOracle(url: fixture) else { throw UsageIndexError.cacheInvalid }
            let context = try store.ensureProjectionContext(root: "reports", statistics: statistics, now: now)
            var intervals: [LeadershipInterval] = []
            var workers: [LeadershipWorker] = []
            let scan = try store.beginDiscovery(root: "reports", runtime: "codex", now: now)
            for index in 0..<3 {
                let id = "source-\(index)", project = "/project-\(index%2)"
                let kind: LeadershipWorkerKind = index == 0 ? .main : (index == 1 ? .subagent : .automation)
                let workerID = "codex:"+kind.rawValue+":"+id
                let projectID = UsageLeadershipAdapter.projectID(runtime:"codex",path:project)
                workers.append(LeadershipWorker(id: workerID, runtime: .codex, kind: kind, projectID: projectID, projectName: URL(fileURLWithPath: project).lastPathComponent, parentID: nil))
                try store.registerSource(id: id, root: "reports", runtime: "codex", logicalID: id, locator: "/fixture/\(id)", now: now)
                try store.recordMetadata(source: id, metadata: UsageSourceMetadata(model: nil, project: project, parentLogicalID: nil, sourceKind: kind.rawValue), now: now)
                let initial = try store.beginGeneration(source: id, identity: id, targetEnd: 1, initialState: "{}", now: now)
                var facts: [UsageIndexFact] = []
                for offset in 0..<12 {
                    let begin = now.addingTimeInterval(-Double(offset+1)*7200+Double(index)*300)
                    let interval = LeadershipInterval(id: "\(id):\(offset)", workerID: workerID, runtime: .codex, workerKind: kind, projectID: projectID,
                        startAt: begin, endAt: begin.addingTimeInterval(8000-Double(index)*500), quality: index == 2 ? .derived : .fact, isAutonomous: index != 0)
                    intervals.append(interval)
                    facts.append(UsageIndexFact(logicalKey: String(format:"%04d", offset), occurredAt: begin, payload: .interval(interval)))
                }
                if index == 0 {
                    facts += parsed.deltas.enumerated().map { UsageIndexFact(logicalKey: String(format:"%04d", $0.offset), occurredAt: $0.element.date, payload: .token($0.element)) }
                    facts += parsed.inferenceSamples.enumerated().map { UsageIndexFact(logicalKey: String(format:"%04d", $0.offset), occurredAt: $0.element.completedAt, payload: .inference($0.element)) }
                    facts.append(UsageIndexFact(logicalKey: "tools", occurredAt: now, payload: .tool(name: "exec_command", count: 7)))
                    facts.append(UsageIndexFact(logicalKey: "skill", occurredAt: now, payload: .skill(SkillLoadEvent(path: "/skills/test/SKILL.md", date: now))))
                }
                let cp = try store.append(source: id, expected: initial, offset: 1, state: "{}", facts: facts, now: now)
                try store.activate(source: id, expected: cp, verifiedIdentity: id, now: now)
                try store.observeSource(source: id, identity: id, targetEnd: 1, status: "readable", now: now)
                try store.execute("UPDATE source SET discovered_epoch=? WHERE id=?", [.integer(scan),.text(id)])
            }
            try store.finishDiscovery(scan: scan, complete: true, now: now)
            let cut = try store.scalar("SELECT max(id) FROM revision")!
            for index in 0..<3 {
                guard var cursor = try store.beginUsageProjection(context: context, source: "source-\(index)", revision: cut, now: now) else { throw UsageIndexError.cacheInvalid }
                while !cursor.finished { cursor = try store.stepUsageProjection(cursor, statistics: statistics, now: now) }
            }
            let build = try store.beginDayArchive(context: context, root: "reports", dayKey: statistics.dayKey(for: now), now: now)
            while try !store.stepDayArchive(build: build, now: now) {}
            phase = "details"
            guard let result = try store.archivePresentation(context: context, statistics: statistics, includeDetails: true) else { throw UsageIndexError.cacheInvalid }
            try check(result.local.toolUsages.first?.callCount == 7 && result.local.skillUsages.first?.loadCount == 1)
            phase = "inference"
            let expected = ModelInferencePerformanceBuilder.makeHistory(samples: parsed.inferenceSamples,
                recordingStartedAt: parsed.inferenceSamples.map(\.completedAt).min()!, dayStart: statistics.startOfDay(for: now), calendar: statistics.calendar)
            try check(result.local.inferencePerformance == expected)
            phase = "leadership"
            let leadership = try store.indexedLeadership(root: "reports", statistics: statistics)
            let oracle = LeadershipAggregator().makeDashboard(workers: workers, intervals: intervals, now: now, calendar: statistics.calendar)
            for (actual, expected) in zip(leadership.reports, oracle.reports) {
                try check(actual.score == expected.score && actual.agentCount == expected.agentCount && actual.activeDayCount == expected.activeDayCount)
                try check(abs((actual.aiHours ?? 0)-(expected.aiHours ?? 0)) < 1e-9)
                try check(abs((actual.autonomousHours ?? 0)-(expected.autonomousHours ?? 0)) < 1e-9)
                try check(abs((actual.averageParallelism ?? 0)-(expected.averageParallelism ?? 0)) < 1e-9)
                try check(actual.peakConcurrency == expected.peakConcurrency && actual.projectCount == expected.projectCount)
            }
            phase = "bounded report GC"
            let published = try store.beginDayArchive(context: context, root: "reports", dayKey: statistics.dayKey(for: now), now: now)
            while try !store.stepDayArchive(build: published, now: now) {}
            let active = try store.beginDayArchive(context: context, root: "reports", dayKey: statistics.dayKey(for: now), now: now)
            try store.transaction {
                for index in 0..<1025 {
                    try store.execute("INSERT INTO build_interval VALUES (?,?,?,?,?,?,?,?)",
                        [.text(build), .text("gc-\(index)"), .text("worker"), .text("project"), .integer(1), .integer(2), .text("fact"), .integer(0)])
                }
            }
            let publishedPayload = try store.rows("SELECT payload FROM published_slice", limit: 1)
            var batches = 0
            repeat {
                let removed = try store.collectReportGarbage(now: now.addingTimeInterval(120))
                if removed == 0 { break }
                try check(removed <= 256)
                batches += 1
                if batches == 3 {
                    let remaining = try store.scalar("SELECT count(*) FROM build_interval WHERE build_id=?", [.text(build)])
                    do { _ = try store.withDeadline(milliseconds: 0) { try store.collectReportGarbage(now: now.addingTimeInterval(120)) } }
                    catch UsageIndexError.cancelled {}
                    try check(store.scalar("SELECT count(*) FROM build_interval WHERE build_id=?", [.text(build)]) == remaining)
                }
            } while batches < 100
            try check(batches >= 5 && batches < 100)
            try check(store.scalar("SELECT count(*) FROM report_build WHERE id=?", [.text(build)]) == 0)
            try check(store.scalar("SELECT count(*) FROM report_build WHERE id IN (?,?)", [.text(published), .text(active)]) == 2)
            try check(store.rows("SELECT payload FROM published_slice", limit: 1) == publishedPayload)
            try check(store.scalar("SELECT count(*) FROM fact")! > 0)
            // Leave no unfinished test report pin to affect the later predecessor-cut scenario.
            try store.execute("DELETE FROM revision_pin WHERE owner_id=?", [.text("report:" + active)])
            try store.execute("UPDATE report_build SET state='partial' WHERE id=?", [.text(active)])
            phase = "atomic rollback"
            do {
                try store.transaction {
                    try store.transaction { try store.execute("INSERT INTO index_meta(key,value) VALUES ('atomic-fixture','data')") }
                    throw UsageIndexError.cancelled
                }
            } catch UsageIndexError.cancelled {}
            try check(store.rows("SELECT value FROM index_meta WHERE key='atomic-fixture'", limit: 1).isEmpty)
            phase = "materialization progress"
            let materializer = try UsageIndexMaterializer(store: store, root: "reports", statistics: statistics)
            try materializer.enqueue("source-0")
            try store.execute("UPDATE job SET cursor='preserved' WHERE kind='materialize'")
            try materializer.enqueue("source-0")
            try check(store.rows("SELECT cursor FROM job WHERE kind='materialize'",limit:1).first?.first?.text == "preserved")
            phase = "fixed projection survives append"
            let stableProjection = try store.beginUsageProjection(context: context, source: "source-0", revision: cut, now: now)!
            let projectionObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stableProjection))
            let cursorData = try JSONSerialization.data(withJSONObject: ["revision":cut,"requestedRevision":cut,"phase":"projection",
                "token":["count":0,"finished":false],"inference":["count":0,"finished":false],"projection":projectionObject])
            // Use the normal encoder shape for prefix cursors, including any future fields.
            var cursorObject = try JSONSerialization.jsonObject(with: cursorData) as! [String:Any]
            cursorObject["token"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(UsagePrefixCursor()))
            cursorObject["inference"] = cursorObject["token"]
            let encodedCursor = String(decoding:try JSONSerialization.data(withJSONObject:cursorObject),as:UTF8.self)
            try store.execute("UPDATE job SET cursor=?,cut_revision=? WHERE kind='materialize'",[.text(encodedCursor),.integer(cut)])
            let beforeAppend = try store.checkpoint(source:"source-0")!
            _ = try store.observeAppend(source:"source-0",expected:beforeAppend,targetEnd:2,verifiedIdentity:beforeAppend.identity,now:now)
            _ = try materializer.step()
            try check(store.rows("SELECT status FROM job WHERE kind='materialize'",limit:1).first?.first?.text == "done")
            phase = "GC retains pinned predecessor"
            // Pause archive membership selection, then publish a source projection newer than its cut.
            try store.execute("DELETE FROM published_slice")
            try store.execute("DELETE FROM build_member")
            let pinnedCut = try store.transaction { try store.allocateRevision(now:now) }
            try store.execute("INSERT INTO revision_pin(owner_id,revision_id,updated_at_ms) VALUES ('gc-test',?,?)",
                [.integer(pinnedCut),.integer(try usageIndexMilliseconds(now))])
            let oldProjection = try store.rows("SELECT id FROM source_projection WHERE source_id='source-1'",limit:1).first!.first!.text!
            try store.recordMetadata(source:"source-1",metadata:UsageSourceMetadata(model:nil,project:"/renamed",parentLogicalID:nil),now:now)
            let newerCut = try store.scalar("SELECT max(id) FROM revision")!
            var newer = try store.beginUsageProjection(context:context,source:"source-1",revision:newerCut,now:now)!
            while !newer.finished { newer = try store.stepUsageProjection(newer,statistics:statistics,now:now) }
            _ = try store.collectGarbage(now:now.addingTimeInterval(120))
            try check(store.scalar("SELECT count(*) FROM source_projection WHERE id=?",[.text(oldProjection)]) == 1)
            phase = "inventory preserves queue age"
            try store.enqueueSource("source-2",priority:2,now:now)
            let age = try store.scalar("SELECT updated_at_ms FROM job WHERE dedup_key='parse:source-2'")
            try store.enqueueDiscoveredSource("source-2",priority:1,now:now.addingTimeInterval(60))
            try check(store.scalar("SELECT updated_at_ms FROM job WHERE dedup_key='parse:source-2'") == age)
            try check(store.scalar("SELECT priority FROM job WHERE dedup_key='parse:source-2'") == 1)
            print("history reports: exact inference ranks, SQL leadership union/sweep oracle parity, tools/skills, nested rollback and unchanged-progress preservation passed")
            return true
        } catch {
            print("history reports failed at \(phase): \(error)")
            return false
        }
    }
}
