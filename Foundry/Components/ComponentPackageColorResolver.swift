import Foundation

nonisolated enum ComponentPackageColorResolver {
    static func resolve(
        _ value: ComponentPackageColorValue,
        theme: Theme,
        opacity: Bool
    ) -> String {
        let baseColor: String
        if ComponentThemeValueSelection.isManualCustom(value.source) {
            baseColor = value.customColor
        } else if let resolved = value.selection.resolve(in: theme.colourPalettes) {
            baseColor = resolved
        } else {
            baseColor = value.customColor
        }
        guard opacity, ComponentThemeValueSelection.isManualCustom(value.source) else { return baseColor }
        return ComponentTemplateRenderer.colorWithAlpha(
            baseColor,
            alpha: min(max(value.opacity, 0), 1)
        )
    }
}
