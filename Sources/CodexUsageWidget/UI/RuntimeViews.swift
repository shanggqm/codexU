import SwiftUI

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
                    .frame(minWidth: scope == .claudeCode ? 112 : 78, minHeight: titlebarControlHeight)
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
        case .claudeCode:
            return language.text("Claude Code", "Claude Code")
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
                    quotaColumn(
                        title: language.text("5小时剩余", "5h left"),
                        value: summary.fiveHourRemainingPercent,
                        resetsAt: summary.fiveHourResetsAt
                    )
                    quotaColumn(
                        title: language.text("7日剩余", "7d left"),
                        value: summary.sevenDayRemainingPercent,
                        resetsAt: summary.sevenDayResetsAt
                    )
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

    private func quotaColumn(title: String, value: Double?, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(runtimeFormatPercent(value))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(WidgetPalette.surfaceTrack)
                    Capsule(style: .continuous)
                        .fill(statusTint.opacity(0.72))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, value ?? 0)) / 100))
                }
            }
            .frame(height: 4)
            Text(resetsAt.map { runtimeTimeOnly($0) } ?? "--")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 86, alignment: .leading)
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
        if language.isChinese {
            switch summary.scope {
            case .codex:
                return summary.fiveHourRemainingPercent == nil ? "本机统计；额度暂不可用" : "官方额度 + 本机统计"
            case .claudeCode:
                return summary.fiveHourRemainingPercent == nil ? "本机统计；额度需 active snapshot" : "active snapshot + 本机统计"
            }
        }
        switch summary.scope {
        case .codex:
            return summary.fiveHourRemainingPercent == nil ? "Local records; quota unavailable" : "Official quota + local records"
        case .claudeCode:
            return summary.fiveHourRemainingPercent == nil ? "Local records; quota needs active snapshot" : "Active snapshot + local records"
        }
    }
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
        case .claudeCode:
            return "curlybraces"
        }
    }
}

private enum RuntimeLogo {
    static func image(for scope: RuntimeScope) -> NSImage? {
        let name: String
        switch scope {
        case .codex:
            name = "codex-color"
        case .claudeCode:
            name = "claudecode-color"
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
