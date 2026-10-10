import SwiftUI

struct InheritColourSwatch: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.3)) }
            .overlay { Image(systemName: "questionmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}
