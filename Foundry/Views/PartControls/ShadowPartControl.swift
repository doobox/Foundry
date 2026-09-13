import SwiftUI

struct ShadowPartControl: View {
    let label: String
    let choices: [PartPropertyChoice]
    @Binding var source: String
    @Binding var customLayers: [ThemeShadowLayer]
    let indicator: InspectorRowIndicator

    var body: some View {
        if !choices.isEmpty {
            InspectorRow(title: label, indicator: indicator) {
                InspectorPopup(selection: $source, options: popupOptions, accessibilityLabel: label, help: label)
            }
        }
        if PartThemeValueSelection.isManualCustom(source) || choices.isEmpty {
            InspectorShadowControl(layers: $customLayers)
        }
    }

    private var popupOptions: [InspectorPopupOption<String>] {
        var options = choices.map {
            InspectorPopupOption(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
        }
        options.append(.init(
            title: "Custom",
            value: PartThemeValueSelection.manualCustom,
            separatorBefore: !options.isEmpty
        ))
        if !options.contains(where: { $0.value == source }) {
            options.insert(.init(title: "Missing Theme Shadow", value: source), at: 0)
        }
        return options
    }
}

#Preview {
    @Previewable @State var source = PartThemeValueSelection.manualCustom
    @Previewable @State var layers = [ThemeShadowLayer(x: 0, y: 4, blur: 8, opacity: 0.2)]
    PartControlPreview {
        ShadowPartControl(
            label: "Shadow",
            choices: Theme.standard.shadowChoices,
            source: $source,
            customLayers: $layers,
            indicator: .preview
        )
    }
}
