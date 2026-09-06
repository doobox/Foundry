import Foundation

nonisolated struct Theme: Codable, Equatable, Sendable {
    var colors: ColorTokens
    var spacing: SpacingTokens
    var typography: TypographyTokens
    var screens: ScreenTokens

    init(
        colors: ColorTokens,
        spacing: SpacingTokens,
        typography: TypographyTokens,
        screens: ScreenTokens = .standard
    ) {
        self.colors = colors
        self.spacing = spacing
        self.typography = typography
        self.screens = screens
    }

    enum CodingKeys: String, CodingKey {
        case colors, spacing, typography, screens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colors = try container.decode(ColorTokens.self, forKey: .colors)
        spacing = try container.decode(SpacingTokens.self, forKey: .spacing)
        typography = try container.decode(TypographyTokens.self, forKey: .typography)
        screens = try container.decode(ScreenTokens.self, forKey: .screens)
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
        case .doubleExtraLarge: "XXL"
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
        case .viewportWidth: "View Width"
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
    case background
    case surface
    case text
    case accent
    case links

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

nonisolated struct TypographyTokens: Codable, Equatable, Sendable {
    static let rootSize = 16.0

    var bodyFont: ThemeFontDefinition
    var headingFont: ThemeFontDefinition
    var monospacedFont: ThemeFontDefinition
    var customFonts: [ThemeCustomFont]
    var predefinedFontSizes: [ThemeFontSize]
    var customFontSizes: [ThemeFontSize]

    static let standardFontSizes: [ThemeFontSize] = [
        .init(id: "xs", title: "xs", size: 0.75, lineHeight: 4 / 3),
        .init(id: "sm", title: "sm", size: 0.875, lineHeight: 10 / 7),
        .init(id: "base", title: "base", size: 1, lineHeight: 1.5),
        .init(id: "lg", title: "lg", size: 1.125, lineHeight: 14 / 9),
        .init(id: "xl", title: "xl", size: 1.25, lineHeight: 1.4),
        .init(id: "2xl", title: "2xl", size: 1.5, lineHeight: 4 / 3),
        .init(id: "3xl", title: "3xl", size: 1.875, lineHeight: 1.2),
        .init(id: "4xl", title: "4xl", size: 2.25, lineHeight: 10 / 9),
        .init(id: "5xl", title: "5xl", size: 3, lineHeight: 1),
        .init(id: "6xl", title: "6xl", size: 3.75, lineHeight: 1),
        .init(id: "7xl", title: "7xl", size: 4.5, lineHeight: 1),
        .init(id: "8xl", title: "8xl", size: 6, lineHeight: 1),
        .init(id: "9xl", title: "9xl", size: 8, lineHeight: 1)
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
    var colorChoices: [ComponentPropertyChoice] {
        ThemeColorRole.allCases.map { .init(value: $0.rawValue, label: $0.title) }
    }

    func color(for role: ThemeColorRole) -> String {
        switch role {
        case .background: colors.background
        case .surface: colors.surface
        case .text: colors.text
        case .accent: colors.accent
        case .links: colors.links
        }
    }

    var fontFamilyChoices: [ComponentPropertyChoice] {
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

    var fontSizeChoices: [ComponentPropertyChoice] {
        typography.fontSizes.enumerated().map { index, size in
            return .init(
                value: size.id,
                label: size.title,
                separatorBefore: index == TypographyTokens.standardFontSizes.count && !typography.customFontSizes.isEmpty
            )
        }
    }

    var spacingChoices: [ComponentPropertyChoice] {
        let predefined: [(String, String, Double)] = [
            ("3xs", "3XS", spacing.threeExtraSmall),
            ("2xs", "2XS", spacing.doubleExtraSmall),
            ("xs", "Extra Small", spacing.extraSmall),
            ("sm", "Small", spacing.small),
            ("md", "Medium", spacing.medium),
            ("lg", "Large", spacing.large),
            ("xl", "Extra Large", spacing.extraLarge),
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
        assets: [UUID: ProjectAssetContent],
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
                return files.compactMap { reference in
                    guard let id = reference.foundryAssetID,
                          let content = assets[id] else { return nil }
                    let source = switch destination {
                    case .canvas:
                        "data:\(content.asset.mediaType);base64,\(content.data.base64EncodedString())"
                    case .export:
                        exportedSource?(content.asset) ?? content.asset.storageFilename
                    }
                    let filename = content.asset.filename.lowercased()
                    let style = filename.contains("italic") ? "italic" : "normal"
                    return "@font-face{font-family:'\(definition.family.cssSingleQuoted)';src:url('\(source)');font-style:\(style);font-weight:100 900;font-display:swap;}"
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
