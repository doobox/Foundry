import Foundation

/// Reusable Bootstrap appearance only. Project layout and additions are not presets.
nonisolated struct ThemePreset: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var colourPalettes: [ColourPalette]
    var bodyFont: ThemeFontDefinition
    var headingFont: ThemeFontDefinition
    var monospacedFont: ThemeFontDefinition
    var bootstrapTokens: BootstrapEditorTokens

    init(_ theme: Theme) {
        colourPalettes = theme.fixedThemeColourPalettes
        bodyFont = theme.typography.bodyFont
        headingFont = theme.typography.headingFont
        monospacedFont = theme.typography.monospacedFont
        let supported = Set(BootstrapEditorSection.allCases.flatMap { $0.tokens.map(\.id) })
        bootstrapTokens = .init(values: theme.bootstrapTokens.values.filter { supported.contains($0.key) })
    }

    var theme: Theme {
        var result = Theme.standard
        result.colourPalettes = colourPalettes
        result.typography.bodyFont = bodyFont
        result.typography.headingFont = headingFont
        result.typography.monospacedFont = monospacedFont
        result.bootstrapTokens = bootstrapTokens
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, colourPalettes, bodyFont, headingFont, monospacedFont, bootstrapTokens
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.schemaVersion) else {
            // Read old bundles once through their former model; never write that payload again.
            self.init(try Theme(from: decoder))
            return
        }
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values,
                debugDescription: "Unsupported theme preset version \(version)")
        }
        var theme = Theme.standard
        if let palettes = try values.decodeIfPresent([ColourPalette].self, forKey: .colourPalettes) {
            theme.colourPalettes = palettes
        }
        theme.typography.bodyFont = try values.decodeIfPresent(ThemeFontDefinition.self, forKey: .bodyFont) ?? theme.typography.bodyFont
        theme.typography.headingFont = try values.decodeIfPresent(ThemeFontDefinition.self, forKey: .headingFont) ?? theme.typography.headingFont
        theme.typography.monospacedFont = try values.decodeIfPresent(ThemeFontDefinition.self, forKey: .monospacedFont) ?? theme.typography.monospacedFont
        theme.bootstrapTokens = try values.decodeIfPresent(BootstrapEditorTokens.self, forKey: .bootstrapTokens) ?? .init()
        self.init(theme)
    }
}
