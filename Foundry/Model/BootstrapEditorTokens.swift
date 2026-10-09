import Foundation

/// Only explicit edits are stored. Defaults are read from the bundled Bootstrap CSS.
nonisolated struct BootstrapEditorTokens: Codable, Equatable, Sendable {
    var values: [String: String] = [:]
    var custom: [String: [String]] = [:]

    func value(_ token: BootstrapEditorToken) -> String {
        guard let value = values[token.id], BootstrapEditorToken.safeValue(value) else { return token.defaultValue }
        return value
    }
    func tokens(in section: BootstrapEditorSection) -> [BootstrapEditorToken] {
        section.tokens + (custom[section.rawValue] ?? []).flatMap { section.customTokens(named: $0) }
    }
    func isChanged(_ section: BootstrapEditorSection) -> Bool {
        section.tokens.contains { values[$0.id] != nil }
    }
}

nonisolated struct BootstrapEditorToken: Identifiable, Sendable {
    let id: String
    let label: String
    let defaultValue: String
    var range: ClosedRange<Double> = 0...10
    var step: Double = 0.125

    init(_ id: String, _ label: String? = nil, fallback: String? = nil,
         range: ClosedRange<Double> = 0...10, step: Double = 0.125) {
        self.id = id
        self.label = label ?? id
        self.defaultValue = fallback ?? BootstrapColourCatalogue.declarations["--bs-" + id] ?? "0"
        self.range = id.contains("font-weight") ? 1...1000 : range
        self.step = id.contains("font-weight") ? 1 : step
    }

    static func safeValue(_ value: String) -> Bool {
        !value.isEmpty && value.count < 4000 && !value.contains(where: { "{};<>@\\\n\r".contains($0) })
            && !value.localizedCaseInsensitiveContains("url(")
    }

    func acceptsNumber(_ number: Double) -> Bool {
        guard number.isFinite else { return false }
        if id.hasPrefix("z-") { return number.rounded() == number }
        if id.contains("font-weight") { return (1...1000).contains(number) }
        if id == "control-disabled-opacity" { return (0...1).contains(number) }
        return id == "focus-ring-offset" || number >= 0
    }
}

nonisolated enum BootstrapEditorSection: String, CaseIterable, Sendable {
    case fontSize, fontWeight, borderWidth, borderRadius, shadows, zIndex, body, links, focusRing, controls

    var title: String {
        switch self {
        case .fontSize: "Font Sizes & Line Heights"
        case .fontWeight: "Font Weights"
        case .borderWidth: "Border Widths"
        case .borderRadius: "Border Radius"
        case .shadows: "Shadows"
        case .zIndex: "Z-index"
        case .body: "Body Typography"
        case .links: "Links"
        case .focusRing: "Focus Ring"
        case .controls: "Buttons & Inputs"
        }
    }

    static let sizes = ["xs", "sm", "md", "lg", "xl", "2xl", "3xl", "4xl", "5xl", "6xl"]
    static let weights = ["lighter", "light", "normal", "medium", "semibold", "bold", "bolder"]
    static let levels = ["n1", "0", "1", "2", "3", "menu", "sticky", "fixed", "drawer", "dialog", "popover", "tooltip", "toast"]
    var allowsCustom: Bool { [.fontSize, .borderWidth, .borderRadius, .shadows, .zIndex].contains(self) }

    var tokens: [BootstrapEditorToken] {
        switch self {
        case .fontSize:
            return Self.sizes.flatMap { [BootstrapEditorToken("font-size-" + $0, "fs-" + $0), BootstrapEditorToken("line-height-" + $0, "Line height", range: 0.5...3, step: 0.05)] }
        case .fontWeight:
            return Self.weights.map { .init("font-weight-" + $0, "fw-" + $0, range: 1...1000, step: 100) }
        case .borderWidth:
            return [.init("border-width", "Default", range: 0...12, step: 0.5), .init("border-width-keyline", "border-keyline", range: 0...12, step: 0.5)]
                + (1...5).map { .init("border-width-\($0)", "border-\($0)", fallback: "\($0)px", range: 0...12, step: 0.5) }
        case .borderRadius:
            return (0...9).map { .init("radius-\($0)", "rounded-\($0)", range: 0...5) } + [.init("radius-pill", "rounded-pill", range: 0...50)]
        case .shadows:
            return ["", "-xs", "-sm", "-lg", "-xl", "-inset"].map { .init("box-shadow" + $0, $0 == "-inset" ? "Inset" : ($0.isEmpty ? "shadow" : "shadow" + $0)) }
                + [.init("shadow-color", "Colour"), .init("shadow-strength-light", "Light strength", fallback: "1", range: 0...5, step: 0.1), .init("shadow-strength-dark", "Dark strength", fallback: "2.4", range: 0...5, step: 0.1)]
        case .zIndex:
            return Self.levels.map { .init("z-" + $0, "z-" + $0, range: -10...1100, step: 1) }
        case .body:
            return [.init("body-font-size", "Font size", range: 0.5...3), .init("body-font-weight", "Font weight"), .init("body-line-height", "Line height", range: 0.5...3, step: 0.05), .init("heading-color", "Heading colour"), .init("code-font-size", "Code size", range: 50...150, step: 1), .init("code-color", "Code colour")]
        case .links:
            return ["link-color", "link-hover-color", "link-decoration", "link-underline-offset"].map { .init($0) }
        case .focusRing:
            return [.init("focus-ring-width", "Width", range: 0...12, step: 0.5), .init("focus-ring-offset", "Offset", range: -10...10, step: 0.5), .init("focus-ring-color", "Colour")]
        case .controls:
            return ["", "xs-", "sm-", "lg-"].flatMap { size in
                ["gap", "min-height", "padding-y", "padding-x", "font-size", "line-height", "border-radius"].map {
                    BootstrapEditorToken("btn-input-" + size + $0, (size.isEmpty ? "Default " : size.replacingOccurrences(of: "-", with: " ")) + $0)
                }
            } + [.init("btn-input-font-weight"), .init("control-disabled-opacity", range: 0...1, step: 0.05)]
        }
    }

    func customTokens(named name: String) -> [BootstrapEditorToken] {
        switch self {
        case .fontSize: [.init("font-size-" + name, "fs-" + name, fallback: "1rem"), .init("line-height-" + name, "Line height", fallback: "1.5", range: 0.5...3, step: 0.05)]
        case .borderWidth: [.init("border-width-" + name, "border-" + name, fallback: "1px", range: 0...12, step: 0.5)]
        case .borderRadius: [.init("radius-" + name, "rounded-" + name, fallback: "0.5rem", range: 0...5)]
        case .shadows: [.init("box-shadow-" + name, "shadow-" + name, fallback: BootstrapColourCatalogue.declarations["--bs-box-shadow"]!)]
        case .zIndex: [.init("z-" + name, "z-" + name, fallback: "1", range: -10...1100, step: 1)]
        default: []
        }
    }
}
