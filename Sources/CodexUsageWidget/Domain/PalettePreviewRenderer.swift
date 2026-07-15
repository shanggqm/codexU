import AppKit
import SwiftUI

enum PalettePreviewRenderer {
    static func renderBuiltIns(to outputDirectory: URL) -> Bool {
        let catalog = PaletteCatalog.loadFromMainBundle()
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            for paletteID in [PaletteCatalog.defaultPaletteID, "codexu.blue-white-porcelain"] {
                for appearance in PaletteAppearance.allCases {
                    let tokens = catalog.resolve(id: paletteID, appearance: appearance)
                    let scheme: ColorScheme = appearance == .dark ? .dark : .light
                    let root = PalettePreviewCanvas()
                        .environment(\.visualTokens, tokens)
                        .environment(\.colorScheme, scheme)
                        .frame(width: 360, height: 230)
                    let host = NSHostingView(rootView: root)
                    host.frame = NSRect(x: 0, y: 0, width: 360, height: 230)
                    host.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
                    let name = "\(paletteID)-\(appearance.rawValue).png"
                    try png.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
                }
            }
            return true
        } catch {
            print("palette preview render failed: \(error.localizedDescription)")
            return false
        }
    }
}

private struct PalettePreviewCanvas: View {
    @Environment(\.visualTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                QuotaRingSegment(
                    percent: 93,
                    tokens: tokens.quota.primary,
                    ringAsset: tokens.assets[.quotaRingPrimary],
                    capAsset: tokens.assets[.quotaCapPrimary],
                    lineWidth: 16
                )
                .frame(width: 145, height: 145)
                QuotaRingSegment(
                    percent: 73,
                    tokens: tokens.quota.secondary,
                    ringAsset: tokens.assets[.quotaRingSecondary],
                    capAsset: tokens.assets[.quotaCapSecondary],
                    lineWidth: 16
                )
                .frame(width: 107, height: 107)
                VStack(spacing: 2) {
                    Text("5h  93%")
                    Text("7d  73%")
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(tokens.identity.paletteID == PaletteCatalog.defaultPaletteID ? "Default" : "青花瓷")
                    .font(.system(size: 16, weight: .semibold))
                QuotaValueProgressBar(currentValue: 5_300, maxValue: 46_500)
                    .frame(width: 150, height: 18)
                HStack(spacing: 5) {
                    ForEach(Array(tokens.data.series.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color.color).frame(width: 14, height: 14)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.primary)
        .background(colorScheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.11) : Color(red: 0.96, green: 0.97, blue: 0.98))
    }
}
