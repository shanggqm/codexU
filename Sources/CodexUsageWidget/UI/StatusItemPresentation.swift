import Cocoa

enum StatusItemQuotaPaletteRole: Equatable {
    case primary
    case secondary
}

struct StatusItemSourceSnapshot: Equatable {
    let runtime: RuntimeScope
    let status: RuntimeMenuStatus
    let fiveHourRemainingPercent: Double?
    let fiveHourResetsAt: Date?
    let sevenDayRemainingPercent: Double?
    let sevenDayResetsAt: Date?
    let todayTokens: Int64?

    init(summary: RuntimeMenuSummary) {
        runtime = summary.scope
        status = summary.status
        fiveHourRemainingPercent = summary.fiveHourRemainingPercent
        fiveHourResetsAt = summary.fiveHourResetsAt
        sevenDayRemainingPercent = summary.sevenDayRemainingPercent
        sevenDayResetsAt = summary.sevenDayResetsAt
        todayTokens = summary.todayTokens
    }

    static func unavailable(runtime: RuntimeScope) -> StatusItemSourceSnapshot {
        StatusItemSourceSnapshot(
            runtime: runtime,
            status: .unavailable,
            fiveHourRemainingPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayRemainingPercent: nil,
            sevenDayResetsAt: nil,
            todayTokens: nil
        )
    }

    init(
        runtime: RuntimeScope,
        status: RuntimeMenuStatus = .available,
        fiveHourRemainingPercent: Double?,
        fiveHourResetsAt: Date?,
        sevenDayRemainingPercent: Double?,
        sevenDayResetsAt: Date?,
        todayTokens: Int64?
    ) {
        self.runtime = runtime
        self.status = status
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayRemainingPercent = sevenDayRemainingPercent
        self.sevenDayResetsAt = sevenDayResetsAt
        self.todayTokens = todayTokens
    }
}

struct StatusItemMetricPresentation: Equatable, Identifiable {
    let metric: StatusItemMetric
    let label: String
    let value: String
    let compactValue: String
    let fraction: CGFloat?
    let paletteRole: StatusItemQuotaPaletteRole?
    let resetText: String?
    let isAvailable: Bool

    var id: String { metric.rawValue }
    var isQuota: Bool { metric.isQuota }
}

struct StatusItemPresentation: Equatable {
    let mode: StatusItemDisplayMode
    let quotaMode: QuotaDisplayMode
    let showsResetCountdown: Bool
    let runtime: RuntimeScope
    let imageSize: NSSize
    let itemLength: CGFloat
    let showsNoActiveQuota: Bool
    let metrics: [StatusItemMetricPresentation]
    let tooltip: String
    let accessibilityValue: String

    var quotaMetrics: [StatusItemMetricPresentation] {
        metrics.filter(\.isQuota)
    }

    var todayMetric: StatusItemMetricPresentation? {
        metrics.first { $0.metric == .todayTokens }
    }
}

enum StatusItemLayoutMetrics {
    static let imageHeight: CGFloat = 22
    static let itemOuterPadding: CGFloat = 8
    static let minimalImageWidth: CGFloat = 26
    static let minimalOuterRingDiameter: CGFloat = 21
    static let minimalInnerRingDiameter: CGFloat = 14
    static let minimalOuterRingLineWidth: CGFloat = 2.5
    static let minimalInnerRingLineWidth: CGFloat = 2.2
    static let minimalRingClearance: CGFloat = 0.75
    static let leadingContentWidth: CGFloat = 22
    static let classicQuotaUnitWidth: CGFloat = 23
    static let classicTokenUnitWidth: CGFloat = 54
    static let richQuotaWidthWithReset: CGFloat = 126
    static let richQuotaWidthWithoutReset: CGFloat = 98
    static let richTokenOnlyWidth: CGFloat = 70
    static let richTokenExtensionWidth: CGFloat = 54
    static let richSingleQuotaBarRect = NSRect(x: 45, y: 4.5, width: 49, height: 13)
    static let richSingleQuotaResetRect = NSRect(x: 96, y: 4.5, width: 28, height: 13)
    static let richResetIconSide: CGFloat = 7
    static let richResetIconTextSpacing: CGFloat = 0.75
    static let richResetFontSize: CGFloat = 8.2
    static let todayTokenFontSize: CGFloat = NSFont.systemFontSize

