import Foundation

nonisolated extension Site {
    var hasNamedThemeOverrides: Bool {
        (theme.colourPalettes + projectThemeValues.colours
         + themeStates.flatMap { $0.theme.colourPalettes }).contains {
            $0.origin == .custom && BootstrapColourCatalogue.themeRoles.contains($0.name)
        }
    }

    /// One-time conversion of same-name custom colours into directly editable roles.
    /// This is data migration only; rendering has no override/compatibility path.
    mutating func foldNamedThemeOverrides() {
        guard hasNamedThemeOverrides else { return }
        let shared = projectThemeValues.colours.filter {
            $0.origin == .custom && BootstrapColourCatalogue.themeRoles.contains($0.name)
        }
        var references: [String: String] = [:]
        func fold(_ theme: inout Theme) {
            let overrides = shared + theme.colourPalettes.filter {
                $0.origin == .custom && BootstrapColourCatalogue.themeRoles.contains($0.name)
            }
            for source in overrides {
                guard let role = ThemePaletteColorRole(rawValue: source.name) else { continue }
                var target = BootstrapColourCatalogue.palette(role: role)
                try! target.replaceShades(source.shades)
                target.setLightDefault(source.lightDefaultShade)
                target.setDarkDefault(source.darkDefaultShade)
                target.bootstrapHue = source.bootstrapHue
                target.bootstrapScale = source.bootstrapScale
                target.bootstrapTokens = source.bootstrapTokens
                target.bootstrapGeneratedContrast = source.bootstrapGeneratedContrast
                if let index = theme.colourPalettes.firstIndex(where: { $0.id == target.id }) {
                    theme.colourPalettes[index] = target
                } else {
                    theme.colourPalettes.append(target)
                }
                references[source.id] = target.id
            }
            theme.colourPalettes.removeAll {
                $0.origin == .custom && BootstrapColourCatalogue.themeRoles.contains($0.name)
            }
        }
        fold(&theme)
        for index in themeStates.indices { fold(&themeStates[index].theme) }
        for (old, new) in references { replacePartThemeReference(old, with: new) }
        projectThemeValues.colours.removeAll { references[$0.id] != nil }
    }
}
