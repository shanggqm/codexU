import Foundation

extension UsageIndexStore {
    /// Disk-backed interval union and sweep. The returned object is bounded by 28 daily points
    /// and the visible project list, rather than by the number of historical turns.
    func indexedLeadership(root: String, statistics: StatisticsContext) throws -> LeadershipDashboardSnapshot {
        let context = try ensureProjectionContext(root: root, statistics: statistics, now: statistics.now)
        let today = statistics.startOfDay(for: statistics.now)
        let start = statistics.calendar.date(byAdding: .day, value: -27, to: today)!
        let cocoaOffset = Date(timeIntervalSince1970: 0).timeIntervalSinceReferenceDate
        try execute("DROP TABLE IF EXISTS temp.leadership_metadata")
        try execute("CREATE TEMP TABLE leadership_metadata(source TEXT PRIMARY KEY,generation INTEGER,cut INTEGER,runtime TEXT,logical TEXT,worker TEXT,kind TEXT,project TEXT,path TEXT,confidence REAL,autonomous INTEGER,created REAL)")
        var after = ""
        while true {
            let page = try rows("""
                SELECT s.id,p.generation,b.cut_revision,s.runtime,s.logical_id,v.payload
                FROM published_slice ps JOIN report_build b ON b.id=ps.build_id JOIN build_member m ON m.build_id=b.id
                JOIN source s ON s.id=m.source_id JOIN source_projection p ON p.id=m.projection_id
                JOIN source_metadata_version v ON v.source_id=s.id AND v.valid_from<=b.cut_revision AND (v.valid_to IS NULL OR v.valid_to>b.cut_revision)
                WHERE ps.context_id=? AND ps.domain='archive' AND s.id>? ORDER BY s.id LIMIT 12
                """, [.text(context),.text(after)],limit:12)
            if page.isEmpty { break }
            for row in page {
                guard let source=row[0].text,let runtime=row[3].text,let logical=row[4].text,let payload=row[5].text else { throw UsageIndexError.cacheInvalid }
                after=source
                let metadata=try JSONDecoder().decode(UsageSourceMetadata.self,from:Data(payload.utf8))
                let kind = metadata.sourceKind == "automation" ? "automation" : (metadata.sourceKind == "subagent" ? "subagent" : "main")
                let worker = kind == "automation" && metadata.automationID != nil ? "codex:automation:"+metadata.automationID! : "codex:"+kind+":"+logical
                try execute("INSERT INTO leadership_metadata VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", [row[0],row[1],row[2],row[3],row[4],.text(worker),.text(kind),
                    .text(UsageLeadershipAdapter.projectID(runtime: runtime,path:metadata.project)),.text(metadata.project),
                    .real(kind == "automation" && metadata.automationID == nil ? 0.9 : 1),.integer(kind == "main" ? 0 : 1),.real(Double(metadata.createdAt ?? 0))])
            }
        }
        try execute("DROP TABLE IF EXISTS temp.leadership_raw")
        try execute("DROP TABLE IF EXISTS temp.leadership_merged")
        defer {
            try? execute("DROP TABLE IF EXISTS temp.leadership_metadata")
            try? execute("DROP TABLE IF EXISTS temp.leadership_raw")
            try? execute("DROP TABLE IF EXISTS temp.leadership_merged")
        }
        try execute("""
            CREATE TEMP TABLE leadership_raw AS
            WITH candidates AS (
              SELECT json_extract(f.payload,'$.interval._0.id') id,
                CASE WHEN lm.runtime='codex' THEN lm.worker ELSE json_extract(f.payload,'$.interval._0.workerID') END worker,
                CASE WHEN lm.runtime='codex' THEN lm.kind ELSE json_extract(f.payload,'$.interval._0.workerKind') END kind,
                CASE WHEN lm.runtime='codex' THEN lm.project ELSE json_extract(f.payload,'$.interval._0.projectID') END project,
                json_extract(f.payload,'$.interval._0.startAt')-? start,
                json_extract(f.payload,'$.interval._0.endAt')-? end,
                CASE WHEN lm.runtime='codex' THEN lm.confidence ELSE CASE json_extract(f.payload,'$.interval._0.quality') WHEN 'fact' THEN 1.0 WHEN 'derived' THEN 0.9 ELSE 0.0 END END confidence,
                CASE WHEN lm.runtime='codex' THEN lm.autonomous ELSE json_extract(f.payload,'$.interval._0.isAutonomous') END autonomous,
                lm.path path,
                row_number() OVER(PARTITION BY json_extract(f.payload,'$.interval._0.id') ORDER BY lm.logical,f.sequence) ordinal
              FROM fact f JOIN leadership_metadata lm ON lm.source=f.source_id AND lm.generation=f.generation
              WHERE f.kind='interval' AND f.operation='upsert' AND f.commit_revision<=lm.cut
                AND (lm.runtime<>'codex' OR json_extract(f.payload,'$.interval._0.startAt')+978307200>=lm.created-2)
                AND NOT EXISTS (SELECT 1 FROM fact n WHERE n.source_id=f.source_id AND n.generation=f.generation
                  AND n.kind=f.kind AND n.logical_key=f.logical_key AND n.commit_revision<=lm.cut
                  AND (n.commit_revision>f.commit_revision OR (n.commit_revision=f.commit_revision AND n.sequence>f.sequence))))
            SELECT * FROM candidates WHERE ordinal=1 AND confidence>0 AND end>? AND start<?
            """, [.real(cocoaOffset),.real(cocoaOffset),
                  .real(start.timeIntervalSince1970),.real(statistics.now.timeIntervalSince1970)])
        try execute("CREATE INDEX temp.leadership_raw_worker ON leadership_raw(worker,start,end)")
        var reports: [LeadershipReport] = []
        for period in LeadershipPeriod.allCases {
            let windowStart = statistics.calendar.date(byAdding: .day, value: 1-period.dayCount, to: today)!
            try execute("DROP TABLE IF EXISTS temp.leadership_merged")
            try execute("""
                CREATE TEMP TABLE leadership_merged AS
                WITH clipped AS (SELECT *,max(start,?) a,min(end,?) b FROM leadership_raw WHERE end>? AND start<?),
                  prior AS (SELECT *,max(b) OVER(PARTITION BY worker ORDER BY a,b,id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) previous FROM clipped),
                  islands AS (SELECT *,sum(CASE WHEN previous IS NULL OR a>previous THEN 1 ELSE 0 END)
                    OVER(PARTITION BY worker ORDER BY a,b,id) island FROM prior),
                  numbered AS (SELECT *,row_number() OVER(PARTITION BY worker,island ORDER BY a,b,id) first FROM islands),
                  grouped AS (SELECT worker,island,min(a) start,max(b) end,min(confidence) confidence,max(autonomous) autonomous,
                    max(CASE WHEN first=1 THEN kind END) kind,max(CASE WHEN first=1 THEN project END) project,
                    max(CASE WHEN first=1 THEN path END) path FROM numbered GROUP BY worker,island)
                SELECT * FROM grouped
                """, [.real(windowStart.timeIntervalSince1970),.real(statistics.now.timeIntervalSince1970),
                      .real(windowStart.timeIntervalSince1970),.real(statistics.now.timeIntervalSince1970)])
            func metrics(start: Date, end: Date) throws -> (active: Double, parallel: Double, multi: Double, peak: Int, hours: Double, workers: Int, autonomous: Bool) {
                let args: [UsageSQLValue] = [.real(start.timeIntervalSince1970),.real(end.timeIntervalSince1970),
                    .real(start.timeIntervalSince1970),.real(end.timeIntervalSince1970)]
                let clipped = "WITH clipped AS (SELECT *,max(start,?) a,min(end,?) b FROM leadership_merged WHERE end>? AND start<?)"
                let totals = try rows(clipped + " SELECT sum(b-a),count(DISTINCT worker),max(autonomous) FROM clipped", args, limit: 1).first!
                let sweep = try rows(clipped + """
                    , pp AS (SELECT *,max(b) OVER(PARTITION BY project ORDER BY a,b,worker ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) previous FROM clipped),
                      pi AS (SELECT *,sum(CASE WHEN previous IS NULL OR a>previous THEN 1 ELSE 0 END)
                        OVER(PARTITION BY project ORDER BY a,b,worker) island FROM pp),
                      pu AS (SELECT project,island,min(a) a,max(b) b FROM pi GROUP BY project,island),
                      boundaries AS (SELECT a t,1 dw,0 dp FROM clipped UNION ALL SELECT b,-1,0 FROM clipped
                        UNION ALL SELECT a,0,1 FROM pu UNION ALL SELECT b,0,-1 FROM pu),
                      grouped AS (SELECT t,sum(dw) dw,sum(dp) dp FROM boundaries GROUP BY t),
                      running AS (SELECT t,lead(t) OVER(ORDER BY t)-t duration,sum(dw) OVER(ORDER BY t) workers,sum(dp) OVER(ORDER BY t) projects FROM grouped)
                    SELECT sum(CASE WHEN workers>0 THEN duration ELSE 0 END),sum(CASE WHEN workers>=2 THEN duration ELSE 0 END),
                      sum(CASE WHEN projects>=2 THEN duration ELSE 0 END),max(workers) FROM running
                    """, args, limit: 1).first!
                return (sweep[0].number ?? 0,sweep[1].number ?? 0,sweep[2].number ?? 0,Int(sweep[3].integer ?? 0),
                        (totals[0].number ?? 0)/3600,Int(totals[1].integer ?? 0),(totals[2].integer ?? 0)>0)
            }
            let overall = try metrics(start: windowStart, end: statistics.now)
            var points: [LeadershipDayPoint] = []
            var activeDays = 0
            for offset in 0..<period.dayCount {
                let day = statistics.calendar.date(byAdding: .day, value: offset, to: windowStart)!
                let next = min(statistics.calendar.date(byAdding: .day, value: 1, to: day)!, statistics.now)
                let daily = try metrics(start: day, end: next)
                points.append(LeadershipDayPoint(day: day, agentCount: daily.workers, aiHours: daily.hours, peakConcurrency: daily.peak))
                if daily.hours>=0.25 || daily.workers>0 && daily.autonomous { activeDays += 1 }
            }
            let totals = try rows("""
                SELECT sum(CASE WHEN autonomous=1 THEN end-start ELSE 0 END),sum(CASE WHEN kind='subagent' THEN end-start ELSE 0 END),
                  max(CASE WHEN autonomous=1 THEN end-start ELSE 0 END),sum(confidence*(end-start)),count(DISTINCT project)
                FROM leadership_merged
                """, limit: 1).first!
            let autonomousHours = (totals[0].number ?? 0)/3600
            let delegatedHours = (totals[1].number ?? 0)/3600
            let confidence = overall.hours>0 ? (totals[3].number ?? 0)/(overall.hours*3600) : 0
            let effective = try rows("SELECT sum(min(hours,1.0)) FROM (SELECT sum(end-start)/3600 hours FROM leadership_merged GROUP BY worker)", limit: 1).first?.first?.number ?? 0
            // Autonomous day semantics use the start day of merged intervals, matching the existing score model.
            var autonomousDays = 0
            for offset in 0..<period.dayCount {
                let day = statistics.calendar.date(byAdding: .day, value: offset, to: windowStart)!
                let next = statistics.calendar.date(byAdding: .day, value: 1, to: day)!
                if try scalar("SELECT 1 FROM leadership_merged WHERE autonomous=1 AND start>=? AND start<? LIMIT 1",
                    [.real(day.timeIntervalSince1970),.real(next.timeIntervalSince1970)]) != nil { autonomousDays += 1 }
            }
            let dimensions = activeDays>0 ? LeadershipScoreModel.dimensions(effectiveWorkers: effective, peakConcurrency: overall.peak,
                dailyAIHours: overall.hours/Double(activeDays), averageParallelism: overall.active>0 ? overall.hours*3600/overall.active : 0,
                delegatedShare: overall.hours>0 ? delegatedHours/overall.hours : 0, parallelShare: overall.active>0 ? overall.parallel/overall.active : 0,
                multiProjectShare: overall.active>0 ? overall.multi/overall.active : 0, autonomousShare: overall.hours>0 ? autonomousHours/overall.hours : 0,
                longestAutonomousHours: (totals[2].number ?? 0)/3600, autonomousDayShare: Double(autonomousDays)/Double(activeDays), confidence: confidence) : []
            let coverage = dimensions.reduce(0.0) { $0+$1.kind.weight*$1.confidence }
            let final = LeadershipScoreModel.finalScore(dimensions: dimensions, activeDays: activeDays, evidenceCoverage: coverage)
            let projectRows = try rows("SELECT project,min(path),count(DISTINCT worker),sum(end-start)/3600,sum(CASE WHEN autonomous=1 THEN end-start ELSE 0 END)/3600 FROM leadership_merged GROUP BY project ORDER BY 4 DESC,2 LIMIT 1001", limit: 1000)
            let projects = projectRows.compactMap { row -> LeadershipProjectContribution? in
                guard let id = row[0].text else { return nil }
                let path = row[1].text ?? ""
                return LeadershipProjectContribution(projectID: id, projectName: path.isEmpty ? "未归类" : URL(fileURLWithPath: path).lastPathComponent,
                    agentCount: Int(row[2].integer ?? 0), aiHours: row[3].number ?? 0, autonomousHours: row[4].number ?? 0)
            }
            reports.append(LeadershipReport(period: period, score: final?.score, coreScore: final?.core,
                title: final.map { LeadershipScoreModel.title(for: $0.score) }, dimensions: dimensions,
                maturity: LeadershipScoreModel.maturity(activeDays: activeDays), evidenceCoverage: coverage, activeDayCount: activeDays,
                agentCount: overall.workers>0 ? overall.workers : nil, aiHours: overall.workers>0 ? overall.hours : nil,
                autonomousHours: overall.workers>0 ? autonomousHours : nil,
                averageParallelism: overall.workers>0 ? (overall.active>0 ? overall.hours*3600/overall.active : 0) : nil,
                peakConcurrency: overall.workers>0 ? overall.peak : nil, projectCount: Int(totals[4].integer ?? 0), dailyPoints: points, projects: projects))
        }
        let observed = try rows("SELECT min(observed_at_ms) FROM published_slice WHERE context_id=? AND domain='archive'", [.text(context)],limit:1).first?.first?.number
        return LeadershipDashboardSnapshot(modelVersion: LeadershipScoreModel.version,
            refreshedAt: observed.map { Date(timeIntervalSince1970:$0/1000) } ?? statistics.now, reports: reports)
    }
}
