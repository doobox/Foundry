import SwiftUI

struct ThemeColorsPartControl: View {
    @Environment(\.canvasAppearance) private var appearance
    let label: String
    let theme: Theme
    var indicator: InspectorRowIndicator? = nil
    var tokenSections: [String] = ["themes"]
    var linksOnly = false
    var allowsInherit = false
    @Binding var selection: String
    @State private var showsColours = false
    @State private var tokenPreviews: [String: String] = [:]
    private var selectionTitle: String {
        if selection == "inherit" { return "Inherit" }
        if let token = PartColourToken.parse(selection) { return PartColourToken.label(token.id, palettes: palettes, linksOnly: linksOnly) }
        return palette?.pickerLabel ?? "Missing Colour"
    }
    private var previewCSS: String {
        BootstrapColorCSS.canvas(theme: theme, appearance: appearance) + BootstrapThemeCSS.render(theme: theme)
    }

    private var selectedID: String { selection == "inherit" ? "inherit" : palette?.id ?? BootstrapPaletteTheme.paletteID(selection) }
    private var palettes: [ColourPalette] { theme.colourPalettes }
    private var palette: ColourPalette? { BootstrapPaletteTheme.effectivePalette(selection, in: theme) }
    private var preview: String {
        if let token = PartColourToken.parse(selection) { return tokenPreviews[token.id] ?? "#808080" }
        guard let palette else { return "#808080" }
        if let hex = tokenPreviews[palette.id] { return hex }
        let shade = palette.defaultShade(for: appearance)
        return palette.colour(at: .shade(shade))
    }

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            Button { showsColours = true } label: {
                HStack {
                    if selection == "inherit" {
                        InheritColourSwatch().frame(width: 24)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: preview) ?? .gray)
                            .frame(width: 24, height: 20)
                    }
                    Text(selectionTitle)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose \(label)")
            .accessibilityValue(selectionTitle)
            .popover(isPresented: $showsColours) {
                InspectorPaletteMenu(palettes: palettes, selectedID: selectedID, tokenPreviews: tokenPreviews,
                    allowsInherit: allowsInherit, tokenSections: tokenSections, linksOnly: linksOnly) { id in
                    selection = id
                    showsColours = false
                }
                .padding(12).frame(width: tokenSections.contains("palettes") ? 400 : 320)
            }
        }
        .task(id: previewCSS + tokenSections.joined(separator: ",")) {
            await resolvePreviews()
        }
    }

    private func resolvePreviews() async {
        let values = tokenSections.contains("themes") ? BootstrapPaletteTheme.selectablePalettes(in: theme) : []
        let css = BootstrapColourCatalogue.sourceCSS + previewCSS
        let scaleTokens = PartColourToken.groups(for: tokenSections, palettes: palettes, linksOnly: linksOnly).flatMap { $0.1 }
        do {
            let colours = try await BootstrapScalePreviewResolver().resolve(
                expressions: values.map { "var(--bs-\(BootstrapPaletteTheme.nativeRole($0)!)-bg)" } + scaleTokens.map { "var(--bs-\($0))" },
                css: css, mode: appearance.rawValue)
            try Task.checkCancellation()
            tokenPreviews = Dictionary(uniqueKeysWithValues: zip(values.map(\.id) + scaleTokens, colours))
        } catch {
            if !Task.isCancelled { tokenPreviews = [:] }
        }
    }

}
