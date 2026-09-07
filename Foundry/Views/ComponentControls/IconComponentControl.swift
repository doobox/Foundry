import SwiftUI

struct IconComponentControl: View {
    let label: String
    let indicator: InspectorRowIndicator?
    @Binding var selection: String

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            FoundryIconPicker(selection: $selection, accessibilityLabel: label)
        }
    }
}

#Preview {
    @Previewable @State var selection = "star"
    ComponentControlPreview {
        IconComponentControl(label: "Icon", indicator: .preview, selection: $selection)
    }
}
