import Foundation

/// A palette supplies a complete Bootstrap theme, never per-component overrides.
nonisolated enum BootstrapPaletteTheme {
    static func paletteID(_ selection: String) -> String {
        if selection.hasPrefix("theme-"), BootstrapColourCatalogue.themeRoles.contains(String(selection.dropFirst(6))) {
            return "framework." + selection.dropFirst(6)
        }
        return selection
    }

    static func nativeRole(_ palette: ColourPalette) -> String? {
        let role = String(palette.id.dropFirst("framework.".count))
        return palette.id.hasPrefix("framework.") && BootstrapColourCatalogue.themeRoles.contains(role) ? role : nil
    }

    static func className(for palette: ColourPalette) -> String {
        if let role = nativeRole(palette) { return "theme-" + role }
        if palette.origin == .standard, let hue = palette.bootstrapHue,
           (["black", "white"] + BootstrapColourCatalogue.hues).contains(hue) { return "theme-" + hue }
        // Reversible CSS-safe identity: independent of display name and collision-free.
        return "theme-palette-" + palette.id.utf8.map { String(format: "%02x", $0) }.joined()
    }

    static func resolve(_ selection: String, framework: Framework) -> String {
        guard let palette = framework.colourPalettes.resolvedPalette(id: paletteID(selection)) else { return "theme-reset" }
        return className(for: palette)
    }

    static func properties(for palette: ColourPalette) -> [(String, String)] {
        BootstrapColourCatalogue.themeProperties.map { property in
            var expression = BootstrapColourCatalogue.declarations["--bs-primary-" + property]!
            for shade in ColourShade.allCases {
                let colour: String
                if palette.single {
                    colour = BootstrapColourCatalogue.declarations["--bs-blue-" + shade.bootstrapLabel]!
                        .replacingOccurrences(of: BootstrapColourCatalogue.declarations["--bs-blue-500"]!,
                                              with: palette.cssColour(at: .seven))
                } else { colour = palette.cssColour(at: shade) }
                expression = expression.replacingOccurrences(of: BootstrapColourCatalogue.reference(hue: "blue", shade: shade), with: colour)
            }
            if property == "contrast" { expression = contrast(for: palette) }
            return ("--bs-theme-" + property, expression)
        }
    }

    private static func contrast(for palette: ColourPalette) -> String {
        let hex = palette.shades[6].trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return "var(--bs-white)" }
        func linear(_ byte: UInt32) -> Double {
            let x = Double(byte) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((value >> 16) & 255) + 0.7152 * linear((value >> 8) & 255) + 0.0722 * linear(value & 255)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? "var(--bs-black)" : "var(--bs-white)"
    }

    static func css(framework: Framework) -> String {
        let rules = framework.colourPalettes.filter { nativeRole($0) == nil }.map { palette in
            let tokens = properties(for: palette).map { "\($0.0):\($0.1)" }.joined(separator: ";")
            return ".\(className(for: palette)){\(tokens)}"
        }
        return "\n@layer helpers{\(rules.joined(separator: "\n"))}"
    }
}
