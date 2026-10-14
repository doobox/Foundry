import SwiftUI

/// Uniform swatch for every choice in the Inspector colour popover.
struct ColourPickerSwatch: View {
    static let width: CGFloat = 36
    static let height: CGFloat = 28
    static let columns = Array(repeating: GridItem(.fixed(width), spacing: 8), count: 5)

    var preview: AdaptiveColourPreview?
    var isInherit = false
    var isSelected = false

    var body: some View {
        Group {
            if isInherit {
                InheritColourSwatch(width: Self.width, height: Self.height, cornerRadius: 6)
            } else {
                AdaptiveColourSwatch(preview: preview)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.tint, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}
