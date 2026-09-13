import SwiftUI

struct NoteBlockControl: View {
    let title: String?
    let text: String
    let systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title, !title.isEmpty {
                HStack(spacing: 6) {
                    if let systemImage, !systemImage.isEmpty {
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                }
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            } else if let systemImage, !systemImage.isEmpty {
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    BlockControlPreview {
        NoteBlockControl(
            title: "About Note controls",
            text: "Helpful information supplied by the block developer.",
            systemImage: "info.circle"
        )
    }
}
