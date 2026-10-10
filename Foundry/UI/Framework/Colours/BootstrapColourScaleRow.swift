import SwiftUI

struct BootstrapColourScaleRow: View {
    let hue: String
    let framework: Framework
    let editor: ProjectEditor
    let previews: [String: String]
    @State private var picker = BootstrapColourPicker()
    @State private var selection = ""

    private var selectedHue: String {
        BootstrapColourCatalogue.hues.first { candidate in
            ColourShade.allCases.allSatisfy { shade in
                framework.bootstrapTokens.value(BootstrapEditorToken("\(hue)-\(shade.bootstrapLabel)"))
                    == BootstrapColourCatalogue.declarations["--bs-\(candidate)-\(shade.bootstrapLabel)"]
            }
        } ?? ""
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(hue.capitalized).font(.headline)
                Spacer()
                Button { open(.seven, wholeScale: true) } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: previews[hue + "-500"] ?? "") ?? .clear)
                            .frame(width: 22, height: 18)
                        Text("Customise…")
                    }
                }
                .disabled(previews[hue + "-500"] == nil)
                .help("Regenerate all 13 shades from one colour. Replaces individual shade edits.")
                Picker("\(hue.capitalized) scale", selection: $selection) {
                    if selectedHue.isEmpty { Text("Custom shades").tag("") }
                    ForEach(BootstrapColourCatalogue.hues, id: \.self) { source in
                        Text(source.capitalized).tag(source)
                    }
                }.labelsHidden().frame(width: 130)
            }
            ColourSwatchStrip(swatches: ColourShade.allCases.map { shade in
                let token = hue + "-" + shade.bootstrapLabel
                return ColourSwatchStrip.Swatch(
                    id: token,
                    label: shade.bootstrapLabel,
                    hex: previews[token],
                    accessibilityLabel: "Edit \(hue) \(shade.bootstrapLabel)",
                    help: "--bs-\(token) · \(previews[token] ?? "")")
            }) { swatch in
                if let shade = ColourShade.allCases.first(where: { hue + "-" + $0.bootstrapLabel == swatch.id }) {
                    open(shade)
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear { selection = selectedHue }
        .onChange(of: selectedHue) { _, value in selection = value }
        .onChange(of: selection) { _, value in
            guard !value.isEmpty, value != selectedHue, let scale = BootstrapColourScale.native(value) else { return }
            picker.stop()
            editor.setBootstrapColourScale(hue, scale: scale)
        }
        .onDisappear { picker.stop() }
    }

    private func open(_ shade: ColourShade, wholeScale: Bool = false) {
        let id = hue + "-" + shade.bootstrapLabel
        guard let hex = previews[id], let colour = Color(hex: hex) else { return }
        picker.open(colour: NSColor(colour)) { picked in
            guard let scale = BootstrapColourScale.picked(picked) else { return }
            if wholeScale { editor.setBootstrapColourScale(hue, scale: scale) }
            else { editor.setBootstrapToken(BootstrapEditorToken(id), value: scale.base) }
        }
    }
}
