import Foundation

nonisolated struct Theme: Codable, Equatable, Sendable {
    var colourPalettes: [ColourPalette]

    /// The shared colour roles that a reusable theme owns. Project custom colours
    /// and Foundry's standard library are not part of a saved theme.
    var fixedThemeColourPalettes: [ColourPalette] {
        let ids = Set(ThemeColorRole.allCases.map { "theme." + $0.rawValue })
        return colourPalettes.filter { $0.origin == .theme && ids.contains($0.id) }
    }

    /// Exactly the settings persisted in a reusable theme bundle.
    var savedSettings: Theme {
        var settings = self
        settings.colourPalettes = fixedThemeColourPalettes
        // Breakpoints and container widths belong to the project. Keep a neutral
        // value in reusable bundles; applying a theme preserves project screens.
        settings.screens = .standard
        return settings
    }

    var colors: ColorTokens {
        get {
            func value(_ id: String) -> String {
                colourPalettes.resolvedPalette(id: "theme." + id)?.colour(at: .default) ?? "#000000"
            }
            return .init(background: value("background"), surface: value("surface"), text: value("text"),
                         accent: value("accent"), links: value("links"))
        }
        set {
            let values = [("background", newValue.background), ("surface", newValue.surface),
                          ("text", newValue.text), ("accent", newValue.accent), ("links", newValue.links)]
            for (id, hex) in values {
                guard let index = colourPalettes.firstIndex(where: { $0.id == "theme." + id }),
                      colourPalettes[index].colour(at: .default) != hex else { continue }
                var shades = colourPalettes[index].shades
                shades[colourPalettes[index].lightDefaultShade.rawValue - 1] = hex
                try? colourPalettes[index].replaceShades(shades)
                colourPalettes[index].generation = nil
            }
        }
    }
    var spacing: SpacingTokens
    var shadows: ShadowTokens
    var typography: TypographyTokens
    var screens: ScreenTokens
    var borderWidths: ThemeDimensionTokens
    var borderRadii: ThemeDimensionTokens
    var zIndexes: ThemeDimensionTokens

    init(
        colors: ColorTokens,
        spacing: SpacingTokens,
        shadows: ShadowTokens = .standard,
        typography: TypographyTokens,
        screens: ScreenTokens = .standard,
        borderWidths: ThemeDimensionTokens = .standardBorderWidths,
        borderRadii: ThemeDimensionTokens = .standardBorderRadii,
        zIndexes: ThemeDimensionTokens = .standardZIndexes
    ) {
        self.colourPalettes = ColourPaletteDefaults.make(colors: colors)
        self.spacing = spacing
        self.shadows = shadows
        self.typography = typography
        self.screens = screens
        self.borderWidths = borderWidths
        self.borderRadii = borderRadii
        self.zIndexes = zIndexes
    }

    enum CodingKeys: String, CodingKey {
        case colors, colourPalettes, spacing, shadows, typography, screens, borderWidths, borderRadii, zIndexes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let palettes = try container.decodeIfPresent([ColourPalette].self, forKey: .colourPalettes) {
            colourPalettes = palettes
        } else {
            // Bundled theme definitions may still provide the concise role colours.
            colourPalettes = ColourPaletteDefaults.make(colors: try container.decode(ColorTokens.self, forKey: .colors))
        }
        spacing = try container.decode(SpacingTokens.self, forKey: .spacing)
        shadows = try container.decodeIfPresent(ShadowTokens.self, forKey: .shadows) ?? .standard
        typography = try container.decode(TypographyTokens.self, forKey: .typography)
        screens = try container.decode(ScreenTokens.self, forKey: .screens)
        borderWidths = try container.decodeIfPresent(ThemeDimensionTokens.self, forKey: .borderWidths) ?? .standardBorderWidths
        borderRadii = try container.decodeIfPresent(ThemeDimensionTokens.self, forKey: .borderRadii) ?? .standardBorderRadii
        zIndexes = try container.decodeIfPresent(ThemeDimensionTokens.self, forKey: .zIndexes) ?? .standardZIndexes
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(colourPalettes, forKey: .colourPalettes)
        try values.encode(spacing, forKey: .spacing)
        try values.encode(shadows, forKey: .shadows)
        try values.encode(typography, forKey: .typography)
        try values.encode(screens, forKey: .screens)
        try values.encode(borderWidths, forKey: .borderWidths)
        try values.encode(borderRadii, forKey: .borderRadii)
        try values.encode(zIndexes, forKey: .zIndexes)
    }

    static let standard = Theme(
        colors: .init(
            background: "#F7F7F8",
            surface: "#FFFFFF",
            text: "#171719",
            accent: "#5B5BD6",
            links: "#5B5BD6"
        ),
        spacing: .standard,
        typography: .init(
            bodyFont: .system(family: "system-ui", weights: [400, 500, 600, 700]),
            headingFont: .system(family: "system-ui", weights: [500, 600, 700, 800]),
            monospacedFont: .system(family: "ui-monospace", weights: [400, 500, 600, 700]),
            customFonts: [],
            customFontSizes: []
        )
    )
}

