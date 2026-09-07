import SwiftUI

struct BasicColorComponentControl<TokenPicker: View>: View {
    let label: String
    let selectedToken: DesignToken?
    let indicator: InspectorRowIndicator?
    @Binding var color: Color
    @ViewBuilder let tokenPicker: () -> TokenPicker

    var body: some View {
        Group {
            InspectorRow(title: "Source", control: tokenPicker)
            if selectedToken == nil {
                InspectorRow(title: label, alignment: .center, indicator: indicator) {
                    InspectorColorWell(color: $color)
                }
            }
        }
    }
}

#Preview("Colour") {
    @Previewable @State var color = Color.blue
    ComponentControlPreview {
        BasicColorComponentControl(label: "Colour", selectedToken: nil, indicator: .preview, color: $color) {
            Text("Custom colour")
        }
    }
}

#Preview("Theme colour") {
    @Previewable @State var source = ComponentThemeValueSelection.manualCustom
    @Previewable @State var color = Color.blue.opacity(0.75)
    @Previewable @State var adjustment = 0.0
    ComponentControlPreview {
        ColorComponentControl(
            label: "Colour",
            choices: Theme.standard.colorChoices,
            theme: .standard,
            source: $source,
            customColor: $color,
            adjustment: $adjustment,
            allowsOpacity: true,
            indicator: .preview
        )
    }
}

struct ColorComponentControl: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    let theme: Theme
    @Binding var source: String
    @Binding var customColor: Color
    let adjustment: Binding<Double>?
    let allowsOpacity: Bool
    let indicator: InspectorRowIndicator

    var body: some View {
        Group {
            if !choices.isEmpty {
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
                        } + [.init(
                            title: "Custom",
                            value: ComponentThemeValueSelection.manualCustom,
                            separatorBefore: !choices.isEmpty,
                            swatchHex: customColor.hexString
                        )],
                        accessibilityLabel: label,
                        help: label
                    )
                }
            }
            if ComponentThemeValueSelection.isManualCustom(source) || choices.isEmpty {
                InspectorRow(
                    title: choices.isEmpty ? label : "",
                    alignment: .center,
                    indicator: choices.isEmpty ? indicator : nil
                ) {
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
