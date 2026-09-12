import SwiftUI

struct ThemeColorComponentControl: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    let allowsCustom: Bool
    let theme: Theme
    @Binding var source: String
    @Binding var shade: ColourShade
    @Binding var customColor: Color
    let allowsOpacity: Bool
    let indicator: InspectorRowIndicator
    @State private var showsPalettes = false

    private var paletteID: String {
        ThemeColorRole(rawValue: source) != nil ? "theme." + source : source
    }
    private var palette: ColourPalette? {
        theme.colourPalettes.resolvedPalette(id: paletteID)
    }
    private var selectedShade: ColourShade? {
        shade
    }

    var body: some View {
        Group {
            InspectorRow(title: label, indicator: indicator) {
                HStack(spacing: 6) {
                    if let palette {
                        HStack(spacing: 0) {
                            ForEach(palette.single ? [palette.defaultShade] : ColourShade.allCases, id: \.self) { step in
                                Button {
                                    guard !palette.single else { return }
                                    shade = step
                                } label: {
                                    Rectangle()
                                        .fill(Color(hex: palette.colour(at: .shade(step))) ?? .clear)
                                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                                        .overlay {
                                            if !palette.single && selectedShade == step {
                                                Rectangle().strokeBorder(.white, lineWidth: 2)
                                                    .padding(1)
                                                    .overlay { Rectangle().strokeBorder(.black.opacity(0.7), lineWidth: 1) }
                                            }
                                        }
                                }
                                .buttonStyle(InspectorPaletteSwatchStyle())
                                .help("\(palette.name) · Shade \(step.rawValue)")
                                .accessibilityLabel("\(palette.name), shade \(step.rawValue)")
                                .accessibilityAddTraits(selectedShade == step ? .isSelected : [])
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                        .accessibilityLabel("\(label) shades")
                        Button { shade = palette.defaultShade } label: {
                            Image(systemName: palette.single || shade == palette.defaultShade ? "star.fill" : "star")
                        }
                        .buttonStyle(.borderless)
                        .help("Select \(palette.name)’s current default shade")
                        .accessibilityLabel("Select default shade")
                        .accessibilityValue(palette.single || shade == palette.defaultShade ? "Selected" : "Not selected")
                    } else {
                        Button(ComponentThemeValueSelection.isManualCustom(source) ? "Custom Colour" : "Missing Colour") {
                            showsPalettes = true
                        }
                        .buttonStyle(.borderless)
                        Spacer(minLength: 0)
                    }
                    Button { showsPalettes.toggle() } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help(palette.map { "Choose colour · \($0.name)" } ?? "Choose colour")
                    .accessibilityLabel("Choose \(label)")
                    .popover(isPresented: $showsPalettes) {
                        InspectorPaletteMenu(palettes: choices.isEmpty ? [] : theme.colourPalettes,
                                             selectedID: paletteID, allowsCustom: allowsCustom) { value in
                            // The source binding updates source and default shade atomically.
                            let role = value.hasPrefix("theme.") ? ThemeColorRole(rawValue: String(value.dropFirst(6))) : nil
                            source = role?.rawValue ?? value
                            showsPalettes = false
                        }
                    }
                }
                .controlSize(.small)
            }
            if allowsCustom && ComponentThemeValueSelection.isManualCustom(source) {
                InspectorRow(title: "", alignment: .center) {
                    InspectorColorWell(color: $customColor, supportsAlpha: allowsOpacity)
                }
            }
        }
    }

}

private struct InspectorPaletteSwatchStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private struct InspectorPaletteMenu: View {
    let palettes: [ColourPalette]
    let selectedID: String
    let allowsCustom: Bool
    let select: (String) -> Void
    @State private var search = ""

    private var filtered: [ColourPalette] {
        palettes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search colours", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search colours")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach([ColourPalette.Origin.custom, .theme, .standard], id: \.self) { group in
                        let matches = filtered.filter { $0.origin == group }
                        if !matches.isEmpty {
                            Text(group == .custom ? "Custom Colours" : (group == .theme ? "Theme Colours" : "Standard Colours"))
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.top, 6)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(matches) { palette in
                                Button { select(palette.id) } label: {
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(hex: (palettes.resolvedPalette(id: palette.id) ?? palette).colour(at: .default)) ?? .clear)
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
                    if filtered.isEmpty { Text("No matching colours").foregroundStyle(.secondary).padding(6) }
                }
            }
            .frame(maxHeight: 320)
            if allowsCustom {
                Divider()
                Button("Custom Colour…") { select(ComponentThemeValueSelection.manualCustom) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(width: 260)
        .controlSize(.small)
    }
}

#Preview("Theme colour") {
    @Previewable @State var source = ThemeColorRole.accent.rawValue
    @Previewable @State var color = Color.blue.opacity(0.75)
    @Previewable @State var shade = ColourShade.six

    ComponentControlPreview {
        ThemeColorComponentControl(
            label: "Colour",
            choices: Theme.standard.colorChoices,
            allowsCustom: true,
            theme: .standard,
            source: $source,
            shade: $shade,
            customColor: $color,
            allowsOpacity: true,
            indicator: .preview
        )
    }
}
