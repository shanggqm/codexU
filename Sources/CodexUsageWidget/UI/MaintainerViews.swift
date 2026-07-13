import SwiftUI

struct MaintainerPanel: View {
    @ObservedObject var store: MaintainerStore
    let language: WidgetLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            configurationCard
            if store.tasks.isEmpty {
                emptyState
            } else {
                ForEach(store.tasks.prefix(20)) { task in
                    taskCard(task)
                }
            }
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(WidgetPalette.brandPrimary)
                Text(language.text("GitHub 触发器", "GitHub trigger"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("", isOn: $store.configuration.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                labeledField(language.text("仓库", "Repository"), text: $store.configuration.repository, placeholder: "owner/repo")
                labeledField(language.text("触发标签", "Trigger label"), text: $store.configuration.triggerLabel, placeholder: "codex:review")
                    .frame(width: 210)
            }
            labeledField(language.text("本地仓库", "Local repository"), text: $store.configuration.localRepositoryPath, placeholder: "/Users/me/project")

            HStack(spacing: 8) {
                Button(language.text("保存配置", "Save")) { store.saveConfiguration() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button {
                    store.scanNow()
                } label: {
                    Label(language.text("立即扫描", "Scan now"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isSyncing || !store.configuration.isValid)
                if store.isSyncing { ProgressView().controlSize(.small) }
                Spacer()
                Text(store.statusMessage ?? language.text("默认每 60 秒增量检查", "Incremental check every 60 seconds"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(WidgetPalette.controlFill(colorScheme))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(WidgetPalette.controlStroke(colorScheme), lineWidth: 0.8))
                )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.secondary)
            Text(language.text("暂无维护任务", "No maintainer tasks"))
                .font(.system(size: 12, weight: .semibold))
            Text(language.text("给 Issue 或 PR 添加触发标签，然后点击立即扫描。", "Add the trigger label to an issue or PR, then scan."))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func taskCard(_ task: MaintainerTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: task.kind == .pullRequest ? "arrow.triangle.pull" : "smallcircle.filled.circle")
                    .foregroundStyle(statusColor(task.status))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(task.kind.displayName) #\(task.number) · \(task.title)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Text("@\(task.author) · \(localizedStatus(task.status))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if task.status.isBusy { ProgressView().controlSize(.small) }
            }

            if let review = task.review {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(review.verdict.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(statusColor(task.status))
                        Text(review.summary)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(2)
                    }
                    Text(review.markdown)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(12)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(WidgetPalette.controlFill(colorScheme)))
            }

            if let error = task.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetPalette.statusWarning)
                    .textSelection(.enabled)
            }

            HStack(spacing: 7) {
                Button(language.text("GitHub", "GitHub")) { store.openGitHub(task) }
                    .buttonStyle(.bordered).controlSize(.small)
                if task.codexThreadID != nil {
                    Button(language.text("打开 Codex", "Open Codex")) { store.openCodex() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                if task.status == .awaitingApproval {
                    Button(language.text("批准并发布", "Approve & publish")) { store.approveAndPublish(taskID: task.id) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                if task.status == .failed || task.status == .published || task.status == .ignored || task.status == .awaitingApproval {
                    Button(language.text("重新审查", "Review again")) { store.reviewAgain(taskID: task.id) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                if task.status == .published, task.publishedCommentURL != nil {
                    Button(language.text("查看评论", "View comment")) { store.openPublishedComment(task) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Spacer()
                if !task.status.isBusy && task.status != .published && task.status != .ignored {
                    Button(language.text("忽略", "Ignore")) { store.ignore(taskID: task.id) }
                        .buttonStyle(.plain).controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(WidgetPalette.cardFill(colorScheme))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(WidgetPalette.cardStroke(colorScheme), lineWidth: 0.8))
    }

    private func localizedStatus(_ status: MaintainerTaskStatus) -> String {
        switch status {
        case .discovered: return language.text("等待审查", "Queued")
        case .reviewing: return language.text("Codex 审查中", "Reviewing")
        case .awaitingApproval: return language.text("等待批准", "Awaiting approval")
        case .publishing: return language.text("发布中", "Publishing")
        case .published: return language.text("已发布", "Published")
        case .failed: return language.text("失败", "Failed")
        case .ignored: return language.text("已忽略", "Ignored")
        }
    }

    private func statusColor(_ status: MaintainerTaskStatus) -> Color {
        switch status {
        case .awaitingApproval: return WidgetPalette.statusWarning
        case .failed: return WidgetPalette.statusDanger
        case .published: return WidgetPalette.statusSuccess
        case .reviewing, .publishing: return WidgetPalette.statusInfo
        default: return WidgetPalette.brandSecondary
        }
    }
}
