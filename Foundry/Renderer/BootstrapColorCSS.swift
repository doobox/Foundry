import Foundation

/// Runtime Bootstrap 6 color overrides compiled from the framework editor.
/// Bootstrap's distributed stylesheet owns component rules; Foundry only
/// replaces its documented semantic and layer custom properties.
nonisolated enum BootstrapColorCSS {
    private static let themeRoles: [FrameworkColorRole] = [
        .primary, .accent, .success, .danger, .warning, .info, .inverse, .secondary
    ]

    static func canvas(framework: Framework, appearance: SiteAppearance) -> String {
        build(framework: framework) { light, dark in
            appearance == .light ? light : dark
        }
    }

    static func export(framework: Framework, mode: SiteAppearanceMode) -> String {
        build(framework: framework) { light, dark in
            mode.colour(light: light, dark: dark)
        }
    }

    private static func build(
        framework: Framework,
        adaptive: (_ light: String, _ dark: String) -> String
    ) -> String {
        let themes = themeRoles.compactMap { role -> String? in
            guard let palette = framework.colourPalettes.resolvedPalette(id: "framework.\(role.rawValue)") else {
                return nil
            }
            let base = palette.colour(at: .shade(.seven))
            let focus = adaptive(
                "color-mix(in oklch, \(base) 50%, var(--bs-bg-body))",
                "color-mix(in oklch, \(base) 75%, var(--bs-bg-body))"
            )
            return [
                "--bs-\(role.rawValue)-base:\(base)",
                "--bs-\(role.rawValue)-fg:\(adaptive(shade(.eight, palette), shade(.six, palette)))",
                "--bs-\(role.rawValue)-fg-emphasis:\(adaptive(shade(.ten, palette), shade(.five, palette)))",
                "--bs-\(role.rawValue)-bg:\(base)",
                "--bs-\(role.rawValue)-bg-subtle:\(adaptive(shade(.three, palette), shade(.eleven, palette)))",
                "--bs-\(role.rawValue)-bg-muted:\(adaptive(shade(.four, palette), shade(.ten, palette)))",
                "--bs-\(role.rawValue)-border:\(adaptive(shade(.five, palette), shade(.eight, palette)))",
                "--bs-\(role.rawValue)-focus-ring:\(focus)",
                "--bs-\(role.rawValue)-contrast:\(adaptive(contrast(for: base), contrast(for: base)))"
            ].joined(separator: ";")
        }.joined(separator: ";")

        guard let backgrounds = framework.colourPalettes.resolvedPalette(id: "framework.background"),
              let foregrounds = framework.colourPalettes.resolvedPalette(id: "framework.foreground"),
              let borders = framework.colourPalettes.resolvedPalette(id: "framework.border") else {
            return ":root,:host{\(themes)}"
        }

        let layers = [
            "--bs-bg-body:\(adaptive(shade(.one, backgrounds), shade(.thirteen, backgrounds)))",
            "--bs-bg-1:\(adaptive(shade(.two, backgrounds), shade(.twelve, backgrounds)))",
            "--bs-bg-2:\(adaptive(shade(.three, backgrounds), shade(.eleven, backgrounds)))",
            "--bs-bg-3:\(adaptive(shade(.four, backgrounds), shade(.ten, backgrounds)))",
            "--bs-bg-4:\(adaptive(shade(.five, backgrounds), shade(.nine, backgrounds)))",
            "--bs-fg-body:\(adaptive(shade(.eleven, foregrounds), shade(.two, foregrounds)))",
            "--bs-fg-1:\(adaptive(shade(.ten, foregrounds), shade(.four, foregrounds)))",
            "--bs-fg-2:\(adaptive(shade(.nine, foregrounds), shade(.five, foregrounds)))",
            "--bs-fg-3:\(adaptive(shade(.eight, foregrounds), shade(.seven, foregrounds)))",
            "--bs-fg-4:\(adaptive(shade(.seven, foregrounds), shade(.eight, foregrounds)))",
            "--bs-border-body:\(adaptive(shade(.five, borders), shade(.ten, borders)))",
            "--bs-border-muted:\(adaptive(shade(.four, borders), shade(.ten, borders)))",
            "--bs-border-subtle:\(adaptive(shade(.three, borders), shade(.eleven, borders)))",
            "--bs-border-emphasized:\(adaptive(shade(.six, borders), shade(.eight, borders)))"
        ].joined(separator: ";")

        return "/* Foundry Bootstrap 6 colors */\n:root,:host{\(themes);\(layers)}"
    }

    private static func shade(_ shade: ColourShade, _ palette: ColourPalette) -> String {
        palette.colour(at: .shade(shade))
    }

    private static func contrast(for hex: String) -> String {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return "#FFFFFF" }
        let channels = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)]
            .map { channel -> Double in
                let normalized = channel / 255
                return normalized <= 0.04045 ? normalized / 12.92 : pow((normalized + 0.055) / 1.055, 2.4)
            }
        let luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        return luminance > 0.45 ? "#171719" : "#FFFFFF"
    }
}
