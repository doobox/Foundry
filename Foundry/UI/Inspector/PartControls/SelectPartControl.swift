import SwiftUI

struct SelectPartControl: View {
    let label: String
    let options: [InspectorPopupOption<String>]
    let indicator: InspectorRowIndicator?
    @Binding var selection: String

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            InspectorPopup(selection: $selection, options: options, accessibilityLabel: label, help: label)
        }
    }
}

#Preview {
    @Previewable @State var selection = "center"
    PartControlPreview {
        SelectPartControl(
            label: "Alignment",
            options: [
                .init(title: "Leading", value: "leading"),
                .init(title: "Centre", value: "center"),
                .init(title: "Trailing", value: "trailing")
            ],
            indicator: .preview,
            selection: $selection
        )
    }
}
