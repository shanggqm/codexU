import SwiftUI

private struct VisualTokensEnvironmentKey: EnvironmentKey {
    static let defaultValue = ResolvedVisualTokens.safeDefault(.light)
}

extension EnvironmentValues {
    var visualTokens: ResolvedVisualTokens {
        get { self[VisualTokensEnvironmentKey.self] }
        set { self[VisualTokensEnvironmentKey.self] = newValue }
    }
}

extension View {
    func appVisualEnvironment(catalog: PaletteCatalog, paletteID: String, appearance: PaletteAppearance) -> some View {
        environment(\.visualTokens, catalog.resolve(id: paletteID, appearance: appearance))
    }
}
