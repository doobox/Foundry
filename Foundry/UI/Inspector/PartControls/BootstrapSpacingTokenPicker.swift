import SwiftUI

struct BootstrapSpacingTokenPicker<Policy: ThemeSpacingPolicy>: View {
    @Binding var binding: ThemeSpacingValue<Policy>.EdgeValue
    let title: String
    let classPrefix: String
    let spacing: SpacingTokens

    var body: some View {
        Picker(title, selection: $binding.token) {
            Text("Inherit").tag("none")
            Section("Bootstrap") {
                ForEach(SpacingTokens.standard.choices) { size in
                    Text("\(classPrefix)-\(size.id) — \(size.amount.formatted(.number.precision(.fractionLength(0...4))))rem").tag(size.id)
                }
                if Policy.allowsAutoAndNegative {
                    Text("\(classPrefix)-auto").tag("auto")
                }
            }
            if !spacing.custom.isEmpty {
                Section("Custom") {
                    ForEach(spacing.custom) { size in
                        Text("\(classPrefix)-\(size.name) — \(size.value.formatted(.number.precision(.fractionLength(0...4))))rem").tag(size.name)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .buttonSizing(.flexible)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title) \(Policy.label.lowercased())")
    }

}
