import SwiftUI

struct CPAQuotaAccountsView: View {
    let accounts: [CPAQuotaAccount]
    let isStale: Bool
    let language: WidgetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.brandPrimary)
                Text(language.text("CPA 账号额度", "CPA account quotas"))
                    .font(.system(size: 11, weight: .semibold))
                Text(
                    isStale
                        ? language.text("上次成功快照", "Last successful snapshot")
                        : language.text("主环采用最低额度账号", "Main rings use the lowest account")
                )
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(accounts.filter { $0.status == .available }.count)/\(accounts.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(accounts) { account in
                        CPAQuotaAccountCard(account: account, isStale: isStale, language: language)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CPAQuotaAccountCard: View {
    let account: CPAQuotaAccount
    let isStale: Bool
    let language: WidgetLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(account.displayName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let planType = account.planType, !planType.isEmpty {
                    Text(planType.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if account.status == .available {
                if account.fiveHourQuota != nil {
                    CPAQuotaCompactBar(
                        label: "5h",
                        quota: account.fiveHourQuota,
                        colors: [WidgetPalette.brandPrimaryLight, WidgetPalette.brandPrimary],
                        language: language
                    )
                }
                if account.sevenDayQuota != nil {
                    CPAQuotaCompactBar(
                        label: "7d",
                        quota: account.sevenDayQuota,
                        colors: [WidgetPalette.brandHighlight, WidgetPalette.brandSecondary],
                        language: language
                    )
                }
                if account.monthlyQuota != nil {
                    CPAQuotaCompactBar(
                        label: language.text("月", "30d"),
                        quota: account.monthlyQuota,
                        colors: [WidgetPalette.brandSecondary, WidgetPalette.brandSecondaryStrong],
                        language: language
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WidgetPalette.statusWarning)
                    Text(localizedMessage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            }
        }
        .padding(10)
        .frame(
            width: 220,
            height: cardHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WidgetPalette.cardFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(WidgetPalette.cardStroke(colorScheme), lineWidth: 0.8)
                )
        )
        .accessibilityElement(children: .combine)
    }

    private var localizedMessage: String {
        guard !language.isChinese else { return account.message ?? "额度暂不可用" }
        guard let message = account.message else { return "Quota unavailable" }
        if message.contains("超时") { return "Quota request timed out" }
        if message.contains("管理 Key") { return "Management key rejected" }
        if message.contains("无法识别") { return "Unrecognized quota response" }
        if message.contains("连接失败") { return "Connection failed" }
        if message.contains("HTTP") { return message }
        return "Quota unavailable"
    }

    private var statusColor: Color {
        if isStale || account.status == .unavailable {
            return WidgetPalette.statusWarning
        }
        return WidgetPalette.statusSuccess
    }

    private var cardHeight: CGFloat {
        guard account.status == .available else { return 102 }
        let quotaCount = [
            account.fiveHourQuota,
            account.sevenDayQuota,
            account.monthlyQuota
        ].compactMap { $0 }.count
        switch quotaCount {
        case 0, 1:
            return 82
        case 2:
            return 102
        default:
            return 128
        }
    }
}

private struct CPAQuotaCompactBar: View {
    let label: String
    let quota: RateWindow?
    let colors: [Color]
    let language: WidgetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .frame(width: 18, alignment: .leading)
                Text(percentText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 3)
                Text(resetText)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(WidgetPalette.surfaceTrack)
                    if let quota {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * quota.remainingPercent / 100)
                    }
                }
            }
            .frame(height: 5)
        }
    }

    private var percentText: String {
        quota.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "--"
    }

    private var resetText: String {
        guard let resetsAt = quota?.resetsAt else {
            return language.text("暂无重置时间", "No reset time")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: resetsAt)
    }
}
