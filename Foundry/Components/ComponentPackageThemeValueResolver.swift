import Foundation

nonisolated enum ComponentPackageThemeValueResolver {
    static func choices(
        for source: ComponentPackageThemeValueSource,
        theme: Theme
    ) -> [ComponentPropertyChoice] {
        switch source {
        case .colors: theme.colorChoices
        case .fontFamilies: theme.fontFamilyChoices
        case .fontSizes: theme.fontSizeChoices
        case .spacing: theme.spacingChoices
        }
    }

    static func resolve(
        _ reference: String,
        from source: ComponentPackageThemeValueSource,
        theme: Theme
    ) -> String? {
        switch source {
        case .colors:
            guard let role = ThemeColorRole(rawValue: reference) else { return nil }
            return theme.color(for: role)
        case .fontFamilies:
            guard theme.fontFamilyChoices.contains(where: { $0.value == reference }) else { return nil }
            return theme.fontCSSVariable(for: reference)
        case .fontSizes:
            guard theme.fontSizeChoices.contains(where: { $0.value == reference }) else { return nil }
            return theme.fontSizeCSSVariable(for: reference)
        case .spacing:
            return theme.spacingCSSVariable(for: reference)
        }
    }
}
