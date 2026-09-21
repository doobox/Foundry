import Foundation

nonisolated enum DesignToken: String, Codable, CaseIterable, Identifiable, Sendable {
    case backgroundColor
    case surfaceColor
    case textColor
    case accentColor
    case linksColor
    case threeExtraSmallSpacing
    case doubleExtraSmallSpacing
    case extraSmallSpacing
    case smallSpacing
    case mediumSpacing
    case largeSpacing
    case extraLargeSpacing
    case doubleExtraLargeSpacing
    case threeExtraLargeSpacing
    case fourExtraLargeSpacing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backgroundColor: "Background"
        case .surfaceColor: "Surface"
        case .textColor: "Text"
        case .accentColor: "Accent"
        case .linksColor: "Links"
        case .threeExtraSmallSpacing: "3XS"
        case .doubleExtraSmallSpacing: "2XS"
        case .extraSmallSpacing: "XS"
        case .smallSpacing: "SM"
        case .mediumSpacing: "MD"
        case .largeSpacing: "LG"
        case .extraLargeSpacing: "XL"
        case .doubleExtraLargeSpacing: "2XL"
        case .threeExtraLargeSpacing: "3XL"
        case .fourExtraLargeSpacing: "4XL"
        }
    }

    static let colorTokens: [DesignToken] = [
        .backgroundColor, .surfaceColor, .textColor, .accentColor, .linksColor
    ]
    static let spacingTokens: [DesignToken] = [
        .threeExtraSmallSpacing, .doubleExtraSmallSpacing, .extraSmallSpacing,
        .smallSpacing, .mediumSpacing, .largeSpacing, .extraLargeSpacing,
        .doubleExtraLargeSpacing, .threeExtraLargeSpacing, .fourExtraLargeSpacing
    ]
}
