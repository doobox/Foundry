import SwiftUI

/// Inline text selects paint tokens, never a complete component theme.
struct RichTextColourPicker: View {
    let theme: Theme
    let reference: RichTextColourReference?
    let previews: [String: String]
    let apply: (RichTextColourReference) -> Void

    var body: some View {
        InspectorPaletteMenu(
            palettes: theme.colourPalettes,
            selectedID: reference?.foregroundToken?.selection ?? "",
            tokenPreviews: previews,
            tokenSections: ["foregrounds"]
        ) { selection in
            guard let token = PartColourToken.parse(selection) else { return }
            apply(RichTextColourReference(foregroundToken: token))
        }
        .padding(12)
        .frame(width: 320)
        .controlSize(.small)
    }
}
