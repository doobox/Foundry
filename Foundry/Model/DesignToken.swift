import Foundation

nonisolated enum DesignToken: String, Codable, CaseIterable, Identifiable, Sendable {
    case backgroundColor
    case surfaceColor
    case textColor
    case accentColor
    case smallSpacing
    case mediumSpacing
    case largeSpacing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backgroundColor: "Background"
        case .surfaceColor: "Surface"
        case .textColor: "Text"
        case .accentColor: "Accent"
        case .smallSpacing: "Small"
        case .mediumSpacing: "Medium"
        case .largeSpacing: "Large"
        }
    }

    static let colorTokens: [DesignToken] = [.backgroundColor, .surfaceColor, .textColor, .accentColor]
    static let spacingTokens: [DesignToken] = [.smallSpacing, .mediumSpacing, .largeSpacing]
}
