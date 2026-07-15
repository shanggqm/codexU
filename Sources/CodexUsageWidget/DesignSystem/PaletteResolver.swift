import Foundation

enum PaletteResolver {
    static func resolve(definition: ValidatedPaletteDefinition, appearance: PaletteAppearance) -> ResolvedVisualTokens {
        guard let variant = definition.variants[appearance] else {
            return .safeDefault(appearance)
        }
        var assets: [PaletteAssetSlot: PaletteAssetDescriptor] = [:]
        for asset in definition.assets where asset.appearance == appearance {
            assets[asset.slot] = asset
        }
        return ResolvedVisualTokens(
            identity: PaletteRenderIdentity(
                paletteID: definition.manifest.id,
                packageVersion: definition.manifest.version,
                appearance: appearance
            ),
            accent: variant.accent,
            quota: variant.quota,
            data: variant.data,
            selection: variant.selection,
            surfaceTint: variant.surfaceTint,
            ornament: variant.ornament,
            assets: assets
        )
    }
}
