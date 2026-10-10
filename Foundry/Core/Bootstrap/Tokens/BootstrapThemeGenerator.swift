import Foundation

/// Regenerates native Bootstrap role mappings from an exact 500 base. Browser
/// previews are used only for contrast selection, never as exported scale values.
@MainActor
enum BootstrapThemeGenerator {
    static func generate(role: ThemePaletteColorRole, scale: BootstrapColourScale) async throws -> ColourPalette {
        var palette = BootstrapColourCatalogue.palette(role: role)
        let shades = try await BootstrapScalePreviewResolver().resolve(scale)
        try palette.setBootstrapScale(scale, previews: shades)
        guard BootstrapColourCatalogue.themeRoles.contains(role.rawValue) else { return palette }

        var theme = Theme.standard
        theme.colourPalettes = [palette]
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(theme: theme, mode: .both)
        let expressions = ["var(--bs-\(role.rawValue)-bg)"]
        let light = try await BootstrapScalePreviewResolver().resolve(expressions: expressions, css: css, mode: "light")
        let dark = try await BootstrapScalePreviewResolver().resolve(expressions: expressions, css: css, mode: "dark")
        try Task.checkCancellation()
        palette.bootstrapGeneratedContrast = BootstrapTokenColour(
            light: foreground(on: light[0]), dark: foreground(on: dark[0]))
        return palette
    }

    private static func foreground(on hex: String) -> BootstrapColourScale? {
        // Use the exact same visual preference as the existing contrastColor API.
        // The editor's separate normal-text warning continues to use 4.5:1.
        guard let channels = PartColorChannels(hex: hex) else { return nil }
        return BootstrapColourScale.native(channels.preferredContrastColor == "#FFFFFF" ? "white" : "black")
    }
}
