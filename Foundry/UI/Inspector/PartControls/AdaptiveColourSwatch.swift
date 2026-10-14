import SwiftUI

struct AdaptiveColourSwatch: View {
    let preview: AdaptiveColourPreview?
    var cornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            Color(hex: preview?.light ?? "") ?? .gray
            Color(hex: preview?.dark ?? "") ?? .gray
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5)
        }
    }
}
