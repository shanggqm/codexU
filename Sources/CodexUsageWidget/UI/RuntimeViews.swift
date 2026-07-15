import SwiftUI

struct LocalSystemStatusStrip: View {
    let snapshot: LocalSystemSnapshot
    let language: WidgetLanguage

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(language.text("本机状态", "Local system"))
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 110, alignment: .leading)

            systemMetric(
                title: "CPU",
                value: snapshot.cpuUsagePercent.map { String(format: "%.0f%%", $0) } ?? "--",
                detail: language.text("系统总占用", "System total"),
                systemName: "cpu",
                tint: metricTint(snapshot.cpuUsagePercent)
            )
            Divider().frame(height: 34)
            systemMetric(
                title: language.text("内存", "Memory"),
                value: memoryPercentText,
                detail: memoryDetailText,
                systemName: "memorychip",
                tint: metricTint(memoryPercent)
            )
            Divider().frame(height: 34)
            systemMetric(
                title: language.text("温度 / 热状态", "Temperature / thermal"),
                value: temperatureText,
                detail: temperatureDetailText,
                systemName: "thermometer.medium",
                tint: thermalTint
            )
            .help(language.text(
                "优先显示温度传感器；本机没有可用的公开传感器时显示 macOS 热状态。",
                "Shows a sensor temperature when available; otherwise shows the macOS thermal state."
            ))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .sectionBackground()
        .accessibilityElement(children: .contain)
    }

    private func systemMetric(
        title: String,
        value: String,
        detail: String,
        systemName: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var memoryPercent: Double? {
        guard let used = snapshot.memoryUsedBytes,
              let total = snapshot.memoryTotalBytes,
              total > 0 else { return nil }
        return Double(used) / Double(total) * 100
    }

    private var memoryPercentText: String {
        memoryPercent.map { String(format: "%.0f%%", $0) } ?? "--"
    }

    private var memoryDetailText: String {
        guard let used = snapshot.memoryUsedBytes,
              let total = snapshot.memoryTotalBytes else {
            return language.text("系统物理内存", "Physical memory")
        }
        return "\(formatSystemBytes(used)) / \(formatSystemBytes(total))"
    }

    private var temperatureText: String {
        if let temperature = snapshot.temperatureCelsius {
            return String(format: "%.0f°C", temperature)
        }
        switch snapshot.thermalLevel {
        case .nominal:
            return language.text("正常", "Normal")
        case .fair:
            return language.text("偏热", "Warm")
        case .serious:
            return language.text("较热", "Hot")
        case .critical:
            return language.text("严重", "Critical")
        case .unknown:
            return "--"
        }
    }

    private var temperatureDetailText: String {
        snapshot.temperatureCelsius == nil
            ? language.text("macOS 热状态", "macOS thermal state")
            : language.text("本机传感器", "Local sensor")
    }

    private var thermalTint: Color {
        switch snapshot.thermalLevel {
        case .nominal:
            return WidgetPalette.statusSuccess
        case .fair:
            return WidgetPalette.statusWarning
        case .serious, .critical:
            return WidgetPalette.statusDanger
        case .unknown:
            return WidgetPalette.statusInfo
        }
    }

    private func metricTint(_ percent: Double?) -> Color {
        guard let percent else { return WidgetPalette.statusInfo }
        if percent >= 90 { return WidgetPalette.statusDanger }
        if percent >= 75 { return WidgetPalette.statusWarning }
        return WidgetPalette.statusSuccess
    }

    private func formatSystemBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}

