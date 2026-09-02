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
        screens = try container.decodeIfPresent(ScreenTokens.self, forKey: .screens) ?? .standard
    }

    static let standard = Theme(
        colors: .init(
            background: "#F7F7F8",
            surface: "#FFFFFF",
            text: "#171719",
            accent: "#5B5BD6"
        ),
        spacing: .standard,
        typography: .init(
            bodyFont: .system(family: "system-ui", weights: [400, 500, 600, 700]),
            headingFont: .system(family: "system-ui", weights: [500, 600, 700, 800]),
            monospacedFont: .system(family: "ui-monospace", weights: [400, 500, 600, 700]),
            customFonts: [],
            baseSize: 16,
            customFontSizes: []
        )
    )
}

nonisolated enum ThemeScreenID: String, Codable, CaseIterable, Identifiable, Sendable {
    case mobile, small, medium, large, extraLarge, doubleExtraLarge

    var id: String { rawValue }
    var shortTitle: String {
        switch self {
        case .mobile: "Mobile"
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
        case .small, .extraLarge: "laptopcomputer"
        case .medium: "ipad"
        case .large: "ipad.landscape"
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
        .init(id: .extraLarge, isEnabled: false, minimumWidth: 1280, container: .init(value: 1280, unit: .auto)),
        .init(id: .doubleExtraLarge, isEnabled: false, minimumWidth: 1536, container: .init(value: 1536, unit: .auto))
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
}

nonisolated enum ThemeColorRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case background
    case surface
    case text
    case accent

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
        threeExtraSmall = try container.decodeIfPresent(Double.self, forKey: .threeExtraSmall) ?? Self.standard.threeExtraSmall
        doubleExtraSmall = try container.decodeIfPresent(Double.self, forKey: .doubleExtraSmall) ?? Self.standard.doubleExtraSmall
        extraSmall = try container.decodeIfPresent(Double.self, forKey: .extraSmall) ?? Self.standard.extraSmall
        small = try container.decodeIfPresent(Double.self, forKey: .small) ?? Self.standard.small
        medium = try container.decodeIfPresent(Double.self, forKey: .medium) ?? Self.standard.medium
        large = try container.decodeIfPresent(Double.self, forKey: .large) ?? Self.standard.large
        extraLarge = try container.decodeIfPresent(Double.self, forKey: .extraLarge) ?? Self.standard.extraLarge
        doubleExtraLarge = try container.decodeIfPresent(Double.self, forKey: .doubleExtraLarge) ?? Self.standard.doubleExtraLarge
        threeExtraLarge = try container.decodeIfPresent(Double.self, forKey: .threeExtraLarge) ?? Self.standard.threeExtraLarge
        custom = try container.decodeIfPresent([ThemeSpacing].self, forKey: .custom) ?? []
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
    var bodyFont: ThemeFontDefinition
    var headingFont: ThemeFontDefinition
    var monospacedFont: ThemeFontDefinition
    var customFonts: [ThemeCustomFont]
    var baseSize: Double
    var customFontSizes: [ThemeFontSize]

    static let standardFontSizes: [ThemeFontSize] = [
        .init(id: "xs", title: "Extra Small", size: 0.75, lineHeight: .snug),
        .init(id: "sm", title: "Small", size: 0.875, lineHeight: .normal),
        .init(id: "base", title: "Base", size: 1, lineHeight: .normal),
        .init(id: "lg", title: "Large", size: 1.125, lineHeight: .relaxed),
        .init(id: "xl", title: "Extra Large", size: 1.25, lineHeight: .normal),
        .init(id: "2xl", title: "2XL", size: 1.5, lineHeight: .snug),
        .init(id: "3xl", title: "3XL", size: 1.875, lineHeight: .tight),
        .init(id: "4xl", title: "4XL", size: 2.25, lineHeight: .tight),
        .init(id: "5xl", title: "5XL", size: 3, lineHeight: .none),
        .init(id: "6xl", title: "6XL", size: 3.75, lineHeight: .none),
        .init(id: "7xl", title: "7XL", size: 4.5, lineHeight: .none),
        .init(id: "8xl", title: "8XL", size: 6, lineHeight: .none),
        .init(id: "9xl", title: "9XL", size: 8, lineHeight: .none)
    ]

    var fontSizes: [ThemeFontSize] {
        let reservedIDs = Set(Self.standardFontSizes.map(\.id))
        return Self.standardFontSizes + customFontSizes.filter { !reservedIDs.contains($0.id) }
    }
}

nonisolated struct ThemeFontSize: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var size: Double
    var lineHeight: ThemeLineHeight
}

nonisolated enum ThemeLineHeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case tight
    case snug
    case normal
    case relaxed
    case loose

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var value: Double {
        switch self {
        case .none: 1
        case .tight: 1.25
        case .snug: 1.375
        case .normal: 1.5
        case .relaxed: 1.625
        case .loose: 2
        }
    }
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
        }
    }

    var fontFamilyChoices: [ComponentPropertyChoice] {
        [
            .init(value: ThemeFontRole.body.rawValue, label: "Body — \(typography.bodyFont.family)"),
            .init(value: ThemeFontRole.heading.rawValue, label: "Heading — \(typography.headingFont.family)"),
            .init(value: ThemeFontRole.monospaced.rawValue, label: "Monospaced — \(typography.monospacedFont.family)")
        ] + typography.customFonts.map { font in
            .init(value: "custom:\(font.id.uuidString.lowercased())", label: "\(font.name) — \(font.font.family)")
        }
    }

    var fontSizeChoices: [ComponentPropertyChoice] {
        typography.fontSizes.map {
            let pixels = ($0.size * typography.baseSize).formatted(
                .number.precision(.fractionLength(0...1))
            )
            return .init(value: $0.id, label: "\($0.title) — \($0.size.formatted()) rem (\(pixels) px)")
        }
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
            "--foundry-font-size-\($0.id):\($0.size)rem;--foundry-font-size-\($0.id)-line-height:\($0.lineHeight.value);"
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
        case .backgroundColor, .surfaceColor, .textColor, .accentColor: nil
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
