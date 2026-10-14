import SwiftUI

struct PartColourTokenPicker: View {
    let previews: [String: String]
    var adaptivePreviews: [String: AdaptiveColourPreview] = [:]
    let sections: [String]
    let selectedID: String
    var palettes: [ColourPalette] = []
    var linksOnly = false
    var search = ""
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PartColourToken.groups(for: sections, palettes: palettes, linksOnly: linksOnly), id: \.0) { title, tokens in
                if title == "Foregrounds" {
                    grid(title: title, tokens: BootstrapColourCatalogue.tokens(for: "foreground"))
                    ForEach(palettes.filter { $0.origin == .custom && $0.colourKind == .foreground }) { palette in
                        grid(title: palette.name, tokens: palette.colourTokens, showsTitle: false)
                    }
                } else {
                    grid(title: title, tokens: tokens)
                }
            }
        }
        .padding(4)
    }

    private func grid(title: String, tokens: [String], showsTitle: Bool = true) -> some View {
        ColourTokenSwatchGrid(title: title, tokens: tokens, previews: previews,
            adaptivePreviews: adaptivePreviews, selectedID: selectedID, palettes: palettes,
            linksOnly: linksOnly, search: search, select: select, showsTitle: showsTitle)
    }
}
