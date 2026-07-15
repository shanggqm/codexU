import SwiftUI

struct PaletteSettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var descriptors: [PaletteDescriptor] {
        settings.paletteCatalog.descriptors(language: settings.language == .zh ? "zh-Hans" : "en")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 6) {
                ForEach(descriptors) { descriptor in
                    paletteButton(descriptor)
                }
            }
            if let notice = settings.paletteFallbackNotice {
                Text(settings.language.text("配色不可用，已恢复默认", "Palette unavailable; restored to default"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(FixedVisualPalette.statusWarning)
                    .help(notice.unavailableID)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(settings.language.text("配色", "Color palette"))
    }

    private func paletteButton(_ descriptor: PaletteDescriptor) -> some View {
        let selected = settings.paletteID == descriptor.id
        let tokens = settings.paletteCatalog.resolve(id: descriptor.id, appearance: PaletteAppearance(colorScheme))
        return Button {
            settings.selectPalette(descriptor.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    Circle().fill(tokens.quota.primary.start.color)
                    Circle().fill(tokens.quota.primary.end.color)
                    Circle().fill(tokens.quota.secondary.start.color)
                    Circle().fill(tokens.quota.secondary.end.color)
                }
                .frame(height: 10)

                Text(descriptor.displayName)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? tokens.selection.foreground.color : Color.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? tokens.selection.fill.color : FixedVisualPalette.controlFill(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? tokens.selection.stroke.color : FixedVisualPalette.controlStroke(colorScheme), lineWidth: selected ? 1.1 : 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(descriptor.shortDescription)
        .accessibilityLabel(descriptor.displayName)
        .accessibilityValue(selected ? settings.language.text("已选择", "Selected") : "")
    }
}
