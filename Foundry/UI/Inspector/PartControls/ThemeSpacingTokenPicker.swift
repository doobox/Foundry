import SwiftUI

struct ThemeSpacingTokenPicker<Policy: ThemeSpacingPolicy>: View {
    let binding: Binding<ThemeSpacingValue<Policy>.EdgeValue>
    let title: String
    let options: [ThemeEdgeChoice]

    var body: some View {
        Picker(title, selection: selectionBinding) {
            Text("None").tag("none")

            if Policy.allowsAutoAndNegative {
                Text("Auto").tag("auto")
            }

            if hasMissingSelection {
                Text("Missing value").tag(binding.wrappedValue.token)
            }

            if !customOptions.isEmpty {
                Section("Custom") {
                    ForEach(customOptions) { option in
                        optionText(option)
                    }
                }
            }

            Section("Theme values") {
                ForEach(predefinedOptions) { option in
                    optionText(option)
                }
            }
        }
        .pickerStyle(.menu)
        .buttonSizing(.flexible)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title) \(Policy.label.lowercased())")
    }

    private var customOptions: [ThemeEdgeChoice] {
        options.filter { $0.id.hasPrefix("custom:") }
    }

    private var predefinedOptions: [ThemeEdgeChoice] {
        options.filter { !$0.id.hasPrefix("custom:") }
    }

    private func optionText(_ option: ThemeEdgeChoice) -> some View {
        Text("\(option.label) - \(formatted(option.amount))\(Policy.themeUnit)")
            .tag(option.id)
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { binding.wrappedValue.token },
            set: { binding.wrappedValue.token = $0 }
        )
    }

    private var hasMissingSelection: Bool {
        let token = binding.wrappedValue.token
        guard token != "none", !(Policy.allowsAutoAndNegative && token == "auto") else {
            return false
        }
        return !options.contains { $0.id == token }
    }

    private func formatted(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...3)))
    }
}
