import Foundation

struct PaletteCatalog {
    static let defaultPaletteID = "codexu.default"

    private let definitions: [String: ValidatedPaletteDefinition]
    let diagnostics: [PaletteDiagnostic]

    var paletteIDs: [String] { definitions.keys.sorted() }

    static func loadFromMainBundle() -> PaletteCatalog {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.5"
        guard let resources = Bundle.main.resourceURL else {
            return PaletteCatalog(definitions: [:], diagnostics: [
                PaletteDiagnostic(paletteID: nil, severity: .error, ruleID: "PAL001", relativePath: "Palettes", message: "Bundle resource directory is unavailable.")
            ])
        }
        return load(rootURL: resources.appendingPathComponent("Palettes", isDirectory: true), appVersion: version)
    }

    static func load(rootURL: URL, appVersion: String, includeExperimental: Bool = false) -> PaletteCatalog {
        var definitions: [String: ValidatedPaletteDefinition] = [:]
        var diagnostics: [PaletteDiagnostic] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let children = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? child.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let result = PaletteValidator.validate(packageURL: child, appVersion: appVersion, includeExperimental: includeExperimental)
            diagnostics.append(contentsOf: result.diagnostics)
            guard let definition = result.definition else { continue }
            if definitions[definition.manifest.id] != nil {
                diagnostics.append(PaletteDiagnostic(
                    paletteID: definition.manifest.id,
                    severity: .error,
                    ruleID: "PAL003",
                    relativePath: definition.manifest.id,
                    message: "Duplicate palette id was isolated."
                ))
                definitions.removeValue(forKey: definition.manifest.id)
            } else {
                definitions[definition.manifest.id] = definition
            }
        }

        if definitions[defaultPaletteID] == nil {
            diagnostics.append(PaletteDiagnostic(paletteID: defaultPaletteID, severity: .error, ruleID: "PAL001", relativePath: defaultPaletteID, message: "Default package is unavailable; using compiled safe defaults."))
        }
        return PaletteCatalog(definitions: definitions, diagnostics: diagnostics)
    }

    func contains(_ id: String) -> Bool {
        definitions[id] != nil
    }

    func descriptors(language: String) -> [PaletteDescriptor] {
        definitions.values.map { definition in
            let manifest = definition.manifest
            let preferredLocale = language.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
            let localization = definition.localizations[preferredLocale]
                ?? definition.localizations[manifest.defaultLocale]
                ?? PaletteLocalizationDTO(displayName: manifest.id, shortDescription: "", inspirationNote: "")
            return PaletteDescriptor(
                id: manifest.id,
                version: manifest.version,
                displayName: localization.displayName,
                shortDescription: localization.shortDescription,
                inspirationNote: localization.inspirationNote,
                isDefault: manifest.id == Self.defaultPaletteID
            )
        }.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    func resolve(id: String, appearance: PaletteAppearance) -> ResolvedVisualTokens {
        let requested = definitions[id] ?? definitions[Self.defaultPaletteID]
        guard let definition = requested else { return .safeDefault(appearance) }
        return PaletteResolver.resolve(definition: definition, appearance: appearance)
    }
}
