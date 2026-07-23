import Foundation

enum RuntimeLegacyQuotaCompatibility {
    static func secondaryWindow(in snapshot: UsageSnapshot) -> RateWindow? {
        snapshot.sevenDayQuota
    }
}

func dumpJSON(_ snapshot: MultiRuntimeUsageSnapshot) {
    let codexSnapshot = snapshot.runtime(for: .codex)?.snapshot
    var object: [String: Any] = [
        "schemaVersion": 2,
        "refreshedAt": runtimeISOString(snapshot.refreshedAt) ?? "",
        "aggregate": runtimeJSONObject(snapshot.aggregate),
        "runtimes": snapshot.runtimes.map { runtimeJSONObject($0) },
        "leadership": leadershipJSONObject(snapshot.leadership),
        "compat": [
            "codex": codexSnapshot.map { runtimeJSONObject($0) } ?? NSNull()
        ] as [String: Any]
    ]

    if let codexSnapshot {
        object.merge(runtimeLegacyJSONObject(codexSnapshot)) { current, _ in current }
    }

    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

private func leadershipJSONObject(_ snapshot: LeadershipDashboardSnapshot) -> [String: Any] {
    let today = snapshot.todayReport
    return [
        "modelVersion": snapshot.modelVersion,
        "refreshedAt": runtimeISOString(snapshot.refreshedAt) ?? "",
        "defaultReport": snapshot.defaultReport.map { leadershipJSONObject($0) } ?? NSNull(),
        "today": today.map { report in
            [
                "agentCount": runtimeJSONValue(report.agentCount),
                "aiHours": runtimeJSONValue(report.aiHours)
            ] as [String: Any]
        } ?? NSNull(),
        "reports": snapshot.reports.map { leadershipJSONObject($0) }
    ] as [String: Any]
}

private func leadershipJSONObject(_ report: LeadershipReport) -> [String: Any] {
    [
        "period": report.period.rawValue,
        "score": runtimeJSONValue(report.score),
        "coreScore": runtimeJSONValue(report.coreScore),
        "title": report.title.map { title in
            [
                "level": title.level,
                "name": title.name,
                "lowerBound": title.lowerBound,
                "upperBound": title.upperBound
            ] as [String: Any]
        } ?? NSNull(),
        "maturity": report.maturity,
        "evidenceCoverage": report.evidenceCoverage,
        "activeDayCount": report.activeDayCount,
        "agentCount": runtimeJSONValue(report.agentCount),
        "aiHours": runtimeJSONValue(report.aiHours),
        "autonomousHours": runtimeJSONValue(report.autonomousHours),
        "averageParallelism": runtimeJSONValue(report.averageParallelism),
        "peakConcurrency": runtimeJSONValue(report.peakConcurrency),
        "projectCount": report.projectCount,
        "dimensions": report.dimensions.map { dimension in
            [
                "kind": dimension.kind.rawValue,
                "score": dimension.score,
                "confidence": dimension.confidence,
                "summaryValue": dimension.summaryValue
            ] as [String: Any]
        },
        "dailyPoints": report.dailyPoints.map { point in
            [
                "day": runtimeISOString(point.day) ?? "",
                "agentCount": point.agentCount,
                "aiHours": point.aiHours,
                "peakConcurrency": point.peakConcurrency
            ] as [String: Any]
        },
        "projects": report.projects.map { project in
            [
                "id": project.projectID,
                "name": project.projectName,
                "agentCount": project.agentCount,
                "aiHours": project.aiHours,
                "autonomousHours": project.autonomousHours
            ] as [String: Any]
        }
    ] as [String: Any]
}

private func runtimeJSONObject(_ runtime: RuntimeUsageSnapshot) -> [String: Any] {
    [
        "id": runtime.id,
        "scope": runtime.scope.rawValue,
        "displayName": runtime.displayName,
        "status": runtime.status.rawValue,
        "quotaSourceLabel": runtime.quotaSourceLabel,
        "usageSourceLabel": runtime.usageSourceLabel,
        "snapshot": runtimeJSONObject(runtime.snapshot)
    ] as [String: Any]
}

private func runtimeJSONObject(_ snapshot: UsageSnapshot) -> [String: Any] {
    var object = runtimeLegacyJSONObject(snapshot)
    object["refreshedAt"] = runtimeISOString(snapshot.refreshedAt) ?? ""
    object["quotaReadSucceeded"] = snapshot.quotaReadSucceeded
    object["quotaWindows"] = [
        "fiveHour": snapshot.fiveHourQuota.map(runtimeJSONObject) ?? NSNull(),
        "sevenDay": snapshot.sevenDayQuota.map(runtimeJSONObject) ?? NSNull(),
        "monthly": snapshot.monthlyQuota.map(runtimeJSONObject) ?? NSNull()
    ] as [String: Any]
    object["messages"] = snapshot.messages
    return object
}

private func runtimeLegacyJSONObject(_ snapshot: UsageSnapshot) -> [String: Any] {
    var object: [String: Any] = [:]

    if let account = snapshot.account {
        object["account"] = [
            "type": account.type,
            "planType": runtimeJSONValue(account.planType),
            "emailPresent": account.emailPresent
        ] as [String: Any]
    }

    if let primary = snapshot.fiveHourQuota {
        object["primary"] = runtimeJSONObject(primary)
    }

    if let secondary = RuntimeLegacyQuotaCompatibility.secondaryWindow(in: snapshot) {
        object["secondary"] = runtimeJSONObject(secondary)
    }

    if let credits = snapshot.credits {
        object["credits"] = [
            "hasCredits": credits.hasCredits,
            "unlimited": credits.unlimited,
            "balance": runtimeJSONValue(credits.balance),
            "resetCredits": runtimeJSONValue(credits.resetCredits),
            "resetCreditDetails": credits.resetCreditDetails.map { details in
                details.map { detail in
                    ["expiresAt": runtimeJSONValue(runtimeISOString(detail.expiresAt))]
                }
            } ?? NSNull()
        ] as [String: Any]
    }

    if let local = snapshot.local {
        object["local"] = runtimeJSONObject(local)
    }

    if let taskBoard = snapshot.taskBoard {
        object["taskBoard"] = runtimeJSONObject(taskBoard)
    }

    return object
}

private func runtimeJSONObject(_ window: RateWindow) -> [String: Any] {
    [
        "usedPercent": window.usedPercent,
        "remainingPercent": window.remainingPercent,
        "windowDurationMins": runtimeJSONValue(window.windowDurationMins),
        "resetsAt": runtimeJSONValue(runtimeISOString(window.resetsAt))
    ] as [String: Any]
}

private func runtimeJSONObject(_ local: LocalUsage) -> [String: Any] {
    var object: [String: Any] = [
        "todayTokens": local.todayTokens,
        "sevenDayTokens": local.sevenDayTokens,
        "lifetimeTokens": local.lifetimeTokens,
        "threadCount": local.threadCount,
        "lastUpdatedAt": runtimeJSONValue(runtimeISOString(local.lastUpdatedAt)),
        "dailyBuckets": local.dailyBuckets.map { bucket in
            [
                "day": bucket.id,
                "label": bucket.label,
                "tokens": bucket.tokens
            ] as [String: Any]
        },
        "toolUsages": local.toolUsages.prefix(20).map { runtimeJSONObject($0) },
        "skillUsages": local.skillUsages.prefix(20).map { runtimeJSONObject($0) }
    ]

    if let detailed = local.detailedUsage {
        object["detailedUsage"] = [
            "today": runtimeJSONObject(detailed.today),
            "sevenDay": runtimeJSONObject(detailed.sevenDay),
            "month": runtimeJSONObject(detailed.month),
            "lifetime": runtimeJSONObject(detailed.lifetime),
            "parsedFileCount": detailed.parsedFileCount,
            "tokenEventCount": detailed.tokenEventCount
        ] as [String: Any]
    }

    if let trend = local.usageTrend {
        let modelTrends: Any = trend.modelTrends.map { trends in
            trends.map { modelTrend in
                [
                    "id": modelTrend.id,
                    "model": modelTrend.model ?? NSNull(),
                    "dayCount": modelTrend.dayBuckets.count,
                    "activeDayCount": modelTrend.activeDayCount,
                    "sevenDay": runtimeJSONObject(modelTrend.summary.sevenDay),
                    "dailyAverageTokens": modelTrend.summary.dailyAverageTokens,
                    "changePercent": runtimeJSONValue(modelTrend.summary.changePercent)
                ] as [String: Any]
            }
        } ?? NSNull()
        let modelSeries: Any = trend.modelTrends.map { _ in
            ModelUsageAreaSeriesBuilder.build(from: trend).map { series in
                [
                    "id": series.id,
                    "model": runtimeJSONValue(series.model),
                    "isAggregate": series.isAggregate,
                    "dayCount": series.dayBuckets.count,
                    "activeDayCount": series.activeDayCount,
                    "sourceQuality": series.sourceQuality.rawValue,
                    "costAvailable": series.costAvailable,
                    "usesReferencePricing": series.usesReferencePricing,
                    "dayBuckets": series.dayBuckets.map { bucket in
                        [
                            "day": bucket.id,
                            "tokens": bucket.tokens,
                            "estimatedCostUSD": runtimeJSONValue(series.costAvailable ? bucket.usage.estimatedCostUSD : nil)
                        ] as [String: Any]
                    }
                ] as [String: Any]
            }
        } ?? NSNull()
        object["usageTrend"] = [
            "sourceQuality": trend.sourceQuality.rawValue,
            "dayCount": trend.dayBuckets.count,
            "activeDayCount": trend.activeDayCount,
            "sevenDay": runtimeJSONObject(trend.summary.sevenDay),
            "dailyAverageTokens": trend.summary.dailyAverageTokens,
            "peakDay": trend.summary.peakDay.map { bucket in
                [
                    "day": bucket.id,
                    "tokens": bucket.tokens,
                    "estimatedCostUSD": bucket.usage.estimatedCostUSD
                ] as [String: Any]
            } ?? NSNull(),
            "modelAttribution": trend.modelTrends == nil ? "unsupported" : "available",
            "modelTrends": modelTrends,
            "modelSeries": modelSeries,
            "changePercent": runtimeJSONValue(trend.summary.changePercent),
            "isNewActivity": trend.summary.isNewActivity,
            "month": runtimeJSONObject(trend.month),
            "projectedMonthCostUSD": runtimeJSONValue(trend.projectedMonthCostUSD)
        ] as [String: Any]
    }

    if let projectBoard = local.projectBoard {
        object["projectBoard"] = [
            "recentProjects": projectBoard.recentProjects.prefix(8).map { runtimeJSONObject($0) },
            "allProjects": projectBoard.allProjects.prefix(8).map { runtimeJSONObject($0) }
        ] as [String: Any]
    }

    return object
}

private func runtimeJSONObject(_ taskBoard: TaskBoard) -> [String: Any] {
    [
        "refreshedAt": runtimeISOString(taskBoard.refreshedAt) ?? "",
        "totalCount": taskBoard.totalCount,
        "columns": taskBoard.columns.map { column in
            [
                "id": column.id.rawValue,
                "title": column.title,
                "count": column.count,
                "items": column.items.map { item in
                    [
                        "id": item.id,
                        "code": item.code,
                        "title": item.title,
                        "detail": item.detail,
                        "chip": item.chip,
                        "runtimeState": item.runtimeState.rawValue,
                        "isRealtime": item.isRealtime,
                        "sourceKind": item.sourceKind.rawValue,
                        "displayState": item.displayState.rawValue,
                        "stateBasis": item.stateBasis.rawValue,
                        "rawStatus": runtimeJSONValue(item.rawStatus),
                        "nextRunAt": runtimeJSONValue(runtimeISOString(item.nextRunAt)),
                        "updatedAt": runtimeJSONValue(runtimeISOString(item.updatedAt)),
                        "tokens": runtimeJSONValue(item.tokens)
                    ] as [String: Any]
                }
            ] as [String: Any]
        }
    ] as [String: Any]
}

private func runtimeJSONObject(_ usage: PricedTokenUsage) -> [String: Any] {
    [
        "tokens": [
            "inputTokens": usage.tokens.inputTokens,
            "cachedInputTokens": usage.tokens.cachedInputTokens,
            "uncachedInputTokens": usage.tokens.uncachedInputTokens,
            "outputTokens": usage.tokens.outputTokens,
            "reasoningOutputTokens": usage.tokens.reasoningOutputTokens,
            "totalTokens": usage.tokens.totalTokens,
            "visibleTotalTokens": usage.tokens.visibleTotalTokens
        ] as [String: Any],
        "estimatedCostUSD": usage.estimatedCostUSD
    ] as [String: Any]
}

private func runtimeJSONObject(_ project: ProjectUsage) -> [String: Any] {
    [
        "name": project.name,
        "fullPath": project.fullPath,
        "tokens": project.tokens,
        "estimatedCostUSD": runtimeJSONValue(project.estimatedCostUSD),
        "threadCount": project.threadCount,
        "lastActiveAt": runtimeJSONValue(runtimeISOString(project.lastActiveAt)),
        "sourceQuality": project.sourceQuality.rawValue
    ] as [String: Any]
}

private func runtimeJSONObject(_ tool: ToolUsage) -> [String: Any] {
    [
        "name": tool.name,
        "category": tool.category,
        "callCount": tool.callCount,
        "estimatedTokens": runtimeJSONValue(tool.estimatedTokens),
        "estimatedCostUSD": runtimeJSONValue(tool.estimatedCostUSD)
    ] as [String: Any]
}

private func runtimeJSONObject(_ skill: SkillUsage) -> [String: Any] {
    [
        "name": skill.name,
        "path": skill.path,
        "sourceLabel": skill.sourceLabel,
        "loadCount": skill.loadCount,
        "threadCount": skill.threadCount,
        "staticTokenEstimate": runtimeJSONValue(skill.staticTokenEstimate),
        "staticByteCount": runtimeJSONValue(skill.staticByteCount),
        "lastLoadedAt": runtimeJSONValue(runtimeISOString(skill.lastLoadedAt))
    ] as [String: Any]
}

private func runtimeJSONValue<T>(_ value: T?) -> Any {
    value ?? NSNull()
}

private func runtimeISOString(_ date: Date?) -> String? {
    guard let date else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
