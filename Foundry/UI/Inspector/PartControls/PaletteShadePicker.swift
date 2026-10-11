import SwiftUI

/// Bootstrap's named hue scales are individual paints, not semantic themes.
struct PaletteShadePicker: View {
    let previews: [String: String]
    let selectedID: String
    let search: String
    let select: (String) -> Void

    private var hues: [String] {
        BootstrapColourCatalogue.hues.filter { hue in
            search.isEmpty || "Palettes".localizedCaseInsensitiveContains(search)
                || hue.localizedCaseInsensitiveContains(search)
                || ColourShade.allCases.contains { (hue + " " + $0.bootstrapLabel).localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        if !hues.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Palettes")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(hues, id: \.self) { hue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hue.capitalized).font(.caption)
                        HStack(spacing: 0) {
                            ForEach(ColourShade.allCases, id: \.self) { shade in
                                let token = hue + "-" + shade.bootstrapLabel
                                let selection = "token:" + token
                                let hex = previews[token] ?? BootstrapColourCatalogue.previews.palettes[hue]?[shade.rawValue - 1] ?? "#808080"
                                Button { select(selection) } label: {
                                    Rectangle()
                                        .fill(Color(hex: hex) ?? .gray)
                                        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                                        .overlay {
                                            if selectedID == selection {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.white)
                                                    .shadow(color: .black, radius: 1)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(hue.capitalized + " " + shade.bootstrapLabel)
                                .accessibilityLabel(hue.capitalized + " " + shade.bootstrapLabel)
                                .accessibilityAddTraits(selectedID == selection ? .isSelected : [])
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(4)
        }
    }
}