nonisolated struct ThemeDimensionToken: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    var value: Double
}

nonisolated struct ThemeDimensionTokens: Codable, Equatable, Sendable {
    var predefined: [ThemeDimensionToken]

    static let standardBorderWidths = ThemeDimensionTokens(predefined: [
        .init(id: "none", title: "None", value: 0),
        .init(id: "xs", title: "XS", value: 0.5),
        .init(id: "sm", title: "SM", value: 1),
        .init(id: "md", title: "MD", value: 2),
        .init(id: "lg", title: "LG", value: 4),
        .init(id: "xl", title: "XL", value: 8)
    ])

    static let standardBorderRadii = ThemeDimensionTokens(predefined: [
        .init(id: "none", title: "None", value: 0),
        .init(id: "xs", title: "XS", value: 2),
        .init(id: "sm", title: "SM", value: 4),
        .init(id: "md", title: "MD", value: 8),
        .init(id: "lg", title: "LG", value: 12),
        .init(id: "xl", title: "XL", value: 16),
        .init(id: "2xl", title: "2XL", value: 24),
        .init(id: "full", title: "Full", value: 9_999)
    ])

    static let standardZIndexes = ThemeDimensionTokens(predefined: [
        .init(id: "base", title: "Base", value: 0),
        .init(id: "dropdown", title: "Dropdown", value: 1_000),
        .init(id: "sticky", title: "Sticky", value: 1_100),
        .init(id: "overlay", title: "Overlay", value: 1_200),
        .init(id: "modal", title: "Modal", value: 1_300),
        .init(id: "tooltip", title: "Tooltip", value: 1_400),
        .init(id: "toast", title: "Toast", value: 1_500)
    ])
}

nonisolated enum ThemeScreenID: String, Codable, CaseIterable, Identifiable, Sendable {
    case mobile, small, medium, large, extraLarge, doubleExtraLarge

    var id: String { rawValue }
    var shortTitle: String {
        switch self {
        case .mobile: "XS"
        case .small: "SM"
        case .medium: "MD"
        case .large: "LG"
        case .extraLarge: "XL"
        case .doubleExtraLarge: "2XL"
        }
    }
    var systemImage: String {
        switch self {
        case .mobile: "iphone"
        case .small: "iphone.landscape"
        case .medium: "ipad"
        case .large: "ipad.landscape"
        case .extraLarge: "laptopcomputer"
        case .doubleExtraLarge: "desktopcomputer"
        }
    }
}

nonisolated enum ThemeContainerUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, pixels, viewportWidth, percent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Auto"
        case .pixels: "Pixels"
        case .viewportWidth: "Viewport Width"
        case .percent: "%"
        }
    }
}

nonisolated struct ThemeContainerWidth: Codable, Equatable, Sendable {
    var value: Double
    var unit: ThemeContainerUnit
}

nonisolated struct ThemeScreen: Codable, Equatable, Identifiable, Sendable {
    let id: ThemeScreenID
    var isEnabled: Bool
    var minimumWidth: Double
    var container: ThemeContainerWidth
}

