import AppKit
import SwiftUI

struct PartClassToken: View {
    let name: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)

            Button("Remove \(name)", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("Remove \(name)")
        }
        .font(.body)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlColor), in: Capsule())
    }
}
