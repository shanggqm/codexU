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

struct StatusItemRenderer {
    func render(_ presentation: StatusItemPresentation) -> NSImage {
        let image = NSImage(size: presentation.imageSize)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        NSGraphicsContext.current?.imageInterpolation = .high
        drawBackground(in: NSRect(origin: .zero, size: presentation.imageSize))

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

    private func drawBackground(in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.24).setFill()
        NSBezierPath(
            roundedRect: rect.insetBy(dx: 1, dy: 1),
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        ).fill()
    }

    private func drawMinimal(_ presentation: StatusItemPresentation) {
        let quotaMetrics = presentation.quotaMetrics
        drawRuntimeLogo(presentation.runtime, in: NSRect(x: 8, y: 6, width: 10, height: 10))

        for (index, metric) in quotaMetrics.prefix(2).enumerated() {
            let rect: NSRect
            let lineWidth: CGFloat
            if index == 0 {
                rect = NSRect(x: 3, y: 2, width: 20, height: 18)
                lineWidth = 1.5
            } else {
                rect = NSRect(x: 5.5, y: 4.5, width: 15, height: 13)
                lineWidth = 1.2
            }
            drawCircularProgress(
                in: rect,
                fraction: metric.fraction,
                role: metric.paletteRole,
                lineWidth: lineWidth
            )
        }
    }

    private func drawClassic(_ presentation: StatusItemPresentation) {
        drawRuntimeLogo(presentation.runtime, in: NSRect(x: 4, y: 4, width: 14, height: 14))
        var x = StatusItemLayoutMetrics.leadingContentWidth

        for metric in presentation.quotaMetrics {
            let ringRect = NSRect(x: x + 1, y: 1, width: 20, height: 20)
            drawCircularProgress(
                in: ringRect,
                fraction: metric.fraction,
                role: metric.paletteRole,
                lineWidth: 1.5
            )
            let palette = StatusItemQuotaPalette.palette(for: metric.paletteRole)
            drawText(
                metric.label,
                in: NSRect(x: x + 3, y: 10.7, width: 16, height: 7),
                font: .systemFont(ofSize: 5.2, weight: .semibold),
                color: metric.isAvailable ? palette.end : mutedTextColor,
                alignment: .center
            )
            drawText(
                metric.compactValue,
                in: NSRect(x: x + 2, y: 4.0, width: 18, height: 8),
                font: .monospacedDigitSystemFont(ofSize: 6.5, weight: .bold),
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
        drawRuntimeLogo(presentation.runtime, in: NSRect(x: 5, y: 4, width: 14, height: 14))
        let quotaMetrics = presentation.quotaMetrics

        if quotaMetrics.count >= 2 {
            drawRichQuotaRow(quotaMetrics[0], y: 11.3, showsReset: presentation.showsResetCountdown)
            drawRichQuotaRow(quotaMetrics[1], y: 1.2, showsReset: presentation.showsResetCountdown)
        } else if let metric = quotaMetrics.first {
            drawRichQuotaRow(metric, y: 6.2, showsReset: presentation.showsResetCountdown)
        }

        guard let today = presentation.todayMetric else { return }
        let tokenX: CGFloat
        if quotaMetrics.isEmpty {
            tokenX = StatusItemLayoutMetrics.leadingContentWidth
        } else {
            tokenX = presentation.showsResetCountdown
                ? StatusItemLayoutMetrics.richQuotaWidthWithReset
                : StatusItemLayoutMetrics.richQuotaWidthWithoutReset
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(rect: NSRect(x: tokenX - 1, y: 4, width: 1, height: 14)).fill()
        }
        drawCompactToken(today, x: tokenX, width: StatusItemLayoutMetrics.richTokenExtensionWidth)
    }

    private func drawRichQuotaRow(
        _ metric: StatusItemMetricPresentation,
        y: CGFloat,
        showsReset: Bool
    ) {
        let palette = StatusItemQuotaPalette.palette(for: metric.paletteRole)
        drawText(
            metric.label,
            in: NSRect(x: 22, y: y - 1, width: 17, height: 11),
            font: .monospacedDigitSystemFont(ofSize: 8.2, weight: .semibold),
            color: metric.isAvailable ? palette.end : mutedTextColor,
            alignment: .right
        )
        drawLinearProgress(
            in: NSRect(x: 45, y: y + 2.2, width: 23, height: 4),
            fraction: metric.fraction,
            role: metric.paletteRole
        )
        drawText(
            metric.value,
            in: NSRect(x: 70, y: y - 1, width: 24, height: 11),
            font: .monospacedDigitSystemFont(ofSize: 8.2, weight: .semibold),
            color: metric.isAvailable ? primaryTextColor : mutedTextColor,
            alignment: .right
        )
        if showsReset {
            drawText(
                metric.resetText ?? "--",
                in: NSRect(x: 98, y: y - 1, width: 15, height: 11),
                font: .monospacedDigitSystemFont(ofSize: 7.7, weight: .medium),
                color: secondaryTextColor,
                alignment: .left
            )
        }
    }

    private func drawCompactToken(
        _ metric: StatusItemMetricPresentation,
        x: CGFloat,
        width: CGFloat
    ) {
        drawText(
            "T",
            in: NSRect(x: x + 3, y: 10.2, width: width - 6, height: 8),
            font: .systemFont(ofSize: 6.2, weight: .semibold),
            color: secondaryTextColor,
            alignment: .center
        )
        drawText(
            metric.compactValue,
            in: NSRect(x: x + 2, y: 3.1, width: width - 4, height: 9),
            font: .monospacedDigitSystemFont(ofSize: 7.8, weight: .bold),
            color: metric.isAvailable ? primaryTextColor : mutedTextColor,
            alignment: .center
        )
    }

    private func drawCircularProgress(
        in rect: NSRect,
        fraction: CGFloat?,
        role: StatusItemQuotaPaletteRole?,
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
        for index in 0..<segmentCount {
            let startFraction = CGFloat(index) / CGFloat(segmentCount) * progress
            let endFraction = CGFloat(index + 1) / CGFloat(segmentCount) * progress
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90 - startFraction * 360,
                endAngle: 90 - endFraction * 360,
                clockwise: true
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
            angle: 90 - progress * 360,
            diameter: lineWidth,
            color: palette.end
        )
    }

    private func drawLinearProgress(
        in rect: NSRect,
        fraction: CGFloat?,
        role: StatusItemQuotaPaletteRole?
    ) {
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        guard let fraction else { return }
        let progress = max(0, min(1, fraction))
        guard progress > 0.001 else { return }
        let fillWidth = max(rect.height, rect.width * progress)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        let palette = StatusItemQuotaPalette.palette(for: role)
        guard let context = NSGraphicsContext.current?.cgContext,
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [palette.start.cgColor, palette.end.cgColor] as CFArray,
                locations: [0, 1]
              )
        else {
            palette.end.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            return
        }

        context.saveGState()
        NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2).addClip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: []
        )
        context.restoreGState()
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
        if let image = runtimeLogo(for: scope) {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
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

    private func runtimeLogo(for scope: RuntimeScope) -> NSImage? {
        let name = scope == .codex ? "codex-color" : "claudecode-color"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
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
        NSColor.white.withAlphaComponent(0.94)
    }

    private var secondaryTextColor: NSColor {
        NSColor.white.withAlphaComponent(0.64)
    }

    private var mutedTextColor: NSColor {
        NSColor.white.withAlphaComponent(0.42)
    }
}
