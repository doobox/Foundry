import SwiftUI

struct FrameworkSpacingStepRow: View {
    let step: Int
    let amount: Double
    let editor: ProjectEditor
    @State private var value = 0.0

    var body: some View {
        HStack(spacing: 14) {
            Text(String(step)).fontWeight(.medium).frame(width: 120, alignment: .leading)
            Slider(value: $value, in: 0...max(12, amount), step: 0.125)
                .accessibilityLabel("Spacing \(step)")
            FrameworkNumberField(title: "Spacing \(step)", value: $value, unit: "rem", step: 0.125, precision: 3)
        }
        .padding(.vertical, 8)
        .onAppear { value = amount }
        .onChange(of: amount) { _, updated in value = updated }
        .onChange(of: value) { _, updated in
            if updated.isFinite && updated >= 0 { editor.setBootstrapSpacing(step, value: updated) }
            else { value = amount }
        }
    }
}
