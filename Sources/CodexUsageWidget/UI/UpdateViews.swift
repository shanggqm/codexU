import SwiftUI

private let updateControlCornerRadius: CGFloat = 8

struct AppUpdateFooterButton: View {
    @ObservedObject var updateStore: AppUpdateStore
    let language: WidgetLanguage

    var body: some View {
        if updateStore.result.status == .updateAvailable, let version = updateStore.result.latestVersionLabel {
            Button {
                updateStore.openPreferredUpdateURL()
            } label: {
                Label(language.text("新版 \(version)", "Update \(version)"), systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FixedVisualPalette.statusInfo)
            .help(language.text("下载新版 codexU", "Download the latest codexU release"))
        }
    }
}

struct AppUpdateMenuRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var updateStore: AppUpdateStore
    let language: WidgetLanguage

    var body: some View {
        Button {
            if updateStore.result.status == .updateAvailable {
                updateStore.openPreferredUpdateURL()
            } else {
                updateStore.checkNow()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(statusDetail)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 8)
                Image(systemName: trailingIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FixedVisualPalette.controlFill(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(FixedVisualPalette.controlStroke(colorScheme), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(updateStore.isChecking)
        .help(statusDetail)
    }

    private var statusTitle: String {
        switch updateStore.result.status {
        case .updateAvailable:
            return language.text("发现新版本", "Update available")
        case .checking:
            return language.text("正在检查更新", "Checking for updates")
        case .upToDate:
            return language.text("已是最新版本", "Up to date")
        case .failed:
            return language.text("更新检查失败", "Update check failed")
        case .disabled:
            return language.text("自动检查已关闭", "Auto-check disabled")
        case .idle:
            return language.text("检查更新", "Check for updates")
        }
    }

    private var statusDetail: String {
        switch updateStore.result.status {
        case .updateAvailable:
            let version = updateStore.result.latestVersionLabel ?? "--"
            return language.text("可下载 \(version)", "\(version) is ready")
        case .checking:
            return language.text("正在读取 GitHub Release", "Reading GitHub Releases")
        case .upToDate:
            return language.text("当前版本 \(updateStore.result.currentVersion)", "Current \(updateStore.result.currentVersion)")
        case .failed:
            return language.text("稍后可在设置中重试", "Retry from Settings later")
        case .disabled:
            return language.text("点击可手动检查", "Click to check manually")
        case .idle:
            return language.text("从 GitHub Release 获取版本", "Read version from GitHub Releases")
        }
    }

    private var statusIcon: String {
        switch updateStore.result.status {
        case .updateAvailable:
            return "arrow.down.circle.fill"
        case .checking:
            return "hourglass"
        case .upToDate:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .disabled:
            return "pause.circle.fill"
        case .idle:
            return "arrow.clockwise.circle"
        }
    }

    private var trailingIcon: String {
        updateStore.result.status == .updateAvailable ? "arrow.up.right" : "arrow.clockwise"
    }

    private var statusColor: Color {
        switch updateStore.result.status {
        case .updateAvailable, .checking:
            return FixedVisualPalette.statusInfo
        case .upToDate:
            return FixedVisualPalette.statusSuccess
        case .failed:
            return FixedVisualPalette.statusWarning
        case .disabled, .idle:
            return FixedVisualPalette.statusNeutral
        }
    }
}

struct AppUpdateSettingsRows: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateStore: AppUpdateStore
    let language: WidgetLanguage

    var body: some View {
        SettingsToggleRow(
            title: language.text("自动检查更新", "Check automatically"),
            detail: language.text("每天最多读取一次 GitHub Release，包含 beta 版本", "Reads GitHub Releases at most once per day, including beta releases")
        ) {
            SettingsSwitchToggle(isOn: $settings.automaticUpdateChecksEnabled)
        }

        SettingsBaseRow(
            title: language.text("更新检查", "Update check"),
            detail: settingsStatusDetail
        ) {
            HStack(spacing: 8) {
                UpdateIconButton(
                    systemName: updateStore.isChecking ? "hourglass" : "arrow.clockwise",
                    help: language.text("检查更新", "Check for updates"),
                    isDisabled: updateStore.isChecking
                ) {
                    updateStore.checkNow()
                }

                if updateStore.result.status == .updateAvailable {
                    UpdateIconButton(
                        systemName: "arrow.down.circle.fill",
                        help: language.text("下载新版", "Download update"),
                        tint: FixedVisualPalette.statusInfo
                    ) {
                        updateStore.openPreferredUpdateURL()
                    }

                    UpdateIconButton(
                        systemName: "eye.slash",
                        help: language.text("忽略此版本", "Skip this version")
                    ) {
                        updateStore.skipCurrentAvailableVersion()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var settingsStatusDetail: String {
        switch updateStore.result.status {
        case .updateAvailable:
            let version = updateStore.result.latestVersionLabel ?? "--"
            let asset = updateStore.result.preferredAsset == nil
                ? language.text("未找到匹配架构安装包，将打开 Release 页面", "No matching DMG; opens release page")
                : language.text("已匹配当前 Mac 的 DMG", "Matched a DMG for this Mac")
            return language.text("发现 \(version) · \(asset)", "\(version) available · \(asset)")
        case .checking:
            return language.text("正在读取 GitHub Release", "Reading GitHub Releases")
        case .upToDate:
            return language.text("当前版本 \(updateStore.result.currentVersion) 已是最新", "Current \(updateStore.result.currentVersion) is up to date")
        case .failed:
            return updateStore.result.errorMessage ?? language.text("暂时无法检查更新", "Unable to check right now")
        case .disabled:
            return language.text("自动检查已关闭，仍可手动检查", "Automatic checks are off; manual checks still work")
        case .idle:
            return language.text("默认接收 beta 版本", "Beta releases are included")
        }
    }
}

private struct UpdateIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    let systemName: String
    let help: String
    var tint: Color?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: updateControlCornerRadius, style: .continuous)
                        .fill(isHovering ? FixedVisualPalette.controlSelectedFill(colorScheme) : FixedVisualPalette.controlFill(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: updateControlCornerRadius, style: .continuous)
                                .strokeBorder(FixedVisualPalette.controlStroke(colorScheme), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var foregroundColor: Color {
        if isDisabled {
            return Color.secondary.opacity(0.55)
        }
        return tint ?? Color.secondary
    }
}
