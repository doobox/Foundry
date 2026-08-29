import Foundation

nonisolated enum ComponentPackageColorResolver {
    static func resolve(
        node: ComponentNode,
        key: ComponentProperty.Key,
        theme: Theme,
        customColorKey: ComponentProperty.Key,
        colorMathKey: ComponentProperty.Key?,
        opacityKey: ComponentProperty.Key?
    ) -> String {
        let source = node.property(key)
        let baseColor: String
        if source == "custom" {
            baseColor = node.colorProperty(customColorKey, theme: theme)
        } else if let role = ThemeColorRole(rawValue: source) {
            baseColor = theme.color(for: role)
        } else {
            baseColor = node.colorProperty(customColorKey, theme: theme)
        }
        let adjustedColor: String
        if let colorMathKey {
            let adjustment = min(max(node.numberProperty(colorMathKey, theme: theme), -100), 100)
            adjustedColor = ComponentTemplateRenderer.transformColor(
                baseColor,
                target: adjustment < 0 ? 0 : 255,
                amount: abs(adjustment) / 100
            )
        } else {
            adjustedColor = baseColor
        }
        guard let opacityKey else { return adjustedColor }
        return ComponentTemplateRenderer.colorWithAlpha(
            adjustedColor,
            alpha: node.numberProperty(opacityKey, theme: theme)
        )
    }
}
