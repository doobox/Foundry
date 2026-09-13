import SwiftUI

struct NumberBlockControl: View {
    let label: String
    let range: ClosedRange<Double>
    let step: Double
    let unit: String?
    let indicator: InspectorRowIndicator?
    @Binding var value: Double

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            HStack(spacing: 6) {
                InspectorNumberField(value: $value, range: range, accessibilityLabel: label, help: label)
                InspectorStepper(value: $value, range: range, increment: step, accessibilityLabel: label)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var value = 24.0
    BlockControlPreview {
        NumberBlockControl(label: "Width", range: 0...100, step: 1, unit: "px", indicator: .preview, value: $value)
    }
}
