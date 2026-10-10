import Foundation

final class MultiRuntimeUsageReader {
    private let registry: RuntimeProviderRegistry
    private let aggregator: AgentUsageAggregator

    init(
        registry: RuntimeProviderRegistry = RuntimeProviderRegistry(),
        aggregator: AgentUsageAggregator = AgentUsageAggregator()
    ) {
        self.registry = registry
        self.aggregator = aggregator
    }

    func load(
        statisticsPreference: StatisticsTimeZonePreference = .default,
        generation: UInt64 = 0
    ) -> MultiRuntimeUsageSnapshot {
        let span = PerformanceMonitor.shared.begin(.runtimeLoad)
        let context = RuntimeLoadContext.live(statisticsPreference: statisticsPreference)
        let runtimeSnapshots = registry.providers.map { provider in
            provider.loadSnapshot(context: context)
        }
        let refreshedAt = Date()
        let aggregate = aggregator.aggregate(runtimeSnapshots, at: refreshedAt)
        let leadership = LeadershipDataReader().load(context: context)
        let snapshot = MultiRuntimeUsageSnapshot(
            refreshedAt: refreshedAt,
            runtimes: runtimeSnapshots,
            aggregate: aggregate,
            leadership: leadership,
            statisticsIdentity: StatisticsIdentity(
                preference: context.statistics.preference,
                resolvedIdentifier: context.statistics.resolvedIdentifier,
                generation: generation,
                now: context.now
            )
        )
        PerformanceMonitor.shared.end(span)
        return snapshot
    }

    func loadTaskBoard(
        scope: RuntimeScope,
        statisticsPreference: StatisticsTimeZonePreference = .default
    ) -> TaskBoard? {
        let span = PerformanceMonitor.shared.begin(.taskLoad)
        let context = RuntimeLoadContext.live(statisticsPreference: statisticsPreference)
        let board = registry.provider(for: scope)?.loadTaskBoard(context: context)
        PerformanceMonitor.shared.end(span, success: board != nil)
        return board
    }

    func loadQuota(scope: RuntimeScope, context: RuntimeLoadContext) -> RuntimeUsageSnapshot? {
        registry.provider(for: scope)?.loadQuotaSnapshot(context: context)
    }

    // The caller serializes local loads: legacy analytics caches have one owner.
    func loadLocal(scope: RuntimeScope, context: RuntimeLoadContext) -> RuntimeUsageSnapshot? {
        registry.provider(for: scope)?.loadLocalSnapshot(context: context)
    }
}
