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

    static func resolveFontSizeLineHeight(
        _ value: ComponentPackageFontSizeValue,
        usesThemeValues: Bool,
        theme: Theme
    ) -> String {
        guard usesThemeValues,
              !ComponentThemeValueSelection.isManualCustom(value.source) else {
            return validCustomLineHeight(value.customLineHeight) ?? "1.5"
        }
        return theme.lineHeightCSSVariable(for: value.source)
    }

    private static func validCustomLineHeight(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        let pattern = #"^(normal|(?:\d+(?:\.\d*)?|\.\d+)(?:px|rem|em|%|vw|vh|vmin|vmax|ch|ex)?)$"#
        guard trimmedValue.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }
        return trimmedValue
    }
}
