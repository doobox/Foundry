import SwiftUI

/// The theme symbol button that switches a spacing control between theme tokens and
/// raw custom values — shared so the single spacing row and the box-model editors
/// stay visually identical.
struct ThemeModeToggle: View {
    let usesThemeTokens: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "theatermask.and.paintbrush")
                .imageScale(.large)
                .foregroundStyle(usesThemeTokens ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use theme values")
        .accessibilityAddTraits(usesThemeTokens ? .isSelected : [])
        .animation(.easeInOut(duration: 0.15), value: usesThemeTokens)
        .help(usesThemeTokens ? "Switch to custom values" : "Switch to theme values")
    }
}
