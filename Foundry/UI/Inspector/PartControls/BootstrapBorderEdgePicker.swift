import SwiftUI

/// Uses the shared edge widget, with native Bootstrap border presence choices.
struct BootstrapBorderEdgePicker<Policy: ThemeSpacingPolicy>: View {
    @Binding var value: ThemeSpacingValue<Policy>.EdgeValue
    let title: String

    var body: some View {
        Picker(title, selection: $value.token) {
            Text("Inherit").tag("none")
            Text("Border").tag("1")
            Text("No border").tag("0")
        }
        .pickerStyle(.menu)
        .buttonSizing(.flexible)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title) border")
    }
}
