import Foundation

nonisolated struct Framework: Codable, Equatable, Sendable {
    var colourPalettes: [ColourPalette]

    /// The shared colour roles that a reusable framework owns. Project custom colours
    /// and Foundry's standard library are not part of a saved framework.
    var fixedFrameworkColourPalettes: [ColourPalette] {
        let ids = Set(FrameworkColorRole.allCases.map { "framework." + $0.rawValue })
        return colourPalettes.filter { $0.origin == .framework && ids.contains($0.id) }
    }

    /// Exactly the settings persisted in a reusable framework bundle.
    var savedSettings: Framework {
        var settings = self
        settings.colourPalettes = fixedFrameworkColourPalettes
        // Breakpoints and container widths belong to the project. Keep a neutral
        // value in reusable bundles; applying a framework preserves project screens.
        settings.screens = .standard
        return settings
    }

    var colors: ColorTokens {
        get {
            func value(_ id: String) -> String {
                colourPalettes.resolvedPalette(id: "framework." + id)?.colour(at: .default) ?? "#000000"
            }
            return .init(background: value("background"), surface: value("background"), text: value("foreground"),
                         accent: value("accent"), links: value("primary"))
        }
        set {
            let values = [("background", newValue.background), ("foreground", newValue.text),
                          ("accent", newValue.accent), ("primary", newValue.links)]
            for (id, hex) in values {
                guard let index = colourPalettes.firstIndex(where: { $0.id == "framework." + id }),
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
    var borderWidths: FrameworkDimensionTokens
    var borderRadii: FrameworkDimensionTokens
    var zIndexes: FrameworkDimensionTokens

    init(
        spacing: SpacingTokens,
        shadows: ShadowTokens = .standard,
        typography: TypographyTokens,
        screens: ScreenTokens = .standard,
        borderWidths: FrameworkDimensionTokens = .standardBorderWidths,
        borderRadii: FrameworkDimensionTokens = .standardBorderRadii,
        zIndexes: FrameworkDimensionTokens = .standardZIndexes
    ) {
        self.colourPalettes = ColourPaletteDefaults.make()
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
            // Standard hues come from the installed Bootstrap version, never a
            // saved copy of the obsolete Foundry/Tailwind-like catalogue.
            colourPalettes = palettes.filter { $0.origin != .standard }
            if palettes.contains(where: { $0.origin == .standard }) {
                colourPalettes += ColourPaletteDefaults.standard
            }
        } else {
            // Definitions without palettes use the bundled Bootstrap defaults.
            colourPalettes = ColourPaletteDefaults.make()
        }
        spacing = try container.decode(SpacingTokens.self, forKey: .spacing)
        shadows = try container.decodeIfPresent(ShadowTokens.self, forKey: .shadows) ?? .standard
        typography = try container.decode(TypographyTokens.self, forKey: .typography)
        screens = try container.decode(ScreenTokens.self, forKey: .screens)
        borderWidths = try container.decodeIfPresent(FrameworkDimensionTokens.self, forKey: .borderWidths) ?? .standardBorderWidths
        borderRadii = try container.decodeIfPresent(FrameworkDimensionTokens.self, forKey: .borderRadii) ?? .standardBorderRadii
        zIndexes = try container.decodeIfPresent(FrameworkDimensionTokens.self, forKey: .zIndexes) ?? .standardZIndexes
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

    static let standard = Framework(
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

nonisolated struct FrameworkDimensionToken: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    var value: Double
}

/// A user-created value extending one of the dimension scales. The CSS
/// variable prefix comes from the owning scale (border-width, border-radius
/// or z-index), so the same shape serves all three.
nonisolated struct FrameworkCustomDimension: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var value: Double

    init(id: UUID = UUID(), name: String, value: Double) {
        self.id = id
        self.name = name
        self.value = value
    }

    func cssVariable(prefix: String) -> String {
        "--foundry-\(prefix)-custom-\(id.uuidString.lowercased())"
    }

    var reference: String {
        "custom:\(id.uuidString.lowercased())"
    }
}

nonisolated struct FrameworkDimensionTokens: Codable, Equatable, Sendable {
    var predefined: [FrameworkDimensionToken]
    var custom: [FrameworkCustomDimension] = []

    static let standardBorderWidths = FrameworkDimensionTokens(predefined: [
        .init(id: "none", title: "None", value: 0),
        .init(id: "xs", title: "XS", value: 0.5),
        .init(id: "sm", title: "SM", value: 1),
        .init(id: "md", title: "MD", value: 2),
        .init(id: "lg", title: "LG", value: 4),
        .init(id: "xl", title: "XL", value: 8)
    ])

    static let standardBorderRadii = FrameworkDimensionTokens(predefined: [
        .init(id: "none", title: "None", value: 0),
        .init(id: "xs", title: "XS", value: 2),
        .init(id: "sm", title: "SM", value: 4),
        .init(id: "md", title: "MD", value: 8),
        .init(id: "lg", title: "LG", value: 12),
        .init(id: "xl", title: "XL", value: 16),
        .init(id: "2xl", title: "2XL", value: 24),
        .init(id: "full", title: "Full", value: 9_999)
    ])

    static let standardZIndexes = FrameworkDimensionTokens(predefined: [
        .init(id: "base", title: "Base", value: 0),
        .init(id: "dropdown", title: "Dropdown", value: 1_000),
        .init(id: "sticky", title: "Sticky", value: 1_100),
        .init(id: "overlay", title: "Overlay", value: 1_200),
        .init(id: "modal", title: "Modal", value: 1_300),
        .init(id: "tooltip", title: "Tooltip", value: 1_400),
        .init(id: "toast", title: "Toast", value: 1_500)
    ])
}

nonisolated enum FrameworkScreenID: String, Codable, CaseIterable, Identifiable, Sendable {
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

nonisolated enum FrameworkContainerUnit: String, Codable, CaseIterable, Identifiable, Sendable {
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

nonisolated struct FrameworkContainerWidth: Codable, Equatable, Sendable {
    var value: Double
    var unit: FrameworkContainerUnit
}

nonisolated struct FrameworkScreen: Codable, Equatable, Identifiable, Sendable {
    let id: FrameworkScreenID
    var isEnabled: Bool
    var minimumWidth: Double
    var container: FrameworkContainerWidth
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

    var screens: [FrameworkScreen]

    var enabledScreens: [FrameworkScreen] {
        screens.filter(\.isEnabled).sorted { $0.minimumWidth < $1.minimumWidth }
    }

    func screen(_ id: FrameworkScreenID) -> FrameworkScreen {
        screens.first(where: { $0.id == id })
            ?? Self.standard.screens.first(where: { $0.id == id })
            ?? FrameworkScreen(id: id, isEnabled: true, minimumWidth: 0, container: .init(value: 0, unit: .auto))
    }

    func activeScreen(for viewportWidth: Double) -> FrameworkScreen {
        enabledScreens.last(where: { $0.minimumWidth <= viewportWidth }) ?? screen(.mobile)
    }

    func canvasWidth(for screen: FrameworkScreen) -> Double {
        guard screen.id == .mobile else { return screen.minimumWidth }
        let nextMinimum = enabledScreens.first(where: { $0.id != .mobile })?.minimumWidth ?? 640
        return max(320, min(390, nextMinimum - 1))
    }

    mutating func update(_ id: FrameworkScreenID, _ update: (inout FrameworkScreen) -> Void) {
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

    private func containerCSSValue(for screen: FrameworkScreen) -> String {
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

nonisolated enum FrameworkColorRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case primary
    case accent
    case success
    case danger
    case warning
    case info
    case inverse
    case secondary
    case background
    case foreground
    case border

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

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
        threeExtraLarge: 24,
        fourExtraLarge: 32
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
    var fourExtraLarge: Double
    var custom: [FrameworkSpacing]

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
        fourExtraLarge: Double = 32,
        custom: [FrameworkSpacing] = []
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
        self.fourExtraLarge = fourExtraLarge
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
        case fourExtraLarge
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
        fourExtraLarge = try container.decode(Double.self, forKey: .fourExtraLarge)
        custom = try container.decode([FrameworkSpacing].self, forKey: .custom)
    }

    func matchesPredefinedScale(of other: SpacingTokens) -> Bool {
        threeExtraSmall == other.threeExtraSmall &&
            doubleExtraSmall == other.doubleExtraSmall &&
            extraSmall == other.extraSmall &&
            small == other.small &&
            medium == other.medium &&
            large == other.large &&
            extraLarge == other.extraLarge &&
            doubleExtraLarge == other.doubleExtraLarge &&
            threeExtraLarge == other.threeExtraLarge &&
            fourExtraLarge == other.fourExtraLarge
    }

    var usesStandardPredefinedScale: Bool { matchesPredefinedScale(of: .standard) }
}

nonisolated struct FrameworkSpacing: Codable, Equatable, Identifiable, Sendable {
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
    var predefined: [FrameworkShadow]
    var custom: [FrameworkShadow]

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

    init(predefined: [FrameworkShadow], custom: [FrameworkShadow]) {
        self.predefined = Self.migratingLegacyDefault(in: predefined)
        self.custom = custom
    }

    private enum CodingKeys: String, CodingKey {
        case predefined, custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        predefined = Self.migratingLegacyDefault(
            in: try container.decode([FrameworkShadow].self, forKey: .predefined)
        )
        custom = try container.decodeIfPresent([FrameworkShadow].self, forKey: .custom) ?? []
    }

    var shadows: [FrameworkShadow] { custom + predefined }

    private static func migratingLegacyDefault(in values: [FrameworkShadow]) -> [FrameworkShadow] {
        var result = values.filter { $0.id != "default" }
        if !result.contains(where: { $0.id == "sm" }),
           let legacyDefault = values.first(where: { $0.id == "default" }) {
            result.append(.init(id: "sm", title: "SM", layers: legacyDefault.layers))
        }
        return result
    }
}

nonisolated struct FrameworkShadow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var layers: [FrameworkShadowLayer]

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

nonisolated struct FrameworkShadowLayer: Codable, Equatable, Identifiable, Sendable {
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

    /// CSS drop shadows have no inset or spread. Their blur argument is a
    /// standard deviation, half the corresponding box-shadow blur radius.
    var dropShadowCSS: String? {
        guard !isInset else { return nil }
        return "drop-shadow(\(x.rounded().cssNumber)px \(y.rounded().cssNumber)px \((max(0, blur) / 2).cssNumber)px \(cssColor))"
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

    var bodyFont: FrameworkFontDefinition
    var headingFont: FrameworkFontDefinition
    var monospacedFont: FrameworkFontDefinition
    var customFonts: [FrameworkCustomFont]
    var predefinedFontSizes: [FrameworkFontSize]
    var customFontSizes: [FrameworkFontSize]

    static let standardFontSizes: [FrameworkFontSize] = [
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
        bodyFont: FrameworkFontDefinition,
        headingFont: FrameworkFontDefinition,
        monospacedFont: FrameworkFontDefinition,
        customFonts: [FrameworkCustomFont],
        predefinedFontSizes: [FrameworkFontSize] = Self.standardFontSizes,
        customFontSizes: [FrameworkFontSize]
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
        bodyFont = try container.decode(FrameworkFontDefinition.self, forKey: .bodyFont)
        headingFont = try container.decode(FrameworkFontDefinition.self, forKey: .headingFont)
        monospacedFont = try container.decode(FrameworkFontDefinition.self, forKey: .monospacedFont)
        customFonts = try container.decode([FrameworkCustomFont].self, forKey: .customFonts)
        predefinedFontSizes = try container.decode([FrameworkFontSize].self, forKey: .predefinedFontSizes)
        customFontSizes = try container.decode([FrameworkFontSize].self, forKey: .customFontSizes)
    }

    var fontSizes: [FrameworkFontSize] {
        let reservedIDs = Set(Self.standardFontSizes.map(\.id))
        return predefinedFontSizes + customFontSizes.filter { !reservedIDs.contains($0.id) }
    }

    var usesStandardPredefinedFontSizes: Bool {
        predefinedFontSizes == Self.standardFontSizes
    }
}

nonisolated struct FrameworkFontSize: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var size: Double
    var lineHeight: Double
}

nonisolated struct FrameworkCustomFont: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var font: FrameworkFontDefinition

    init(id: UUID = UUID(), name: String, font: FrameworkFontDefinition) {
        self.id = id
        self.name = name
        self.font = font
    }
}

nonisolated struct FrameworkFontDefinition: Codable, Equatable, Sendable {
    var family: String
    var fallbacks: [String]
    var source: FrameworkFontSource
    var weights: [Int]
    var styles: [FrameworkFontStyle]
    /// The last Font Names configuration, retained while another source is active.
    var systemFontNames: [String]? = nil
    var googleConfiguration: GoogleFontConfiguration? = nil

    static func system(family: String, weights: [Int]) -> FrameworkFontDefinition {
        FrameworkFontDefinition(
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

nonisolated enum FrameworkFontSource: Codable, Equatable, Sendable {
    case system
    case bundled(files: [String])
    case remote(stylesheetURL: URL)
}

nonisolated enum FrameworkFontStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case italic

    var id: String { rawValue }
}

nonisolated enum FrameworkFontRole: String, Codable, CaseIterable, Identifiable, Sendable {
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

nonisolated enum FrameworkFontReference: Codable, Equatable, Hashable, Sendable {
    case role(FrameworkFontRole)
    case custom(UUID)
}

nonisolated extension Framework {
    var colorChoices: [PartPropertyChoice] {
        FrameworkColorRole.allCases.map { .init(value: $0.rawValue, label: $0.title) }
    }

    func color(for role: FrameworkColorRole, appearance: SiteAppearance = .light) -> String {
        guard let palette = colourPalettes.resolvedPalette(id: "framework." + role.rawValue) else { return "#000000" }
        return palette.colour(at: .shade(palette.defaultShade(for: appearance)))
    }

    var fontFamilyChoices: [PartPropertyChoice] {
        let custom: [PartPropertyChoice] = typography.customFonts.map { font in
            PartPropertyChoice(
                value: overriddenFontRole(named: font.name)?.rawValue
                    ?? "custom:\(font.id.uuidString.lowercased())",
                label: font.name,
                separatorBefore: false
            )
        }
        let overriddenRoles = Set(custom.compactMap { FrameworkFontRole(rawValue: $0.value) })
        let availableRoles = FrameworkFontRole.allCases.filter { !overriddenRoles.contains($0) }
        let predefined = availableRoles.enumerated().map { index, role in
            PartPropertyChoice(
                value: role.rawValue,
                label: role.title,
                separatorBefore: index == 0 && !custom.isEmpty
            )
        }
        return custom + predefined
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
            ("3xl", "3XL", spacing.threeExtraLarge),
            ("4xl", "4XL", spacing.fourExtraLarge)
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
        }.joined() + borderWidths.custom.map {
            "\($0.cssVariable(prefix: "border-width")):\($0.value.cssNumber)px;"
        }.joined()
        let radii = borderRadii.predefined.map {
            "--foundry-border-radius-\($0.id):\($0.value.cssNumber)px;"
        }.joined() + borderRadii.custom.map {
            "\($0.cssVariable(prefix: "border-radius")):\($0.value.cssNumber)px;"
        }.joined()
        return widths + radii
    }

    /// Custom values lead: they are the user's own, so pickers surface them
    /// above the predefined scale.
    var zIndexChoices: [PartPropertyChoice] {
        zIndexes.custom.map { .init(value: $0.reference, label: $0.name) }
        + zIndexes.predefined.enumerated().map { index, token in
            .init(value: token.id, label: token.title, separatorBefore: index == 0 && !zIndexes.custom.isEmpty)
        }
    }

    func zIndexCSSVariable(for reference: String) -> String {
        if zIndexes.predefined.contains(where: { $0.id == reference }) {
            return "var(--foundry-z-index-\(reference))"
        }
        if let custom = zIndexes.custom.first(where: { $0.reference == reference }) {
            return "var(\(custom.cssVariable(prefix: "z-index")))"
        }
        return "var(--foundry-z-index-base)"
    }

    var zIndexCSSVariables: String {
        zIndexes.predefined.map {
            "--foundry-z-index-\($0.id):\($0.value.cssNumber);"
        }.joined() + zIndexes.custom.map {
            "\($0.cssVariable(prefix: "z-index")):\($0.value.cssNumber);"
        }.joined()
    }

    func spacingCSSVariable(for reference: String) -> String? {
        let predefined = Set(["3xs", "2xs", "xs", "sm", "md", "lg", "xl", "2xl", "3xl", "4xl"])
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
        let predefined = "--foundry-spacing-base:\(SpacingTokens.baseRem)rem;--foundry-space-3xs:calc(var(--foundry-spacing-base) * \(spacing.threeExtraSmall));--foundry-space-2xs:calc(var(--foundry-spacing-base) * \(spacing.doubleExtraSmall));--foundry-space-xs:calc(var(--foundry-spacing-base) * \(spacing.extraSmall));--foundry-space-sm:calc(var(--foundry-spacing-base) * \(spacing.small));--foundry-space-md:calc(var(--foundry-spacing-base) * \(spacing.medium));--foundry-space-lg:calc(var(--foundry-spacing-base) * \(spacing.large));--foundry-space-xl:calc(var(--foundry-spacing-base) * \(spacing.extraLarge));--foundry-space-2xl:calc(var(--foundry-spacing-base) * \(spacing.doubleExtraLarge));--foundry-space-3xl:calc(var(--foundry-spacing-base) * \(spacing.threeExtraLarge));--foundry-space-4xl:calc(var(--foundry-spacing-base) * \(spacing.fourExtraLarge));"
        return predefined + spacing.custom.map {
            "\($0.cssVariable):calc(var(--foundry-spacing-base) * \($0.value));"
        }.joined()
    }

    func fontCSSVariable(for reference: String) -> String {
        if let custom = typography.customFonts.first(where: {
            overriddenFontRole(named: $0.name)?.rawValue == reference
        }) {
            return "var(--foundry-font-custom-\(custom.id.uuidString.lowercased()))"
        }
        switch reference {
        case FrameworkFontRole.heading.rawValue:
            return "var(--foundry-font-heading)"
        case FrameworkFontRole.monospaced.rawValue:
            return "var(--foundry-font-monospace)"
        default:
            if reference.hasPrefix("custom:"),
               let id = UUID(uuidString: String(reference.dropFirst("custom:".count))),
               typography.customFonts.contains(where: { $0.id == id }) {
                return "var(--foundry-font-custom-\(id.uuidString.lowercased()))"
            } else {
                return "var(--foundry-font-body)"
            }
        }
    }

    private func overriddenFontRole(named name: String) -> FrameworkFontRole? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return FrameworkFontRole.allCases.first {
            $0.title.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    func fontSourceCSS(
        assets: ProjectAssetContents,
        destination: FrameworkFontCSSDestination,
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
             .doubleExtraLargeSpacing, .threeExtraLargeSpacing, .fourExtraLargeSpacing: nil
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
        case .fourExtraLargeSpacing: spacing.fourExtraLarge
        case .backgroundColor, .surfaceColor, .textColor, .accentColor, .linksColor: nil
        }
    }
}

nonisolated enum FrameworkFontCSSDestination: Sendable {
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
    var allFonts: [FrameworkFontDefinition] {
        [bodyFont, headingFont, monospacedFont] + customFonts.map(\.font)
    }
}
