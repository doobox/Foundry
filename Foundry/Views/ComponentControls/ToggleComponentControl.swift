import SwiftUI

struct ToggleComponentControl: View {
    let label: String
    let indicator: InspectorRowIndicator?
    @Binding var isOn: Bool

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            Toggle("", isOn: $isOn).labelsHidden()
        }
    }
}

#Preview {
    @Previewable @State var isOn = true
    ComponentControlPreview {
        ToggleComponentControl(label: "Enabled", indicator: .preview, isOn: $isOn)
    }
}
