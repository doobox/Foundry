import SwiftUI

struct ThemeFontSizeComponentControl: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    @Binding var source: String
    @Binding var customValue: String
    @Binding var customLineHeight: String
    let indicator: InspectorRowIndicator

    var body: some View {
        if !choices.isEmpty {
            InspectorRow(title: label, indicator: indicator) {
                InspectorPopup(selection: $source, options: popupOptions, accessibilityLabel: label, help: label)
            }
        }
        if ComponentThemeValueSelection.isManualCustom(source) || choices.isEmpty {
            InspectorRow(title: "Size", indicator: choices.isEmpty ? indicator : nil) {
                InspectorTextField(text: $customValue, accessibilityLabel: "Size")
            }
            InspectorRow(title: "Line Height") {
                InspectorTextField(text: $customLineHeight, accessibilityLabel: "Line Height")
            }
        }
    }

    private var popupOptions: [InspectorPopupOption<String>] {
        choices.map {
            .init(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
        } + [.init(
            title: "Custom",
            value: ComponentThemeValueSelection.manualCustom,
            separatorBefore: !choices.isEmpty
        )]
    }
}

#Preview {
    @Previewable @State var source = ComponentThemeValueSelection.manualCustom
    @Previewable @State var size = "1.25rem"
    @Previewable @State var lineHeight = "1.5"
    ComponentControlPreview {
        ThemeFontSizeComponentControl(
            label: "Font size",
            choices: Theme.standard.fontSizeChoices,
            source: $source,
            customValue: $size,
            customLineHeight: $lineHeight,
            indicator: .preview
        )
    }
}
