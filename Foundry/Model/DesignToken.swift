import Foundation

nonisolated enum DesignToken: String, Codable, CaseIterable, Identifiable, Sendable {
    case backgroundColor
    case surfaceColor
    case textColor
    case accentColor
    case extraSmallSpacing
    case smallSpacing
    case mediumSpacing
    case largeSpacing
    case extraLargeSpacing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backgroundColor: "Background"
        case .surfaceColor: "Surface"
        case .textColor: "Text"
        case .accentColor: "Accent"
        case .extraSmallSpacing: "Extra Small"
        case .smallSpacing: "Small"
        case .mediumSpacing: "Medium"
        case .largeSpacing: "Large"
        case .extraLargeSpacing: "Extra Large"
        }
    }

    static let colorTokens: [DesignToken] = [.backgroundColor, .surfaceColor, .textColor, .accentColor]
    static let spacingTokens: [DesignToken] = [
        .extraSmallSpacing, .smallSpacing, .mediumSpacing, .largeSpacing, .extraLargeSpacing
    ]
}
