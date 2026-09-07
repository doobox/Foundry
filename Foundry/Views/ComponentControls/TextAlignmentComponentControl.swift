import SwiftUI

struct TextAlignmentComponentControl: View {
    let label: String
    let segments: [InspectorSegment<String>]
    let indicator: InspectorRowIndicator?
    @Binding var selection: String

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            InspectorSegmentedControl(selection: $selection, segments: segments)
        }
    }
}

#Preview {
    @Previewable @State var selection = "center"
    ComponentControlPreview {
        TextAlignmentComponentControl(
            label: "Text alignment",
            segments: [
                .init(value: "left", systemImage: "text.alignleft", accessibilityLabel: "Left"),
                .init(value: "center", systemImage: "text.aligncenter", accessibilityLabel: "Centre"),
                .init(value: "right", systemImage: "text.alignright", accessibilityLabel: "Right")
            ],
            indicator: .preview,
            selection: $selection
        )
    }
}
