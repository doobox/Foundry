import SwiftUI

struct ThemeShadowPartControl: View {
    let label: String
    let choices: [PartPropertyChoice]
    @Binding var source: String
    @Binding var customLayers: [ThemeShadowLayer]
    let indicator: InspectorRowIndicator

    private var isCustom: Bool {
        PartThemeValueSelection.isManualCustom(source)
    }

    var body: some View {
        if !choices.isEmpty {
            InspectorRow(title: label, indicator: indicator) {
                HStack(spacing: 8) {
                    if isCustom {
                        Text("Custom")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        InspectorPopup(selection: $source, options: popupOptions, accessibilityLabel: label, help: label)
                    }
                    ThemeModeToggle(usesThemeTokens: !isCustom) {
                        source = isCustom
                            ? (choices.first?.value ?? source)
                            : PartThemeValueSelection.manualCustom
                    }
                }
            }
        }
        if isCustom || choices.isEmpty {
            InspectorShadowControl(layers: $customLayers)
        }
    }

    private var popupOptions: [InspectorPopupOption<String>] {
        var options = choices.map {
            InspectorPopupOption(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
        }
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
        ThemeShadowPartControl(
            label: "Shadow",
            choices: Theme.standard.shadowChoices,
            source: $source,
            customLayers: $layers,
            indicator: .preview
        )
    }
}
