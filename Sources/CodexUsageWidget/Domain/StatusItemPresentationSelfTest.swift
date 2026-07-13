import Cocoa

enum StatusItemPresentationSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        expect(TokenFormatter.format(nil) == "--", "missing tokens should remain unavailable")
        expect(TokenFormatter.format(999) == "999", "sub-thousand tokens should remain unabridged")
        expect(TokenFormatter.format(1_000) == "1.0K", "thousands should use K")
        expect(TokenFormatter.format(999_949) == "999.9K", "values below the rounded boundary should stay in K")
        expect(TokenFormatter.format(999_950) == "1.0M", "rounded K boundary should promote to M")
        expect(TokenFormatter.format(999_999_999) == "1.0B", "rounded M boundary should promote to B")
        expect(TokenFormatter.format(1_234_567_890) == "1.2B", "billions should use B")
        expect(TokenFormatter.format(-1_234_567) == "-1.2M", "negative values should preserve their sign")

        let suiteName = "codexU.status-item-self-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("status item self-test failed: could not create UserDefaults suite")
            return false
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let defaultPreferences = StatusItemPreferencesStore.load(defaults: defaults)
        expect(defaultPreferences == .default, "missing keys should load the current rich defaults")
        expect(QuotaDisplayMode.used.drawsClockwise, "used quota should draw clockwise")
        expect(!QuotaDisplayMode.remaining.drawsClockwise, "remaining quota should draw counterclockwise")
        expect(QuotaDisplayMode.used.startsAtLeadingEdge, "used linear bar should start at the leading edge")
        expect(!QuotaDisplayMode.remaining.startsAtLeadingEdge, "remaining linear bar should start at the trailing edge")

        defaults.set("unknown-mode", forKey: StatusItemPreferencesStore.displayModeKey)
        defaults.set("unknown-direction", forKey: StatusItemPreferencesStore.quotaModeKey)
        defaults.set([], forKey: StatusItemPreferencesStore.visibleMetricsKey)
        let repairedPreferences = StatusItemPreferencesStore.load(defaults: defaults)
        expect(repairedPreferences.displayMode == .rich, "unknown display mode should fall back to rich")
        expect(repairedPreferences.quotaMode == .used, "unknown quota mode should fall back to used")
        expect(
            repairedPreferences.visibleMetrics == [.fiveHourQuota, .sevenDayQuota],
            "empty visible metrics should be repaired to both quota windows"
        )

        var noMetrics = StatusItemPreferences.default
        noMetrics.visibleMetrics = []
        expect(noMetrics.validationError() == .requiresVisibleMetric, "empty metrics should be rejected")

        var minimalTokensOnly = StatusItemPreferences.default
        minimalTokensOnly.displayMode = .minimal
        minimalTokensOnly.visibleMetrics = [.todayTokens]
        expect(
            minimalTokensOnly.validationError() == .minimalRequiresQuotaMetric,
            "minimal mode should require a quota metric"
        )
        expect(
            minimalTokensOnly.normalized().hasVisibleQuota,
            "stored minimal token-only state should repair itself"
        )

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = StatusItemSourceSnapshot(
            runtime: .codex,
            fiveHourRemainingPercent: 89,
            fiveHourResetsAt: now.addingTimeInterval(90 * 60),
            sevenDayRemainingPercent: 76,
            sevenDayResetsAt: now.addingTimeInterval(26 * 60 * 60),
            todayTokens: 1_234_567
        )
        let builder = StatusItemPresentationBuilder()

        var usedPreferences = StatusItemPreferences.default
        usedPreferences.visibleMetrics.insert(.todayTokens)
        let used = builder.build(
            source: source,
            preferences: usedPreferences,
            language: .en,
            now: now
        )
        let usedFiveHour = used.metrics.first { $0.metric == .fiveHourQuota }
        let usedSevenDay = used.metrics.first { $0.metric == .sevenDayQuota }
        expect(usedFiveHour?.value == "11%", "used mode should invert remaining percentage")
        expect(usedFiveHour?.fraction == 0.11, "used mode ring fraction should match its number")
        expect(usedFiveHour?.paletteRole == .primary, "5h should use the main blue ring palette")
        expect(usedSevenDay?.paletteRole == .secondary, "7d should use the main purple ring palette")
        expect(usedFiveHour?.resetText == "1h", "reset countdown should use injected time")
        expect(usedSevenDay?.resetText == "1d", "long reset countdown should prefer days")
        expect(used.todayMetric?.value == "1.2M", "today tokens should use compact formatting")
        expect(used.tooltip.contains("used"), "English tooltip should name the quota direction")

        var remainingPreferences = usedPreferences
        remainingPreferences.quotaMode = .remaining
        let remaining = builder.build(
            source: source,
            preferences: remainingPreferences,
            language: .zh,
            now: now
        )
        let remainingFiveHour = remaining.metrics.first { $0.metric == .fiveHourQuota }
        expect(remainingFiveHour?.value == "89%", "remaining mode should preserve remaining percentage")
        expect(remainingFiveHour?.fraction == 0.89, "remaining ring fraction should match its number")
        expect(remainingFiveHour?.paletteRole == .primary, "quota direction must not change palette identity")
        expect(remaining.tooltip.contains("剩余"), "Chinese tooltip should name the quota direction")

        let clampedSource = StatusItemSourceSnapshot(
            runtime: .claudeCode,
            fiveHourRemainingPercent: -10,
            fiveHourResetsAt: nil,
            sevenDayRemainingPercent: 110,
            sevenDayResetsAt: nil,
            todayTokens: nil
        )
        let clamped = builder.build(
            source: clampedSource,
            preferences: remainingPreferences,
            language: .en,
            now: now
        )
        expect(clamped.metrics.first { $0.metric == .fiveHourQuota }?.value == "0%", "negative quota should clamp to zero")
        expect(clamped.metrics.first { $0.metric == .sevenDayQuota }?.value == "100%", "quota above 100 should clamp")
        expect(clamped.todayMetric?.isAvailable == false, "missing token data should remain unavailable")

        var minimalPreferences = StatusItemPreferences.default
        minimalPreferences.displayMode = .minimal
        let minimal = builder.build(source: source, preferences: minimalPreferences, language: .en, now: now)
        expect(minimal.itemLength <= 36, "minimal double-ring item should stay within 36pt")
        let minimalOuterRingRect = StatusItemLayoutMetrics.minimalOuterRingRect
        let minimalInnerRingRect = StatusItemLayoutMetrics.minimalInnerRingRect
        expect(
            minimalOuterRingRect.midX == minimalInnerRingRect.midX
                && minimalOuterRingRect.midY == minimalInnerRingRect.midY,
            "minimal quota rings should share one center"
        )
        let minimalInnerRingOuterRadius = StatusItemLayoutMetrics.minimalInnerRingDiameter / 2
        let minimalOuterRingInnerRadius = StatusItemLayoutMetrics.minimalOuterRingDiameter / 2
            - StatusItemLayoutMetrics.minimalOuterRingLineWidth
        expect(
            minimalInnerRingOuterRadius + StatusItemLayoutMetrics.minimalRingClearance
                <= minimalOuterRingInnerRadius,
            "minimal quota rings should remain visibly separated"
        )
        let renderer = StatusItemRenderer()
        let minimalImage = renderer.render(minimal, appearance: NSAppearance(named: .aqua))
        if let bitmap = minimalImage.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
           let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2) {
            expect(center.alphaComponent < 0.01, "minimal mode center should remain transparent without a runtime logo")
        } else {
            failures.append("minimal status item render should produce a readable bitmap")
        }
        let todayTokenFont = NSFont.monospacedDigitSystemFont(
            ofSize: StatusItemLayoutMetrics.todayTokenFontSize,
            weight: .semibold
        )
        let maximumTokenWidth = ("999.9M" as NSString).size(withAttributes: [.font: todayTokenFont]).width
        expect(
            maximumTokenWidth <= StatusItemLayoutMetrics.classicTokenUnitWidth - 4,
            "menu bar body-sized token text should fit its fixed classic slot"
        )
        expect(
            maximumTokenWidth <= StatusItemLayoutMetrics.richTokenExtensionWidth - 4,
            "menu bar body-sized token text should fit its fixed rich slot"
        )

        var classicPreferences = StatusItemPreferences.default
        classicPreferences.displayMode = .classic
        let classic = builder.build(source: source, preferences: classicPreferences, language: .en, now: now)
        expect(classic.itemLength <= 88, "classic double-ring item should stay within 88pt")
        expect(classic.mode == .classic, "classic presentation should select the number-ring renderer")
        let aquaImage = renderer.render(classic, appearance: NSAppearance(named: .aqua))
        let darkImage = renderer.render(classic, appearance: NSAppearance(named: .darkAqua))
        expect(aquaImage.size == classic.imageSize, "Aqua render should preserve presentation size")
        expect(darkImage.size == classic.imageSize, "Dark Aqua render should preserve presentation size")
        if let bitmap = aquaImage.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
           let corner = bitmap.colorAt(x: 0, y: 0) {
            expect(corner.alphaComponent < 0.01, "status item image background should remain transparent")
        } else {
            failures.append("status item render should produce a readable bitmap")
        }

        let rich = builder.build(source: source, preferences: .default, language: .en, now: now)
        expect(rich.itemLength <= 124, "default rich item should not exceed the previous width")

        let unavailable = builder.build(
            source: .unavailable(runtime: .codex),
            preferences: classicPreferences,
            language: .en,
            now: now
        )
        expect(unavailable.itemLength == classic.itemLength, "data availability must not change item width")
        expect(unavailable.quotaMetrics.allSatisfy { !$0.isAvailable }, "missing quotas should stay unavailable")

        if failures.isEmpty {
            print("status item self-test passed")
            return true
        }

        for failure in failures {
            print("status item self-test failed: \(failure)")
        }
        return false
    }
}
