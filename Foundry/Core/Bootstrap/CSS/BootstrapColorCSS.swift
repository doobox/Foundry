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
        let palettes = FrameworkColorRole.allCases.map { role in
            framework.colourPalettes.resolvedPalette(id: "framework." + role.rawValue)
                ?? BootstrapColourCatalogue.palette(role: role)
        } + framework.colourPalettes.filter { $0.origin == .custom && BootstrapPaletteTheme.validCustomRole($0.name) }
        for palette in palettes {
            let definition = BootstrapPaletteTheme.definitionRole(palette)
            let role = BootstrapPaletteTheme.nativeRole(palette) ?? definition
            let originalHue = BootstrapColourCatalogue.defaultHue(for: definition)
            let sourceTokens = palette.origin == .custom ? palette.colourKind.sourceTokens : BootstrapColourCatalogue.tokens(for: definition)
            for sourceToken in sourceTokens {
                let token = palette.colourToken(sourceToken)
                let name = "--bs-" + token
                guard var expression = BootstrapColourCatalogue.declarations["--bs-" + sourceToken] else {
                    preconditionFailure("Bundled Bootstrap is missing \(name)")
                }
                if palette.origin == .custom, palette.colourKind == .link {
                    for property in ["base", "fg"] {
                        if let value = BootstrapColourCatalogue.declarations["--bs-primary-" + property] {
                            expression = expression.replacingOccurrences(of: "var(--bs-primary-\(property))", with: value)
                        }
                    }
                    expression = expression.replacingOccurrences(of: "var(--bs-link-color)", with: "var(--bs-\(palette.colourToken("link-color")))")
                }
                for shade in ColourShade.allCases {
                    expression = expression.replacingOccurrences(
                        of: BootstrapColourCatalogue.reference(hue: originalHue, shade: shade),
                        with: palette.cssColour(at: shade))
                }
                if token == role + "-contrast", let generated = palette.bootstrapGeneratedContrast {
                    expression = generated.expression(default: expression)
                }
                if let override = palette.bootstrapTokens[token] {
                    expression = override.expression(default: expression)
                }
                declarations.append("\(name):\(expression)")
            }
        }
        return "/* Bootstrap 6 framework colours */\n:root,:host{\(declarations.joined(separator: ";"))}\n"
            + ":root:not([data-bs-theme]),:host:not([data-bs-theme]){color-scheme:\(colorScheme); }"
            + palettes.filter { $0.origin == .custom }.map(customClasses).joined()
            + "@layer utilities{" + BootstrapColourCatalogue.themeRoles.map {
                ".underline-\($0){--bs-underline-color:var(--bs-\($0)-fg)}:where(.underline-\($0)){text-decoration-color:var(--bs-underline-color)}"
            }.joined() + "}"
    }

    private static func customClasses(_ palette: ColourPalette) -> String {
        guard let role = BootstrapPaletteTheme.nativeRole(palette) else { return "" }
        let mappings = BootstrapColourCatalogue.themeProperties.map {
            "--bs-theme-\($0):var(--bs-\(role)-\($0))"
        }.joined(separator: ";")
        // Same composition variables and cascade layers as the bundled utility definitions.
        let utilities: [(String, String, String, String)] = [
            ("fg", "fg", "color", "fg"), ("fg-emphasis", "fg", "color", "fg-emphasis"),
            ("fg-contrast", "fg", "color", "contrast"),
            ("bg", "bg", "background-color", "bg"), ("bg-subtle", "bg", "background-color", "bg-subtle"),
            ("bg-muted", "bg", "background-color", "bg-muted"),
            ("border", "bc", "border-color", "bg"), ("border-subtle", "bc", "border-color", "border"),
            ("underline", "underline-color", "text-decoration-color", "fg")
        ]
        let rules = utilities.map { name, variable, property, token in
            ".\(name)-\(role){--bs-\(variable):var(--bs-\(role)-\(token))}:where(.\(name)-\(role)){\(property):var(--bs-\(variable))}"
        }.joined()
        return "@layer helpers{.theme-\(role){\(mappings)}}@layer utilities{\(rules).shadow-\(role){--bs-sc:var(--bs-\(role)-base)}}"
    }
}