    static func richResetContentWidth(for text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: richResetFontSize, weight: .medium)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return richResetIconSide + richResetIconTextSpacing + textWidth
    }

    static var minimalOuterRingRect: NSRect {
        centeredMinimalRect(side: minimalOuterRingDiameter)
    }

    static var minimalInnerRingRect: NSRect {
        centeredMinimalRect(side: minimalInnerRingDiameter)
    }

    private static func centeredMinimalRect(side: CGFloat) -> NSRect {
        NSRect(
            x: (minimalImageWidth - side) / 2,
            y: (imageHeight - side) / 2,
            width: side,
            height: side
        )
    }

    static func imageWidth(
        for preferences: StatusItemPreferences,
        metrics: [StatusItemMetricPresentation],
        showsNoActiveQuota: Bool
    ) -> CGFloat {
        let normalized = preferences.normalized()
        let quotaCount = metrics.filter(\.isQuota).count
        let showsToday = metrics.contains { $0.metric == .todayTokens }

        switch normalized.displayMode {
        case .minimal:
            return minimalImageWidth
        case .classic:
            return leadingContentWidth
                + CGFloat(quotaCount + (showsNoActiveQuota ? 1 : 0)) * classicQuotaUnitWidth
                + (showsToday ? classicTokenUnitWidth : 0)
                + 2
        case .rich:
            if quotaCount > 0 || showsNoActiveQuota {
                let quotaWidth = normalized.showsResetCountdown
                    && !showsNoActiveQuota ? richQuotaWidthWithReset
                    : richQuotaWidthWithoutReset
                return quotaWidth + (showsToday ? richTokenExtensionWidth : 0)
            }
            return showsToday ? richTokenOnlyWidth : richQuotaWidthWithoutReset
        }
    }
}

struct StatusItemPresentationBuilder {
    func build(
        source: StatusItemSourceSnapshot,
        preferences: StatusItemPreferences,
        language: WidgetLanguage,
        shortcutName: String? = GlobalShortcut.default.displayName,
        now: Date = Date()
    ) -> StatusItemPresentation {
        let preferences = preferences.normalized()
        let configuredMetrics = preferences.orderedVisibleMetrics.map { metric in
            makeMetric(
                metric,
                source: source,
                preferences: preferences,
                language: language,
                now: now
            )
        }
        let availableQuotaMetrics = [StatusItemMetric.fiveHourQuota, .sevenDayQuota]
            .map { metric in
                makeMetric(
                    metric,
                    source: source,
                    preferences: preferences,
                    language: language,
                    now: now
                )
            }
            .filter(\.isAvailable)
        let showsNoActiveQuota = source.status == .available
            && availableQuotaMetrics.isEmpty
            && preferences.hasVisibleQuota
        let metrics = effectiveMetrics(
            from: configuredMetrics,
            availableQuotaMetrics: availableQuotaMetrics,
            sourceStatus: source.status
        )
        let imageWidth = StatusItemLayoutMetrics.imageWidth(
            for: preferences,
            metrics: metrics,
            showsNoActiveQuota: showsNoActiveQuota
        )
        let description = accessibilityDescription(
            source: source,
            preferences: preferences,
            metrics: metrics,
            showsNoActiveQuota: showsNoActiveQuota,
            language: language
        )
        let action: String
        if let shortcutName {
            action = language.text(
                "点击查看 Runtime 用量菜单，快捷键 \(shortcutName)",
                "Click for the runtime usage menu, shortcut \(shortcutName)"
            )
        } else {
            action = language.text("点击查看 Runtime 用量菜单", "Click for the runtime usage menu")
        }

        return StatusItemPresentation(
            mode: preferences.displayMode,
            quotaMode: preferences.quotaMode,
            showsResetCountdown: preferences.showsResetCountdown,
            runtime: source.runtime,
            imageSize: NSSize(width: imageWidth, height: StatusItemLayoutMetrics.imageHeight),
            itemLength: imageWidth + StatusItemLayoutMetrics.itemOuterPadding,
            showsNoActiveQuota: showsNoActiveQuota,
            metrics: metrics,
            tooltip: "codexU · \(description) · \(action)",
            accessibilityValue: description
        )
    }

    /// Preferences remain persistent, while the rendered set follows the last
    /// authoritative quota topology. If every selected quota has disappeared,
    /// temporarily show the first real quota instead of leaving an empty item.
    private func effectiveMetrics(
        from configuredMetrics: [StatusItemMetricPresentation],
        availableQuotaMetrics: [StatusItemMetricPresentation],
        sourceStatus: RuntimeMenuStatus
    ) -> [StatusItemMetricPresentation] {
        guard sourceStatus == .available || sourceStatus == .stale else {
            return configuredMetrics
        }

        if availableQuotaMetrics.isEmpty {
            return sourceStatus == .available
                ? configuredMetrics.filter { !$0.isQuota }
                : configuredMetrics
        }

        let configuredAvailable = configuredMetrics.filter { metric in
            !metric.isQuota || metric.isAvailable
        }
        if configuredAvailable.contains(where: \.isQuota) {
            return configuredAvailable
        }
        guard configuredMetrics.contains(where: \.isQuota),
              let fallbackQuota = availableQuotaMetrics.first
        else { return configuredAvailable }
        return [fallbackQuota] + configuredAvailable
    }

