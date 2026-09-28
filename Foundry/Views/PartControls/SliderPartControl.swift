import SwiftUI

struct SliderPartControl: View {
    let label: String
    let options: SliderOptions
    let indicator: InspectorRowIndicator?
    @Binding var value: Double

    var body: some View {
        InspectorRow(title: label, alignment: .sliderTrack, indicator: indicator) {
            HStack(alignment: .sliderTrack, spacing: 8) {
                InspectorSlider(
                    value: $value,
                    options: options,
                    accessibilityLabel: label,
                    help: label
                )
                if options.editableValue {
                    InspectorNumberField(
                        value: $value,
                        range: options.range,
                        step: options.step,
                        accessibilityLabel: "\(label) value",
                        help: label
                    )
                    .frame(width: 64)
                    if !options.unit.isEmpty {
                        Text(options.unit).foregroundStyle(.secondary).fixedSize()
                    }
                } else {
                    InspectorSliderValueLabel(value: value, options: options, unit: options.unit)
                }
            }
        }
    }
}

/// The read-only value shown beside a slider when the value is not editable.
///
/// The label reserves the width of the widest text it can show, so dragging
/// the slider never resizes it or shifts the slider's track.
struct InspectorSliderValueLabel: View {
    let value: Double
    let options: SliderOptions
    let unit: String

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(formatted(options.range.lowerBound)).hidden()
            Text(formatted(options.range.upperBound)).hidden()
            ForEach(options.valueLabels, id: \.value) { label in
                Text(label.text).hidden()
            }
            Text(options.valueLabel(for: value) ?? formatted(value))
        }
        .monospacedDigit()
        .fixedSize()
        .accessibilityHidden(true)
    }

    /// Shows as many decimal places as the step needs: a step of 1 shows
    /// whole numbers, 0.1 one place, 0.25 two places.
    private var fractionDigits: Int {
        guard options.step > 0 else { return 0 }
        return (0...3).first { digits in
            let scaled = options.step * pow(10, Double(digits))
            return abs(scaled - scaled.rounded()) < 0.000_001
        } ?? 3
    }

    private func formatted(_ number: Double) -> String {
        let text = number.formatted(.number.precision(.fractionLength(fractionDigits)))
        guard !unit.isEmpty else { return text }
        // Symbols sit against the number; words take a space.
        return unit == "%" || unit == "°" ? text + unit : "\(text) \(unit)"
    }
}

#Preview {
    @Previewable @State var value = 48.0
    @Previewable @State var rows = 0.0
    PartControlPreview {
        SliderPartControl(
            label: "Opacity",
            options: SliderOptions(range: 0...100, step: 1, unit: "%"),
            indicator: .preview,
            value: $value
        )
        SliderPartControl(
            label: "Rows",
            options: SliderOptions(
                range: 0...12,
                step: 1,
                tickLabels: [.init(value: 0, text: "Auto"), .init(value: 6, text: "6"), .init(value: 12, text: "12")],
                valueLabels: [.init(value: 0, text: "Auto")]
            ),
            indicator: .preview,
            value: $rows
        )
        SliderPartControl(
            label: "Blur",
            options: SliderOptions(range: 0...40, step: 0.5, unit: "px", editableValue: true),
            indicator: .preview,
            value: $value
        )
    }
}
