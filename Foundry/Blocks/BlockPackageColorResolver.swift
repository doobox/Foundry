import Foundation

nonisolated enum BlockPackageColorResolver {
    static func resolve(
        _ value: BlockPackageColorValue,
        theme: Theme,
        opacity: Bool,
        appearance: SiteAppearance = .light
    ) -> String {
        let baseColor: String
        if BlockThemeValueSelection.isManualCustom(value.source) {
            baseColor = appearance == .light ? value.customColor : value.darkCustomColor
        } else if let resolved = PaletteColourValue.palette(id: value.paletteID, selection: .shade(appearance == .light ? value.shade : value.darkShade)).resolve(in: theme.colourPalettes) {
            baseColor = resolved
        } else {
            baseColor = value.customColor
        }
        guard opacity, BlockThemeValueSelection.isManualCustom(value.source) else { return baseColor }
        return BlockTemplateRenderer.colorWithAlpha(
            baseColor,
            alpha: min(max(appearance == .light ? value.opacity : value.darkOpacity, 0), 1)
        )
    }
}