nonisolated struct ScreenTokens: Codable, Equatable, Sendable {
    static let standard = ScreenTokens(screens: [
        .init(id: .mobile, isEnabled: true, minimumWidth: 0, container: .init(value: 0, unit: .auto)),
        .init(id: .small, isEnabled: true, minimumWidth: 640, container: .init(value: 640, unit: .auto)),
        .init(id: .medium, isEnabled: true, minimumWidth: 768, container: .init(value: 768, unit: .auto)),
        .init(id: .large, isEnabled: true, minimumWidth: 1024, container: .init(value: 1024, unit: .auto)),
        .init(id: .extraLarge, isEnabled: true, minimumWidth: 1280, container: .init(value: 1280, unit: .auto)),
        .init(id: .doubleExtraLarge, isEnabled: true, minimumWidth: 1536, container: .init(value: 1536, unit: .auto))
    ])

    var screens: [ThemeScreen]

    var enabledScreens: [ThemeScreen] {
        screens.filter(\.isEnabled).sorted { $0.minimumWidth < $1.minimumWidth }
    }

    func screen(_ id: ThemeScreenID) -> ThemeScreen {
        screens.first(where: { $0.id == id })
            ?? Self.standard.screens.first(where: { $0.id == id })
            ?? ThemeScreen(id: id, isEnabled: true, minimumWidth: 0, container: .init(value: 0, unit: .auto))
    }

    func activeScreen(for viewportWidth: Double) -> ThemeScreen {
        enabledScreens.last(where: { $0.minimumWidth <= viewportWidth }) ?? screen(.mobile)
    }

    func canvasWidth(for screen: ThemeScreen) -> Double {
        guard screen.id == .mobile else { return screen.minimumWidth }
        let nextMinimum = enabledScreens.first(where: { $0.id != .mobile })?.minimumWidth ?? 640
        return max(320, min(390, nextMinimum - 1))
    }

    mutating func update(_ id: ThemeScreenID, _ update: (inout ThemeScreen) -> Void) {
        guard let index = screens.firstIndex(where: { $0.id == id }) else { return }
        update(&screens[index])
        screens[index].isEnabled = id == .mobile ? true : screens[index].isEnabled
        if id == .mobile {
            screens[index].minimumWidth = 0
        } else {
            let lowerBound = id == .small
                ? 321
                : (index > screens.startIndex ? screens[index - 1].minimumWidth + 1 : 1)
            let upperBound = index < screens.index(before: screens.endIndex)
                ? screens[index + 1].minimumWidth - 1
                : .greatestFiniteMagnitude
            screens[index].minimumWidth = min(max(screens[index].minimumWidth, lowerBound), upperBound)
        }
        screens[index].container.value = max(0, screens[index].container.value)
    }

    var containerCSS: String {
        screens.compactMap { screen in
            guard screen.isEnabled else { return nil }
            let value = containerCSSValue(for: screen)
            if screen.id == .mobile {
                return ":root{--foundry-container-width:\(value)}"
            }
            return "@media(min-width:\(screen.minimumWidth.cssNumber)px){:root{--foundry-container-width:\(value)}}"
        }.joined(separator: "\n")
    }

    private func containerCSSValue(for screen: ThemeScreen) -> String {
        switch screen.container.unit {
        case .auto: screen.id == .mobile ? "none" : "\(screen.minimumWidth.cssNumber)px"
        case .pixels: "\(screen.container.value.cssNumber)px"
        case .viewportWidth: "\(screen.container.value.cssNumber)vw"
        case .percent: "\(screen.container.value.cssNumber)%"
        }
    }
}

nonisolated private extension Double {
    var cssNumber: String {
        rounded() == self ? String(Int(self)) : formatted(.number.precision(.fractionLength(0...3)))
    }
}

nonisolated struct ColorTokens: Codable, Equatable, Sendable {
    var background: String
    var surface: String
    var text: String
    var accent: String
    var links: String

    enum CodingKeys: String, CodingKey {
        case background, surface, text, accent, links
    }

    init(background: String, surface: String, text: String, accent: String, links: String) {
        self.background = background
        self.surface = surface
        self.text = text
        self.accent = accent
        self.links = links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = try container.decode(String.self, forKey: .background)
        surface = try container.decode(String.self, forKey: .surface)
        text = try container.decode(String.self, forKey: .text)
        accent = try container.decode(String.self, forKey: .accent)
        links = try container.decode(String.self, forKey: .links)
    }
}

nonisolated enum ThemeColorRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case page
    case background
    case surface
    case text
    case mutedText = "muted-text"
    case accent
    case links

    var id: String { rawValue }
    var title: String { self == .mutedText ? "Muted Text" : rawValue.capitalized }
}

