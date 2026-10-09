import SwiftUI

struct FrameworkColorPartControl: View {
    let label: String
    let choices: [PartPropertyChoice]
    let allowsCustom: Bool
    let framework: Framework
    @Binding var source: String
    @Binding var shade: ColourShade
    @Binding var customColor: Color
    @Binding var opacityPercent: Double
    let allowsOpacity: Bool
    let indicator: InspectorRowIndicator
    var resetToFramework: (() -> Void)? = nil
    var canResetToFramework = false

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            FrameworkColorControlContent(
                label: label,
                choices: choices,
                allowsCustom: allowsCustom,
                framework: framework,
                source: $source,
                shade: $shade,
                customColor: $customColor,
                allowsOpacity: allowsOpacity,
                resetToFramework: resetToFramework,
                canResetToFramework: canResetToFramework
            )
            .controlSize(.small)
        }
        if allowsOpacity {
            SliderPartControl(
                label: "Opacity",
                options: SliderOptions(range: 0...100, step: 1, unit: "%"),
                indicator: indicator,
                value: $opacityPercent
            )
        }
    }
}

/// The colour control's working parts — shade strip, default-shade star,
/// optional reset, palette picker, and custom toggle — free of Inspector row
/// chrome, so surfaces like Page Info can present them inside their own form
/// styling. `label` names the control for accessibility only.
struct FrameworkColorControlContent: View {
    @Environment(\.canvasAppearance) private var appearance
    let label: String
    let choices: [PartPropertyChoice]
    let allowsCustom: Bool
    let framework: Framework
    @Binding var source: String
    @Binding var shade: ColourShade
    @Binding var customColor: Color
    let allowsOpacity: Bool
    var resetToFramework: (() -> Void)? = nil
    var canResetToFramework = false
    @State private var showsPalettes = false

    private var isCustom: Bool {
        PartFrameworkValueSelection.isManualCustom(source)
    }

    private var paletteID: String {
        FrameworkColorRole(rawValue: source) != nil ? "framework." + source : source
    }
    private var palette: ColourPalette? {
        framework.colourPalettes.resolvedPalette(id: paletteID)
    }
    private var selectedShade: ColourShade? {
        shade
    }

    var body: some View {
                HStack(spacing: 6) {
                    if isCustom {
                        InspectorColorWell(color: $customColor, supportsAlpha: allowsOpacity)
                        Spacer(minLength: 0)
                    } else if let palette {
                        HStack(spacing: 0) {
                            ForEach(palette.single ? [palette.lightDefaultShade] : ColourShade.allCases, id: \.self) { step in
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
                        Button { shade = palette.defaultShade(for: appearance) } label: {
                            Image(systemName: palette.single || shade == palette.defaultShade(for: appearance) ? "star.fill" : "star")
                                .frame(width: 22, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Select \(palette.name)’s current default shade")
                        .accessibilityLabel("Select default shade")
                        .accessibilityValue(palette.single || shade == palette.defaultShade(for: appearance) ? "Selected" : "Not selected")
                    } else {
                        Button("Missing Colour") {
                            showsPalettes = true
                        }
                        .buttonStyle(.borderless)
                        Spacer(minLength: 0)
                    }
                    if let resetToFramework {
                        Button(action: resetToFramework) {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 22, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canResetToFramework)
                        .help("Reset to framework Page defaults")
                        .accessibilityLabel("Reset to framework Page defaults")
                    }
                    if !isCustom {
                        Button { showsPalettes.toggle() } label: {
                            Image(systemName: "chevron.down")
                                .frame(width: 22, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help(palette.map { "Choose colour · \($0.name)" } ?? "Choose colour")
                        .accessibilityLabel("Choose \(label)")
                        .popover(isPresented: $showsPalettes) {
                            InspectorPaletteMenu(palettes: choices.isEmpty ? [] : framework.colourPalettes,
                                                 selectedID: paletteID) { value in
                                // The source binding updates source and default shade atomically.
                                let role = value.hasPrefix("framework.") ? FrameworkColorRole(rawValue: String(value.dropFirst(6))) : nil
                                source = role?.rawValue ?? value
                                showsPalettes = false
                            }
                            .padding(10)
                            .frame(width: 260)
                            .controlSize(.small)
                        }
                    }
                    if allowsCustom {
                        FrameworkModeToggle(usesFrameworkTokens: !isCustom) {
                            source = isCustom
                                ? (choices.first?.value ?? source)
                                : PartFrameworkValueSelection.manualCustom
                        }
                    }
                }
    }
}

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
    var usesThemeBase = false
    let select: (String) -> Void
    @State private var search = ""

    private var filtered: [ColourPalette] {
        palettes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func menuColour(_ palette: ColourPalette) -> String {
        let resolved = palettes.resolvedPalette(id: palette.id) ?? palette
        let shade = usesThemeBase && BootstrapPaletteTheme.nativeRole(resolved) == nil
            ? ColourShade.seven : resolved.defaultShade(for: appearance)
        return resolved.colour(at: .shade(shade))
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search colours", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search colours")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach([ColourPalette.Origin.custom, .framework, .standard], id: \.self) { group in
                        let matches = filtered.filter { $0.origin == group }
                        if !matches.isEmpty {
                            Text(group == .custom ? "Custom Colours" : (group == .framework ? "Framework Colours" : "Bootstrap Hue Scales"))
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
                    if filtered.isEmpty { Text("No matching colours").foregroundStyle(.secondary).padding(6) }
                }
            }
            .frame(maxHeight: 320)
        }
    }
}

#Preview("Framework colour") {
    @Previewable @State var source = FrameworkColorRole.accent.rawValue
    @Previewable @State var color = Color.blue.opacity(0.75)
    @Previewable @State var shade = ColourShade.six
    @Previewable @State var opacityPercent = 75.0

    PartControlPreview {
        FrameworkColorPartControl(
            label: "Colour",
            choices: Framework.standard.colorChoices,
            allowsCustom: true,
            framework: .standard,
            source: $source,
            shade: $shade,
            customColor: $color,
            opacityPercent: $opacityPercent,
            allowsOpacity: true,
            indicator: .preview
        )
    }
}
