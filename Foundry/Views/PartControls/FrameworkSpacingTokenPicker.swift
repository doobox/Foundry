import SwiftUI

struct FrameworkSpacingTokenPicker<Policy: FrameworkSpacingPolicy>: View {
    let binding: Binding<FrameworkSpacingValue<Policy>.EdgeValue>
    let title: String
    let options: [FrameworkEdgeChoice]

    var body: some View {
        Picker(title, selection: selectionBinding) {
            Text("None - 0").tag("none")

            if Policy.allowsAutoAndNegative {
                Text("Auto").tag("auto")
            }

            if hasMissingSelection {
                Text("Missing value").tag(binding.wrappedValue.token)
            }

            Section("Framework values") {
                ForEach(options) { option in
                    Text("\(option.label) - \(formatted(option.amount))\(Policy.frameworkUnit)")
                        .tag(option.id)
                }
            }
        }
        .pickerStyle(.menu)
        .buttonSizing(.flexible)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title) \(Policy.label.lowercased())")
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
