import Foundation

nonisolated enum ResponsiveBreakpoint: String, Codable, CaseIterable, Identifiable, Sendable {
    case mobile
    case small
    case medium
    case large
    case extraLarge
    case doubleExtraLarge

    var id: String { rawValue }

    /// The names part authors use in manifest breakpoint defaults.
    var manifestKey: String {
        switch self {
        case .mobile: "xs"
        case .small: "sm"
        case .medium: "md"
        case .large: "lg"
        case .extraLarge: "xl"
        case .doubleExtraLarge: "2xl"
        }
    }

    init?(manifestKey: String) {
        switch manifestKey {
        case "xs": self = .mobile
        case "sm": self = .small
        case "md": self = .medium
        case "lg": self = .large
        case "xl": self = .extraLarge
        case "2xl": self = .doubleExtraLarge
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .mobile: "Extra Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .doubleExtraLarge: "Double Extra Large"
        }
    }

    var screenID: ThemeScreenID {
        switch self {
        case .mobile: .mobile
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .extraLarge: .extraLarge
        case .doubleExtraLarge: .doubleExtraLarge
        }
    }

    var minimumWidth: Int? {
        switch self {
        case .mobile: nil
        case .small: 576
        case .medium: 768
        case .large: 1024
        case .extraLarge: 1280
        case .doubleExtraLarge: 1536
        }
    }

    func minimumWidth(in screens: ScreenTokens) -> Int? {
        guard self != .mobile else { return nil }
        let screen = screens.screen(screenID)
        return screen.isEnabled ? Int(screen.minimumWidth.rounded()) : nil
    }

    var inheritedBreakpoints: [ResponsiveBreakpoint] {
        let breakpoints = Self.allCases
        guard let index = breakpoints.firstIndex(of: self), index > breakpoints.startIndex else {
            return []
        }
        return Array(breakpoints[breakpoints.index(after: breakpoints.startIndex)...index].reversed())
    }

    static func forViewportWidth(_ width: Double) -> ResponsiveBreakpoint {
        for breakpoint in allCases.reversed() {
            if let minimumWidth = breakpoint.minimumWidth, width >= Double(minimumWidth) {
                return breakpoint
            }
        }
        return .mobile
    }

    static func forViewportWidth(_ width: Double, screens: ScreenTokens) -> ResponsiveBreakpoint {
        for breakpoint in allCases.reversed() where breakpoint != .mobile {
            let screen = screens.screen(breakpoint.screenID)
            if screen.isEnabled, width >= screen.minimumWidth {
                return breakpoint
            }
        }
        return .mobile
    }
}

nonisolated struct ResponsivePropertyOverride: Codable, Equatable, Sendable {
    var breakpoint: ResponsiveBreakpoint
    var key: PartProperty.Key
    var value: PartProperty.Value
}
