import SwiftUI

struct TextBlockControl: View {
    let label: String
    let indicator: InspectorRowIndicator?
    @Binding var text: String

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            InspectorTextField(text: $text, accessibilityLabel: label, help: label)
        }
    }
}

#Preview("Text") {
    @Previewable @State var text = "Editable text"
    BlockControlPreview {
        TextBlockControl(label: "Text", indicator: .preview, text: $text)
    }
}

#Preview("Text area") {
    @Previewable @State var text = "A longer editable value that can span multiple lines."
    BlockControlPreview {
        TextAreaBlockControl(label: "Content", indicator: .preview, text: $text)
    }
}

struct TextAreaBlockControl: View {
    let label: String
    let indicator: InspectorRowIndicator?
    @Binding var text: String

    var body: some View {
        InspectorRow(title: label, alignment: .top, indicator: indicator) {
            TextEditor(text: $text)
                .frame(minHeight: 72)
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
        }
    }
}
