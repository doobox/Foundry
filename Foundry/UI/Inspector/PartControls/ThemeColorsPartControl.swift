import SwiftUI

struct ThemeColorsPartControl: View {
    @Environment(\.canvasAppearance) private var appearance
    let label: String
    let theme: Theme
    var indicator: InspectorRowIndicator? = nil
    var tokenSections: [String] = ["themes"]
    var themePreviewRole = "bg"
    var linksOnly = false
    var allowsInherit = false
    @Binding var selection: String
    @State private var showsColours = false
    @State private var tokenPreviews: [String: String] = [:]
    @State private var adaptiveTokenPreviews: [String: AdaptiveColourPreview] = [:]
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
    private var selectedAdaptivePreview: AdaptiveColourPreview {
        let id = PartColourToken.parse(selection)?.id ?? palette?.id
        return id.flatMap { adaptiveTokenPreviews[$0] } ?? AdaptiveColourPreview(solid: preview)
    }

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            Button { showsColours = true } label: {
                HStack {
                    if selection == "inherit" {
                        InheritColourSwatch(width: 24, height: 20)
                    } else {
                        AdaptiveColourSwatch(preview: selectedAdaptivePreview, cornerRadius: 4)
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
                InspectorPaletteMenu(palettes: palettes, selectedID: selectedID, tokenPreviews: tokenPreviews, adaptiveTokenPreviews: adaptiveTokenPreviews,
                    allowsInherit: allowsInherit, tokenSections: tokenSections, linksOnly: linksOnly) { id in
                    selection = id
                    showsColours = false
                }
                .padding(12).frame(width: tokenSections.contains("palettes") ? 400 : 320)
            }
        }
        .task(id: previewCSS + tokenSections.joined(separator: ",") + themePreviewRole + String(linksOnly)) {
            await resolvePreviews()
        }
    }

    private func resolvePreviews() async {
        let values = tokenSections.contains("themes") ? BootstrapPaletteTheme.selectablePalettes(in: theme) : []
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(theme: theme, mode: .both) + BootstrapThemeCSS.render(theme: theme)
        let scaleTokens = PartColourToken.groups(for: tokenSections, palettes: palettes, linksOnly: linksOnly).flatMap { $0.1 }
        let ids = values.map(\.id) + scaleTokens
        let expressions = values.map { "var(--bs-\(BootstrapPaletteTheme.nativeRole($0)!)-\(themePreviewRole))" } + scaleTokens.map { "var(--bs-\($0))" }
        do {
            let resolver = BootstrapScalePreviewResolver()
            let light = try await resolver.resolve(expressions: expressions, css: css, mode: "light")
            let dark = try await resolver.resolve(expressions: expressions, css: css, mode: "dark")
            try Task.checkCancellation()
            tokenPreviews = Dictionary(uniqueKeysWithValues: zip(ids, appearance == .light ? light : dark))
            adaptiveTokenPreviews = Dictionary(uniqueKeysWithValues: zip(ids, zip(light, dark).map { AdaptiveColourPreview(light: $0.0, dark: $0.1) }))
        } catch {
            if !Task.isCancelled { tokenPreviews = [:]; adaptiveTokenPreviews = [:] }
        }
    }

}
