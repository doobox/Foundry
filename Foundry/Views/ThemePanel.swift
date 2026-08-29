import SwiftUI

struct ThemePanel: View {
    let theme: Theme
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
                    Stepper(value: spacingBinding(for: token), in: 0...160, step: 1) {
                        LabeledContent(token.displayName, value: "\(spacingValue(for: token).formatted()) px")
                    }
                }
            }

            Section("Typography") {
                TextField("Body font", text: bodyFontBinding)
                Stepper(value: baseSizeBinding, in: 10...40, step: 1) {
                    LabeledContent("Base size", value: "\(theme.typography.baseSize.formatted()) px")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(for token: DesignToken) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme.color(for: token) ?? "#FFFFFF") ?? .white },
            set: { editor.setThemeColor(token, value: $0.hexString ?? "#FFFFFF") }
        )
    }

    private func spacingBinding(for token: DesignToken) -> Binding<Double> {
        Binding(
            get: { spacingValue(for: token) },
            set: { editor.setThemeSpacing(token, value: $0) }
        )
    }

    private func spacingValue(for token: DesignToken) -> Double {
        theme.number(for: token) ?? 0
    }

    private var bodyFontBinding: Binding<String> {
        Binding(
            get: { theme.typography.bodyFont.family },
            set: editor.setThemeBodyFont
        )
    }

    private var baseSizeBinding: Binding<Double> {
        Binding(
            get: { theme.typography.baseSize },
            set: editor.setThemeBaseSize
        )
    }
}
