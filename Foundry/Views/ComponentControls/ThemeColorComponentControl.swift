import SwiftUI

struct ThemeColorComponentControl: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    let allowsCustom: Bool
    let theme: Theme
    @Binding var source: String
    @Binding var customColor: Color
    let adjustment: Binding<Double>?
    let allowsOpacity: Bool
    let indicator: InspectorRowIndicator

    var body: some View {
        Group {
            InspectorRow(title: label, indicator: indicator) {
                InspectorPopup(
                    selection: $source,
                    options: choices.map {
                        .init(
                            title: $0.label,
                            value: $0.value,
                            separatorBefore: $0.separatorBefore,
                            swatchHex: previewColorHex(for: $0.value)
                        )
                    } + (allowsCustom ? [.init(
                        title: "Custom",
                        value: ComponentThemeValueSelection.manualCustom,
                        separatorBefore: !choices.isEmpty,
                        swatchHex: customColor.hexString
                    )] : []),
                    accessibilityLabel: label,
                    help: label
                )
            }
            if allowsCustom && ComponentThemeValueSelection.isManualCustom(source) {
                InspectorRow(title: "", alignment: .center) {
                    InspectorColorWell(color: $customColor, supportsAlpha: allowsOpacity)
                }
            }
            if let adjustment {
                InspectorRow(title: "Lighter or darker", alignment: .center) {
                    HStack {
                        InspectorSlider(
                            value: adjustment,
                            range: -100...100,
                            step: 1,
                            accessibilityLabel: "Lighter or darker",
                            help: "Adjust the selected colour"
                        )
                        Text(adjustment.wrappedValue.formatted() + "%")
                            .monospacedDigit()
                            .frame(minWidth: 42, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func previewColorHex(for value: String) -> String? {
        guard let role = ThemeColorRole(rawValue: value) else { return nil }
        return theme.color(for: role)
    }
}

#Preview("Theme colour") {
    @Previewable @State var source = ThemeColorRole.accent.rawValue
    @Previewable @State var color = Color.blue.opacity(0.75)
    @Previewable @State var adjustment = 0.0

    ComponentControlPreview {
        ThemeColorComponentControl(
            label: "Colour",
            choices: Theme.standard.colorChoices,
            allowsCustom: true,
            theme: .standard,
            source: $source,
            customColor: $color,
            adjustment: $adjustment,
            allowsOpacity: true,
            indicator: .preview
        )
    }
}
