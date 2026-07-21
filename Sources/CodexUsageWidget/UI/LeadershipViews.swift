import SwiftUI

struct LeadershipPyramidButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.visualTokens) private var visualTokens
    let snapshot: LeadershipDashboardSnapshot
    let language: WidgetLanguage
    let action: () -> Void

    private var report: LeadershipReport? { snapshot.defaultReport }
    private var today: LeadershipReport? { snapshot.todayReport }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(language.text("AI 领导力", "AI Leadership"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text("28D")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(visualTokens.accent.primary.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(visualTokens.accent.primary.color.opacity(0.12))
                        )
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(report?.score.map(String.init) ?? "--")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(report?.title?.name ?? language.text("记录建立中", "Building history"))
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                        Text(scoreCaption)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                LeadershipPyramidGraphic(currentLevel: report?.title?.level ?? 0)
                    .frame(height: 77)

                HStack(spacing: 4) {
                    LeadershipTodayFact(
                        systemName: "person.3.fill",
                        value: todayAgentValue,
                        label: language.text("Agent", "Agents")
                    )
                    LeadershipTodayFact(
                        systemName: "clock.fill",
                        value: todayHoursValue,
                        label: language.text("AI 工时", "AI hours")
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 201, alignment: .topLeading)
            .cardBackground(cornerRadius: 12, elevated: true)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
        .buttonStyle(.plain)
        .help(language.text("查看 AI 领导力详情", "View AI leadership details"))
    }

    private var scoreCaption: String {
        guard let report else { return language.text("本机事实数据", "Local facts") }
        return language.text(
            "\(report.activeDayCount)/28 活跃日",
            "\(report.activeDayCount)/28 active days"
        )
    }

    private var todayAgentValue: String {
        today?.agentCount.map(String.init) ?? "--"
    }

    private var todayHoursValue: String {
        leadershipHours(today?.aiHours)
    }

    private var accessibilitySummary: String {
        let score = report?.score.map(String.init) ?? language.text("暂无得分", "No score")
        let title = report?.title?.name ?? language.text("记录建立中", "Building history")
        return language.text(
            "AI 领导力，\(score) 分，\(title)，今日领导 \(todayAgentValue) 个 Agent，AI 工时 \(todayHoursValue)",
            "AI leadership, score \(score), \(title), \(todayAgentValue) agents today, \(todayHoursValue) AI hours"
        )
    }
}

private struct LeadershipTodayFact: View {
    @Environment(\.visualTokens) private var visualTokens
    let systemName: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(visualTokens.accent.primary.color)
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(FixedVisualPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(FixedVisualPalette.controlStroke(colorScheme), lineWidth: 0.7)
                )
        )
    }

    @Environment(\.colorScheme) private var colorScheme
}

private struct LeadershipPyramidGraphic: View {
    @Environment(\.visualTokens) private var visualTokens
    let currentLevel: Int

