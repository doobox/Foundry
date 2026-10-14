import SwiftUI

struct InspectorPaletteSwatchStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The searchable palette list shared by the Inspector colour control and the
/// rich-text editor's colour popover. Callers own the surrounding padding,
/// width and control size so it can embed under other rows.
struct InspectorPaletteMenu: View {
    @Environment(\.canvasAppearance) private var appearance
    let palettes: [ColourPalette]
    let selectedID: String
    var tokenPreviews: [String: String] = [:]
    var adaptiveTokenPreviews: [String: AdaptiveColourPreview] = [:]
    var allowsInherit = false
    var tokenSections: [String] = ["themes"]
    var linksOnly = false
    let select: (String) -> Void
    @State private var search = ""

    private var orderedSections: [String] {
        var seen = Set<String>()
        let unique = tokenSections.filter { seen.insert($0).inserted }
        guard unique.contains("foregrounds") else { return unique }
        let foregroundOrder = ["foregrounds", "themes", "blackWhite"]
        let ordered = foregroundOrder.filter { unique.contains($0) }
        return ordered + unique.filter { !ordered.contains($0) }
    }

    private var filtered: [ColourPalette] {
        palettes.filter { search.isEmpty || $0.pickerLabel.localizedCaseInsensitiveContains(search) }
    }

    private func menuColour(_ palette: ColourPalette) -> String {
        let resolved = palettes.resolvedPalette(id: palette.id) ?? palette
        if let preview = tokenPreviews[palette.id] { return preview }
        let shade = resolved.defaultShade(for: appearance)
        return resolved.colour(at: .shade(shade))
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search colours", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search colours")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if allowsInherit {
                        Text("Inherit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        Button { select("inherit") } label: {
                            ColourPickerSwatch(isInherit: true, isSelected: selectedID == "inherit")
                        }
                        .buttonStyle(.plain)
                        .help("Inherit")
                        .accessibilityLabel("Inherit")
                        .accessibilityAddTraits(selectedID == "inherit" ? .isSelected : [])
                    }
                    ForEach(orderedSections, id: \.self) { section in
                        if section == "palettes" {
                            PaletteShadePicker(previews: tokenPreviews, selectedID: selectedID, search: search, select: select)
                        } else if section != "themes" {
                            PartColourTokenPicker(previews: tokenPreviews, adaptivePreviews: adaptiveTokenPreviews, sections: [section], selectedID: selectedID, palettes: palettes, linksOnly: linksOnly, search: search, select: select)
                        }
                        let matches = section == "themes" && !linksOnly ? filtered.filter { BootstrapPaletteTheme.nativeRole($0) != nil } : []
                        if !matches.isEmpty {
                            Text("Theme Colours")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.top, 6)
                                .accessibilityAddTraits(.isHeader)
                            LazyVGrid(columns: ColourPickerSwatch.columns, alignment: .leading, spacing: 8) {
                                ForEach(matches) { palette in
                                    let preview = adaptiveTokenPreviews[palette.id]
                                        ?? AdaptiveColourPreview(solid: menuColour(palette))
                                    Button { select(palette.id) } label: {
                                        ColourPickerSwatch(preview: preview, isSelected: selectedID == palette.id)
                                    }
                                    .buttonStyle(.plain)
                                    .help(palette.pickerLabel)
                                    .accessibilityLabel(palette.pickerLabel)
                                    .accessibilityValue("Light \(preview.light), dark \(preview.dark)")
                                    .accessibilityAddTraits(selectedID == palette.id ? .isSelected : [])
                                }
                            }
                        }
                    }
                    if orderedSections.contains("foregrounds") {
                        ColourTokenSwatchGrid(title: "Background as Foreground", tokens: ["fg-bg"],
                            previews: tokenPreviews, adaptivePreviews: adaptiveTokenPreviews,
                            selectedID: selectedID, palettes: palettes, linksOnly: linksOnly,
                            search: search, select: select)
                            .padding(4)
                    }
                    if filtered.isEmpty && tokenSections.isEmpty { Text("No matching colours").foregroundStyle(.secondary).padding(6) }
                }
            }
            .frame(height: 400)
        }
    }
}
