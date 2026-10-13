import Foundation

/// A custom colour extends one Bootstrap token family, not every family.
nonisolated enum BootstrapColourKind: String, Codable, CaseIterable, Sendable {
    case theme, surface, foreground, border, link

    var title: String {
        switch self {
        case .theme: "Theme Colours"
        case .surface: "Surfaces"
        case .foreground: "Foregrounds"
        case .border: "Borders"
        case .link: "Link Colours"
        }
    }
    var section: String {
        switch self {
        case .theme: "themes"
        case .surface: "surfaces"
        case .foreground: "foregrounds"
        case .border: "borders"
        case .link: "links"
        }
    }
    var sourceRole: String {
        switch self {
        case .theme, .link: "primary"
        case .surface: "background"
        case .foreground: "foreground"
        case .border: "border"
        }
    }
    var sourceTokens: [String] {
        self == .link ? ["link-color", "link-hover-color"] : BootstrapColourCatalogue.tokens(for: sourceRole)
    }
}

nonisolated extension ColourPalette {
    var colourKind: BootstrapColourKind {
        if origin == .custom { return customKind ?? .theme }
        switch id {
        case "framework.background": return .surface
        case "framework.foreground": return .foreground
        case "framework.border": return .border
        default: return .theme
        }
    }
    /// Stable names keep saved swatch selections intact when the display name changes.
    var customTokenPrefix: String { "custom-" + id.utf8.map { String(format: "%02x", $0) }.joined() + "-" }
    func colourToken(_ source: String) -> String {
        guard origin == .custom else { return source }
        if colourKind == .theme {
            return source.replacingOccurrences(of: "primary-", with: name + "-")
        }
        return customTokenPrefix + source
    }
    var colourTokens: [String] {
        let source = origin == .custom ? colourKind.sourceTokens : BootstrapColourCatalogue.tokens(for: BootstrapPaletteTheme.definitionRole(self))
        return source.map(colourToken)
    }
    var pickerLabel: String {
        guard origin == .custom, let role = BootstrapPaletteTheme.nativeRole(self) else { return name }
        return "theme-" + role
    }
    func publicUtilityClass(for source: String) -> String? {
        guard origin == .custom, BootstrapPaletteTheme.validCustomRole(name),
              colourKind.sourceTokens.contains(source) else { return nil }
        switch colourKind {
        case .theme: return nil
        case .surface: return "bg-\(name)-\(source.dropFirst("bg-".count))"
        case .foreground: return "fg-\(name)-\(source.dropFirst("fg-".count))"
        case .border: return "border-\(name)-\(source.dropFirst("border-".count))"
        case .link: return source == "link-color" ? "link-\(name)" : "link-\(name)-hover"
        }
    }
}
