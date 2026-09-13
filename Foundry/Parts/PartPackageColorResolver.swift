import Foundation

nonisolated enum PartPackageColorResolver {
    static func resolve(
        _ value: PartPackageColorValue,
        theme: Theme,
        opacity: Bool,
        appearance: SiteAppearance = .light
    ) -> String {
        let baseColor: String
        if PartThemeValueSelection.isManualCustom(value.source) {
            baseColor = appearance == .light ? value.customColor : value.darkCustomColor
        } else if let resolved = PaletteColourValue.palette(id: value.paletteID, selection: .shade(appearance == .light ? value.shade : value.darkShade)).resolve(in: theme.colourPalettes) {
            baseColor = resolved
        } else {
            baseColor = value.customColor
        }
        guard opacity, PartThemeValueSelection.isManualCustom(value.source) else { return baseColor }
        return PartTemplateRenderer.colorWithAlpha(
            baseColor,
            alpha: min(max(appearance == .light ? value.opacity : value.darkOpacity, 0), 1)
        )
    }
}
