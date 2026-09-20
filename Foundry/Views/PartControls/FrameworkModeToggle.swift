import SwiftUI

/// The shippingbox button that switches a spacing control between framework tokens and
/// raw custom values — shared so the single spacing row and the box-model editors
/// stay visually identical.
struct FrameworkModeToggle: View {
    let usesFrameworkTokens: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: usesFrameworkTokens ? "shippingbox.fill" : "shippingbox")
                .imageScale(.large)
                .foregroundStyle(usesFrameworkTokens ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use framework values")
        .accessibilityAddTraits(usesFrameworkTokens ? .isSelected : [])
        .animation(.easeInOut(duration: 0.15), value: usesFrameworkTokens)
        .help(usesFrameworkTokens ? "Switch to custom values" : "Switch to framework values")
    }
}
