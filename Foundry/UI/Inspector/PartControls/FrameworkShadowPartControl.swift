import SwiftUI

struct FrameworkShadowPartControl: View {
    let label: String
    let choices: [PartPropertyChoice]
    @Binding var source: String
    @Binding var customLayers: [FrameworkShadowLayer]
    let indicator: InspectorRowIndicator

    private var isCustom: Bool {
        PartFrameworkValueSelection.isManualCustom(source)
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
                    FrameworkModeToggle(usesFrameworkTokens: !isCustom) {
                        source = isCustom
                            ? (choices.first?.value ?? source)
                            : PartFrameworkValueSelection.manualCustom
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
            options.insert(.init(title: "Missing Framework Shadow", value: source), at: 0)
        }
        return options
    }
}

#Preview {
    @Previewable @State var source = PartFrameworkValueSelection.manualCustom
    @Previewable @State var layers = [FrameworkShadowLayer(x: 0, y: 4, blur: 8, opacity: 0.2)]
    PartControlPreview {
        FrameworkShadowPartControl(
            label: "Shadow",
            choices: Framework.standard.shadowChoices,
            source: $source,
            customLayers: $layers,
            indicator: .preview
        )
    }
}
