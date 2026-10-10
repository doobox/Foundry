import AppKit
import SwiftUI

struct BootstrapTokenValueRow: View {
    let token: BootstrapEditorToken
    let value: String
    let editor: ProjectEditor
    @State private var text = ""
    @State private var amount = 0.0
    @State private var colourPicker = BootstrapColourPicker()
    @State private var colourPreview: Color?

    private var numeric: (Double, String)? {
        var resolved = value
        for _ in 0..<8 where resolved.hasPrefix("var(--bs-") && resolved.hasSuffix(")") {
            let key = String(resolved.dropFirst(9).dropLast())
            guard let next = editor.document.site.framework.bootstrapTokens.values[key] ?? BootstrapColourCatalogue.declarations["--bs-" + key], next != resolved else { break }
            resolved = next
        }
        for unit in ["rem", "px", "%", ""] {
            guard resolved.hasSuffix(unit) else { continue }
            let number = unit.isEmpty ? resolved : String(resolved.dropLast(unit.count))
            if let number = Double(number), number.isFinite { return (number, unit) }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(token.label).fontWeight(.medium).frame(width: 150, alignment: .leading)
            if token.id.contains("color") {
                Button("Customise…") {
                    guard let colourPreview else { return }
                    colourPicker.open(colour: NSColor(colourPreview)) { colour in
                        if let scale = BootstrapColourScale.picked(colour) { editor.setBootstrapToken(token, value: scale.base) }
                    }
                }
                .disabled(colourPreview == nil)
                Spacer()
            } else if let (number, unit) = numeric {
                FrameworkSlider(value: $amount, range: min(token.range.lowerBound, number)...max(token.range.upperBound, number), step: token.step)
                    .accessibilityLabel(token.label)
                FrameworkNumberField(title: token.label, value: $amount, unit: unit, step: token.step, precision: token.step >= 1 ? 0 : 3)
                    .onChange(of: amount) { _, updated in
                        guard token.acceptsNumber(updated) else { amount = number; return }
                        guard updated != number else { return }
                        editor.setBootstrapToken(token, value: "\(updated.bootstrapCSSNumber)\(unit)")
                    }
            } else {
                TextField(token.label, text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { editor.setBootstrapToken(token, value: text) }
                Button("Apply") { editor.setBootstrapToken(token, value: text) }
                    .disabled(text == value || !BootstrapEditorToken.safeValue(text))
            }
        }
        .padding(.vertical, 8)
        .onAppear { text = value; amount = numeric?.0 ?? 0 }
        .onChange(of: value) { _, updated in text = updated; amount = numeric?.0 ?? 0 }
        .onDisappear { colourPicker.stop() }
        .task(id: value) {
            guard token.id.contains("color") else { return }
            colourPreview = nil
            let css = BootstrapColourCatalogue.sourceCSS + BootstrapThemeCSS.render(framework: editor.document.site.framework)
            if let hex = try? await BootstrapScalePreviewResolver().resolve(expressions: [value], css: css).first {
                colourPreview = Color(hex: hex)
            }
        }
    }
}
