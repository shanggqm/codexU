import AppKit
import SwiftUI

struct LeadershipPreviewFixture: Equatable {
    let level: Int

    private static let scores = [10, 27, 42, 57, 72, 86, 96, 100]
    private static let peaks = [1, 2, 4, 6, 9, 14, 21, 32]
    private static let agents = [1, 2, 4, 6, 10, 16, 24, 36]
    private static let hours = [0.8, 2.1, 4.6, 8.2, 14.8, 28.6, 46.0, 72.0]

    private var index: Int { min(max(level, 1), 8) - 1 }
    var score: Int { Self.scores[index] }
    var title: LeadershipTitle { LeadershipScoreModel.title(for: score) }
    var peakConcurrency: Int { Self.peaks[index] }
    var agentCount: Int { Self.agents[index] }
    var aiHours: Double { Self.hours[index] }
}

struct LeadershipCommandRadiusButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.visualTokens) private var visualTokens
    let snapshot: LeadershipDashboardSnapshot
    let previewLevel: Int?
    let language: WidgetLanguage
    let action: () -> Void
    @State private var isHovering = false

    private var report: LeadershipReport? { snapshot.defaultReport }
    private var today: LeadershipReport? { snapshot.todayReport }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    LeadershipCommandRadiusGraphic(
                        level: displayTitle?.level ?? 0,
                        peakConcurrency: displayPeakConcurrency,
                        highlighted: isHovering
                    )

                    VStack(spacing: -1) {
                        Text(displayScore.map(String.init) ?? "--")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        LeadershipBadgeLockup(
                            title: displayTitle,
                            emptyTitle: language.text("记录建立中", "Building history"),
                            imageSize: 58,
                            plaqueWidth: 95
                        )
                    }
                    .offset(y: 4)

                    VStack {
                        HStack(alignment: .center, spacing: 4) {
                            Text(language.text("AI 领导力", "AI Leadership"))
                                .font(.system(size: 9, weight: .semibold))
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
                        Spacer()
                        HStack {
                            Spacer()
                            if displayPeakConcurrency > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.right.and.arrow.down.left")
                                        .font(.system(size: 6.5, weight: .bold))
                                    Text(language.text("峰值 \(displayPeakConcurrency)", "Peak \(displayPeakConcurrency)"))
                                }
                                    .font(.system(size: 7, weight: .bold, design: .rounded))
                                    .foregroundStyle(visualTokens.accent.primaryStrong.color)
                                    .padding(.horizontal, 5)
                                    .frame(height: 16)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(visualTokens.accent.primary.color.opacity(0.14))
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .strokeBorder(visualTokens.accent.primary.color.opacity(0.28), lineWidth: 0.7)
                                            )
                                    )
                                    .help(language.text("滚动 28 天的真实峰值并发；轨道最多绘制 8 个节点", "Actual peak concurrency over 28 days; the orbit draws at most 8 nodes"))
                            }
                        }
                    }
                }
                .frame(width: 145, height: 145)

                HStack(spacing: 4) {
                    OverviewFactTile(
                        systemName: "person.3.fill",
                        value: todayAgentValue,
                        label: language.text("Agent", "Agents")
                    )
                    OverviewFactTile(
                        systemName: "clock.fill",
                        value: todayHoursValue,
                        label: language.text("AI 工时", "AI hours")
                    )
                }
                .frame(width: 154)
            }
            .frame(width: 154, alignment: .top)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
        .help(language.text("查看 AI 领导力详情；轨道节点表示滚动 28 天峰值并发", "View AI leadership details; orbit nodes represent 28-day peak concurrency"))
    }

    private var preview: LeadershipPreviewFixture? {
        previewLevel.map(LeadershipPreviewFixture.init(level:))
    }

    private var displayScore: Int? { preview?.score ?? report?.score }
    private var displayTitle: LeadershipTitle? { preview?.title ?? report?.title }
    private var displayPeakConcurrency: Int { preview?.peakConcurrency ?? report?.peakConcurrency ?? 0 }

    private var todayAgentValue: String {
        preview.map { String($0.agentCount) } ?? today?.agentCount.map(String.init) ?? "--"
    }

    private var todayHoursValue: String {
        leadershipHours(preview?.aiHours ?? today?.aiHours)
    }

    private var accessibilitySummary: String {
        let score = displayScore.map(String.init) ?? language.text("暂无得分", "No score")
        let title = displayTitle?.name ?? language.text("记录建立中", "Building history")
        return language.text(
            "AI 领导力，\(score) 分，\(title)，今日领导 \(todayAgentValue) 个 Agent，AI 工时 \(todayHoursValue)",
            "AI leadership, score \(score), \(title), \(todayAgentValue) agents today, \(todayHoursValue) AI hours"
        )
    }
}

struct OverviewFactTile: View {
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
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

private struct LeadershipCommandRadiusGraphic: View {
    @Environment(\.visualTokens) private var visualTokens
    static let maximumVisibleNodes = 8

    let level: Int
    let peakConcurrency: Int
    let highlighted: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 4.5)
            let allRadii: [CGFloat] = [30, 46, 62]
            let radii = Array(allRadii[0..<ringCount])