    var body: some View {
        Canvas { context, size in
            let tierCount = 7
            let visualLevel = min(max(currentLevel, 0), tierCount)
            let centerX = size.width / 2 - 3
            let bottomY = size.height - 3
            let baseHalfWidth = max(30, (size.width - 24) / 2)

            for tier in 0..<tierCount {
                let level = tier + 1
                let halfWidth = max(12, baseHalfWidth - CGFloat(tier) * 7)
                let tierBottom = bottomY - CGFloat(tier) * 8.6
                let tierTop = tierBottom - 6.2
                let depth: CGFloat = 4.2
                let earned = level <= visualLevel
                let current = level == visualLevel
                let baseColor = current
                    ? visualTokens.accent.primaryStrong.color
                    : earned
                        ? visualTokens.accent.primary.color.opacity(0.54 + Double(tier) * 0.035)
                        : FixedVisualPalette.surfaceTrack.opacity(0.72)

                var front = Path()
                front.move(to: CGPoint(x: centerX - halfWidth, y: tierTop))
                front.addLine(to: CGPoint(x: centerX + halfWidth, y: tierTop))
                front.addLine(to: CGPoint(x: centerX + halfWidth + depth, y: tierBottom))
                front.addLine(to: CGPoint(x: centerX - halfWidth + depth, y: tierBottom))
                front.closeSubpath()
                context.fill(front, with: .color(baseColor))

                var top = Path()
                top.move(to: CGPoint(x: centerX - halfWidth, y: tierTop))
                top.addLine(to: CGPoint(x: centerX + halfWidth, y: tierTop))
                top.addLine(to: CGPoint(x: centerX + halfWidth + depth, y: tierTop - depth))
                top.addLine(to: CGPoint(x: centerX - halfWidth + depth, y: tierTop - depth))
                top.closeSubpath()
                context.fill(
                    top,
                    with: .linearGradient(
                        Gradient(colors: [
                            earned ? visualTokens.accent.primaryLight.color : FixedVisualPalette.surfaceTrack,
                            baseColor
                        ]),
                        startPoint: CGPoint(x: centerX - halfWidth, y: tierTop - depth),
                        endPoint: CGPoint(x: centerX + halfWidth, y: tierTop)
                    )
                )

                if current {
                    context.stroke(
                        front,
                        with: .color(visualTokens.accent.highlight.color.opacity(0.9)),
                        lineWidth: 1.2
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct LeadershipDashboardPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.visualTokens) private var visualTokens
    let snapshot: LeadershipDashboardSnapshot
    let language: WidgetLanguage
    @State private var period: LeadershipPeriod = .twentyEightDays
    @State private var runtime: LeadershipRuntimeFilter = .all

    private var report: LeadershipReport? {
        snapshot.report(period: period, runtime: runtime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LeadershipPeriodControl(selection: $period, language: language)
                Spacer(minLength: 8)
                LeadershipRuntimeControl(selection: $runtime, language: language)
            }

            if let report {
                HStack(alignment: .top, spacing: 10) {
                    LeadershipScoreCard(report: report, period: period, language: language)
                        .frame(width: 214)
                    LeadershipDimensionCard(report: report, language: language)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 168)

                LeadershipFactStrip(report: report, language: language)

                HStack(alignment: .top, spacing: 10) {
                    LeadershipTimelineCard(report: report, language: language)
                        .frame(maxWidth: .infinity)
                    LeadershipProjectCard(report: report, language: language)
                        .frame(width: 286)
                }
                .frame(height: 164)
            } else {
                LeadershipEmptyState(language: language)
                    .frame(height: 286)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LeadershipPeriodControl: View {
    @Binding var selection: LeadershipPeriod
    let language: WidgetLanguage

    var body: some View {
        LeadershipMiniSegments(
            selection: $selection,
            options: LeadershipPeriod.allCases,
            label: { period in
                switch period {
                case .today: language.text("今日", "Today")
                case .sevenDays: language.text("7 天", "7 days")
                case .twentyEightDays: language.text("28 天", "28 days")
                }
            }
        )
    }
}

private struct LeadershipRuntimeControl: View {
    @Binding var selection: LeadershipRuntimeFilter
    let language: WidgetLanguage

    var body: some View {
        LeadershipMiniSegments(
            selection: $selection,
            options: LeadershipRuntimeFilter.allCases,
            label: { runtime in
                switch runtime {
                case .all: language.text("全部", "All")
                case .codex: "Codex"
                case .claudeCode: "Claude Code"
                }
            }
        )
    }
}

private struct LeadershipMiniSegments<Option: Identifiable & Equatable>: View where Option.ID: Hashable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.visualTokens) private var visualTokens
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 10, weight: selection == option ? .semibold : .medium))
                        .foregroundStyle(selection == option ? Color.white : Color.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == option ? visualTokens.accent.primary.color : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FixedVisualPalette.controlFill(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(FixedVisualPalette.controlStroke(colorScheme), lineWidth: 0.8)
                )
        )
    }
}

private struct LeadershipScoreCard: View {
    @Environment(\.visualTokens) private var visualTokens
    let report: LeadershipReport
    let period: LeadershipPeriod
    let language: WidgetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(report.score.map(String.init) ?? "--")
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/ 100")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Image(systemName: evidenceIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(evidenceColor)
                    .help(evidenceLabel)
            }

            Text(report.title?.name ?? language.text("记录不足", "Insufficient history"))
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)

