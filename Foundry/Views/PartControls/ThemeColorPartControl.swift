import SwiftUI

struct ThemeColorPartControl: View {
    @Environment(\.canvasAppearance) private var appearance
    let label: String
    let framework: Framework
    let indicator: InspectorRowIndicator
    @Binding var selection: String
    @State private var showsColours = false
    @State private var tokenPreviews: [String: String] = [:]

    private var selectedID: String { palette?.id ?? BootstrapPaletteTheme.paletteID(selection) }
    private var palettes: [ColourPalette] { BootstrapPaletteTheme.selectablePalettes(in: framework) }
    private var palette: ColourPalette? { BootstrapPaletteTheme.effectivePalette(selection, in: framework) }
    private var preview: String {
        guard let palette else { return "#808080" }
        if let hex = tokenPreviews[palette.id] { return hex }
        let shade = palette.defaultShade(for: appearance)
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
                InspectorPaletteMenu(palettes: palettes, selectedID: selectedID, tokenPreviews: tokenPreviews) { id in
                    selection = id
                    showsColours = false
                }
                .padding(12).frame(width: 280)
            }
        }
        .task(id: BootstrapColorCSS.canvas(framework: framework, appearance: appearance)) {
            await resolvePreviews()
        }
    }

    private func resolvePreviews() async {
        let values = palettes
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.canvas(framework: framework, appearance: appearance)
        do {
            let colours = try await BootstrapScalePreviewResolver().resolve(
                expressions: values.map { "var(--bs-\(BootstrapPaletteTheme.nativeRole($0)!)-bg)" },
                css: css, mode: appearance.rawValue)
            try Task.checkCancellation()
            tokenPreviews = Dictionary(uniqueKeysWithValues: zip(values.map(\.id), colours))
        } catch {
            if !Task.isCancelled { tokenPreviews = [:] }
        }
    }
}