            for (index, radius) in radii.enumerated() {
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let strength = Double(index + 1) / Double(max(radii.count, 1))
                let glowOpacity = 0.055 + strength * 0.045 + (highlighted ? 0.025 : 0)
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(visualTokens.accent.primary.color.opacity(glowOpacity)),
                    lineWidth: 7 + CGFloat(index) * 1.5
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(visualTokens.accent.primaryLight.color.opacity(0.13 + strength * 0.08)),
                    lineWidth: 3.6 + CGFloat(index) * 0.7
                )
                let dash: [CGFloat]
                switch index {
                case 0: dash = []
                case 1: dash = [5, 3]
                default: dash = [8, 3, 2, 3]
                }
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(visualTokens.accent.primaryStrong.color.opacity(0.50 + strength * 0.22 + (highlighted ? 0.10 : 0))),
                    style: StrokeStyle(
                        lineWidth: 1.4 + CGFloat(index) * 0.45,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dash
                    )
                )
            }

            let visibleNodeCount = min(max(peakConcurrency, 0), Self.maximumVisibleNodes)
            for index in 0..<visibleNodeCount {
                let ringIndex = index % max(ringCount, 1)
                let nodesOnRing = (visibleNodeCount + ringCount - 1 - ringIndex) / ringCount
                let positionOnRing = index / max(ringCount, 1)
                let phase = -Double.pi / 2 + Double(ringIndex) * 0.54
                let angle = phase + Double(positionOnRing) / Double(max(nodesOnRing, 1)) * Double.pi * 2
                let radius = radii[ringIndex]
                let point = CGPoint(
                    x: center.x + radius * CGFloat(cos(angle)),
                    y: center.y + radius * CGFloat(sin(angle))
                )
                let nodeSize: CGFloat = ringIndex == radii.count - 1 ? 8 : 7
                let nodeRect = CGRect(
                    x: point.x - nodeSize / 2,
                    y: point.y - nodeSize / 2,
                    width: nodeSize,
                    height: nodeSize
                )
                context.fill(
                    Path(ellipseIn: nodeRect.insetBy(dx: -5, dy: -5)),
                    with: .color(visualTokens.accent.primary.color.opacity(highlighted ? 0.18 : 0.12))
                )
                context.fill(Path(ellipseIn: nodeRect), with: .color(visualTokens.accent.primaryStrong.color))
                context.stroke(
                    Path(ellipseIn: nodeRect.insetBy(dx: -1.8, dy: -1.8)),
                    with: .color(visualTokens.accent.primaryLight.color.opacity(0.72)),
                    lineWidth: 1.2
                )
            }
        }
        .opacity(highlighted ? 1 : 0.96)
        .accessibilityHidden(true)
    }

    private var ringCount: Int {
        switch level {
        case ...1: 1
        case 2...4: 2
        default: 3
        }
    }
}

