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
            baseSize: 17
        )
    )
}

nonisolated struct ColorTokens: Codable, Equatable, Sendable {
    var background: String
    var surface: String
    var text: String
    var accent: String
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
    case headings
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: "Body"
        case .headings: "Headings"
        case .monospaced: "Monospaced"
        }
    }

    var systemImage: String {
        switch self {
        case .body: "text.alignleft"
        case .headings: "textformat.size.larger"
        case .monospaced: "chevron.left.forwardslash.chevron.right"
        }
    }
}

nonisolated enum ThemeFontReference: Codable, Equatable, Hashable, Sendable {
    case role(ThemeFontRole)
    case custom(UUID)
}

nonisolated extension Theme {
    var fontFamilyChoices: [ComponentPropertyChoice] {
        [
            .init(value: ThemeFontRole.body.rawValue, label: "Body — \(typography.bodyFont.family)"),
            .init(value: ThemeFontRole.headings.rawValue, label: "Headings — \(typography.headingFont.family)"),
            .init(value: ThemeFontRole.monospaced.rawValue, label: "Monospaced — \(typography.monospacedFont.family)")
        ] + typography.customFonts.map { font in
            .init(value: "custom:\(font.id.uuidString.lowercased())", label: "\(font.name) — \(font.font.family)")
        }
    }

    func fontCSSVariable(for reference: String) -> String {
        switch reference {
        case ThemeFontRole.headings.rawValue:
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
