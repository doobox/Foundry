import SwiftUI

struct SpacePartControl: View {
    @Binding var value: PartSpaceValue
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            if value.isCustom {
                InspectorNumberField(value: amountBinding, range: 0...Double.greatestFiniteMagnitude,
                    accessibilityLabel: "\(label) custom value")
                Picker("Unit", selection: $value.unit) {
                    ForEach(PartSpaceValue.units, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("\(label) unit")
            } else {
                InspectorPopup(selection: $value.preset,
                    options: [.init(title: "Inherit", value: "inherit")] + SpacingTokens.standard.choices.map { choice in
                        .init(title: "\(choice.id) — \(choice.amount.formatted(.number.precision(.fractionLength(0...3))))rem", value: choice.id)
                    }, accessibilityLabel: label, help: label)
            }
            Button(action: toggleMode) {
                Image(systemName: "theatermask.and.paintbrush")
                    .foregroundStyle(value.isCustom ? Color.secondary : Color.accentColor)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(value.isCustom ? "Use Bootstrap space" : "Use custom space")
            .accessibilityLabel(value.isCustom ? "Use Bootstrap space" : "Use custom space")
        }
        .controlSize(.small)
    }

    private var amountBinding: Binding<Double> {
        Binding(get: { value.amount }, set: { value.amount = $0.isFinite ? max(0, $0) : 3.5 })
    }

    private func toggleMode() { value.isCustom.toggle() }
}
