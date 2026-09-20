import SwiftUI

struct FrameworkPanel: View {
    let framework: Framework
    let editor: ProjectEditor

    var body: some View {
        Form {
            Section("Colors") {
                ForEach(DesignToken.colorTokens) { token in
                    ColorPicker(
                        token.displayName,
                        selection: colorBinding(for: token),
                        supportsOpacity: false
                    )
                }
            }

            Section("Spacing") {
                ForEach(DesignToken.spacingTokens) { token in
                    Stepper(value: spacingBinding(for: token), in: 0...40, step: 0.5) {
                        LabeledContent(
                            token.displayName,
                            value: "\(spacingValue(for: token).formatted()) × · \((spacingValue(for: token) * SpacingTokens.baseRem).formatted()) rem"
                        )
                    }
                }
            }

            Section("Typography") {
                TextField("Body font", text: bodyFontBinding)
                ForEach(framework.typography.customFontSizes) { token in
                    Stepper(value: fontSizeBinding(for: token.id), in: 0.5...16, step: 0.125) {
                        LabeledContent(token.title, value: "\(token.size.formatted()) rem")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(for token: DesignToken) -> Binding<Color> {
        Binding(
            get: { Color(hex: framework.color(for: token) ?? "#FFFFFF") ?? .white },
            set: { editor.setFrameworkColor(token, value: $0.hexString ?? "#FFFFFF") }
        )
    }

    private func spacingBinding(for token: DesignToken) -> Binding<Double> {
        Binding(
            get: { spacingValue(for: token) },
            set: { editor.setFrameworkSpacing(token, value: $0) }
        )
    }

    private func spacingValue(for token: DesignToken) -> Double {
        framework.number(for: token) ?? 0
    }

    private var bodyFontBinding: Binding<String> {
        Binding(
            get: { framework.typography.bodyFont.family },
            set: editor.setFrameworkBodyFont
        )
    }

    private func fontSizeBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { framework.typography.fontSizes.first(where: { $0.id == id })?.size ?? 1 },
            set: { editor.setFrameworkFontSize(id: id, value: $0) }
        )
    }
}
