import SwiftUI

struct SliderBlockControl: View {
    let label: String
    let range: ClosedRange<Double>
    let step: Double
    let ticks: Int
    let unit: String?
    let showsValueField: Bool
    let indicator: InspectorRowIndicator?
    @Binding var value: Double

    var body: some View {
        InspectorRow(title: label, alignment: .center, indicator: indicator) {
            HStack(spacing: 8) {
                InspectorSlider(
                    value: $value,
                    range: range,
                    step: step,
                    tickMarkCount: ticks,
                    accessibilityLabel: label,
                    help: label
                )
                if showsValueField {
                    InspectorNumberField(
                        value: $value,
                        range: range,
                        step: step,
                        accessibilityLabel: "\(label) value",
                        help: label
                    )
                    .frame(width: 64)
                    if let unit, !unit.isEmpty {
                        Text(unit).foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var value = 48.0
    BlockControlPreview {
        SliderBlockControl(
            label: "Opacity",
            range: 0...100,
            step: 1,
            ticks: 0,
            unit: "%",
            showsValueField: true,
            indicator: .preview,
            value: $value
        )
    }
}
