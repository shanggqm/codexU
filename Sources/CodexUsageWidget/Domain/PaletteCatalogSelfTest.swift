import AppKit
import Foundation

enum PaletteCatalogSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        expect((try? PaletteColor(hex: "#2866F7"))?.description == "#2866F7FF", "six-digit colors should receive opaque alpha")
        expect((try? PaletteColor(hex: "#2866F780"))?.alpha ?? 0 > 0.49, "eight-digit colors should preserve alpha")
        expect((try? PaletteColor(hex: "blue")) == nil, "named colors should be rejected")

        guard let resources = Bundle.main.resourceURL else {
            print("palette self-test failed: bundle resource URL unavailable")
            return false
        }
        let root = resources.appendingPathComponent("Palettes", isDirectory: true)
        let start = CFAbsoluteTimeGetCurrent()
        let catalog = PaletteCatalog.load(rootURL: root, appVersion: "1.0.5", includeExperimental: true)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        expect(catalog.contains(PaletteCatalog.defaultPaletteID), "default palette should load")
        expect(catalog.contains("codexu.blue-white-porcelain"), "blue-and-white porcelain palette should load")
        expect(catalog.descriptors(language: "zh-Hans").count == 2, "two built-in palettes should be discoverable")
        expect(elapsed < 0.5, "palette catalog should load in under 500ms during self-test")

        let defaultLight = catalog.resolve(id: PaletteCatalog.defaultPaletteID, appearance: .light)
        let safeLight = ResolvedVisualTokens.safeDefault(.light)
        expect(defaultLight.accent == safeLight.accent, "default package accent tokens should match compiled fallback")
        expect(defaultLight.quota == safeLight.quota, "default package quota tokens should match compiled fallback")
        expect(defaultLight.data == safeLight.data && defaultLight.selection == safeLight.selection, "default package data and selection should match compiled fallback")
        expect(defaultLight.assets.isEmpty, "default package should use token fallbacks")
        let defaultDark = catalog.resolve(id: PaletteCatalog.defaultPaletteID, appearance: .dark)
        let safeDark = ResolvedVisualTokens.safeDefault(.dark)
        expect(defaultDark.accent == safeDark.accent, "default dark accent tokens should match compiled fallback")
        expect(defaultDark.quota == safeDark.quota, "default dark quota tokens should match compiled fallback")
        expect(defaultDark.data == safeDark.data && defaultDark.selection == safeDark.selection, "default dark data and selection should match compiled fallback")

        for appearance in PaletteAppearance.allCases {
            let porcelain = catalog.resolve(id: "codexu.blue-white-porcelain", appearance: appearance)
            expect(porcelain.identity.appearance == appearance, "resolved identity should preserve appearance")
            expect(porcelain.assets.count == PaletteAssetSlot.allCases.count, "porcelain should provide all six public asset slots")
            for slot in PaletteAssetSlot.allCases {
                guard let descriptor = porcelain.assets[slot] else {
                    failures.append("missing porcelain asset: \(appearance.rawValue)/\(slot.rawValue)")
                    continue
                }
                guard let image = PaletteAssetStore.shared.image(for: descriptor) else {
                    failures.append("AppKit could not decode: \(descriptor.url.lastPathComponent)")
                    continue
                }
                expect(image.isValid, "decoded asset should be valid: \(descriptor.url.lastPathComponent)")
            }
        }

        let unknown = catalog.resolve(id: "community.missing", appearance: .dark)
        expect(unknown.identity.paletteID == PaletteCatalog.defaultPaletteID, "unknown IDs should resolve to default")

        let suiteName = "codexU.palette-self-test.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("community.missing", forKey: "codexU.paletteID")
            let normalized = AppSettings(defaults: defaults, paletteCatalog: catalog)
            expect(normalized.paletteID == PaletteCatalog.defaultPaletteID, "invalid stored ID should normalize to default")
            expect(normalized.paletteFallbackNotice != nil, "invalid stored ID should expose a fallback notice")
            expect(normalized.selectPalette("codexu.blue-white-porcelain") == .selected, "valid selection should succeed")
            expect(defaults.string(forKey: "codexU.paletteID") == "codexu.blue-white-porcelain", "selection should persist")
            normalized.resetPalette()
            expect(normalized.paletteID == PaletteCatalog.defaultPaletteID, "reset should select default")
        } else {
            failures.append("could not create UserDefaults suite")
        }

        let invalidRoot = FileManager.default.temporaryDirectory.appendingPathComponent("codexU-palette-self-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: invalidRoot) }
        do {
            try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
            let sourcePackage = root.appendingPathComponent(PaletteCatalog.defaultPaletteID)
            let contributed = invalidRoot.appendingPathComponent("community.test")
            try FileManager.default.copyItem(at: sourcePackage, to: contributed)
            let contributedManifestURL = contributed.appendingPathComponent("manifest.json")
            let originalManifest = try JSONDecoder().decode(PaletteManifestDTO.self, from: Data(contentsOf: contributedManifestURL))
            let contributedManifest = PaletteManifestDTO(
                schemaVersion: originalManifest.schemaVersion,
                id: "community.test",
                version: originalManifest.version,
                minimumAppVersion: originalManifest.minimumAppVersion,
                lifecycle: originalManifest.lifecycle,
                defaultLocale: originalManifest.defaultLocale,
                localizations: originalManifest.localizations,
                variants: originalManifest.variants,
                assetManifest: originalManifest.assetManifest,
                author: originalManifest.author,
                license: originalManifest.license,
                source: originalManifest.source,
                capabilities: originalManifest.capabilities
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(contributedManifest).write(to: contributedManifestURL, options: .atomic)
            let contributedCatalog = PaletteCatalog.load(rootURL: invalidRoot, appVersion: "1.0.5", includeExperimental: true)
            expect(contributedCatalog.contains("community.test"), "a valid third package should load without Swift registration")

            let mismatched = invalidRoot.appendingPathComponent("community.wrong-name")
            try FileManager.default.copyItem(at: sourcePackage, to: mismatched)
            let invalidCatalog = PaletteCatalog.load(rootURL: invalidRoot, appVersion: "1.0.5", includeExperimental: true)
            expect(!invalidCatalog.contains(PaletteCatalog.defaultPaletteID), "directory/id mismatch should isolate the package")
            expect(invalidCatalog.diagnostics.contains(where: { $0.ruleID == "PAL003" }), "directory/id mismatch should emit PAL003")
        } catch {
            failures.append("could not construct invalid package fixture: \(error.localizedDescription)")
        }

        if failures.isEmpty {
            print(String(format: "palette self-test passed (catalog %.1fms)", elapsed * 1_000))
            return true
        }
        for diagnostic in catalog.diagnostics {
            print("palette diagnostic \(diagnostic.ruleID) \(diagnostic.paletteID ?? "-") \(diagnostic.relativePath): \(diagnostic.message)")
        }
        failures.forEach { print("palette self-test failed: \($0)") }
        return false
    }
}
