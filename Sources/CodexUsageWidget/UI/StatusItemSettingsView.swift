import SwiftUI

private let statusItemSettingsAccessoryWidth: CGFloat = 220
private let statusItemSettingsControlHeight: CGFloat = 30
private let statusItemSettingsCornerRadius: CGFloat = 8

struct StatusItemSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @State private var preferenceError: StatusItemPreferenceError?

    private var language: WidgetLanguage { settings.language }
    private var preferences: StatusItemPreferences { settings.statusItemPreferences }

    var body: some View {
        StatusItemPreviewRow(
            settings: settings,
            store: store
        )

        SettingsPickerRow(
            title: language.text("展示模式", "Display mode"),
            detail: language.text("简约最省空间，经典用数字环，丰富显示完整标签", "Minimal saves space, Classic uses number rings, Rich shows full labels")
        ) {
            SettingsSegmentedControl(
                selection: displayModeBinding,
                options: [
                    SettingsSegmentOption(value: .minimal, title: language.text("简约", "Minimal")),
                    SettingsSegmentOption(value: .classic, title: language.text("经典", "Classic")),
                    SettingsSegmentOption(value: .rich, title: language.text("丰富", "Rich"))
                ],
                width: statusItemSettingsAccessoryWidth
            )
        }

        SettingsPickerRow(
            title: language.text("额度口径", "Quota direction"),
            detail: language.text("进度环、进度条和数字始终使用同一口径", "Rings, bars, and numbers always use the same direction")
        ) {
            SettingsSegmentedControl(
                selection: quotaModeBinding,
                options: [
                    SettingsSegmentOption(value: .used, title: language.text("已用量", "Used")),
                    SettingsSegmentOption(value: .remaining, title: language.text("剩余量", "Remaining"))
                ],
                width: statusItemSettingsAccessoryWidth
            )
        }

        SettingsPickerRow(
            title: language.text("显示内容", "Visible metrics"),
            detail: metricsDetail
        ) {
            StatusItemMetricMultiSelectControl(
                selectedMetrics: preferences.visibleMetrics,
                language: language,
                onToggle: toggleMetric
            )
            .help(localizedPreferenceError ?? language.text("至少保留一个指标", "Keep at least one metric"))
        }

        SettingsToggleRow(
            title: language.text("重置倒计时", "Reset countdown"),
            detail: language.text("仅在丰富模式中附加到 5h/7d 额度行", "Shown beside 5h/7d only in Rich mode")
        ) {
            SettingsSwitchToggle(
                isOn: resetCountdownBinding,
                isDisabled: preferences.displayMode != .rich || !preferences.hasVisibleQuota,
                help: preferences.displayMode == .rich
                    ? nil
                    : language.text("切换到丰富模式后显示", "Available in Rich mode")
            )
        }

        SettingsBaseRow(
            title: language.text("默认设置", "Defaults"),
            detail: language.text("恢复丰富、已用量、5h + 7d 和重置倒计时", "Restore Rich, Used, 5h + 7d, and reset countdown")
        ) {
            Button {
                settings.resetStatusItemPreferences()
                preferenceError = nil
            } label: {
                Label(language.text("恢复默认", "Restore"), systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.brandPrimary)
                    .frame(width: statusItemSettingsAccessoryWidth, height: statusItemSettingsControlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: statusItemSettingsCornerRadius, style: .continuous)
                            .fill(WidgetPalette.brandPrimary.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var displayModeBinding: Binding<StatusItemDisplayMode> {
        Binding(
            get: { preferences.displayMode },
            set: { mode in
                updatePreferences { $0.displayMode = mode }
            }
        )
    }

    private var quotaModeBinding: Binding<QuotaDisplayMode> {
        Binding(
            get: { preferences.quotaMode },
            set: { mode in
                updatePreferences { $0.quotaMode = mode }
            }
        )
    }

    private var resetCountdownBinding: Binding<Bool> {
        Binding(
            get: { preferences.showsResetCountdown },
            set: { isOn in
                updatePreferences { $0.showsResetCountdown = isOn }
            }
        )
    }

    private var metricsDetail: String {
        if preferences.displayMode == .minimal,
           preferences.visibleMetrics.contains(.todayTokens) {
            return language.text(
                "简约模式只绘制额度环；今日 token 仍保留在提示中",
                "Minimal draws quota rings only; today tokens remain in the tooltip"
            )
        }
        return localizedPreferenceError
            ?? language.text(
                "已确认不可用的额度会自动隐藏，恢复后重新显示",
                "Confirmed unavailable quotas hide and return automatically"
            )
    }

    private var localizedPreferenceError: String? {
        guard let preferenceError else { return nil }
        switch preferenceError {
        case .requiresVisibleMetric:
            return language.text("至少需要保留一个指标", "At least one metric must remain visible")
        case .minimalRequiresQuotaMetric:
            return language.text("简约模式至少需要一个额度指标", "Minimal mode needs at least one quota metric")
        }
    }

    private func toggleMetric(_ metric: StatusItemMetric) {
        updatePreferences { preferences in
            if preferences.visibleMetrics.contains(metric) {
                preferences.visibleMetrics.remove(metric)
            } else {
                preferences.visibleMetrics.insert(metric)
            }
        }
    }

    private func updatePreferences(_ mutation: (inout StatusItemPreferences) -> Void) {
        switch settings.updateStatusItemPreferences(mutation) {
        case .success:
            preferenceError = nil
        case let .failure(error):
            preferenceError = error
        }
    }
}

private struct StatusItemPreviewRow: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    private let builder = StatusItemPresentationBuilder()
    private let renderer = StatusItemRenderer()

    var body: some View {
        SettingsBaseRow(
            title: settings.language.text("实时预览", "Live preview"),
            detail: settings.language.text("与菜单栏使用同一套绘制器", "Uses the same renderer as the menu bar")
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: statusItemSettingsCornerRadius, style: .continuous)
                    .fill(previewBackground)
                Image(nsImage: renderer.render(presentation, appearance: previewAppearance))
                    .interpolation(.high)
                    .frame(
                        width: presentation.imageSize.width,
                        height: presentation.imageSize.height
                    )
            }
            .frame(width: statusItemSettingsAccessoryWidth, height: 38)
            .accessibilityLabel("codexU")
            .accessibilityValue(presentation.accessibilityValue)
        }
    }

    private var source: StatusItemSourceSnapshot {
        if let summary = store.runtimeSnapshot(for: store.selectedRuntimeScope)?.summary {
            return StatusItemSourceSnapshot(summary: summary)
        }
        return .unavailable(runtime: store.selectedRuntimeScope)
    }

    private var presentation: StatusItemPresentation {
        builder.build(
            source: source,
            preferences: settings.statusItemPreferences,
            language: settings.language
        )
    }

    private var previewBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.075)
    }

    private var previewAppearance: NSAppearance? {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}

