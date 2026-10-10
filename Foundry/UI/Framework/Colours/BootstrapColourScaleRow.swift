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
            HStack(spacing: 0) {
                ForEach(ColourShade.allCases, id: \.self) { shade in
                    let token = hue + "-" + shade.bootstrapLabel
                    Button { open(shade) } label: {
                        VStack(spacing: 4) {
                            Rectangle().fill(Color(hex: previews[token] ?? "") ?? .clear)
                                .frame(height: 34)
                                .clipShape(UnevenRoundedRectangle(
                                    topLeadingRadius: shade == ColourShade.allCases.first ? 6 : 0,
                                    bottomLeadingRadius: shade == ColourShade.allCases.first ? 6 : 0,
                                    bottomTrailingRadius: shade == ColourShade.allCases.last ? 6 : 0,
                                    topTrailingRadius: shade == ColourShade.allCases.last ? 6 : 0))
                            Text(shade.bootstrapLabel).font(.caption2)
                            Image(systemName: framework.bootstrapTokens.values[token] == nil ? "circle" : "pencil.circle.fill")
                                .font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(previews[token] == nil)
                        .accessibilityLabel("Edit \(hue) \(shade.bootstrapLabel)")
                        .help("--bs-\(token) · \(previews[token] ?? "")")
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
