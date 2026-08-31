import Foundation

nonisolated enum ResponsiveBreakpoint: String, Codable, CaseIterable, Identifiable, Sendable {
    case mobile
    case tabletPortrait
    case tabletLandscape
    case desktop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mobile: "Mobile"
        case .tabletPortrait: "Tablet Portrait"
        case .tabletLandscape: "Tablet Landscape"
        case .desktop: "Desktop"
        }
    }

    var minimumWidth: Int? {
        switch self {
        case .mobile: nil
        case .tabletPortrait: 768
        case .tabletLandscape: 1024
        case .desktop: 1280
        }
    }

    func minimumWidth(in screens: ScreenTokens) -> Int? {
        let screenID: ThemeScreenID? = switch self {
        case .mobile: nil
        case .tabletPortrait: .medium
        case .tabletLandscape: .large
        case .desktop: .extraLarge
        }
        guard let screenID else { return nil }
        let screen = screens.screen(screenID)
        return screen.isEnabled ? Int(screen.minimumWidth.rounded()) : nil
    }

    var inheritedBreakpoints: [ResponsiveBreakpoint] {
        switch self {
        case .mobile: []
        case .tabletPortrait: [.tabletPortrait]
        case .tabletLandscape: [.tabletLandscape, .tabletPortrait]
        case .desktop: [.desktop, .tabletLandscape, .tabletPortrait]
        }
    }

    static func forViewportWidth(_ width: Double) -> ResponsiveBreakpoint {
        if width >= 1280 { return .desktop }
        if width >= 1024 { return .tabletLandscape }
        if width >= 768 { return .tabletPortrait }
        return .mobile
    }

    static func forViewportWidth(_ width: Double, screens: ScreenTokens) -> ResponsiveBreakpoint {
        let desktop = screens.screen(.extraLarge)
        let landscape = screens.screen(.large)
        let portrait = screens.screen(.medium)
        if desktop.isEnabled, width >= desktop.minimumWidth { return .desktop }
        if landscape.isEnabled, width >= landscape.minimumWidth { return .tabletLandscape }
        if portrait.isEnabled, width >= portrait.minimumWidth { return .tabletPortrait }
        return .mobile
    }
}

nonisolated struct ResponsivePropertyOverride: Codable, Equatable, Sendable {
    var breakpoint: ResponsiveBreakpoint
    var key: ComponentProperty.Key
    var value: ComponentProperty.Value
}
