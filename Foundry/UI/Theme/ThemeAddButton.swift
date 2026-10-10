import SwiftUI

/// A small plus icon with a full rectangular pointer target.
struct ThemeAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
