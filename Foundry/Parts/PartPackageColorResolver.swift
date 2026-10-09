import Foundation

nonisolated enum PartPackageColorResolver {
    static func resolve(
        _ value: PartPackageColorValue,
        framework: Framework,
        opacity: Bool,
        appearance: SiteAppearance = .light
    ) -> String {
        let baseColor: String
        if PartFrameworkValueSelection.isManualCustom(value.source) {
            baseColor = appearance == .light ? value.customColor : value.darkCustomColor
        } else if let palette = framework.colourPalettes.resolvedPalette(id: value.paletteID) {
            baseColor = palette.cssColour(at: appearance == .light ? value.shade : value.darkShade)
        } else {
            baseColor = value.customColor
        }
        guard opacity else { return baseColor }
        let alpha = min(max(appearance == .light ? value.opacity : value.darkOpacity, 0), 1)
        if alpha == 1, !PartFrameworkValueSelection.isManualCustom(value.source) { return baseColor }
        return PartTemplateRenderer.colorWithAlpha(
            baseColor,
            alpha: alpha
        )
    }

    /// The sRGB channels behind one appearance's selection, for derived template
    /// values (channels, contrast, filters). Follows the same fallbacks as `resolve`
    /// Native Bootstrap colours use their browser-generated sRGB projection; nil only
    /// when that colour is not parseable hex — callers then omit the derived fields
    /// rather than inventing numbers.
    static func channels(
        _ value: PartPackageColorValue,
        framework: Framework,
        opacity: Bool,
        appearance: SiteAppearance
    ) -> PartColorChannels? {
        let baseColor: String
        if PartFrameworkValueSelection.isManualCustom(value.source) {
            baseColor = appearance == .light ? value.customColor : value.darkCustomColor
        } else if let resolved = PaletteColourValue.palette(id: value.paletteID, selection: .shade(appearance == .light ? value.shade : value.darkShade)).resolve(in: framework.colourPalettes) {
            baseColor = resolved
        } else {
            baseColor = value.customColor
        }
        guard let channels = PartColorChannels(hex: baseColor) else { return nil }
        guard opacity else { return channels }
        return channels.withAlpha(min(max(appearance == .light ? value.opacity : value.darkOpacity, 0), 1))
    }
}