struct RuntimeSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    let selected: RuntimeScope
    let scopes: [RuntimeScope]
    let language: WidgetLanguage
    let onSelect: (RuntimeScope) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(scopes) { scope in
                Button {
                    onSelect(scope)
                } label: {
                    HStack(spacing: 5) {
                        RuntimeLogoView(scope: scope, size: 15)
                        Text(label(for: scope))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(selected == scope ? .primary : .secondary)
                    .frame(minWidth: scope == .openClaw ? 104 : 78, minHeight: titlebarControlHeight)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected == scope ? WidgetPalette.controlSelectedFill(colorScheme) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help(label(for: scope))
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
    }

    private func label(for scope: RuntimeScope) -> String {
        switch scope {
        case .codex:
            return "Codex"
        case .openClaw:
            return "OpenClaw"
        }
    }
}

struct RuntimeStatusMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateStore: AppUpdateStore
    let openRuntime: (RuntimeScope) -> Void
    let openCurrent: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    private var language: WidgetLanguage { settings.language }
    private var displayedScopes: [RuntimeScope] { settings.visibleRuntimeScopes }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 9) {
                ForEach(displayedScopes) { scope in
                    RuntimeSummaryCard(
                        summary: summary(for: scope),
                        isSelected: store.selectedRuntimeScope == scope,
                        language: language
                    ) {
                        openRuntime(scope)
                    }
                }
            }
            totalRow
            AppUpdateMenuRow(updateStore: updateStore, language: language)
            footer
        }
        .padding(14)
        .frame(width: 380, height: runtimeStatusPopoverHeight(for: displayedScopes.count), alignment: .top)
        .readableForegroundHierarchy(colorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("codexU")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(language.text("刷新", "Refreshed")) \(runtimeTimeOnly(store.snapshot.refreshedAt))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: store.isRefreshing ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help(language.text("刷新", "Refresh"))
        }
    }

    private var totalRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sum")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(language.text("今日总 token", "Total tokens today"))
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(TokenFormatter.format(store.totalTodayTokens(for: displayedScopes)))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            menuCommandButton(
                title: language.text("打开主界面", "Open"),
                systemName: "rectangle.on.rectangle",
                action: openCurrent
            )
            menuCommandButton(
                title: language.text("设置", "Settings"),
                systemName: "gearshape",
                action: openSettings
            )
            menuCommandButton(
                title: language.text("退出", "Quit"),
                systemName: "power",
                action: quit
            )
        }
    }

    private func menuCommandButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WidgetPalette.controlFill(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func summary(for scope: RuntimeScope) -> RuntimeMenuSummary {
        store.runtimeSnapshot(for: scope)?.summary ?? RuntimeMenuSummary(
            scope: scope,
            displayName: scope.displayName,
            status: .unavailable,
            fiveHourRemainingPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayRemainingPercent: nil,
            sevenDayResetsAt: nil,
            todayTokens: nil,
            sourceLabel: language.text("等待本机统计", "Waiting for local records")
        )
    }
}

