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

        let builtInPaletteIDs = [
            PaletteCatalog.defaultPaletteID,
            "codexu.blue-white-porcelain",
            "codexu.forbidden-city-red",
            "codexu.thousand-li-landscape",
            "codexu.dunhuang-apsara",
            "codexu.orchid-dawn"
        ]
        for paletteID in builtInPaletteIDs {
            expect(catalog.contains(paletteID), "\(paletteID) should load")
        }
        let discoveredDescriptors = catalog.descriptors(language: "zh-Hans")
        expect(Set(builtInPaletteIDs).isSubset(of: Set(discoveredDescriptors.map(\.id))), "required built-in palettes should remain discoverable")
        for descriptor in discoveredDescriptors {
            for appearance in PaletteAppearance.allCases {
                let tokens = catalog.resolve(id: descriptor.id, appearance: appearance)
                expect(tokens.identity.paletteID == descriptor.id, "\(descriptor.id) should resolve without Swift registration")
                expect(tokens.identity.appearance == appearance, "\(descriptor.id) should resolve both appearances")
                expect(tokens.data.series.count == 3 && tokens.data.modelSeries?.count == 9 && tokens.data.heatmap.count == 5, "\(descriptor.id) should expose complete data roles")
            }
        }
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

        for paletteID in builtInPaletteIDs where paletteID != PaletteCatalog.defaultPaletteID && paletteID != "codexu.blue-white-porcelain" {
            for appearance in PaletteAppearance.allCases {
                let tokens = catalog.resolve(id: paletteID, appearance: appearance)
                expect(tokens.identity.paletteID == paletteID, "\(paletteID) should preserve its resolved identity")
                expect(tokens.identity.appearance == appearance, "\(paletteID) should resolve both appearances")
                expect(tokens.assets.isEmpty, "\(paletteID) should remain color-token-only in this phase")
                expect(tokens.data.series.count == 3 && tokens.data.modelSeries?.count == 9 && tokens.data.valueProgress.count == 3, "\(paletteID) should expose complete data roles")
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
            expect(normalized.selectPalette("codexu.thousand-li-landscape") == .selected, "new token palette selection should succeed")
            expect(defaults.string(forKey: "codexU.paletteID") == "codexu.thousand-li-landscape", "new token palette selection should persist")
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
            for appearance in PaletteAppearance.allCases {
                let tokenURL = contributed.appendingPathComponent("tokens/\(appearance.rawValue).json")
                var tokenObject = try JSONSerialization.jsonObject(with: Data(contentsOf: tokenURL)) as? [String: Any] ?? [:]
                var dataObject = tokenObject["data"] as? [String: Any] ?? [:]
                dataObject.removeValue(forKey: "modelSeries")
                tokenObject["data"] = dataObject
                let tokenData = try JSONSerialization.data(withJSONObject: tokenObject, options: [.prettyPrinted, .sortedKeys])
                try tokenData.write(to: tokenURL, options: .atomic)
            }
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
            expect(contributedCatalog.descriptors(language: "en").contains(where: { $0.id == "community.test" }), "a valid contributed package should enter the settings catalog")
            expect(contributedCatalog.resolve(id: "community.test", appearance: .light).data.modelSeries == nil, "legacy packages without model series should remain loadable")

            let mismatched = invalidRoot.appendingPathComponent("community.wrong-name")
            try FileManager.default.copyItem(at: sourcePackage, to: mismatched)

            let forbidden = invalidRoot.appendingPathComponent("community.forbidden")
            try FileManager.default.copyItem(at: sourcePackage, to: forbidden)
            let forbiddenManifestURL = forbidden.appendingPathComponent("manifest.json")
            let forbiddenManifest = PaletteManifestDTO(
                schemaVersion: originalManifest.schemaVersion,
                id: "community.forbidden",
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
            try encoder.encode(forbiddenManifest).write(to: forbiddenManifestURL, options: .atomic)
            try Data("print(\"not allowed\")\n".utf8).write(to: forbidden.appendingPathComponent("forbidden.swift"), options: .atomic)

            let missingDocs = invalidRoot.appendingPathComponent("community.missing-docs")
            try FileManager.default.copyItem(at: sourcePackage, to: missingDocs)
            let missingDocsManifestURL = missingDocs.appendingPathComponent("manifest.json")
            let missingDocsManifest = PaletteManifestDTO(
                schemaVersion: originalManifest.schemaVersion,
                id: "community.missing-docs",
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
            try encoder.encode(missingDocsManifest).write(to: missingDocsManifestURL, options: .atomic)
            try FileManager.default.removeItem(at: missingDocs.appendingPathComponent("README.md"))
            try FileManager.default.removeItem(at: missingDocs.appendingPathComponent("LICENSE"))

            let deprecated = invalidRoot.appendingPathComponent("community.deprecated")
            try FileManager.default.copyItem(at: sourcePackage, to: deprecated)
            let deprecatedManifestURL = deprecated.appendingPathComponent("manifest.json")
            let deprecatedManifest = PaletteManifestDTO(
                schemaVersion: originalManifest.schemaVersion,
                id: "community.deprecated",
                version: originalManifest.version,
                minimumAppVersion: originalManifest.minimumAppVersion,
                lifecycle: .deprecated,
                defaultLocale: originalManifest.defaultLocale,
                localizations: originalManifest.localizations,
                variants: originalManifest.variants,
                assetManifest: originalManifest.assetManifest,
                author: originalManifest.author,
                license: originalManifest.license,
                source: originalManifest.source,
                capabilities: originalManifest.capabilities
            )
            try encoder.encode(deprecatedManifest).write(to: deprecatedManifestURL, options: .atomic)

            let invalidCatalog = PaletteCatalog.load(rootURL: invalidRoot, appVersion: "1.0.5", includeExperimental: true)
            expect(!invalidCatalog.contains(PaletteCatalog.defaultPaletteID), "directory/id mismatch should isolate the package")
            expect(invalidCatalog.diagnostics.contains(where: { $0.ruleID == "PAL003" }), "directory/id mismatch should emit PAL003")
            expect(!invalidCatalog.contains("community.forbidden"), "a package containing Swift should be isolated")
            expect(invalidCatalog.diagnostics.contains(where: { $0.paletteID == "community.forbidden" && $0.ruleID == "PAL008" }), "forbidden files should emit PAL008")
            expect(!invalidCatalog.contains("community.missing-docs"), "a package missing README and LICENSE should be isolated")
            expect(invalidCatalog.diagnostics.contains(where: { $0.paletteID == "community.missing-docs" && $0.ruleID == "PAL010" }), "missing package documentation should emit PAL010")
            expect(invalidCatalog.contains("community.deprecated"), "deprecated packages should remain resolvable for existing preferences")
            expect(!invalidCatalog.descriptors(language: "en").contains(where: { $0.id == "community.deprecated" }), "deprecated packages should not be offered for new selection")
            expect(invalidCatalog.descriptors(language: "en", includingDeprecatedID: "community.deprecated").contains(where: { $0.id == "community.deprecated" }), "the currently selected deprecated package should remain visible")
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
