import SwiftUI

struct ColourTokenSwatchGrid: View {
    let title: String
    let tokens: [String]
    let previews: [String: String]
    let adaptivePreviews: [String: AdaptiveColourPreview]
    let selectedID: String
    let palettes: [ColourPalette]
    let linksOnly: Bool
    let search: String
    let select: (String) -> Void
    var showsTitle = true

    private var matches: [String] {
        tokens.filter { token in
            search.isEmpty || title.localizedCaseInsensitiveContains(search)
                || PartColourToken.label(token, palettes: palettes, linksOnly: linksOnly).localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if showsTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }
                LazyVGrid(columns: ColourPickerSwatch.columns, alignment: .leading, spacing: 8) {
                    ForEach(matches, id: \.self) { token in
                        let name = PartColourToken.label(token, palettes: palettes, linksOnly: linksOnly)
                        let customStrip = palettes.first { $0.origin == .custom && $0.colourKind == .foreground && $0.colourTokens.contains(token) }
                        let preview = adaptivePreviews[token]
                            ?? AdaptiveColourPreview(solid: previews[token] ?? "#808080")
                        Button { select("token:" + token) } label: {
                            ColourPickerSwatch(preview: preview, isSelected: selectedID == "token:" + token)
                        }
                        .buttonStyle(.plain)
                        .help(token == "fg-bg" ? "fg-bg · use the body background colour as foreground"
                            : customStrip.map { "\($0.name) · \(name)" } ?? name)
                        .accessibilityLabel(name)
                        .accessibilityValue("Light \(preview.light), dark \(preview.dark)")
                        .accessibilityAddTraits(selectedID == "token:" + token ? .isSelected : [])
                    }
                }
            }
        }
    }
}
