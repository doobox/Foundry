import Foundation

nonisolated enum DesignToken: String, Codable, CaseIterable, Identifiable, Sendable {
    case backgroundColor
    case surfaceColor
    case textColor
    case accentColor
    case linksColor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backgroundColor: "Background"
        case .surfaceColor: "Surface"
        case .textColor: "Text"
        case .accentColor: "Accent"
        case .linksColor: "Links"
        }
    }

    static let colorTokens: [DesignToken] = [
        .backgroundColor, .surfaceColor, .textColor, .accentColor, .linksColor
    ]
}
