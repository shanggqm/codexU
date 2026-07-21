import SwiftUI

struct WebDAVSyncSettingsView: View {
    @ObservedObject var store: WebDAVSyncStore
    let language: WidgetLanguage
    @Environment(\.visualTokens) private var visualTokens

    var body: some View {
        Group {
            SettingsPickerRow(
                title: language.text("服务器地址", "Server address"),
                detail: language.text("必须使用HTTPS，例如https://dav.example.com/", "HTTPS is required, for example https://dav.example.com/")
            ) {
                TextField("https://", text: $store.serverAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(language.text("WebDAV服务器地址", "WebDAV server address"))
            }

            SettingsPickerRow(
                title: language.text("账户", "Username"),
                detail: language.text("WebDAV登录账户", "WebDAV sign-in username")
            ) {
                TextField("", text: $store.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(language.text("WebDAV账户", "WebDAV username"))
            }

            SettingsPickerRow(
                title: language.text("密码", "Password"),
                detail: language.text("仅保存在本机macOS钥匙串", "Stored only in the local macOS Keychain")
            ) {
                SecureField(language.text("应用密码", "App password"), text: $store.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .privacySensitive()
                    .accessibilityLabel(language.text("WebDAV密码", "WebDAV password"))
            }

            SettingsPickerRow(
                title: language.text("远程目录", "Remote directory"),
                detail: language.text("默认codexu-sync", "Default: codexu-sync")
            ) {
                TextField("codexu-sync", text: $store.remoteDirectory)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }

            SettingsPickerRow(
                title: language.text("配置名", "Profile"),
                detail: language.text("用于区分多套配置，默认default", "Separates configuration sets; default: default")
            ) {
                TextField("default", text: $store.profileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }

            SettingsToggleRow(
                title: language.text("自动同步", "Automatic sync"),
                detail: language.text("本地设置变更2秒后自动上传", "Uploads 2 seconds after local settings change")
            ) {
                SettingsSwitchToggle(isOn: $store.automaticSyncEnabled)
            }

            SettingsValueRow(
                title: language.text("同步内容", "Included settings"),
                detail: language.text("不包含数据库、线程、日志、Skill和快捷键", "Excludes databases, threads, logs, skills, and shortcuts"),
                value: language.text("界面与显示", "Interface & display")
            )

            statusRow
            actionRow
        }
    }

    private var statusRow: some View {
        SettingsBaseRow(
            title: language.text("同步状态", "Sync status"),
            detail: lastSyncText
        ) {
            HStack(spacing: 7) {
                if store.phase.isWorking {
                    ProgressView()
                        .controlSize(.small)
                    Text(language.text("同步中", "Syncing"))
                } else if let message = store.phase.message(language: language) {
                    Image(systemName: phaseIcon)
                        .foregroundStyle(phaseColor)
                    Text(message)
                        .lineLimit(2)
                } else {
                    Text(language.text("尚未同步", "Not synced"))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                store.testConnection()
            } label: {
                Label(language.text("测试", "Test"), systemImage: "link")
            }

            Button {
                store.saveConnectionConfiguration()
            } label: {
                Label(language.text("保存", "Save"), systemImage: "key")
            }

            Spacer(minLength: 4)

            Button {
                store.downloadConfiguration()
            } label: {
                Label(language.text("下载", "Download"), systemImage: "arrow.down.circle")
            }

            Button {
                store.uploadConfiguration()
            } label: {
                Label(language.text("上传", "Upload"), systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(visualTokens.accent.primary.color)
        }
        .controlSize(.small)
        .disabled(store.phase.isWorking)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var lastSyncText: String {
        guard let date = store.lastSyncAt else {
            return language.text("没有同步记录", "No sync history")
        }
        return language.text("上次成功：\(Self.dateFormatter.string(from: date))", "Last success: \(Self.dateFormatter.string(from: date))")
    }

    private var phaseIcon: String {
        if case .failure = store.phase { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var phaseColor: Color {
        if case .failure = store.phase { return FixedVisualPalette.statusDanger }
        return FixedVisualPalette.statusSuccess
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
