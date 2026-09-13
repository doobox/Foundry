import SwiftUI

struct ThemeFontPartControl: View {
    let label: String
    let theme: Theme
    let indicator: InspectorRowIndicator?
    @Binding var selection: String

    private var isMissing: Bool {
        !theme.fontFamilyChoices.contains { $0.value == selection }
    }

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            Picker(label, selection: $selection) {
                if isMissing {
                    Label("Missing font", systemImage: "exclamationmark.triangle")
                        .tag(selection)
                        .disabled(true)
                }
                Section("Theme Fonts") {
                    choices(custom: false)
                }
                if !theme.typography.customFonts.isEmpty {
                    Section("Custom Fonts") {
                        choices(custom: true)
                    }
                }
            }
            .pickerStyle(.menu)
            .buttonSizing(.flexible)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
            .help(isMissing ? "This font is no longer available. Choose a replacement." : label)
        }
    }

    private func choices(custom: Bool) -> some View {
        ForEach(theme.fontFamilyChoices.filter { $0.value.hasPrefix("custom:") == custom }) { choice in
            Text(choice.label).tag(choice.value)
        }
    }
}
