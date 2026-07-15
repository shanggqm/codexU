import Foundation

enum RuntimeScope: String, CaseIterable, Identifiable, Codable, Equatable {
    case codex
    case claudeCode

    var id: String { rawValue }

    static func storedIdentifier(_ value: String) -> RuntimeScope? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { scope in
            scope.rawValue.lowercased() == normalized || scope.runtimeId.lowercased() == normalized
        }
    }

    var runtimeId: String {
        switch self {
        case .codex:
            return "codex"
        case .claudeCode:
            return "claude-code"
        }
    }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        }
    }
}

enum RuntimeMenuStatus: String, Codable, Equatable {
    case available
    case localOnly
    case snapshotNeeded
    case stale
    case unavailable

    func localized(_ language: WidgetLanguage) -> String {
        switch self {
        case .available:
            return language.text("可用", "Available")
        case .localOnly:
            return language.text("本机统计", "Local only")
        case .snapshotNeeded:
            return language.text("需要快照", "Snapshot needed")
        case .stale:
            return language.text("快照过期", "Stale")
        case .unavailable:
            return language.text("暂不可用", "Unavailable")
        }
    }
}

struct RuntimeMenuSummary: Identifiable, Equatable {
    let scope: RuntimeScope
    let displayName: String
    let status: RuntimeMenuStatus
    let fiveHourRemainingPercent: Double?
    let fiveHourResetsAt: Date?
    let sevenDayRemainingPercent: Double?
    let sevenDayResetsAt: Date?
    let todayTokens: Int64?
    let sourceLabel: String

    var id: String { scope.runtimeId }
}

struct RuntimeUsageSnapshot: Identifiable, Equatable {
    let scope: RuntimeScope
    let snapshot: UsageSnapshot
    let status: RuntimeMenuStatus
    let quotaSourceLabel: String
    let usageSourceLabel: String

    var id: String { scope.runtimeId }
    var displayName: String { scope.displayName }

    var todayTokens: Int64? {
        preferredRuntimeTodayTokens(
            detailed: snapshot.local?.detailedUsage?.today.tokens.visibleTotalTokens,
            fallback: snapshot.local?.todayTokens
        )
    }

    var summary: RuntimeMenuSummary {
        RuntimeMenuSummary(
            scope: scope,
            displayName: displayName,
            status: status,
            fiveHourRemainingPercent: snapshot.fiveHourQuota?.remainingPercent,
            fiveHourResetsAt: snapshot.fiveHourQuota?.resetsAt,
            sevenDayRemainingPercent: snapshot.sevenDayQuota?.remainingPercent,
            sevenDayResetsAt: snapshot.sevenDayQuota?.resetsAt,
            todayTokens: todayTokens,
            sourceLabel: quotaSourceLabel
        )
    }

    func replacingTaskBoard(_ taskBoard: TaskBoard?) -> RuntimeUsageSnapshot {
        RuntimeUsageSnapshot(
            scope: scope,
            snapshot: snapshot.replacingTaskBoard(taskBoard),
            status: status,
            quotaSourceLabel: quotaSourceLabel,
            usageSourceLabel: usageSourceLabel
        )
    }
}

enum RuntimeQuotaContinuity {
    static func reconcile(
        previous: [RuntimeUsageSnapshot],
        incoming: [RuntimeUsageSnapshot]
    ) -> [RuntimeUsageSnapshot] {
        let previousByScope = Dictionary(uniqueKeysWithValues: previous.map { ($0.scope, $0) })

        return incoming.map { next in
            guard !next.snapshot.quotaReadSucceeded,
                  let last = previousByScope[next.scope],
                  last.status == .available || last.status == .stale,
                  last.snapshot.fiveHourQuota != nil || last.snapshot.sevenDayQuota != nil
            else {
                return next
            }

            return RuntimeUsageSnapshot(
                scope: next.scope,
                snapshot: next.snapshot.replacingQuotaWindows(
                    fiveHourQuota: last.snapshot.fiveHourQuota,
                    sevenDayQuota: last.snapshot.sevenDayQuota,
                    quotaReadSucceeded: false
                ),
                status: .stale,
                quotaSourceLabel: last.quotaSourceLabel.hasSuffix(" · stale")
                    ? last.quotaSourceLabel
                    : "\(last.quotaSourceLabel) · stale",
                usageSourceLabel: next.usageSourceLabel
            )
        }
    }
}

func preferredRuntimeTodayTokens(detailed: Int64?, fallback: Int64?) -> Int64? {
    detailed ?? fallback
}

struct MultiRuntimeUsageSnapshot: Equatable {
    let refreshedAt: Date
    let runtimes: [RuntimeUsageSnapshot]
    let aggregate: UsageSnapshot
    let statisticsIdentity: StatisticsIdentity

    static let empty = MultiRuntimeUsageSnapshot(
        refreshedAt: Date(),
        runtimes: [],
        aggregate: .empty,
        statisticsIdentity: .empty()
    )

    var totalTodayTokens: Int64 {
        runtimes.reduce(Int64(0)) { total, runtime in
            total + (runtime.todayTokens ?? 0)
        }
    }

    func runtime(for scope: RuntimeScope) -> RuntimeUsageSnapshot? {
        runtimes.first { $0.scope == scope }
    }

    func displaySnapshot(for scope: RuntimeScope) -> UsageSnapshot {
        runtime(for: scope)?.snapshot ?? runtimes.first?.snapshot ?? aggregate
    }

    func defaultScope(preferred: RuntimeScope, allowedScopes: [RuntimeScope] = RuntimeScope.allCases) -> RuntimeScope {
        let allowed = allowedScopes.isEmpty ? RuntimeScope.allCases : allowedScopes
        if allowed.contains(preferred), runtime(for: preferred) != nil {
            return preferred
        }
        if let available = allowed.first(where: { scope in
            runtime(for: scope)?.status != .unavailable
        }) {
            return available
        }
        return allowed.first ?? preferred
    }
}
