import SwiftUI

/// Theme scales can have hundreds of steps. Snap values without constructing
/// a native tick mark for each step.
struct ThemeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        Slider(value: snappedValue, in: range)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: snappedValue.wrappedValue = value + step
                case .decrement: snappedValue.wrappedValue = value - step
                @unknown default: break
                }
            }
    }

    private var snappedValue: Binding<Double> {
        Binding(get: { value }, set: { rawValue in
            let resolved = InspectorSliderValueResolver.resolve(rawValue, range: range, step: step)
            if resolved != value { value = resolved }
        })
    }
}