    private func makeMetric(
        _ metric: StatusItemMetric,
        source: StatusItemSourceSnapshot,
        preferences: StatusItemPreferences,
        language: WidgetLanguage,
        now: Date
    ) -> StatusItemMetricPresentation {
        switch metric {
        case .fiveHourQuota:
            return makeQuotaMetric(
                metric: metric,
                label: "5h",
                remainingPercent: source.fiveHourRemainingPercent,
                resetsAt: source.fiveHourResetsAt,
                paletteRole: .primary,
                preferences: preferences,
                now: now
            )
        case .sevenDayQuota:
            return makeQuotaMetric(
                metric: metric,
                label: "7d",
                remainingPercent: source.sevenDayRemainingPercent,
                resetsAt: source.sevenDayResetsAt,
                paletteRole: .secondary,
                preferences: preferences,
                now: now
            )
        case .todayTokens:
            let value = TokenFormatter.format(source.todayTokens)
            return StatusItemMetricPresentation(
                metric: metric,
                label: language.text("今日", "Today"),
                value: value,
                compactValue: value,
                fraction: nil,
                paletteRole: nil,
                resetText: nil,
                isAvailable: source.todayTokens != nil
            )
        }
    }

    private func makeQuotaMetric(
        metric: StatusItemMetric,
        label: String,
        remainingPercent: Double?,
        resetsAt: Date?,
        paletteRole: StatusItemQuotaPaletteRole,
        preferences: StatusItemPreferences,
        now: Date
    ) -> StatusItemMetricPresentation {
        let remaining = remainingPercent.map { max(0, min(100, $0)) }
        let displayPercent = remaining.map { value in
            preferences.quotaMode == .remaining ? value : 100 - value
        }
        let roundedValue = displayPercent.map { Int($0.rounded()) }
        let compactValue = roundedValue.map(String.init) ?? "--"
        let value = roundedValue.map { "\($0)%" } ?? "--"
        let fraction = displayPercent.map { CGFloat($0 / 100) }
        let resetText = preferences.showsResetCountdown
            ? formatResetCountdown(resetsAt, now: now)
            : nil

        return StatusItemMetricPresentation(
            metric: metric,
            label: label,
            value: value,
            compactValue: compactValue,
            fraction: fraction,
            paletteRole: paletteRole,
            resetText: resetText,
            isAvailable: remaining != nil
        )
    }

    private func accessibilityDescription(
        source: StatusItemSourceSnapshot,
        preferences: StatusItemPreferences,
        metrics: [StatusItemMetricPresentation],
        showsNoActiveQuota: Bool,
        language: WidgetLanguage
    ) -> String {
        let quotaTerm = preferences.quotaMode == .remaining
            ? language.text("剩余", "remaining")
            : language.text("已用", "used")
        let unavailable = language.text("不可用", "unavailable")
        let noRecords = language.text("暂无记录", "no records")

        var values: [String] = []
        if source.status == .stale {
            values.append(language.text("额度快照已过期", "quota snapshot stale"))
        }
        if showsNoActiveQuota {
            values.append(language.text("当前无额度限制", "no active quota limits"))
        }
        values += metrics.map { metric -> String in
            switch metric.metric {
            case .fiveHourQuota, .sevenDayQuota:
                let value = metric.isAvailable ? metric.value : unavailable
                let quotaName: String
                switch metric.metric {
                case .fiveHourQuota:
                    quotaName = language.text("5 小时额度", "5-hour quota")
                case .sevenDayQuota:
                    quotaName = language.text("7 天额度", "7-day quota")
                case .todayTokens:
                    quotaName = metric.label
                }
                var description = "\(quotaName) \(quotaTerm) \(value)"
                if let resetText = metric.resetText {
                    let resetDescription = localizedResetCountdown(resetText, language: language)
                    description += language.text(
                        "，\(resetDescription)",
                        ", \(resetDescription)"
                    )
                }
                return description
            case .todayTokens:
                let value = metric.isAvailable ? metric.value : noRecords
                return language.text("今日 token \(value)", "today tokens \(value)")
            }
        }
        return ([source.runtime.displayName] + values).joined(separator: " · ")
    }

    private func localizedResetCountdown(_ compact: String, language: WidgetLanguage) -> String {
        guard let unit = compact.last,
              let amount = Int(compact.dropLast())
        else {
            return language.text("\(compact) 后重置", "resets in \(compact)")
        }

        if unit == "m", amount == 0 {
            return language.text("即将重置", "resets soon")
        }

        switch unit {
        case "d":
            return language.text(
                "\(amount) 天后重置",
                "resets in \(amount) \(amount == 1 ? "day" : "days")"
            )
        case "h":
            return language.text(
                "\(amount) 小时后重置",
                "resets in \(amount) \(amount == 1 ? "hour" : "hours")"
            )
        case "m":
            return language.text(
                "\(amount) 分钟后重置",
                "resets in \(amount) \(amount == 1 ? "minute" : "minutes")"
            )
        default:
            return language.text("\(compact) 后重置", "resets in \(compact)")
        }
    }

    private func formatResetCountdown(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.down)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

}
