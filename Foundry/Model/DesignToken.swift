import Foundation

nonisolated enum DesignToken: String, Codable, CaseIterable, Identifiable, Sendable {
    case backgroundColor
    case surfaceColor
    case textColor
    case accentColor
    case threeExtraSmallSpacing
    case doubleExtraSmallSpacing
    case extraSmallSpacing
    case smallSpacing
    case mediumSpacing
    case largeSpacing
    case extraLargeSpacing
    case doubleExtraLargeSpacing
    case threeExtraLargeSpacing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backgroundColor: "Background"
        case .surfaceColor: "Surface"
        case .textColor: "Text"
        case .accentColor: "Accent"
        case .threeExtraSmallSpacing: "3XS"
        case .doubleExtraSmallSpacing: "2XS"
        case .extraSmallSpacing: "XS"
        case .smallSpacing: "SM"
        case .mediumSpacing: "MD"
        case .largeSpacing: "LG"
        case .extraLargeSpacing: "XL"
        case .doubleExtraLargeSpacing: "2XL"
        case .threeExtraLargeSpacing: "3XL"
        }
    }

    static let colorTokens: [DesignToken] = [.backgroundColor, .surfaceColor, .textColor, .accentColor]
    static let spacingTokens: [DesignToken] = [
        .threeExtraSmallSpacing, .doubleExtraSmallSpacing, .extraSmallSpacing,
        .smallSpacing, .mediumSpacing, .largeSpacing, .extraLargeSpacing,
        .doubleExtraLargeSpacing, .threeExtraLargeSpacing
    ]
}