nonisolated struct SpacingTokens: Codable, Equatable, Sendable {
    static let baseRem = 0.25
    static let standard = SpacingTokens(
        threeExtraSmall: 1,
        doubleExtraSmall: 2,
        extraSmall: 3,
        small: 4,
        medium: 6,
        large: 8,
        extraLarge: 12,
        doubleExtraLarge: 16,
        threeExtraLarge: 24
    )

    var threeExtraSmall: Double
    var doubleExtraSmall: Double
    var extraSmall: Double
    var small: Double
    var medium: Double
    var large: Double
    var extraLarge: Double
    var doubleExtraLarge: Double
    var threeExtraLarge: Double
    var custom: [ThemeSpacing]

    init(
        threeExtraSmall: Double = 1,
        doubleExtraSmall: Double = 2,
        extraSmall: Double = 3,
        small: Double,
        medium: Double,
        large: Double,
        extraLarge: Double = 12,
        doubleExtraLarge: Double = 16,
        threeExtraLarge: Double = 24,
        custom: [ThemeSpacing] = []
    ) {
        self.threeExtraSmall = threeExtraSmall
        self.doubleExtraSmall = doubleExtraSmall
        self.extraSmall = extraSmall
        self.small = small
        self.medium = medium
        self.large = large
        self.extraLarge = extraLarge
        self.doubleExtraLarge = doubleExtraLarge
        self.threeExtraLarge = threeExtraLarge
        self.custom = custom
    }

    enum CodingKeys: String, CodingKey {
        case threeExtraSmall
        case doubleExtraSmall
        case extraSmall
        case small
        case medium
        case large
        case extraLarge
        case doubleExtraLarge
        case threeExtraLarge
        case custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threeExtraSmall = try container.decode(Double.self, forKey: .threeExtraSmall)
        doubleExtraSmall = try container.decode(Double.self, forKey: .doubleExtraSmall)
        extraSmall = try container.decode(Double.self, forKey: .extraSmall)
        small = try container.decode(Double.self, forKey: .small)
        medium = try container.decode(Double.self, forKey: .medium)
        large = try container.decode(Double.self, forKey: .large)
        extraLarge = try container.decode(Double.self, forKey: .extraLarge)
        doubleExtraLarge = try container.decode(Double.self, forKey: .doubleExtraLarge)
        threeExtraLarge = try container.decode(Double.self, forKey: .threeExtraLarge)
        custom = try container.decode([ThemeSpacing].self, forKey: .custom)
    }

    var usesStandardPredefinedScale: Bool {
        threeExtraSmall == Self.standard.threeExtraSmall &&
            doubleExtraSmall == Self.standard.doubleExtraSmall &&
            extraSmall == Self.standard.extraSmall &&
            small == Self.standard.small &&
            medium == Self.standard.medium &&
            large == Self.standard.large &&
            extraLarge == Self.standard.extraLarge &&
            doubleExtraLarge == Self.standard.doubleExtraLarge &&
            threeExtraLarge == Self.standard.threeExtraLarge
    }
}

nonisolated struct ThemeSpacing: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var value: Double

    init(id: UUID = UUID(), name: String, value: Double) {
        self.id = id
        self.name = name
        self.value = value
    }

    var cssVariable: String {
        "--foundry-space-custom-\(id.uuidString.lowercased())"
    }
}

nonisolated struct ShadowTokens: Codable, Equatable, Sendable {
    var predefined: [ThemeShadow]
    var custom: [ThemeShadow]

    static let standard = ShadowTokens(
        predefined: [
            .init(id: "none", title: "None", layers: []),
            .init(id: "inner", title: "Inner", layers: [
                .init(x: 0, y: 2, blur: 4, opacity: 0.06, isInset: true)
            ]),
            .init(id: "xs", title: "XS", layers: [
                .init(x: 0, y: 1, blur: 2, opacity: 0.05)
            ]),
            .init(id: "sm", title: "SM", layers: [
                .init(x: 0, y: 1, blur: 3, opacity: 0.10),
                .init(x: 0, y: 1, blur: 2, opacity: 0.10)
            ]),
            .init(id: "md", title: "MD", layers: [
                .init(x: 0, y: 4, blur: 6, opacity: 0.10),
                .init(x: 0, y: 2, blur: 4, opacity: 0.10)
            ]),
            .init(id: "lg", title: "LG", layers: [
                .init(x: 0, y: 10, blur: 15, opacity: 0.10),
                .init(x: 0, y: 4, blur: 6, opacity: 0.10)
            ]),
            .init(id: "xl", title: "XL", layers: [
                .init(x: 0, y: 20, blur: 25, opacity: 0.10),
                .init(x: 0, y: 8, blur: 10, opacity: 0.10)
            ]),
            .init(id: "2xl", title: "2XL", layers: [
                .init(x: 0, y: 25, blur: 50, opacity: 0.25)
            ])
        ],
        custom: []
    )

    init(predefined: [ThemeShadow], custom: [ThemeShadow]) {
        self.predefined = Self.migratingLegacyDefault(in: predefined)
        self.custom = custom
    }

    private enum CodingKeys: String, CodingKey {
        case predefined, custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        predefined = Self.migratingLegacyDefault(
            in: try container.decode([ThemeShadow].self, forKey: .predefined)
        )
        custom = try container.decodeIfPresent([ThemeShadow].self, forKey: .custom) ?? []
    }

    var shadows: [ThemeShadow] { custom + predefined }

    private static func migratingLegacyDefault(in values: [ThemeShadow]) -> [ThemeShadow] {
        var result = values.filter { $0.id != "default" }
        if !result.contains(where: { $0.id == "sm" }),
           let legacyDefault = values.first(where: { $0.id == "default" }) {
            result.append(.init(id: "sm", title: "SM", layers: legacyDefault.layers))
        }
        return result
    }
}

