import Foundation

/// Native semantic roles and custom themes share Bootstrap's token contract.
nonisolated enum BootstrapPaletteTheme {
    private static let bundledClasses: Set<String> = {
        let css = BootstrapColourCatalogue.sourceCSS
        let regex = try! NSRegularExpression(pattern: #"\.([a-z][a-z0-9-]*)\{"#)
        return Set(regex.matches(in: css, range: NSRange(css.startIndex..., in: css)).compactMap {
            Range($0.range(at: 1), in: css).map { String(css[$0]) }
        })
    }()
    static func paletteID(_ selection: String) -> String {
        if selection.hasPrefix("theme-"), BootstrapColourCatalogue.themeRoles.contains(String(selection.dropFirst(6))) {
            return "framework." + selection.dropFirst(6)
        }
        return selection
    }

    static func nativeRole(_ palette: ColourPalette) -> String? {
        if palette.origin == .custom, palette.id.hasPrefix("custom.") {
            let role = palette.name
            return validCustomRole(role) ? role : nil
        }
        let role = String(palette.id.dropFirst("framework.".count))
        return palette.id.hasPrefix("framework.") && BootstrapColourCatalogue.themeRoles.contains(role) ? role : nil
    }

    static func validCustomRole(_ name: String) -> Bool {
        return name.range(of: #"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil
            && !(BootstrapColourCatalogue.themeRoles + BootstrapColourCatalogue.hues
                 + ["black", "white", "body", "reset", "inherit", "transparent", "current", "background", "foreground", "border"]).contains(name)
            && ["theme", "fg", "fg-emphasis", "fg-contrast", "bg", "bg-subtle", "bg-muted", "border", "border-subtle", "underline", "shadow"]
                .allSatisfy { !bundledClasses.contains($0 + "-" + name) }
    }

    static func definitionRole(_ palette: ColourPalette) -> String {
        palette.origin == .custom ? "primary" : String(palette.id.dropFirst("framework.".count))
    }

    /// Apply a generated native theme without changing a custom colour's saved identity.
    static func applying(_ source: ColourPalette, to target: ColourPalette) -> ColourPalette {
        guard target.origin == .custom, let role = nativeRole(target) else { return source }
        var result = target
        try! result.replaceShades(source.shades)
        result.setLightDefault(source.lightDefaultShade)
        result.setDarkDefault(source.darkDefaultShade)
        result.bootstrapHue = source.bootstrapHue
        result.bootstrapScale = source.bootstrapScale
        result.bootstrapGeneratedContrast = source.bootstrapGeneratedContrast
        let sourceRole = definitionRole(source)
        result.bootstrapTokens = Dictionary(uniqueKeysWithValues: source.bootstrapTokens.map {
            ($0.key.replacingOccurrences(of: sourceRole + "-", with: role + "-"), $0.value)
        })
        return result
    }

    static func selectablePalettes(in framework: Framework) -> [ColourPalette] {
        framework.colourPalettes.filter { nativeRole($0) != nil }
    }

    static func effectivePalette(_ selection: String, in framework: Framework) -> ColourPalette? {
        selectablePalettes(in: framework).resolvedPalette(id: paletteID(selection))
    }

    static func resolve(_ selection: String, framework: Framework) -> String {
        guard let palette = framework.colourPalettes.resolvedPalette(id: paletteID(selection)),
              let role = nativeRole(palette) else { return "theme-reset" }
        return "theme-" + role
    }
}
