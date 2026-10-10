import SwiftUI

struct FrameworkSpacingCustomInput<Policy: FrameworkSpacingPolicy>: View {
    let binding: Binding<FrameworkSpacingValue<Policy>.EdgeValue>
    let title: String
    let focusNamespace: Namespace.ID
    var unitChoices: [String]? = nil
    @Environment(\.resetFocus) private var resetFocus

    var body: some View {
        HStack(spacing: 2) {
            TextField(
                title,
                value: amountBinding,
                format: .number.precision(.fractionLength(0...2))
            )
            .controlSize(.small)
            .textFieldStyle(.roundedBorder)
            .onSubmit { resetFocus(in: focusNamespace) }
            .accessibilityLabel("\(title) custom \(Policy.label.lowercased())")

            Menu {
                ForEach(unitChoices ?? Policy.units, id: \.self) { unit in
                    Button {
                        binding.wrappedValue.unit = unit
                    } label: {
                        if unit == binding.wrappedValue.unit {
                            Label(unit, systemImage: "checkmark")
                        } else {
                            Text(unit)
                        }
                    }
                }
            } label: {
                Text(binding.wrappedValue.unit)
                    .monospaced()
                    .frame(width: 28, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .accessibilityLabel("\(title) \(Policy.label.lowercased()) unit")
        }
    }

    private var amountBinding: Binding<Double> {
        Binding(
            get: { binding.wrappedValue.amount },
            set: { newValue in
                binding.wrappedValue.amount = sanitized(newValue)
            }
        )
    }

    private func sanitized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Policy.allowsAutoAndNegative ? value : max(0, value)
    }
}