nonisolated struct ThemeShadow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var layers: [ThemeShadowLayer]

    var cssValue: String {
        layers.isEmpty ? "none" : layers.map(\.cssValue).joined(separator: ", ")
    }

    var cssVariable: String {
        if id.hasPrefix("user-") {
            return "--foundry-shadow-custom-\(id.dropFirst("user-".count))"
        }
        return "--foundry-shadow-\(id)"
    }
}

nonisolated struct ThemeShadowLayer: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var x: Double
    var y: Double
    var blur: Double
    var spread: Double
    var color: String
    var opacity: Double
    var isInset: Bool

    init(
        id: UUID = UUID(),
        x: Double,
        y: Double,
        blur: Double,
        spread: Double = 0,
        color: String = "#000000",
        opacity: Double,
        isInset: Bool = false
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.blur = blur
        self.spread = spread
        self.color = color
        self.opacity = opacity
        self.isInset = isInset
    }

    var cssValue: String {
        let inset = isInset ? "inset " : ""
        return "\(inset)\(x.rounded().cssNumber)px \(y.rounded().cssNumber)px \(max(0, blur).cssNumber)px \(spread.rounded().cssNumber)px \(cssColor)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, x, y, blur, spread, color, opacity, isInset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        blur = try container.decode(Double.self, forKey: .blur)
        spread = try container.decodeIfPresent(Double.self, forKey: .spread) ?? 0
        color = try container.decode(String.self, forKey: .color)
        opacity = try container.decode(Double.self, forKey: .opacity)
        isInset = try container.decode(Bool.self, forKey: .isInset)
    }

    private var cssColor: String {
        let hex = color.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return "rgb(0 0 0 / \(min(max(opacity, 0), 1).cssNumber))"
        }
        return "rgb(\((value >> 16) & 255) \((value >> 8) & 255) \(value & 255) / \(min(max(opacity, 0), 1).cssNumber))"
    }
}

nonisolated struct TypographyTokens: Codable, Equatable, Sendable {
    static let rootSize = 16.0

    var bodyFont: ThemeFontDefinition
    var headingFont: ThemeFontDefinition
    var monospacedFont: ThemeFontDefinition
    var customFonts: [ThemeCustomFont]
    var predefinedFontSizes: [ThemeFontSize]
    var customFontSizes: [ThemeFontSize]

    static let standardFontSizes: [ThemeFontSize] = [
        .init(id: "xs", title: "XS", size: 0.75, lineHeight: 4 / 3),
        .init(id: "sm", title: "SM", size: 0.875, lineHeight: 10 / 7),
        .init(id: "base", title: "MD", size: 1, lineHeight: 1.5),
        .init(id: "lg", title: "LG", size: 1.125, lineHeight: 14 / 9),
        .init(id: "xl", title: "XL", size: 1.25, lineHeight: 1.4),
        .init(id: "2xl", title: "2XL", size: 1.5, lineHeight: 4 / 3),
        .init(id: "3xl", title: "3XL", size: 1.875, lineHeight: 1.2),
        .init(id: "4xl", title: "4XL", size: 2.25, lineHeight: 10 / 9),
        .init(id: "5xl", title: "5XL", size: 3, lineHeight: 1),
        .init(id: "6xl", title: "6XL", size: 3.75, lineHeight: 1),
        .init(id: "7xl", title: "7XL", size: 4.5, lineHeight: 1),
        .init(id: "8xl", title: "8XL", size: 6, lineHeight: 1),
        .init(id: "9xl", title: "9XL", size: 8, lineHeight: 1)
    ]

    init(
        bodyFont: ThemeFontDefinition,
        headingFont: ThemeFontDefinition,
        monospacedFont: ThemeFontDefinition,
        customFonts: [ThemeCustomFont],
        predefinedFontSizes: [ThemeFontSize] = Self.standardFontSizes,
        customFontSizes: [ThemeFontSize]
    ) {
        self.bodyFont = bodyFont
        self.headingFont = headingFont
        self.monospacedFont = monospacedFont
        self.customFonts = customFonts
        self.predefinedFontSizes = predefinedFontSizes
        self.customFontSizes = customFontSizes
    }

    enum CodingKeys: String, CodingKey {
        case bodyFont, headingFont, monospacedFont, customFonts, predefinedFontSizes, customFontSizes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bodyFont = try container.decode(ThemeFontDefinition.self, forKey: .bodyFont)
        headingFont = try container.decode(ThemeFontDefinition.self, forKey: .headingFont)
        monospacedFont = try container.decode(ThemeFontDefinition.self, forKey: .monospacedFont)
        customFonts = try container.decode([ThemeCustomFont].self, forKey: .customFonts)
        predefinedFontSizes = try container.decode([ThemeFontSize].self, forKey: .predefinedFontSizes)
        customFontSizes = try container.decode([ThemeFontSize].self, forKey: .customFontSizes)
    }

    var fontSizes: [ThemeFontSize] {
        let reservedIDs = Set(Self.standardFontSizes.map(\.id))
        return predefinedFontSizes + customFontSizes.filter { !reservedIDs.contains($0.id) }
    }

    var usesStandardPredefinedFontSizes: Bool {
        predefinedFontSizes == Self.standardFontSizes
    }
}

