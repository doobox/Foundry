import Foundation

nonisolated enum ColourPaletteDefaults {
    static func make() -> [ColourPalette] {
        ThemePaletteColorRole.allCases.map { BootstrapColourCatalogue.palette(role: $0) } + standard
    }

    static let standard: [ColourPalette] = {
        (["black", "white"] + BootstrapColourCatalogue.hues).map { hue in
            let single = hue == "black" || hue == "white"
            let shades = single
                ? Array(repeating: hue == "black" ? "#000000" : "#FFFFFF", count: ColourShade.allCases.count)
                : BootstrapColourCatalogue.previews.palettes[hue]!
            var palette = try! ColourPalette(id: "standard." + hue, name: hue.capitalized, origin: .standard,
                shades: shades, lightDefaultShade: .seven, darkDefaultShade: .seven)
            palette.bootstrapHue = hue
            palette.single = single
            return palette
        }
    }()
}
