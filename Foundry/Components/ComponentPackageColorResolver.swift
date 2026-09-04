import Foundation

nonisolated enum ComponentPackageColorResolver {
    static func resolve(
        _ value: ComponentPackageColorValue,
        theme: Theme,
        colorMath: Bool,
        opacity: Bool
    ) -> String {
        let baseColor: String
        if ComponentThemeValueSelection.isManualCustom(value.source) {
            baseColor = value.customColor
        } else if let role = ThemeColorRole(rawValue: value.source) {
            baseColor = theme.color(for: role)
        } else {
            baseColor = value.customColor
        }
        let adjustedColor: String
        if colorMath {
            let adjustment = min(max(value.adjustment, -100), 100)
            adjustedColor = ComponentTemplateRenderer.transformColor(
                baseColor,
                target: adjustment < 0 ? 0 : 255,
                amount: abs(adjustment) / 100
            )
        } else {
            adjustedColor = baseColor
        }
        guard opacity, ComponentThemeValueSelection.isManualCustom(value.source) else { return adjustedColor }
        return ComponentTemplateRenderer.colorWithAlpha(
            adjustedColor,
            alpha: min(max(value.opacity, 0), 1)
        )
    }
}
