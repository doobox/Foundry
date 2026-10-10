import Foundation

nonisolated extension Site {
    var hasNamedThemeOverrides: Bool {
        (framework.colourPalettes + projectFrameworkValues.colours
         + frameworkStates.flatMap { $0.framework.colourPalettes }).contains {
            $0.origin == .custom && BootstrapColourCatalogue.themeRoles.contains($0.name)
        }
    }

    /// One-time conversion of same-name custom colours into directly editable roles.
    /// This is data migration only; rendering has no override/compatibility path.
    mutating func foldNamedThemeOverrides() {
        guard hasNamedThemeOverrides else { return }
        let shared = projectFrameworkValues.colours.filter {
            $0.origin == .custom && BootstrapColourCatalogue.themeRoles.contains($0.name)
        }
        var references: [String: String] = [:]
        func fold(_ framework: inout Framework) {
            let overrides = shared + framework.colourPalettes.filter {
                $0.origin == .custom && BootstrapColourCatalogue.themeRoles.contains($0.name)
            }
            for source in overrides {
                guard let role = FrameworkColorRole(rawValue: source.name) else { continue }
                var target = BootstrapColourCatalogue.palette(role: role)
                try! target.replaceShades(source.shades)
                target.setLightDefault(source.lightDefaultShade)
                target.setDarkDefault(source.darkDefaultShade)
                target.bootstrapHue = source.bootstrapHue
                target.bootstrapScale = source.bootstrapScale
                target.bootstrapTokens = source.bootstrapTokens
                target.bootstrapGeneratedContrast = source.bootstrapGeneratedContrast
                if let index = framework.colourPalettes.firstIndex(where: { $0.id == target.id }) {
                    framework.colourPalettes[index] = target
                } else {
                    framework.colourPalettes.append(target)
                }
                references[source.id] = target.id
            }
            framework.colourPalettes.removeAll {
                $0.origin == .custom && BootstrapColourCatalogue.themeRoles.contains($0.name)
            }
        }
        fold(&framework)
        for index in frameworkStates.indices { fold(&frameworkStates[index].framework) }
        for (old, new) in references { replacePartFrameworkReference(old, with: new) }
        projectFrameworkValues.colours.removeAll { references[$0.id] != nil }
    }
}
