import SwiftUI

/// A row of clickable colour swatches with a label under each.
/// Shared by the theme, hue-scale and token colour rows in the theme editor.
struct ColourSwatchStrip: View {
    struct Swatch: Identifiable {
        let id: String
        let label: String
        let hex: String?
        var isEnabled = true
        let accessibilityLabel: String
        let help: String
    }

    let swatches: [Swatch]
    let select: (Swatch) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(swatches) { swatch in
                Button { select(swatch) } label: {
                    VStack(spacing: 4) {
                        Rectangle()
                            .fill(Color(hex: swatch.hex ?? "") ?? .clear)
                            .frame(height: 34)
                            .clipShape(shape(for: swatch))
                        Text(swatch.label)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!swatch.isEnabled || swatch.hex == nil)
                .accessibilityLabel(swatch.accessibilityLabel)
                .help(swatch.help)
            }
        }
    }

    /// Round only the outer ends so the swatches read as one strip.
    private func shape(for swatch: Swatch) -> UnevenRoundedRectangle {
        let leading: CGFloat = swatch.id == swatches.first?.id ? 6 : 0
        let trailing: CGFloat = swatch.id == swatches.last?.id ? 6 : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: leading,
            bottomLeadingRadius: leading,
            bottomTrailingRadius: trailing,
            topTrailingRadius: trailing)
    }
}
