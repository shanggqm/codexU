import Cocoa

private struct StatusItemQuotaPalette {
    let start: NSColor
    let end: NSColor

    static func palette(for role: StatusItemQuotaPaletteRole?) -> StatusItemQuotaPalette {
        switch role {
        case .primary:
            return StatusItemQuotaPalette(
                start: WidgetPalette.brandPrimaryLightRGB.nsColor,
                end: WidgetPalette.brandPrimaryRGB.nsColor
            )
        case .secondary:
            return StatusItemQuotaPalette(
                start: WidgetPalette.brandHighlightRGB.nsColor,
                end: WidgetPalette.brandSecondaryRGB.nsColor
            )
        case nil:
            return StatusItemQuotaPalette(
                start: NSColor.secondaryLabelColor,
                end: NSColor.secondaryLabelColor
            )
        }
    }
}

private extension RingRGBColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

private enum StatusItemTextOpacity {
    static let primary: CGFloat = 0.94
    static let supporting: CGFloat = 0.74
}

struct StatusItemRenderer {
    private static let resetCountdownTemplate: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: StatusItemLayoutMetrics.richResetIconSide,
            weight: .semibold
        )
        return NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
    }()

    func render(
        _ presentation: StatusItemPresentation,
        appearance: NSAppearance? = nil
    ) -> NSImage {
        guard let appearance else {
            return renderImage(presentation)
        }

        var image: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            image = renderImage(presentation)
        }
        return image ?? renderImage(presentation)
    }

    private func renderImage(_ presentation: StatusItemPresentation) -> NSImage {
        let image = NSImage(size: presentation.imageSize)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        NSGraphicsContext.current?.imageInterpolation = .high

        switch presentation.mode {
        case .minimal:
            drawMinimal(presentation)
        case .classic:
            drawClassic(presentation)
        case .rich:
            drawRich(presentation)
        }

        return image
    }

    private func drawMinimal(_ presentation: StatusItemPresentation) {
        if presentation.showsNoActiveQuota {
            drawNoActiveQuota(
                in: NSRect(
                    x: 0,
                    y: 1,
                    width: StatusItemLayoutMetrics.minimalImageWidth,
                    height: 20
                )
            )
            return
        }
        let quotaMetrics = presentation.quotaMetrics

        for (index, metric) in quotaMetrics.prefix(2).enumerated() {
            let rect: NSRect
            let lineWidth: CGFloat
            if index == 0 {
                rect = StatusItemLayoutMetrics.minimalOuterRingRect
                lineWidth = StatusItemLayoutMetrics.minimalOuterRingLineWidth
            } else {
                rect = StatusItemLayoutMetrics.minimalInnerRingRect
                lineWidth = StatusItemLayoutMetrics.minimalInnerRingLineWidth
            }
            drawCircularProgress(
                in: rect,
                fraction: metric.fraction,
                role: metric.paletteRole,
                quotaMode: presentation.quotaMode,
                lineWidth: lineWidth
            )
        }
    }

    private func drawClassic(_ presentation: StatusItemPresentation) {
        drawRuntimeLogo(presentation.runtime, in: NSRect(x: 2, y: 2, width: 18, height: 18))
        var x = StatusItemLayoutMetrics.leadingContentWidth

        if presentation.showsNoActiveQuota {
            drawNoActiveQuota(in: NSRect(x: x, y: 1, width: 22, height: 20))
            x += StatusItemLayoutMetrics.classicQuotaUnitWidth
        }

        for metric in presentation.quotaMetrics {
            let ringRect = NSRect(x: x + 1, y: 1, width: 20, height: 20)
            drawCircularProgress(
                in: ringRect,
                fraction: metric.fraction,
                role: metric.paletteRole,
                quotaMode: presentation.quotaMode,
                lineWidth: 1.5
            )
            drawText(
                metric.compactValue,
                in: NSRect(x: x + 2, y: 5.2, width: 18, height: 11),
                font: .monospacedDigitSystemFont(ofSize: 8.6, weight: .bold),
                color: metric.isAvailable ? primaryTextColor : mutedTextColor,
                alignment: .center
            )
            x += StatusItemLayoutMetrics.classicQuotaUnitWidth
        }

        if let today = presentation.todayMetric {
            drawCompactToken(today, x: x, width: StatusItemLayoutMetrics.classicTokenUnitWidth)
        }
    }

    private func drawRich(_ presentation: StatusItemPresentation) {
        drawRuntimeLogo(presentation.runtime, in: NSRect(x: 2, y: 2, width: 18, height: 18))
        let quotaMetrics = presentation.quotaMetrics

        if presentation.showsNoActiveQuota {
            drawNoActiveQuota(in: NSRect(x: 22, y: 1, width: 74, height: 20))
        }

        if quotaMetrics.count >= 2 {
            drawRichQuotaRow(
                quotaMetrics[0],
                y: 11.3,
                showsReset: presentation.showsResetCountdown,
                quotaMode: presentation.quotaMode
            )
            drawRichQuotaRow(
                quotaMetrics[1],
                y: 1.2,
                showsReset: presentation.showsResetCountdown,
                quotaMode: presentation.quotaMode
            )
        } else if let metric = quotaMetrics.first {
            drawRichSingleQuota(
                metric,
                showsReset: presentation.showsResetCountdown,
                quotaMode: presentation.quotaMode
            )
        }

        guard let today = presentation.todayMetric else { return }
        let tokenX: CGFloat
        if presentation.showsNoActiveQuota {
            tokenX = StatusItemLayoutMetrics.richQuotaWidthWithoutReset
            NSColor.separatorColor.withAlphaComponent(0.36).setFill()
            NSBezierPath(rect: NSRect(x: tokenX - 1, y: 4, width: 1, height: 14)).fill()
        } else if quotaMetrics.isEmpty {
            tokenX = StatusItemLayoutMetrics.leadingContentWidth
        } else {
            tokenX = presentation.showsResetCountdown
                ? StatusItemLayoutMetrics.richQuotaWidthWithReset
                : StatusItemLayoutMetrics.richQuotaWidthWithoutReset
            NSColor.separatorColor.withAlphaComponent(0.36).setFill()
            NSBezierPath(rect: NSRect(x: tokenX - 1, y: 4, width: 1, height: 14)).fill()
        }
        drawCompactToken(today, x: tokenX, width: StatusItemLayoutMetrics.richTokenExtensionWidth)
    }

    private func drawNoActiveQuota(in rect: NSRect) {
        drawText(
            "∞",
            in: rect,
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: secondaryTextColor,
            alignment: .center
        )
    }

    private func drawRichSingleQuota(
        _ metric: StatusItemMetricPresentation,
        showsReset: Bool,
        quotaMode: QuotaDisplayMode
    ) {
        drawText(
            metric.label,
            in: NSRect(x: 22, y: 5.2, width: 17, height: 11),
            font: .monospacedDigitSystemFont(ofSize: 8.2, weight: .semibold),
            color: metric.isAvailable ? secondaryTextColor : mutedTextColor,
            alignment: .right
        )

        let barRect = StatusItemLayoutMetrics.richSingleQuotaBarRect
        let fillPath = drawLinearProgress(
            in: barRect,
            fraction: metric.fraction,
            role: metric.paletteRole,
            quotaMode: quotaMode
        )
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 8.6, weight: .bold)
        let valueColor = metric.isAvailable ? primaryTextColor : mutedTextColor
        drawText(
            metric.value,
            in: NSRect(x: barRect.minX, y: 5.2, width: barRect.width, height: 11),
            font: valueFont,
            color: valueColor,
            alignment: .center
        )

        // The progress palette is appearance-independent. Repaint the part of
        // the label over the filled segment with dark ink, while the unfilled
        // part keeps the system label color. This remains legible in both Aqua
        // appearances and when the progress boundary crosses the glyphs.
        if metric.isAvailable, let fillPath {
            NSGraphicsContext.saveGraphicsState()
            fillPath.addClip()
            drawText(
                metric.value,
                in: NSRect(x: barRect.minX, y: 5.2, width: barRect.width, height: 11),
                font: valueFont,
                color: NSColor.black.withAlphaComponent(0.88),
                alignment: .center
            )
            NSGraphicsContext.restoreGraphicsState()
        }

        if showsReset, let resetText = metric.resetText {
            drawResetCountdown(
                resetText,
                in: StatusItemLayoutMetrics.richSingleQuotaResetRect
            )
        }
    }

    private func drawRichQuotaRow(
        _ metric: StatusItemMetricPresentation,
        y: CGFloat,
        showsReset: Bool,
        quotaMode: QuotaDisplayMode
    ) {
        drawText(
            metric.label,
            in: NSRect(x: 22, y: y - 1, width: 17, height: 11),
            font: .monospacedDigitSystemFont(ofSize: 8.2, weight: .semibold),
            color: metric.isAvailable ? secondaryTextColor : mutedTextColor,
            alignment: .right
        )
        drawLinearProgress(
            in: NSRect(x: 45, y: y + 2.2, width: 23, height: 4),
            fraction: metric.fraction,
            role: metric.paletteRole,
            quotaMode: quotaMode
        )
        drawText(
            metric.value,
            in: NSRect(x: 70, y: y - 1, width: 24, height: 11),
            font: .monospacedDigitSystemFont(ofSize: 8.2, weight: .semibold),
            color: metric.isAvailable ? primaryTextColor : mutedTextColor,
            alignment: .right
        )
        if showsReset, let resetText = metric.resetText {
            drawResetCountdown(
                resetText,
                in: NSRect(
                    x: StatusItemLayoutMetrics.richSingleQuotaResetRect.minX,
                    y: y - 1,
                    width: StatusItemLayoutMetrics.richSingleQuotaResetRect.width,
                    height: 11
                )
            )
        }
    }

    private func drawResetCountdown(_ text: String, in rect: NSRect) {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: StatusItemLayoutMetrics.richResetFontSize,
            weight: .medium
        )
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let iconSide = StatusItemLayoutMetrics.richResetIconSide
        let spacing = StatusItemLayoutMetrics.richResetIconTextSpacing

        guard let template = Self.resetCountdownTemplate else {
            drawText(
                "↻\(text)",
                in: rect,
                font: font,
                color: secondaryTextColor,
                alignment: .center
            )
            return
        }

        let contentWidth = StatusItemLayoutMetrics.richResetContentWidth(for: text)
        let startX = rect.midX - contentWidth / 2
        tintedImage(
            template,
            color: secondaryTextColor,
            size: NSSize(width: iconSide, height: iconSide)
        ).draw(
            in: NSRect(
                x: startX,
                y: rect.midY - iconSide / 2,
                width: iconSide,
                height: iconSide
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        drawText(
            text,
            in: NSRect(
                x: startX + iconSide + spacing,
                y: rect.midY - 5.5,
                width: textWidth,
                height: 11
            ),
            font: font,
            color: secondaryTextColor,
            alignment: .center
        )
    }

    private func drawCompactToken(
        _ metric: StatusItemMetricPresentation,
        x: CGFloat,
        width: CGFloat
    ) {
        drawText(
            metric.compactValue,
            in: NSRect(x: x + 2, y: 2.4, width: width - 4, height: 17),
            font: .monospacedDigitSystemFont(
                ofSize: StatusItemLayoutMetrics.todayTokenFontSize,
                weight: .semibold
            ),
            color: metric.isAvailable ? primaryTextColor : mutedTextColor,
            alignment: .center
        )
    }

    private func drawCircularProgress(
        in rect: NSRect,
        fraction: CGFloat?,
        role: StatusItemQuotaPaletteRole?,
        quotaMode: QuotaDisplayMode,
        lineWidth: CGFloat
    ) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(0, min(rect.width, rect.height) / 2 - lineWidth / 2)
        let track = NSBezierPath()
        track.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: -270,
            clockwise: true
        )
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        trackColor.setStroke()
        track.stroke()

        guard let fraction else { return }
        let progress = max(0, min(1, fraction))
        guard progress > 0.001 else { return }
        let palette = StatusItemQuotaPalette.palette(for: role)
        let segmentCount = max(12, Int(ceil(progress * 72)))
        let direction: CGFloat = quotaMode.drawsClockwise ? -1 : 1
        for index in 0..<segmentCount {
            let startFraction = CGFloat(index) / CGFloat(segmentCount) * progress
            let endFraction = CGFloat(index + 1) / CGFloat(segmentCount) * progress
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90 + direction * startFraction * 360,
                endAngle: 90 + direction * endFraction * 360,
                clockwise: quotaMode.drawsClockwise
            )
            path.lineWidth = lineWidth
            path.lineCapStyle = .butt
            mixedColor(
                from: palette.start,
                to: palette.end,
                fraction: Double(index + 1) / Double(segmentCount)
            ).setStroke()
            path.stroke()
        }

        drawArcCap(
            center: center,
            radius: radius,
            angle: 90,
            diameter: lineWidth,
            color: palette.start
        )
        drawArcCap(
            center: center,
            radius: radius,
            angle: 90 + direction * progress * 360,
            diameter: lineWidth,
            color: palette.end
        )
    }

    @discardableResult
    private func drawLinearProgress(
        in rect: NSRect,
        fraction: CGFloat?,
        role: StatusItemQuotaPaletteRole?,
        quotaMode: QuotaDisplayMode
    ) -> NSBezierPath? {
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        guard let fraction else { return nil }
        let progress = max(0, min(1, fraction))
        guard progress > 0.001 else { return nil }
        let fillWidth = max(0.5, rect.width * progress)
        let fillX = quotaMode.startsAtLeadingEdge ? rect.minX : rect.maxX - fillWidth
        let fillRect = NSRect(x: fillX, y: rect.minY, width: fillWidth, height: rect.height)
        let fillRadius = min(rect.height / 2, fillWidth / 2)
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: fillRadius,
            yRadius: fillRadius
        )
        let palette = StatusItemQuotaPalette.palette(for: role)
        guard let context = NSGraphicsContext.current?.cgContext,
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [palette.start.cgColor, palette.end.cgColor] as CFArray,
                locations: [0, 1]
              )
        else {
            palette.end.setFill()
            fillPath.fill()
            return fillPath
        }

        context.saveGState()
        fillPath.addClip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(
                x: quotaMode.startsAtLeadingEdge ? rect.minX : rect.maxX,
                y: rect.midY
            ),
            end: CGPoint(
                x: quotaMode.startsAtLeadingEdge ? rect.maxX : rect.minX,
                y: rect.midY
            ),
            options: []
        )
        context.restoreGState()
        return fillPath
    }

    private func drawArcCap(
        center: CGPoint,
        radius: CGFloat,
        angle: CGFloat,
        diameter: CGFloat,
        color: NSColor
    ) {
        let radians = angle * .pi / 180
        let point = CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
        ).fill()
    }

    private func mixedColor(from start: NSColor, to end: NSColor, fraction: Double) -> NSColor {
        let start = start.usingColorSpace(.sRGB) ?? start
        let end = end.usingColorSpace(.sRGB) ?? end
        let fraction = max(0, min(1, fraction))
        return NSColor(
            srgbRed: start.redComponent + (end.redComponent - start.redComponent) * fraction,
            green: start.greenComponent + (end.greenComponent - start.greenComponent) * fraction,
            blue: start.blueComponent + (end.blueComponent - start.blueComponent) * fraction,
            alpha: start.alphaComponent + (end.alphaComponent - start.alphaComponent) * fraction
        )
    }

    private func drawRuntimeLogo(_ scope: RuntimeScope, in rect: NSRect) {
        if let template = runtimeTemplate(for: scope) {
            tintedImage(template, color: primaryTextColor, size: rect.size)
                .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        drawText(
            scope == .codex ? "C" : "A",
            in: rect,
            font: .systemFont(ofSize: max(6, rect.height * 0.64), weight: .bold),
            color: primaryTextColor,
            alignment: .center
        )
    }

    // Loaded template PNGs are immutable once decoded; cache them so each icon
    // repaint reuses the decoded bitmap instead of re-reading and re-decoding
    // the file from disk. Accessed on the main thread only (via updateStatusItem).
    private static var templateCache: [String: NSImage] = [:]

    private func runtimeTemplate(for scope: RuntimeScope) -> NSImage? {
        let resourceName: String
        switch scope {
        case .codex:
            resourceName = "codex-template"
        case .claudeCode:
            resourceName = "claudecode-template"
        }
        if let cached = Self.templateCache[resourceName] {
            return cached
        }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Self.templateCache[resourceName] = image
            return image
        }

        let fallbackName = scope == .codex
            ? "apple.terminal.fill"
            : "curlybraces.square.fill"
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        return NSImage(systemSymbolName: fallbackName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func tintedImage(_ source: NSImage, color: NSColor, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        color.setFill()
        NSRect(origin: .zero, size: size).fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private var trackColor: NSColor {
        NSColor.labelColor.withAlphaComponent(0.10)
    }

    private var primaryTextColor: NSColor {
        NSColor.labelColor.withAlphaComponent(StatusItemTextOpacity.primary)
    }

    private var secondaryTextColor: NSColor {
        NSColor.labelColor.withAlphaComponent(StatusItemTextOpacity.supporting)
    }

    private var mutedTextColor: NSColor {
        NSColor.tertiaryLabelColor
    }
}