            Text(scoreExplanation)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(spacing: 5) {
                LeadershipProgressLine(
                    label: language.text("时间成熟度", "Time maturity"),
                    value: report.maturity,
                    color: visualTokens.accent.primary.color
                )
                LeadershipProgressLine(
                    label: language.text("证据可信度", "Evidence confidence"),
                    value: report.evidenceCoverage,
                    color: evidenceColor
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground(cornerRadius: 10, elevated: true)
    }

    private var scoreExplanation: String {
        if let core = report.coreScore {
            return language.text(
                String(format: "Core4 %.1f × M %.0f%% · %d/%d 活跃日", core, report.maturity * 100, report.activeDayCount, period.dayCount),
                String(format: "Core4 %.1f × M %.0f%% · %d/%d active days", core, report.maturity * 100, report.activeDayCount, period.dayCount)
            )
        }
        return language.text("可信证据低于出分门槛", "Evidence is below the scoring threshold")
    }

    private var evidenceLabel: String {
        if report.evidenceCoverage >= 0.9 { return language.text("可信记录", "Verified history") }
        if report.evidenceCoverage >= 0.7 { return language.text("记录有限", "Limited history") }
        return language.text("证据不足", "Insufficient evidence")
    }

    private var evidenceIcon: String {
        report.evidenceCoverage >= 0.9 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var evidenceColor: Color {
        report.evidenceCoverage >= 0.9 ? FixedVisualPalette.statusSuccess : FixedVisualPalette.statusWarning
    }
}

private struct LeadershipProgressLine: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(FixedVisualPalette.surfaceTrack)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(height: 5)
            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 27, alignment: .trailing)
        }
    }
}

private struct LeadershipDimensionCard: View {
    let report: LeadershipReport
    let language: WidgetLanguage

    var body: some View {
        VStack(spacing: 5) {
            ForEach(LeadershipDimensionKind.allCases) { kind in
                LeadershipDimensionRow(
                    dimension: report.dimensions.first { $0.kind == kind },
                    kind: kind,
                    language: language
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardBackground(cornerRadius: 10)
    }
}

private struct LeadershipDimensionRow: View {
    @Environment(\.visualTokens) private var visualTokens
    let dimension: LeadershipDimension?
    let kind: LeadershipDimensionKind
    let language: WidgetLanguage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(visualTokens.data.series[colorIndex].color)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Text(dimension.map { String(format: "%.0f", $0.score) } ?? "--")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FixedVisualPalette.surfaceTrack)
                        Capsule()
                            .fill(visualTokens.data.series[colorIndex].color)
                            .frame(width: geometry.size.width * CGFloat((dimension?.score ?? 0) / 100))
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch kind {
        case .span: language.text("管理半径", "Span")
        case .leverage: language.text("劳动力杠杆", "Leverage")
        case .orchestration: language.text("编排能力", "Orchestration")
        case .autonomy: language.text("自主运行", "Autonomy")
        }
    }

    private var icon: String {
        switch kind {
        case .span: "person.3.fill"
        case .leverage: "clock.fill"
        case .orchestration: "square.stack.3d.up.fill"
        case .autonomy: "bolt.fill"
        }
    }

    private var colorIndex: Int {
        switch kind {
        case .span: 0
        case .leverage: 1
        case .orchestration, .autonomy: 2
        }
    }

    private var summary: String {
        guard let dimension else { return language.text("暂无", "No data") }
        switch kind {
        case .span:
            return language.text(String(format: "%.1f 等效 Agent", dimension.summaryValue), String(format: "%.1f effective agents", dimension.summaryValue))
        case .leverage:
            return language.text(String(format: "日均 %.1fh", dimension.summaryValue), String(format: "%.1fh per day", dimension.summaryValue))
        case .orchestration:
            return language.text(String(format: "委派 %.0f%%", dimension.summaryValue * 100), String(format: "%.0f%% delegated", dimension.summaryValue * 100))
        case .autonomy:
            return language.text(String(format: "自主 %.0f%%", dimension.summaryValue * 100), String(format: "%.0f%% autonomous", dimension.summaryValue * 100))
        }
    }
}

private struct LeadershipFactStrip: View {
    let report: LeadershipReport
    let language: WidgetLanguage

