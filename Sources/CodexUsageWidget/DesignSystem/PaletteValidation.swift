import AppKit
import Foundation

enum PaletteDiagnosticSeverity: String, Hashable {
    case warning
    case error
}

struct PaletteDiagnostic: Hashable {
    let paletteID: String?
    let severity: PaletteDiagnosticSeverity
    let ruleID: String
    let relativePath: String
    let message: String
}

struct PaletteValidationResult {
    let definition: ValidatedPaletteDefinition?
    let diagnostics: [PaletteDiagnostic]

    var isValid: Bool { definition != nil && !diagnostics.contains { $0.severity == .error } }
}

enum PaletteValidator {
    private static let maximumSVGBytes = 512 * 1024
    private static let maximumPackageBytes = 4 * 1024 * 1024
    private static let idPattern = try! NSRegularExpression(pattern: "^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
    private static let semverPattern = try! NSRegularExpression(pattern: "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    private static let capabilities: Set<String> = ["color-tokens", "svg-patterns", "lod-assets"]
    private static let sourceTypes: Set<String> = ["original", "original-design-translation", "licensed-derivative"]

    static func validate(packageURL: URL, appVersion: String, includeExperimental: Bool = false) -> PaletteValidationResult {
        let root = packageURL.standardizedFileURL
        var diagnostics: [PaletteDiagnostic] = []
        let decoder = JSONDecoder()

        func failure(_ rule: String, _ path: String, _ message: String, paletteID: String? = nil) {
            diagnostics.append(PaletteDiagnostic(paletteID: paletteID, severity: .error, ruleID: rule, relativePath: path, message: message))
        }

        guard !isSymbolicLink(root), let totalBytes = packageSize(root), totalBytes <= maximumPackageBytes else {
            failure("PAL009", ".", "Package is a symbolic link, unreadable, or exceeds 4 MiB.")
            return PaletteValidationResult(definition: nil, diagnostics: diagnostics)
        }

        guard let manifestURL = safeURL(relativePath: "manifest.json", root: root),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(PaletteManifestDTO.self, from: manifestData) else {
            failure("PAL001", "manifest.json", "Manifest is missing or cannot be decoded.")
            return PaletteValidationResult(definition: nil, diagnostics: diagnostics)
        }
        let paletteID = manifest.id

        for requiredFile in ["README.md", "LICENSE"] {
            guard let url = safeURL(relativePath: requiredFile, root: root),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty else {
                failure("PAL010", requiredFile, "Required package documentation is missing or empty.", paletteID: paletteID)
                continue
            }
        }
        for violation in packageContentViolations(root) {
            failure(violation.ruleID, violation.relativePath, violation.message, paletteID: paletteID)
        }

        if manifest.schemaVersion != 1 {
            failure("PAL002", "manifest.json", "Only schemaVersion 1 is supported.", paletteID: paletteID)
        }
        if !matches(idPattern, manifest.id) || manifest.id != root.lastPathComponent {
            failure("PAL003", "manifest.json", "Palette id is invalid or does not match its directory.", paletteID: paletteID)
        }
        if !isSemver(manifest.version) || !isSemver(manifest.minimumAppVersion) || compareVersions(manifest.minimumAppVersion, appVersion) == .orderedDescending {
            failure("PAL004", "manifest.json", "Package version metadata is invalid or requires a newer app.", paletteID: paletteID)
        }
        if manifest.lifecycle == .experimental && !includeExperimental {
            failure("PAL004", "manifest.json", "Experimental palettes are not loaded in production.", paletteID: paletteID)
        }
        if Set(manifest.variants.keys) != Set(PaletteAppearance.allCases.map(\.rawValue)) {
            failure("PAL005", "manifest.json", "Both and only light and dark variants are required.", paletteID: paletteID)
        }
        if !manifest.localizations.keys.contains("zh-Hans") || !manifest.localizations.keys.contains("en") || manifest.localizations[manifest.defaultLocale] == nil {
            failure("PAL010", "manifest.json", "zh-Hans, en, and the default locale are required.", paletteID: paletteID)
        }
        if manifest.author.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manifest.author.name.count > 80 {
            failure("PAL010", "manifest.json", "Author name is required and must be at most 80 characters.", paletteID: paletteID)
        }
        if let authorURL = manifest.author.url, URL(string: authorURL)?.scheme != "https" {
            failure("PAL010", "manifest.json", "Author URL must use HTTPS.", paletteID: paletteID)
        }
        if manifest.license != "MIT" || !sourceTypes.contains(manifest.source.type) || manifest.source.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failure("PAL010", "manifest.json", "License and source attribution are invalid.", paletteID: paletteID)
        }
        if !Set(manifest.capabilities).isSubset(of: capabilities) {
            failure("PAL010", "manifest.json", "Manifest declares an unknown capability.", paletteID: paletteID)
        }

        var variants: [PaletteAppearance: PaletteVariantDTO] = [:]
        for appearance in PaletteAppearance.allCases {
            guard let path = manifest.variants[appearance.rawValue],
                  let url = safeURL(relativePath: path, root: root),
                  let data = try? Data(contentsOf: url),
                  let variant = try? decoder.decode(PaletteVariantDTO.self, from: data) else {
                failure("PAL005", manifest.variants[appearance.rawValue] ?? "tokens/\(appearance.rawValue).json", "Variant is missing or invalid.", paletteID: paletteID)
                continue
            }
            let modelSeriesIsValid = variant.data.modelSeries.map { $0.count == 9 } ?? true
            if variant.data.series.count != 3 || !modelSeriesIsValid || variant.data.heatmap.count != 5 || variant.data.valueProgress.count != 3 || variant.data.milestones.count != 3 || !(0...0.12).contains(variant.surfaceTint.maximumOpacity) {
                failure("PAL006", path, "Token array lengths or surface tint opacity are invalid.", paletteID: paletteID)
            }
            variants[appearance] = variant
        }

        var localizations: [String: PaletteLocalizationDTO] = [:]
        for (locale, path) in manifest.localizations {
            guard let url = safeURL(relativePath: path, root: root),
                  let data = try? Data(contentsOf: url),
                  let value = try? decoder.decode(PaletteLocalizationDTO.self, from: data),
                  !value.displayName.isEmpty, !value.shortDescription.isEmpty, !value.inspirationNote.isEmpty else {
                failure("PAL010", path, "Localization is missing or incomplete.", paletteID: paletteID)
                continue
            }
            localizations[locale] = value
        }

        var assets: [PaletteAssetDescriptor] = []
        if let assetManifestURL = safeURL(relativePath: manifest.assetManifest, root: root),
           assetManifestURL.pathExtension == "json",
           let data = try? Data(contentsOf: assetManifestURL),
           let assetManifest = try? decoder.decode(PaletteAssetManifestDTO.self, from: data),
           assetManifest.version == 1 {
            var identities = Set<String>()
            for entry in assetManifest.assets {
                let identity = "\(entry.appearance.rawValue):\(entry.slot.rawValue)"
                guard identities.insert(identity).inserted else {
                    failure("PAL006", manifest.assetManifest, "Duplicate asset slot for an appearance.", paletteID: paletteID)
                    continue
                }
                let assetsRoot = assetManifestURL.deletingLastPathComponent()
                guard let url = safeURL(relativePath: entry.path, root: assetsRoot), url.pathExtension.lowercased() == "svg" else {
                    failure("PAL007", entry.path, "Asset path escapes the assets directory or is not SVG.", paletteID: paletteID)
                    continue
                }
                switch validateSVG(url: url) {
                case .success:
                    guard NSImage(contentsOf: url) != nil else {
                        failure("PAL011", relativePath(url, root: root), "SVG cannot be decoded by AppKit.", paletteID: paletteID)
                        continue
                    }
                    assets.append(PaletteAssetDescriptor(slot: entry.slot, appearance: entry.appearance, lod: entry.lod, url: url, renderMode: entry.renderMode, fallback: entry.fallback))
                case let .failure(message):
                    failure(message.ruleID, relativePath(url, root: root), message.message, paletteID: paletteID)
                }
            }
        } else {
            failure("PAL001", manifest.assetManifest, "Asset manifest is missing or invalid.", paletteID: paletteID)
        }

        guard !diagnostics.contains(where: { $0.severity == .error }), variants.count == 2 else {
            return PaletteValidationResult(definition: nil, diagnostics: diagnostics)
        }
        return PaletteValidationResult(
            definition: ValidatedPaletteDefinition(packageURL: root, manifest: manifest, variants: variants, localizations: localizations, assets: assets),
            diagnostics: diagnostics
        )
    }

    fileprivate struct SVGFailure: Error {
        let ruleID: String
        let message: String
    }

    private static func validateSVG(url: URL) -> Result<Void, SVGFailure> {
        guard !isSymbolicLink(url), let data = try? Data(contentsOf: url), data.count <= maximumSVGBytes,
              let source = String(data: data, encoding: .utf8) else {
            return .failure(SVGFailure(ruleID: "PAL009", message: "SVG is unreadable, linked, or exceeds 512 KiB."))
        }
        if source.range(of: "<!DOCTYPE", options: .caseInsensitive) != nil || source.range(of: "<!ENTITY", options: .caseInsensitive) != nil {
            return .failure(SVGFailure(ruleID: "PAL008", message: "DOCTYPE and entities are forbidden."))
        }
        let inspector = SafeSVGInspector()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = inspector
        guard parser.parse(), inspector.failure == nil else {
            return .failure(inspector.failure ?? SVGFailure(ruleID: "PAL008", message: "SVG XML is malformed."))
        }
        return .success(())
    }

    private static func safeURL(relativePath: String, root: URL) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else { return nil }
        let standardizedRoot = root.standardizedFileURL
        let result = standardizedRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard result.path == standardizedRoot.path || result.path.hasPrefix(standardizedRoot.path + "/"), !isSymbolicLink(result) else { return nil }
        return result
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func packageSize(_ root: URL) -> Int? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) else { return nil }
        var total = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { return nil }
            total += values.fileSize ?? 0
            if total > maximumPackageBytes { return total }
        }
        return total
    }

    private struct PackageContentViolation {
        let ruleID: String
        let relativePath: String
        let message: String
    }

    private static func packageContentViolations(_ root: URL) -> [PackageContentViolation] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return [PackageContentViolation(ruleID: "PAL009", relativePath: ".", message: "Package contents cannot be enumerated.")]
        }

        var violations: [PackageContentViolation] = []
        for case let url as URL in enumerator {
            let path = relativePath(url, root: root)
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else {
                violations.append(PackageContentViolation(ruleID: "PAL007", relativePath: path, message: "Symbolic links are forbidden in palette packages."))
                continue
            }
            if values.isDirectory == true {
                if !isAllowedPackageDirectory(path) {
                    violations.append(PackageContentViolation(ruleID: "PAL008", relativePath: path, message: "Directory is outside the Palette Package v1 layout."))
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else {
                violations.append(PackageContentViolation(ruleID: "PAL008", relativePath: path, message: "Only regular declarative resource files are allowed."))
                continue
            }
            if FileManager.default.isExecutableFile(atPath: url.path) {
                violations.append(PackageContentViolation(ruleID: "PAL008", relativePath: path, message: "Executable files are forbidden in palette packages."))
            } else if !isAllowedPackageFile(path) {
                violations.append(PackageContentViolation(ruleID: "PAL008", relativePath: path, message: "File type or location is outside the Palette Package v1 whitelist."))
            }
        }
        return violations
    }

    private static func isAllowedPackageDirectory(_ path: String) -> Bool {
        [
            "tokens",
            "localizations",
            "assets",
            "assets/light",
            "assets/dark",
            "assets/shared"
        ].contains(path)
    }

    private static func isAllowedPackageFile(_ path: String) -> Bool {
        if ["manifest.json", "README.md", "LICENSE", "tokens/light.json", "tokens/dark.json", "assets/manifest.json"].contains(path) {
            return true
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if components.count == 2, components[0] == "localizations", URL(fileURLWithPath: path).pathExtension == "json" {
            return true
        }
        if components.count == 3,
           components[0] == "assets",
           ["light", "dark", "shared"].contains(String(components[1])),
           URL(fileURLWithPath: path).pathExtension.lowercased() == "svg" {
            return true
        }
        return false
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private static func isSemver(_ value: String) -> Bool { matches(semverPattern, value) }

    private static func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let lhs = left.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = right.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}

private final class SafeSVGInspector: NSObject, XMLParserDelegate {
    private let allowedElements: Set<String> = [
        "svg", "defs", "g", "symbol", "use", "path", "circle", "rect", "ellipse", "line", "polyline", "polygon",
        "linearGradient", "radialGradient", "stop", "clipPath", "mask", "filter", "feGaussianBlur", "feTurbulence", "feColorMatrix", "feBlend"
    ]
    private let filterElements: Set<String> = ["feGaussianBlur", "feTurbulence", "feColorMatrix", "feBlend"]
    private(set) var failure: PaletteValidator.SVGFailure?
    private var elementCount = 0
    private var depth = 0
    private var filterCount = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard failure == nil else { parser.abortParsing(); return }
        elementCount += 1
        depth += 1
        if filterElements.contains(elementName) { filterCount += 1 }
        guard allowedElements.contains(elementName), elementCount <= 4096, depth <= 32, filterCount <= 32 else {
            failure = PaletteValidator.SVGFailure(ruleID: elementCount > 4096 || depth > 32 || filterCount > 32 ? "PAL009" : "PAL008", message: "SVG uses a forbidden element or exceeds complexity limits.")
            parser.abortParsing()
            return
        }
        for (name, value) in attributeDict {
            let lowerName = name.lowercased()
            let lowerValue = value.lowercased()
            if lowerName == "xmlns" || lowerName.hasPrefix("xmlns:") {
                continue
            }
            if lowerName.hasPrefix("on") || lowerValue.contains("javascript:") || lowerValue.contains("http:") || lowerValue.contains("https:") || lowerValue.contains("file:") || lowerValue.contains("data:") {
                failure = PaletteValidator.SVGFailure(ruleID: "PAL008", message: "SVG contains an event handler or external reference.")
                parser.abortParsing()
                return
            }
            if lowerName == "href" || lowerName == "xlink:href" {
                if !value.hasPrefix("#") {
                    failure = PaletteValidator.SVGFailure(ruleID: "PAL008", message: "SVG href must reference a local symbol.")
                    parser.abortParsing()
                    return
                }
            }
            if lowerValue.contains("url(") && !lowerValue.contains("url(#") {
                failure = PaletteValidator.SVGFailure(ruleID: "PAL008", message: "SVG url() must reference a local definition.")
                parser.abortParsing()
                return
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        depth = max(0, depth - 1)
    }
}
