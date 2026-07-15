import AppKit
import SwiftUI

final class PaletteAssetStore {
    static let shared = PaletteAssetStore()

    private let images: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    func image(for descriptor: PaletteAssetDescriptor) -> NSImage? {
        let key = descriptor.url as NSURL
        if let image = images.object(forKey: key) { return image }
        guard let image = NSImage(contentsOf: descriptor.url) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}

struct PaletteRingArtwork: View {
    let descriptor: PaletteAssetDescriptor
    let progress: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        if let image = PaletteAssetStore.shared.image(for: descriptor) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .mask(
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

struct PaletteRingCap: View {
    let descriptor: PaletteAssetDescriptor
    let progress: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            if let image = PaletteAssetStore.shared.image(for: descriptor), progress > 0.001 {
                let radius = (min(proxy.size.width, proxy.size.height) - lineWidth) / 2
                let angle = Double(progress) * 2 * Double.pi - Double.pi / 2
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: lineWidth + 2, height: lineWidth + 2)
                    .position(
                        x: proxy.size.width / 2 + radius * cos(angle),
                        y: proxy.size.height / 2 + radius * sin(angle)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct PaletteAssetFill: View {
    let descriptor: PaletteAssetDescriptor

    var body: some View {
        if let image = PaletteAssetStore.shared.image(for: descriptor) {
            switch descriptor.renderMode {
            case .tileX, .tileY:
                Image(nsImage: image)
                    .resizable(resizingMode: .tile)
                    .interpolation(.high)
            case .fullRing, .fixed:
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            }
        }
    }
}