    var body: some View {
        HStack(spacing: 8) {
            LeadershipFactTile(systemName: "person.3.fill", label: language.text("领导 Agent", "Agents"), value: report.agentCount.map(String.init) ?? "--")
            LeadershipFactTile(systemName: "clock.fill", label: language.text("AI 工时", "AI hours"), value: leadershipHours(report.aiHours))
            LeadershipFactTile(systemName: "arrow.up.right.and.arrow.down.left", label: language.text("峰值并发", "Peak concurrency"), value: report.peakConcurrency.map { "\($0)×" } ?? "--")
            LeadershipFactTile(systemName: "bolt.fill", label: language.text("自主工时", "Autonomous"), value: leadershipHours(report.autonomousHours))
        }
    }
}

private struct LeadershipFactTile: View {
    @Environment(\.visualTokens) private var visualTokens
    let systemName: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(visualTokens.accent.primary.color)
                .frame(width: 22, height: 22)
                .background(Circle().fill(visualTokens.accent.primary.color.opacity(0.11)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 45)
        .cardBackground(cornerRadius: 9)
        .accessibilityElement(children: .combine)
    }
}

private struct LeadershipTimelineCard: View {
    @Environment(\.visualTokens) private var visualTokens
    let report: LeadershipReport
    let language: WidgetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(language.text("AI 劳动力时间线", "AI workforce timeline"), systemImage: "chart.bar.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(language.text("柱高 = AI 工时", "Bar = AI hours"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geometry in
                let maximum = max(report.dailyPoints.map(\.aiHours).max() ?? 0, 0.1)
                HStack(alignment: .bottom, spacing: report.dailyPoints.count > 14 ? 2 : 5) {
                    ForEach(report.dailyPoints) { point in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(point.aiHours > 0 ? visualTokens.accent.primary.color : FixedVisualPalette.surfaceTrack)
                                .frame(height: max(2, (geometry.size.height - 20) * CGFloat(point.aiHours / maximum)))
                                .help(timelineHelp(point))
                            if showLabels {
                                Text(dayLabel(point.day))
                                    .font(.system(size: 7, weight: .medium, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground(cornerRadius: 10)
    }

    private var showLabels: Bool { report.dailyPoints.count <= 7 }

    private func timelineHelp(_ point: LeadershipDayPoint) -> String {
        language.text(
            "\(dayLabel(point.day)) · \(leadershipHours(point.aiHours)) · \(point.agentCount) Agent · 峰值 \(point.peakConcurrency)×",
            "\(dayLabel(point.day)) · \(leadershipHours(point.aiHours)) · \(point.agentCount) agents · peak \(point.peakConcurrency)×"
        )
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

private struct LeadershipProjectCard: View {
    @Environment(\.visualTokens) private var visualTokens
    let report: LeadershipReport
    let language: WidgetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(language.text("项目贡献", "Project contribution"), systemImage: "folder.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(report.projectCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            if report.projects.isEmpty {
                Spacer()
                Text(language.text("暂无可信项目记录", "No trusted project history"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(report.projects.prefix(5).enumerated()), id: \.element.id) { index, project in
                    HStack(spacing: 7) {
                        Text("\(index + 1)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(index == 0 ? visualTokens.accent.primary.color : Color.secondary)
                            .frame(width: 14)
                        Text(project.projectName)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(project.agentCount)A")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Text(leadershipHours(project.aiHours))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground(cornerRadius: 10)
    }
}

private struct LeadershipEmptyState: View {
    let language: WidgetLanguage

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(language.text("正在建立 AI 领导力记录", "Building AI leadership history"))
                .font(.system(size: 12, weight: .semibold))
            Text(language.text("仅使用本机可验证的结构化事件，缺失数据不会记为 0。", "Only verifiable local events are used; missing data is never treated as zero."))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private func leadershipHours(_ value: Double?) -> String {
    guard let value else { return "--" }
    if value >= 100 { return String(format: "%.0fh", value) }
    if value >= 10 { return String(format: "%.1fh", value) }
    return String(format: "%.1fh", value)
}
