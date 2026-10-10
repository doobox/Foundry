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
    var allowsInherit = false
    var tokenSections: [String] = ["themes"]
    var linksOnly = false
    let select: (String) -> Void
    @State private var search = ""

    private var orderedSections: [String] {
        var seen = Set<String>()
        return tokenSections.filter { seen.insert($0).inserted }
    }

    private var filtered: [ColourPalette] {
        palettes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
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
                        Button { select("inherit") } label: {
                            HStack(spacing: 8) {
                                InheritColourSwatch()
                                Text("Inherit")
                                Spacer(minLength: 4)
                                if selectedID == "inherit" { Image(systemName: "checkmark") }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedID == "inherit" ? .isSelected : [])
                    }
                    ForEach(orderedSections, id: \.self) { section in
                        if section != "themes" {
                            PartColourTokenPicker(previews: tokenPreviews, sections: [section], selectedID: selectedID, palettes: palettes, linksOnly: linksOnly, search: search, select: select)
                        }
                        let matches = section == "themes" && !linksOnly ? filtered.filter { BootstrapPaletteTheme.nativeRole($0) != nil } : []
                        if !matches.isEmpty {
                            Text("Theme Colours")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.top, 6)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(matches) { palette in
                                Button { select(palette.id) } label: {
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(hex: menuColour(palette)) ?? .clear)
                                            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.3)) }
                                            .frame(width: 20, height: 20)
                                        Text(palette.name).lineLimit(1)
                                        Spacer(minLength: 4)
                                        if selectedID == palette.id { Image(systemName: "checkmark") }
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(palette.name)
                                .accessibilityAddTraits(selectedID == palette.id ? .isSelected : [])
                            }
                        }
                    }
                    if filtered.isEmpty && tokenSections.isEmpty { Text("No matching colours").foregroundStyle(.secondary).padding(6) }
                }
            }
            .frame(height: 400)
        }
    }
}
