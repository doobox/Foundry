import SwiftUI

struct InheritColourSwatch: View {
    var width: CGFloat = 20
    var height: CGFloat = 20
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5) }
            .overlay { Image(systemName: "questionmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
