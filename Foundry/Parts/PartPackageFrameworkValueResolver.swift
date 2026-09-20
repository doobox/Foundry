import Foundation

nonisolated enum PartPackageFrameworkValueResolver {
    static func choices(
        for source: PartPackageFrameworkValueSource,
        framework: Framework
    ) -> [PartPropertyChoice] {
        switch source {
        case .colors: framework.colorChoices
        case .fontFamilies: framework.fontFamilyChoices
        case .fontSizes: framework.fontSizeChoices
        case .spacing: framework.spacingChoices
        case .shadows: framework.shadowChoices
        }
    }

    static func resolve(
        _ reference: String,
        from source: PartPackageFrameworkValueSource,
        framework: Framework
    ) -> String? {
        switch source {
        case .colors:
            guard let role = FrameworkColorRole(rawValue: reference) else { return nil }
            return framework.color(for: role)
        case .fontFamilies:
            guard framework.fontFamilyChoices.contains(where: { $0.value == reference }) else { return nil }
            return framework.fontCSSVariable(for: reference)
        case .fontSizes:
            guard framework.fontSizeChoices.contains(where: { $0.value == reference }) else { return nil }
            return framework.fontSizeCSSVariable(for: reference)
        case .spacing:
            return framework.spacingCSSVariable(for: reference)
        case .shadows:
            return framework.shadowCSSVariable(for: reference)
        }
    }
}
