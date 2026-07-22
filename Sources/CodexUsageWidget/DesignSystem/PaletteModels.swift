import AppKit
import SwiftUI

struct PaletteColor: Codable, Hashable, CustomStringConvertible {
    let rgba: UInt32

    init(hex: String) throws {
        guard hex.first == "#", hex.count == 7 || hex.count == 9 else {
            throw PaletteModelError.invalidColor(hex)
        }
        let digits = String(hex.dropFirst())
        guard let parsed = UInt32(digits, radix: 16) else {
            throw PaletteModelError.invalidColor(hex)
        }
        rgba = digits.count == 6 ? (parsed << 8) | 0xFF : parsed
    }

    init(rgba: UInt32) {
        self.rgba = rgba
    }

    init(from decoder: Decoder) throws {
        try self.init(hex: decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var description: String {
        String(format: "#%08X", rgba)
    }

    var red: Double { Double((rgba >> 24) & 0xFF) / 255 }
    var green: Double { Double((rgba >> 16) & 0xFF) / 255 }
    var blue: Double { Double((rgba >> 8) & 0xFF) / 255 }
    var alpha: Double { Double(rgba & 0xFF) / 255 }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

enum PaletteModelError: LocalizedError {
    case invalidColor(String)

    var errorDescription: String? {
        switch self {
        case let .invalidColor(value): "Invalid palette color: \(value)"
        }
    }
}

enum PaletteAppearance: String, Codable, CaseIterable, Hashable {
    case light
    case dark

    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

enum PaletteLifecycle: String, Codable, Hashable {
    case experimental
    case stable
    case deprecated
}

enum PaletteAssetSlot: String, Codable, CaseIterable, Hashable {
    case quotaRingPrimary = "quota.ring.primary"
    case quotaRingSecondary = "quota.ring.secondary"
    case quotaCapPrimary = "quota.cap.primary"
    case quotaCapSecondary = "quota.cap.secondary"
    case progressLinear = "progress.linear"
    case chartBar = "chart.bar"
}

enum PaletteAssetLOD: String, Codable, Hashable {
    case l0
    case l1
    case l2
}

enum PaletteAssetRenderMode: String, Codable, Hashable {
    case fullRing
    case tileX
    case tileY
    case fixed
}

struct PaletteAuthorDTO: Codable, Hashable {
    let name: String
    let url: String?
}

struct PaletteSourceDTO: Codable, Hashable {
    let type: String
    let note: String
}

struct PaletteManifestDTO: Codable, Hashable {
    let schemaVersion: Int
    let id: String
    let version: String
    let minimumAppVersion: String
    let lifecycle: PaletteLifecycle
    let defaultLocale: String
    let localizations: [String: String]
    let variants: [String: String]
    let assetManifest: String
    let author: PaletteAuthorDTO
    let license: String
    let source: PaletteSourceDTO
    let capabilities: [String]
}

struct PaletteLocalizationDTO: Codable, Hashable {
    let displayName: String
    let shortDescription: String
    let inspirationNote: String
}

struct AccentTokenSet: Codable, Hashable {
    let primary: PaletteColor
    let primaryStrong: PaletteColor
    let primaryLight: PaletteColor
    let secondary: PaletteColor
    let secondaryStrong: PaletteColor
    let highlight: PaletteColor
}

struct QuotaRoleTokenSet: Codable, Hashable {
    let start: PaletteColor
    let end: PaletteColor
    let track: PaletteColor
    let label: PaletteColor
}

struct QuotaTokenSet: Codable, Hashable {
    let primary: QuotaRoleTokenSet
    let secondary: QuotaRoleTokenSet
}

struct DataTokenSet: Codable, Hashable {
    let series: [PaletteColor]
    let modelSeries: [PaletteColor]?
    let tokenInput: PaletteColor
    let tokenCached: PaletteColor
    let tokenOutput: PaletteColor
    let heatmap: [PaletteColor]
    let zero: PaletteColor
    let valueProgress: [PaletteColor]
    let milestones: [PaletteColor]
}

struct SelectionTokenSet: Codable, Hashable {
    let foreground: PaletteColor
    let fill: PaletteColor
    let stroke: PaletteColor
    let focusRing: PaletteColor
}

struct SurfaceTintTokenSet: Codable, Hashable {
    let color: PaletteColor
    let maximumOpacity: Double
}

struct OrnamentTokenSet: Codable, Hashable {
    let ink: PaletteColor
    let inkSoft: PaletteColor
    let secondaryInk: PaletteColor
    let highlight: PaletteColor
    let metal: PaletteColor
}

struct PaletteVariantDTO: Codable, Hashable {
    let accent: AccentTokenSet
    let quota: QuotaTokenSet
    let data: DataTokenSet
    let selection: SelectionTokenSet
    let surfaceTint: SurfaceTintTokenSet
    let ornament: OrnamentTokenSet
}

struct PaletteAssetEntryDTO: Codable, Hashable {
    let slot: PaletteAssetSlot
    let appearance: PaletteAppearance
    let lod: PaletteAssetLOD
    let path: String
    let renderMode: PaletteAssetRenderMode
    let fallback: String
}

struct PaletteAssetManifestDTO: Codable, Hashable {
    let version: Int
    let assets: [PaletteAssetEntryDTO]
}

struct PaletteAssetDescriptor: Hashable {
    let slot: PaletteAssetSlot
    let appearance: PaletteAppearance
    let lod: PaletteAssetLOD
    let url: URL
    let renderMode: PaletteAssetRenderMode
    let fallback: String
}

struct ValidatedPaletteDefinition: Hashable {
    let packageURL: URL
    let manifest: PaletteManifestDTO
    let variants: [PaletteAppearance: PaletteVariantDTO]
    let localizations: [String: PaletteLocalizationDTO]
    let assets: [PaletteAssetDescriptor]
}

struct PaletteDescriptor: Identifiable, Hashable {
    let id: String
    let version: String
    let displayName: String
    let shortDescription: String
    let inspirationNote: String
    let authorName: String
    let sourceType: String
    let lifecycle: PaletteLifecycle
    let isOfficial: Bool
    let isDefault: Bool
}

struct PaletteRenderIdentity: Hashable {
    let paletteID: String
    let packageVersion: String
    let appearance: PaletteAppearance
}

struct ResolvedVisualTokens: Hashable {
    let identity: PaletteRenderIdentity
    let accent: AccentTokenSet
    let quota: QuotaTokenSet
    let data: DataTokenSet
    let selection: SelectionTokenSet
    let surfaceTint: SurfaceTintTokenSet
    let ornament: OrnamentTokenSet
    let assets: [PaletteAssetSlot: PaletteAssetDescriptor]

    static func safeDefault(_ appearance: PaletteAppearance) -> ResolvedVisualTokens {
        let accent = AccentTokenSet(
            primary: PaletteColor(rgba: 0x2866F7FF),
            primaryStrong: PaletteColor(rgba: 0x1F59EDFF),
            primaryLight: PaletteColor(rgba: 0x7BA0FFFF),
            secondary: PaletteColor(rgba: 0x8B6DFFFF),
            secondaryStrong: PaletteColor(rgba: 0x6D45E8FF),
            highlight: PaletteColor(rgba: 0xDAA3FAFF)
        )
        return ResolvedVisualTokens(
            identity: PaletteRenderIdentity(paletteID: PaletteCatalog.defaultPaletteID, packageVersion: "safe-default", appearance: appearance),
            accent: accent,
            quota: QuotaTokenSet(
                primary: QuotaRoleTokenSet(start: accent.primaryLight, end: accent.primary, track: PaletteColor(rgba: 0x2866F71A), label: accent.primary),
                secondary: QuotaRoleTokenSet(start: accent.highlight, end: accent.secondary, track: PaletteColor(rgba: 0x8B6DFF1A), label: accent.secondary)
            ),
            data: DataTokenSet(
                series: [accent.primary, accent.secondary, accent.highlight],
                modelSeries: [
                    accent.primary,
                    accent.secondary,
                    accent.highlight,
                    PaletteColor(rgba: 0x2AA198FF),
                    PaletteColor(rgba: 0xE07A5FFF),
                    PaletteColor(rgba: 0xD4A72CFF),
                    PaletteColor(rgba: 0x5C9DEDFF),
                    PaletteColor(rgba: 0xB04A8FFF),
                    PaletteColor(rgba: 0x6FAE75FF)
                ],
                tokenInput: PaletteColor(rgba: 0x0A84FFFF),
                tokenCached: accent.secondary,
                tokenOutput: PaletteColor(rgba: 0xFF9F0AFF),
                heatmap: [PaletteColor(rgba: 0x0000001A), PaletteColor(rgba: 0x2866F747), PaletteColor(rgba: 0x2866F775), PaletteColor(rgba: 0x2866F7B3), PaletteColor(rgba: 0x2866F7F5)],
                zero: PaletteColor(rgba: 0x98989D59),
                valueProgress: [accent.primaryLight, accent.primary, accent.secondaryStrong],
                milestones: [accent.primary, accent.secondary, accent.highlight]
            ),
            selection: SelectionTokenSet(foreground: accent.primary, fill: PaletteColor(rgba: 0x2866F71F), stroke: PaletteColor(rgba: 0x2866F757), focusRing: PaletteColor(rgba: 0x2866F7A6)),
            surfaceTint: SurfaceTintTokenSet(color: accent.primary, maximumOpacity: 0.08),
            ornament: OrnamentTokenSet(ink: accent.primary, inkSoft: accent.primaryLight, secondaryInk: accent.secondary, highlight: PaletteColor(rgba: 0xFFFFFFFF), metal: PaletteColor(rgba: 0xD2B27BFF)),
            assets: [:]
        )
    }
}
