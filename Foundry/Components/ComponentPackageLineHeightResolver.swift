import Foundation

nonisolated enum ComponentPackageLineHeightResolver {
    static func resolve(
        _ source: String,
        fontSizeKey: ComponentProperty.Key?,
        node: ComponentNode,
        theme: Theme
    ) -> String {
        if let lineHeight = ThemeLineHeight(rawValue: source) {
            return lineHeight.value.formatted(.number.precision(.fractionLength(0...3)))
        }

        let fontSizeReference = fontSizeKey.map(node.property) ?? "base"
        let themeSizeID = theme.typography.fontSizes.contains(where: { $0.id == fontSizeReference })
            ? fontSizeReference
            : "base"
        return theme.lineHeightCSSVariable(for: themeSizeID)
    }
}
