import Foundation

nonisolated struct Theme: Codable, Equatable, Sendable {
    var colors: ColorTokens
    var spacing: SpacingTokens
    var typography: TypographyTokens

    static let standard = Theme(
        colors: .init(
            background: "#F7F7F8",
            surface: "#FFFFFF",
            text: "#171719",
            accent: "#5B5BD6"
        ),
        spacing: .init(small: 8, medium: 16, large: 32),
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
    var small: Double
    var medium: Double
    var large: Double
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

    static func system(family: String, weights: [Int]) -> ThemeFontDefinition {
        ThemeFontDefinition(
            family: family,
            fallbacks: [],
            source: .system,
            weights: weights,
            styles: [.normal]
        )
    }

    var cssFamily: String {
        ([family] + fallbacks).joined(separator: ", ")
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
        return "var(--font-size-\(id))"
    }

    func lineHeightCSSVariable(for reference: String) -> String {
        let id = typography.fontSizes.contains(where: { $0.id == reference }) ? reference : "base"
        return "var(--font-size-\(id)-line-height)"
    }

    var fontSizeCSSVariables: String {
        typography.fontSizes.map {
            "--font-size-\($0.id):\($0.size)rem;--font-size-\($0.id)-line-height:\($0.lineHeight.value);"
        }.joined()
    }

    func fontCSSVariable(for reference: String) -> String {
        switch reference {
        case ThemeFontRole.heading.rawValue:
            "var(--font-heading)"
        case ThemeFontRole.monospaced.rawValue:
            "var(--font-monospace)"
        default:
            if reference.hasPrefix("custom:"),
               let id = UUID(uuidString: String(reference.dropFirst("custom:".count))),
               typography.customFonts.contains(where: { $0.id == id }) {
                "var(--font-custom-\(id.uuidString.lowercased()))"
            } else {
                "var(--font-body)"
            }
        }
    }

    var remoteFontImports: String {
        typography.allFonts.compactMap { definition in
            guard case .remote(let stylesheetURL) = definition.source else { return nil }
            return "@import url('\(stylesheetURL.absoluteString)');"
        }.joined(separator: "\n")
    }

    var customFontCSSVariables: String {
        typography.customFonts.map { font in
            "--font-custom-\(font.id.uuidString.lowercased()):\(font.font.cssFamily);"
        }.joined()
    }

    func color(for token: DesignToken) -> String? {
        switch token {
        case .backgroundColor: colors.background
        case .surfaceColor: colors.surface
        case .textColor: colors.text
        case .accentColor: colors.accent
        case .smallSpacing, .mediumSpacing, .largeSpacing: nil
        }
    }

    func number(for token: DesignToken) -> Double? {
        switch token {
        case .smallSpacing: spacing.small
        case .mediumSpacing: spacing.medium
        case .largeSpacing: spacing.large
        case .backgroundColor, .surfaceColor, .textColor, .accentColor: nil
        }
    }
}

nonisolated extension TypographyTokens {
    var allFonts: [ThemeFontDefinition] {
        [bodyFont, headingFont, monospacedFont] + customFonts.map(\.font)
    }
}
