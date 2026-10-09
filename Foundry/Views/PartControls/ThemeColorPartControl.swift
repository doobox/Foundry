import SwiftUI

struct ThemeColorPartControl: View {
    @Environment(\.canvasAppearance) private var appearance
    let label: String
    let framework: Framework
    let indicator: InspectorRowIndicator
    @Binding var selection: String
    @State private var showsColours = false

    private var selectedID: String { BootstrapPaletteTheme.paletteID(selection) }
    private var palette: ColourPalette? { framework.colourPalettes.resolvedPalette(id: selectedID) }
    private var preview: String {
        guard let palette else { return "#808080" }
        let shade = BootstrapPaletteTheme.nativeRole(palette) == nil ? ColourShade.seven : palette.defaultShade(for: appearance)
        return palette.colour(at: .shade(shade))
    }

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            Button { showsColours = true } label: {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: preview) ?? .gray)
                        .frame(width: 24, height: 20)
                    Text(palette?.name ?? "Missing Colour")
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose \(label)")
            .accessibilityValue(palette?.name ?? "Missing Colour")
            .popover(isPresented: $showsColours) {
                InspectorPaletteMenu(palettes: framework.colourPalettes, selectedID: selectedID, usesThemeBase: true) { id in
                    selection = id
                    showsColours = false
                }
                .padding(12).frame(width: 280)
            }
        }
    }
}
