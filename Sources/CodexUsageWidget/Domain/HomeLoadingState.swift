import Foundation

enum HomeDataKind: String, CaseIterable, Hashable {
    case quota, local, tasks, leadership
}

struct HomeDataKey: Hashable {
    let scope: RuntimeScope?
    let kind: HomeDataKind
}

struct HomeLoadStatus: Equatable {
    enum Phase { case waiting, refreshing, ready, cached, background, unavailable }
    var phase: Phase = .waiting
    var observedAt: Date?
    // A disk snapshot contains summaries only. A completed in-memory history
    // remains usable while the next refresh is waiting or has failed.
    var hasDetails: Bool = false
    var historyError: UsageIndexError?

    var isWaiting: Bool { phase == .waiting || phase == .refreshing }

    mutating func begin() { phase = observedAt == nil ? .waiting : .refreshing }
    mutating func finish(at date: Date?) {
        if let date {
            observedAt = date
            phase = .ready
        } else {
            phase = observedAt == nil ? .unavailable : .cached
        }
    }

    func label(_ language: WidgetLanguage, kind: HomeDataKind) -> String {
        if let historyError {
            switch historyError {
            case .diskFull:
                return language.text("历史缓存空间不足 · 正在回收", "History cache full · reclaiming space")
            case .indexBusy:
                return language.text("历史索引被占用 · 稍后重试", "History index in use · retrying")
            case .resourceLimited:
                return language.text("历史处理暂缓 · 稍后重试", "History processing paused · retrying")
            case .unsupportedSchema:
                return language.text("历史缓存版本不兼容", "History cache version unsupported")
            default:
                return language.text("历史读取失败 · 稍后重试", "History read failed · retrying")
            }
        }
        switch phase {
        case .waiting:
            return language.text("正在读取", "Reading")
        case .refreshing:
            return language.text("上次结果 · 更新中", "Previous result · updating")
        case .ready:
            return language.text("已更新", "Updated")
        case .cached:
            return language.text("上次结果", "Previous result")
        case .background:
            return observedAt == nil
                ? language.text("历史统计正在补全", "History is being prepared")
                : language.text("上次完整结果 · 历史补全中", "Last complete result · preparing history")
        case .unavailable:
            return language.text("暂未取得数据 · 可重试", "Data unavailable · retry")
        }
    }
}

struct HomePresentation {
    let snapshot: MultiRuntimeUsageSnapshot
    let statuses: [HomeDataKey: HomeLoadStatus]
    let isRefreshing: Bool

    func sectionStatus(scope: RuntimeScope?, kind: HomeDataKind) -> HomeLoadStatus {
        statuses[HomeDataKey(scope: scope, kind: kind)] ?? HomeLoadStatus()
    }
}

extension LocalUsage {
    // The aggregate is used for the home total. Never regroup every historical
    // project, tool, event or day on the main thread when a quota reply arrives.
    var homeSummary: LocalUsage {
        LocalUsage(
            lifetimeTokens: lifetimeTokens, todayTokens: todayTokens,
            sevenDayTokens: sevenDayTokens, threadCount: threadCount,
            lastUpdatedAt: lastUpdatedAt, dailyBuckets: [], recentThreads: [],
            detailedUsage: detailedUsage, usageTrend: nil, inferencePerformance: nil,
            projectBoard: nil, toolUsages: [], skillUsages: []
        )
    }
}

extension UsageSnapshot {
    func replacingLocal(_ local: LocalUsage?, observedAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            refreshedAt: observedAt ?? refreshedAt, account: account,
            limitId: limitId, limitName: limitName, quotaReadSucceeded: quotaReadSucceeded,
            fiveHourQuota: fiveHourQuota, sevenDayQuota: sevenDayQuota,
            monthlyQuota: monthlyQuota, credits: credits, cloudLifetimeTokens: cloudLifetimeTokens,
            local: local, taskBoard: taskBoard, messages: messages
        )
    }
}

extension TaskBoard {
    // Display caches and fast reads contain only the visible page. Preserve
    // counts of unmaterialized records when adding current live observations.
    func mergingHomeTasks(_ live: CodexTaskLiveSnapshot) -> TaskBoard {
        let isPartialPage = columns.contains(where: { $0.count > $0.items.count })
        let liveRecords: [String: TaskLiveRecord]
        if isPartialPage {
            // Only known visible IDs can change a partial page's counts. Look
            // them up directly so a large live dictionary does not enter the
            // main-thread rendering path or hide updates to visible cards.
            var visibleRecords: [String: TaskLiveRecord] = [:]
            for column in columns.prefix(4) {
                for item in column.items.prefix(6) {
                    if let id = item.threadID, let record = live.records[id] {
                        visibleRecords[id] = record
                    }
                }
            }
            liveRecords = visibleRecords
        } else {
            liveRecords = Dictionary(uniqueKeysWithValues: live.records.prefix(24).map { ($0.key, $0.value) })
        }
        let boundedLive = CodexTaskLiveSnapshot(
            connectionMode: live.connectionMode,
            records: liveRecords,
            refreshedAt: live.refreshedAt
        )
        let merged = merging(boundedLive)
        let hidden = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, max(0, $0.count - $0.items.count)) })
        return TaskBoard(refreshedAt: merged.refreshedAt, columns: merged.columns.map {
            TaskColumn(id: $0.id, title: $0.title, count: $0.count + (hidden[$0.id] ?? 0), items: Array($0.items.prefix(6)))
        })
    }
}
