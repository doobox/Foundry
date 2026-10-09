import Foundation

/// Retains Bootstrap's theme formulas, including inverse/secondary and nested
/// light-dark() behaviour. Framework edits remap the underlying hue references.
nonisolated enum BootstrapColorCSS {
    static func canvas(framework: Framework, appearance: SiteAppearance) -> String {
        build(framework: framework, colorScheme: appearance.rawValue)
    }

    static func export(framework: Framework, mode: SiteAppearanceMode) -> String {
        build(framework: framework, colorScheme: mode.cssColorScheme)
    }

    private static func build(framework: Framework, colorScheme: String) -> String {
        var declarations: [String] = []
        for role in FrameworkColorRole.allCases {
            let palette = framework.colourPalettes.resolvedPalette(id: "framework." + role.rawValue)
                ?? BootstrapColourCatalogue.palette(role: role)
            let originalHue = BootstrapColourCatalogue.defaultHue(for: role.rawValue)
            for token in BootstrapColourCatalogue.tokens(for: role.rawValue) {
                let name = "--bs-" + token
                guard var expression = BootstrapColourCatalogue.declarations[name] else {
                    preconditionFailure("Bundled Bootstrap is missing \(name)")
                }
                for shade in ColourShade.allCases {
                    expression = expression.replacingOccurrences(
                        of: BootstrapColourCatalogue.reference(hue: originalHue, shade: shade),
                        with: palette.cssColour(at: shade))
                }
                declarations.append("\(name):\(expression)")
            }
        }
        return "/* Bootstrap 6 framework colours */\n:root,:host{\(declarations.joined(separator: ";"))}\n"
            + ":root:not([data-bs-theme]),:host:not([data-bs-theme]){color-scheme:\(colorScheme); }"
    }
}
