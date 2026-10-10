import SwiftUI

struct TogglePartControl: View {
    let label: String
    let indicator: InspectorRowIndicator?
    @Binding var isOn: Bool
    var usesSwitch = false

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            if usesSwitch {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            } else {
                Toggle("", isOn: $isOn).labelsHidden()
            }
        }
    }
}

#Preview {
    @Previewable @State var isOn = true
    PartControlPreview {
        TogglePartControl(label: "Enabled", indicator: .preview, isOn: $isOn)
    }
}