struct RuntimeSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: RuntimeMenuSummary
    let isSelected: Bool
    let language: WidgetLanguage
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 8) {
                    RuntimeLogoView(scope: summary.scope, size: 24)
                    Text(summary.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(summary.status.localized(language))
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(statusTint.opacity(0.16))
                        )
                        .foregroundStyle(statusTint)
                }

                HStack(spacing: 10) {
                    if quotaItems.isEmpty {
                        quotaUnavailableColumn
                    } else {
                        ForEach(quotaItems) { item in
                            quotaColumn(item, width: quotaColumnWidth)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("今日 token", "Today"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(TokenFormatter.format(summary.todayTokens))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(width: 82, alignment: .leading)
                }

                Text(localizedSourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? selectedFill : WidgetPalette.cardFill(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? selectedStroke : WidgetPalette.cardStroke(colorScheme), lineWidth: 0.9)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(language.text("打开 \(summary.displayName)", "Open \(summary.displayName)"))
    }

    private var quotaItems: [RuntimeQuotaSummaryItem] {
        var items: [RuntimeQuotaSummaryItem] = []
        if let value = summary.fiveHourRemainingPercent {
            items.append(RuntimeQuotaSummaryItem(
                id: "five-hour",
                title: language.text("5小时剩余", "5h left"),
                value: value,
                resetsAt: summary.fiveHourResetsAt
            ))
        }
        if let value = summary.sevenDayRemainingPercent {
            items.append(RuntimeQuotaSummaryItem(
                id: "seven-day",
                title: language.text("7日剩余", "7d left"),
                value: value,
                resetsAt: summary.sevenDayResetsAt
            ))
        }
        return items
    }

    private var quotaColumnWidth: CGFloat {
        quotaItems.count == 1 ? 182 : 86
    }

    private func quotaColumn(_ item: RuntimeQuotaSummaryItem, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(runtimeFormatPercent(item.value))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(WidgetPalette.surfaceTrack)
                    Capsule(style: .continuous)
                        .fill(statusTint.opacity(0.72))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, item.value)) / 100))
                }
            }
            .frame(height: 4)
            Text(item.resetsAt.map { runtimeTimeOnly($0) } ?? "--")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(width: width, alignment: .leading)
    }

    private var quotaUnavailableColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.text("额度", "Quota"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Image(systemName: quotaUnavailableSystemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusTint)
                Text(quotaUnavailableTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Text(quotaUnavailableDetail)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(width: 182, alignment: .leading)
    }

    private var quotaUnavailableTitle: String {
        switch summary.status {
        case .available:
            return language.text("当前无额度限制", "No active quota limits")
        case .localOnly:
            return language.text("暂无额度数据", "No quota data")
        case .snapshotNeeded:
            return language.text("需要额度快照", "Quota snapshot needed")
        case .stale:
            return language.text("额度快照已过期", "Quota snapshot is stale")
        case .unavailable:
            return language.text("额度暂不可用", "Quota unavailable")
        }
    }

    private var quotaUnavailableDetail: String {
        switch summary.status {
        case .available:
            return language.text("服务端未返回活动额度窗口", "No active quota window was returned")
        case .localOnly:
            return language.text("当前仅显示本机统计", "Showing local records only")
        case .snapshotNeeded:
            return language.text("打开 Runtime 后刷新", "Open the runtime, then refresh")
        case .stale:
            return language.text("打开 Runtime 获取最新快照", "Open the runtime for a fresh snapshot")
        case .unavailable:
            return language.text("请检查登录状态或数据源", "Check sign-in and the data source")
        }
    }

    private var quotaUnavailableSystemName: String {
        switch summary.status {
        case .available:
            return "checkmark.circle"
        case .snapshotNeeded:
            return "waveform.path.ecg"
        case .stale:
            return "clock.badge.exclamationmark"
        case .localOnly:
            return "info.circle"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusTint: Color {
        switch summary.status {
        case .available:
            return WidgetPalette.statusSuccess
        case .localOnly, .snapshotNeeded:
            return WidgetPalette.statusWarning
        case .stale:
            return WidgetPalette.statusInfo
        case .unavailable:
            return WidgetPalette.statusDanger
        }
    }

    private var selectedFill: Color {
        WidgetPalette.brandPrimary.opacity(colorScheme == .dark ? 0.20 : 0.12)
    }

    private var selectedStroke: Color {
        WidgetPalette.brandPrimary.opacity(colorScheme == .dark ? 0.42 : 0.34)
    }

    private var localizedSourceLabel: String {
        let hasQuota = summary.fiveHourRemainingPercent != nil
            || summary.sevenDayRemainingPercent != nil
        if language.isChinese {
            switch summary.scope {
            case .codex:
                if hasQuota { return "官方额度 + 本机统计" }
                return summary.status == .available
                    ? "官方额度：当前无限制 · 本机统计"
                    : "本机统计；额度暂不可用"
            case .openClaw:
                return "本机 OpenClaw 记录"
            }
        }
        switch summary.scope {
        case .codex:
            if hasQuota { return "Official quota + local records" }
            return summary.status == .available
                ? "Official quota: no active limits · local records"
                : "Local records; quota unavailable"
        case .openClaw:
            return "Local OpenClaw records"
        }
    }
}

private struct RuntimeQuotaSummaryItem: Identifiable {
    let id: String
    let title: String
    let value: Double
    let resetsAt: Date?
}

struct RuntimeLogoView: View {
    @Environment(\.colorScheme) private var colorScheme
    let scope: RuntimeScope
    let size: CGFloat

    var body: some View {
        Group {
            if let image = RuntimeLogo.image(for: scope) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
                    .background(WidgetPalette.controlFill(colorScheme))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.22), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(4, size * 0.22), style: .continuous)
                .strokeBorder(WidgetPalette.cardStroke(colorScheme), lineWidth: 0.7)
        )
        .accessibilityHidden(true)
    }

    private var fallbackSystemName: String {
        switch scope {
        case .codex:
            return "terminal"
        case .openClaw:
            return "pawprint.fill"
        }
    }
}

private enum RuntimeLogo {
    static func image(for scope: RuntimeScope) -> NSImage? {
        let name: String
        switch scope {
        case .codex:
            name = "codex-color"
        case .openClaw:
            name = "openclaw-color"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private func runtimeFormatPercent(_ value: Double?) -> String {
    guard let value else { return "--" }
    if value > 0, value < 1 {
        return "<1%"
    }
    return "\(Int(value.rounded()))%"
}

private func runtimeTimeOnly(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}