private struct StatusItemMetricMultiSelectControl: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedMetrics: Set<StatusItemMetric>
    let language: WidgetLanguage
    let onToggle: (StatusItemMetric) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(StatusItemMetric.allCases.enumerated()), id: \.element.id) { index, metric in
                Button {
                    onToggle(metric)
                } label: {
                    Text(label(for: metric))
                        .font(.system(size: 11, weight: isSelected(metric) ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected(metric) ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: statusItemSettingsControlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: statusItemSettingsCornerRadius, style: .continuous)
                                .fill(isSelected(metric) ? selectionColor(for: metric) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: metric))
                .accessibilityValue(
                    isSelected(metric)
                        ? language.text("已选择", "Selected")
                        : language.text("未选择", "Not selected")
                )

                if index < StatusItemMetric.allCases.count - 1 {
                    Rectangle()
                        .fill(WidgetPalette.controlStroke(colorScheme))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 1)
                }
            }
        }
        .padding(3)
        .frame(width: statusItemSettingsAccessoryWidth, height: statusItemSettingsControlHeight + 6)
        .background(
            RoundedRectangle(cornerRadius: statusItemSettingsCornerRadius, style: .continuous)
                .fill(WidgetPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: statusItemSettingsCornerRadius, style: .continuous)
                        .strokeBorder(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: statusItemSettingsCornerRadius, style: .continuous))
    }

    private func isSelected(_ metric: StatusItemMetric) -> Bool {
        selectedMetrics.contains(metric)
    }

    private func label(for metric: StatusItemMetric) -> String {
        switch metric {
        case .fiveHourQuota:
            return "5h"
        case .sevenDayQuota:
            return "7d"
        case .todayTokens:
            return language.text("今日", "Today")
        }
    }

    private func selectionColor(for metric: StatusItemMetric) -> Color {
        switch metric {
        case .fiveHourQuota:
            return WidgetPalette.brandPrimary
        case .sevenDayQuota:
            return WidgetPalette.brandSecondary
        case .todayTokens:
            return WidgetPalette.brandPrimaryStrong
        }
    }
}