private struct LeadershipBadgeLockup: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.visualTokens) private var visualTokens
    let title: LeadershipTitle?
    let emptyTitle: String
    let imageSize: CGFloat
    let plaqueWidth: CGFloat

    var body: some View {
        VStack(spacing: -5) {
            LeadershipBadgeImage(level: title?.level ?? 0)
                .frame(width: imageSize, height: imageSize)
                .shadow(color: visualTokens.accent.primary.color.opacity(0.18), radius: 5, y: 2)

            HStack(spacing: 3) {
                if let title {
                    Text("L\(min(title.level, 7))")
                        .foregroundStyle(visualTokens.accent.primaryStrong.color)
                }
                Text(title?.name ?? emptyTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .frame(width: plaqueWidth, height: 18)
            .background(
                Capsule(style: .continuous)
                    .fill(FixedVisualPalette.controlFill(colorScheme))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(visualTokens.accent.primary.color.opacity(0.38), lineWidth: 0.8)
                    )
            )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LeadershipBadgeImage: View {
    let level: Int

    var body: some View {
        Group {
            if let image = LeadershipBadgeAssets.image(for: level) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: "circle.hexagongrid.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tertiary)
                    .padding(7)
            }
        }
        .accessibilityHidden(true)
    }
}

private enum LeadershipBadgeAssets {
    private static let cache = NSCache<NSNumber, NSImage>()

    static func image(for level: Int) -> NSImage? {
        guard level > 0 else { return nil }
        let assetLevel = min(max(level, 1), 7)
        let key = NSNumber(value: assetLevel)
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = Bundle.main.url(
            forResource: "leadership-badge-l\(assetLevel)",
            withExtension: "png",
            subdirectory: "LeadershipBadges"
        ), let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct LeadershipDashboardPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.visualTokens) private var visualTokens
    let snapshot: LeadershipDashboardSnapshot
    let language: WidgetLanguage
    @Binding var previewLevel: Int?
    @State private var period: LeadershipPeriod = .twentyEightDays

    private var report: LeadershipReport? {
        snapshot.report(period: period)
    }

    private var preview: LeadershipPreviewFixture? {
        previewLevel.map(LeadershipPreviewFixture.init(level:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LeadershipRankProgressHeader(
                score: preview?.score ?? report?.score,
                title: preview?.title ?? report?.title,
                isPreviewing: preview != nil,
                language: language
            )

            HStack(spacing: 10) {
                LeadershipPeriodControl(selection: $period, language: language)
                Spacer(minLength: 10)
                LeadershipPreviewMenu(selection: $previewLevel, language: language)
            }

            if let report {
                HStack(alignment: .top, spacing: 10) {
                    LeadershipScoreCard(report: report, period: period, preview: preview, language: language)
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

private struct LeadershipRankProgressHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.visualTokens) private var visualTokens
    let score: Int?
    let title: LeadershipTitle?
    let isPreviewing: Bool
    let language: WidgetLanguage

    private var normalizedScore: Double {
        Double(min(max(score ?? 0, 0), 100)) / 100
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                LeadershipBadgeImage(level: title?.level ?? 0)
                    .frame(width: 42, height: 42)
                    .shadow(color: visualTokens.accent.primary.color.opacity(0.20), radius: 5, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("当前等级", "Current rank"))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(currentTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if isPreviewing {
                        Text(language.text("样式预览", "Style preview"))
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(visualTokens.accent.primaryStrong.color)
                    }
                }
            }
            .frame(width: 176, alignment: .leading)

            VStack(spacing: 5) {
                HStack {
                    Text(score.map { "\($0) / 100" } ?? "-- / 100")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text(distanceLabel)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FixedVisualPalette.surfaceTrack)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [visualTokens.accent.primary.color, visualTokens.accent.primaryStrong.color],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(normalizedScore))
                        ForEach([0.20, 0.35, 0.50, 0.65, 0.80, 0.93], id: \.self) { threshold in
                            Circle()
                                .fill(FixedVisualPalette.controlFill(colorScheme))
                                .overlay(Circle().strokeBorder(visualTokens.accent.primary.color.opacity(0.55), lineWidth: 0.8))
                                .frame(width: 6, height: 6)
                                .offset(x: max(0, geometry.size.width * CGFloat(threshold) - 3))
                        }
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: 7) {
                LeadershipBadgeImage(level: 7)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("最高等级", "Top rank"))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(language.text("一人成军", "One-person army"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            }
            .frame(width: 126, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .cardBackground(cornerRadius: 10, elevated: true)
        .accessibilityElement(children: .combine)
    }

    private var currentTitle: String {
        guard let title else { return language.text("记录建立中", "Building history") }
        return "L\(min(title.level, 8)) · \(title.name)"
    }

    private var distanceLabel: String {
        guard let score else { return language.text("距离暂不可用", "Distance unavailable") }
        let distance = max(100 - score, 0)
        return distance == 0
            ? language.text("已达一人成军", "Top rank reached")
            : language.text("距一人成军 \(distance) 分", "\(distance) pts to top")
    }
}

private struct LeadershipPreviewMenu: View {
    @Binding var selection: Int?
    let language: WidgetLanguage

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                Label(language.text("真实数据", "Live data"), systemImage: selection == nil ? "checkmark" : "chart.line.uptrend.xyaxis")
            }
            Divider()
            ForEach(1...8, id: \.self) { level in
                let fixture = LeadershipPreviewFixture(level: level)
                Button {
                    selection = level
                } label: {
                    Label("L\(level) · \(fixture.title.name)", systemImage: selection == level ? "checkmark" : "circle.hexagongrid")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "testtube.2")
                Text(selection.map { "L\($0)" } ?? language.text("样式预览", "Style preview"))
            }
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 26)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(language.text("仅预览等级样式，不修改真实数据", "Preview rank styles without changing live data"))
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
    let preview: LeadershipPreviewFixture?
    let language: WidgetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .center, spacing: 7) {
                    LeadershipBadgeLockup(
                        title: preview?.title ?? report.title,
                        emptyTitle: language.text("记录不足", "Insufficient history"),
                        imageSize: 46,
                        plaqueWidth: 85
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(preview.map { String($0.score) } ?? report.score.map(String.init) ?? "--")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("/100")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        Text(periodLabel)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Image(systemName: evidenceIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(evidenceColor)
                    .help(evidenceLabel)
            }

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
        if preview != nil {
            return language.text("样式预览不会修改真实得分或统计记录", "Style preview does not change your live score or history")
        }
        if let core = report.coreScore {
            return language.text(
                String(format: "Core4 %.1f × M %.0f%% · %d/%d 活跃日", core, report.maturity * 100, report.activeDayCount, period.dayCount),
                String(format: "Core4 %.1f × M %.0f%% · %d/%d active days", core, report.maturity * 100, report.activeDayCount, period.dayCount)
            )
        }
        return language.text("可信证据低于出分门槛", "Evidence is below the scoring threshold")
    }

    private var periodLabel: String {
        switch period {
        case .today: return language.text("今日", "Today")
        case .sevenDays: return language.text("近 7 天", "7 days")
        case .twentyEightDays: return language.text("近 28 天", "28 days")
        }
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