nonisolated struct ThemeFontSize: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var size: Double
    var lineHeight: Double
}

nonisolated struct ThemeCustomFont: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var font: ThemeFontDefinition

    init(id: UUID = UUID(), name: String, font: ThemeFontDefinition) {
        self.id = id
        self.name = name
        self.font = font
    }
}

nonisolated struct ThemeFontDefinition: Codable, Equatable, Sendable {
    var family: String
    var fallbacks: [String]
    var source: ThemeFontSource
    var weights: [Int]
    var styles: [ThemeFontStyle]
    /// The last Font Names configuration, retained while another source is active.
    var systemFontNames: [String]? = nil
    var googleConfiguration: GoogleFontConfiguration? = nil

    static func system(family: String, weights: [Int]) -> ThemeFontDefinition {
        ThemeFontDefinition(
            family: family,
            fallbacks: [],
            source: .system,
            weights: weights,
            styles: [.normal],
            systemFontNames: [family]
        )
    }

    var cssFamily: String {
        ([family] + fallbacks).joined(separator: ", ")
    }

    static func googleStylesheetURL(for family: String) -> URL? {
        let encodedFamily = family
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "+")
        return URL(string: "https://fonts.googleapis.com/css2?family=\(encodedFamily)&display=swap")
    }
}

nonisolated enum ThemeFontSource: Codable, Equatable, Sendable {
    case system
    case bundled(files: [String])
    case remote(stylesheetURL: URL)
}

nonisolated enum ThemeFontStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case italic

    var id: String { rawValue }
}

nonisolated enum ThemeFontRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case body
    case heading
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: "Body"
        case .heading: "Heading"
        case .monospaced: "Monospaced"
        }
    }

    var systemImage: String {
        switch self {
        case .body: "text.alignleft"
        case .heading: "textformat.size.larger"
        case .monospaced: "chevron.left.forwardslash.chevron.right"
        }
    }
}

nonisolated enum ThemeFontReference: Codable, Equatable, Hashable, Sendable {
    case role(ThemeFontRole)
    case custom(UUID)
}

nonisolated extension Theme {
    var colorChoices: [PartPropertyChoice] {
        ThemeColorRole.allCases.map { .init(value: $0.rawValue, label: $0.title) }
    }

    func color(for role: ThemeColorRole, appearance: SiteAppearance = .light) -> String {
        if appearance == .dark, let palette = colourPalettes.resolvedPalette(id: "theme." + role.rawValue) {
            return palette.colour(at: .shade(palette.darkDefaultShade))
        }
        return switch role {
        case .page: colourPalettes.resolvedPalette(id: "theme.page")?.colour(at: .default) ?? "#000000"
        case .background: colors.background
        case .surface: colors.surface
        case .text: colors.text
        case .mutedText: colourPalettes.resolvedPalette(id: "theme.muted-text")?.colour(at: .default) ?? colors.text
        case .accent: colors.accent
        case .links: colors.links
        }
    }

    var fontFamilyChoices: [PartPropertyChoice] {
        [
            .init(value: ThemeFontRole.body.rawValue, label: ThemeFontRole.body.title),
            .init(value: ThemeFontRole.heading.rawValue, label: ThemeFontRole.heading.title),
            .init(value: ThemeFontRole.monospaced.rawValue, label: ThemeFontRole.monospaced.title)
        ] + typography.customFonts.enumerated().map { index, font in
            .init(
                value: "custom:\(font.id.uuidString.lowercased())",
                label: font.name,
                separatorBefore: index == 0
            )
        }
    }

    var fontSizeChoices: [PartPropertyChoice] {
        typography.fontSizes.enumerated().map { index, size in
            return .init(
                value: size.id,
                label: size.title,
                separatorBefore: index == TypographyTokens.standardFontSizes.count && !typography.customFontSizes.isEmpty
            )
        }
    }

    var spacingChoices: [PartPropertyChoice] {
        let predefined: [(String, String, Double)] = [
            ("3xs", "3XS", spacing.threeExtraSmall),
            ("2xs", "2XS", spacing.doubleExtraSmall),
            ("xs", "XS", spacing.extraSmall),
            ("sm", "SM", spacing.small),
            ("md", "MD", spacing.medium),
            ("lg", "LG", spacing.large),
            ("xl", "XL", spacing.extraLarge),
            ("2xl", "2XL", spacing.doubleExtraLarge),
            ("3xl", "3XL", spacing.threeExtraLarge)
        ]
        return predefined.map { id, title, _ in
            return .init(
                value: id,
                label: title
            )
        } + spacing.custom.enumerated().map { index, item in
            return .init(
                value: "custom:\(item.id.uuidString.lowercased())",
                label: item.name,
                separatorBefore: index == 0
            )
        }
    }

    var shadowChoices: [PartPropertyChoice] {
        shadows.shadows.enumerated().map { index, shadow in
            .init(
                value: shadow.id,
                label: shadow.title,
                separatorBefore: index == shadows.custom.count && !shadows.custom.isEmpty
            )
        }
    }

    func shadowCSSVariable(for reference: String) -> String? {
        let migratedReference = reference == "default" ? "sm" : reference
        guard let shadow = shadows.shadows.first(where: { $0.id == migratedReference }) else { return nil }
        return "var(\(shadow.cssVariable))"
    }

    var shadowCSSVariables: String {
        shadows.shadows.map { "\($0.cssVariable):\($0.cssValue);" }.joined()
    }

    var borderCSSVariables: String {
        let widths = borderWidths.predefined.map {
            "--foundry-border-width-\($0.id):\($0.value.cssNumber)px;"
        }.joined()
        let radii = borderRadii.predefined.map {
            "--foundry-border-radius-\($0.id):\($0.value.cssNumber)px;"
        }.joined()
        return widths + radii
    }

    var zIndexCSSVariables: String {
        zIndexes.predefined.map {
            "--foundry-z-index-\($0.id):\($0.value.cssNumber);"
        }.joined()
    }

    func spacingCSSVariable(for reference: String) -> String? {
        let predefined = Set(["3xs", "2xs", "xs", "sm", "md", "lg", "xl", "2xl", "3xl"])
        if predefined.contains(reference) {
            return "var(--foundry-space-\(reference))"
        }
        guard reference.hasPrefix("custom:"),
              let id = UUID(uuidString: String(reference.dropFirst("custom:".count))),
              let spacing = spacing.custom.first(where: { $0.id == id }) else {
            return nil
        }
        return "var(\(spacing.cssVariable))"
    }

    func fontSizeCSSVariable(for reference: String) -> String {
        let id = typography.fontSizes.contains(where: { $0.id == reference }) ? reference : "base"
        return "var(--foundry-font-size-\(id))"
    }

    func lineHeightCSSVariable(for reference: String) -> String {
        let id = typography.fontSizes.contains(where: { $0.id == reference }) ? reference : "base"
        return "var(--foundry-font-size-\(id)-line-height)"
    }

    var fontSizeCSSVariables: String {
        typography.fontSizes.map {
            "--foundry-font-size-\($0.id):\($0.size)rem;--foundry-font-size-\($0.id)-line-height:\($0.lineHeight);"
        }.joined()
    }

    var spacingCSSVariables: String {
        let predefined = "--foundry-spacing-base:\(SpacingTokens.baseRem)rem;--foundry-space-3xs:calc(var(--foundry-spacing-base) * \(spacing.threeExtraSmall));--foundry-space-2xs:calc(var(--foundry-spacing-base) * \(spacing.doubleExtraSmall));--foundry-space-xs:calc(var(--foundry-spacing-base) * \(spacing.extraSmall));--foundry-space-sm:calc(var(--foundry-spacing-base) * \(spacing.small));--foundry-space-md:calc(var(--foundry-spacing-base) * \(spacing.medium));--foundry-space-lg:calc(var(--foundry-spacing-base) * \(spacing.large));--foundry-space-xl:calc(var(--foundry-spacing-base) * \(spacing.extraLarge));--foundry-space-2xl:calc(var(--foundry-spacing-base) * \(spacing.doubleExtraLarge));--foundry-space-3xl:calc(var(--foundry-spacing-base) * \(spacing.threeExtraLarge));"
        return predefined + spacing.custom.map {
            "\($0.cssVariable):calc(var(--foundry-spacing-base) * \($0.value));"
        }.joined()
    }

    func fontCSSVariable(for reference: String) -> String {
        switch reference {
        case ThemeFontRole.heading.rawValue:
            "var(--foundry-font-heading)"
        case ThemeFontRole.monospaced.rawValue:
            "var(--foundry-font-monospace)"
        default:
            if reference.hasPrefix("custom:"),
               let id = UUID(uuidString: String(reference.dropFirst("custom:".count))),
               typography.customFonts.contains(where: { $0.id == id }) {
                "var(--foundry-font-custom-\(id.uuidString.lowercased()))"
            } else {
                "var(--foundry-font-body)"
            }
        }
    }

    func fontSourceCSS(
        assets: ProjectAssetContents,
        destination: ThemeFontCSSDestination,
        exportedSource: ((ProjectAsset) -> String)? = nil
    ) -> String {
        let rules = typography.allFonts.flatMap { definition -> [String] in
            switch definition.source {
            case .system:
                return []
            case .remote(let stylesheetURL):
                return ["@import url('\(stylesheetURL.absoluteString)');"]
            case .bundled(let files):
                let family = files.compactMap { reference -> FontFileMetadata? in
                    guard let id = reference.foundryAssetID, let content = assets[id] else { return nil }
                    return FontFileMetadata.read(content)
                }.first
                return files.compactMap { reference in
                    guard let id = reference.foundryAssetID,
                          let content = assets[id],
                          let metadata = FontFileMetadata.read(content),
                          let family, metadata.belongsToSameFamily(as: family) else { return nil }
                    let source = switch destination {
                    case .canvas:
                        "data:\(content.asset.mediaType);base64,\(content.data.base64EncodedString())"
                    case .export:
                        exportedSource?(content.asset) ?? content.asset.storageFilename
                    }
                    return "@font-face{font-family:'\(definition.family.cssSingleQuoted)';src:url('\(source)');font-style:\(metadata.cssStyle);font-weight:\(metadata.cssWeight);font-display:swap;}"
                }
            }
        }
        var emitted = Set<String>()
        return rules.filter { emitted.insert($0).inserted }
            .joined(separator: "\n")
    }

    var customFontCSSVariables: String {
        typography.customFonts.map { font in
            "--foundry-font-custom-\(font.id.uuidString.lowercased()):\(font.font.cssFamily);"
        }.joined()
    }

    func color(for token: DesignToken) -> String? {
        switch token {
        case .backgroundColor: colors.background
        case .surfaceColor: colors.surface
        case .textColor: colors.text
        case .accentColor: colors.accent
        case .linksColor: colors.links
        case .threeExtraSmallSpacing, .doubleExtraSmallSpacing, .extraSmallSpacing,
             .smallSpacing, .mediumSpacing, .largeSpacing, .extraLargeSpacing,
             .doubleExtraLargeSpacing, .threeExtraLargeSpacing: nil
        }
    }

    func number(for token: DesignToken) -> Double? {
        switch token {
        case .threeExtraSmallSpacing: spacing.threeExtraSmall
        case .doubleExtraSmallSpacing: spacing.doubleExtraSmall
        case .extraSmallSpacing: spacing.extraSmall
        case .smallSpacing: spacing.small
        case .mediumSpacing: spacing.medium
        case .largeSpacing: spacing.large
        case .extraLargeSpacing: spacing.extraLarge
        case .doubleExtraLargeSpacing: spacing.doubleExtraLarge
        case .threeExtraLargeSpacing: spacing.threeExtraLarge
        case .backgroundColor, .surfaceColor, .textColor, .accentColor, .linksColor: nil
        }
    }
}

nonisolated enum ThemeFontCSSDestination: Sendable {
    case canvas
    case export
}

private nonisolated extension String {
    var cssSingleQuoted: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}

nonisolated extension TypographyTokens {
    var allFonts: [ThemeFontDefinition] {
        [bodyFont, headingFont, monospacedFont] + customFonts.map(\.font)
    }
}
