import Foundation

/// Only explicit edits are stored. Defaults are read from the bundled Bootstrap CSS.
nonisolated struct BootstrapEditorTokens: Codable, Equatable, Sendable {
    var values: [String: String] = [:]
    var custom: [String: [String]] = [:]

    /// Project-owned additions only; edits to Bootstrap's built-in tokens stay with the theme.
    var customAdditions: Self {
        let sections = custom.filter { BootstrapEditorSection(rawValue: $0.key)?.allowsCustom == true }
        let ids = Set(sections.flatMap { key, names in
            names.flatMap { BootstrapEditorSection(rawValue: key)?.customTokens(named: $0).map(\.id) ?? [] }
        })
        return Self(values: values.filter { ids.contains($0.key) }, custom: sections)
    }

    func value(_ token: BootstrapEditorToken) -> String {
        guard let value = values[token.id], BootstrapEditorToken.safeValue(value) else { return token.defaultValue }
        return value
    }
    func tokens(in section: BootstrapEditorSection) -> [BootstrapEditorToken] {
        section.tokens + customTokens(in: section)
    }
    func customTokens(in section: BootstrapEditorSection) -> [BootstrapEditorToken] {
        (custom[section.rawValue] ?? []).flatMap { section.customTokens(named: $0) }
    }
    func isChanged(_ section: BootstrapEditorSection) -> Bool {
        section.tokens.contains { values[$0.id] != nil }
    }
    /// Only Bootstrap's component tokens and the project's own additions accept edits.
    func isEditable(_ token: BootstrapEditorToken) -> Bool {
        BootstrapEditorSection.allCases.contains { section in
            section.tokens.contains { $0.id == token.id } || customTokens(in: section).contains { $0.id == token.id }
        }
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

/// Bootstrap's editable settings, limited to tokens whose variables Bootstrap's own
/// components read. Scales that Bootstrap bakes into utilities (text sizes, weights,
/// spacing steps, numbered radii and borders, numeric z-index) are not editable;
/// their sections carry only project-named additions.
nonisolated enum BootstrapEditorSection: String, CaseIterable, Sendable {
    case fontSize, borderWidth, borderRadius, shadows, shadowColours, blackWhite, colourScales, zIndex, body, links, linkColours, focusRing, controls

    var title: String {
        switch self {
        case .fontSize: "Text Sizes"
        case .borderWidth: "Border Width"
        case .borderRadius: "Corners"
        case .shadows: "Shadows"
        case .shadowColours: "Shadow Colour"
        case .blackWhite: "Black & White"
        case .colourScales: "Colour Scales"
        case .zIndex: "Z-index"
        case .body: "Body Typography"
        case .links: "Links"
        case .linkColours: "Link Colours"
        case .focusRing: "Focus Ring"
        case .controls: "Buttons & Inputs"
        }
    }

    /// Bootstrap's fixed utility scales. Offered to parts as shipped; never edited.
    static let sizes = ["xs", "sm", "md", "lg", "xl", "2xl", "3xl", "4xl", "5xl", "6xl"]
    static let weights = ["lighter", "light", "normal", "medium", "semibold", "bold", "bolder"]
    /// Component stacking layers. Bootstrap's components read these variables.
    static let levels = ["menu", "sticky", "fixed", "drawer", "dialog", "popover", "tooltip", "toast"]
    var allowsCustom: Bool { [.fontSize, .borderWidth, .borderRadius, .shadows, .zIndex].contains(self) }

    var tokens: [BootstrapEditorToken] {
        switch self {
        case .fontSize:
            return []
        case .borderWidth:
            return [.init("border-width", "Components", range: 0...12, step: 0.5)]
        case .borderRadius:
            return [.init("radius-5", "Buttons and inputs", range: 0...5), .init("radius-7", "Cards", range: 0...5), .init("radius-pill", "Pill", range: 0...50)]
        case .shadows:
            return [.init("shadow-strength-light", "Light strength", fallback: "1", range: 0...5, step: 0.1), .init("shadow-strength-dark", "Dark strength", fallback: "2.4", range: 0...5, step: 0.1)]
        case .shadowColours:
            return [.init("shadow-color", "Shadow")]
        case .blackWhite:
            return [.init("black", "Black"), .init("white", "White")]
        case .colourScales:
            return BootstrapColourCatalogue.hues.flatMap { hue in
                ColourShade.allCases.map { .init("\(hue)-\($0.bootstrapLabel)", $0.bootstrapLabel) }
            }
        case .zIndex:
            return Self.levels.map { .init("z-" + $0, "z-" + $0, range: -10...1100, step: 1) }
        case .body:
            return [.init("body-font-size", "Font size", range: 0.5...3), .init("body-font-weight", "Font weight"), .init("body-line-height", "Line height", range: 0.5...3, step: 0.05), .init("heading-color", "Heading colour"), .init("code-font-size", "Code size", range: 50...150, step: 1), .init("code-color", "Code colour")]
        case .links:
            return ["link-decoration", "link-underline-offset"].map { .init($0) }
        case .linkColours:
            return [.init("link-color", "Link"), .init("link-hover-color", "Link hover")]
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
        case .fontSize: [.init("font-size-" + name, "text-" + name, fallback: "1rem")]
        case .borderWidth: [.init("border-width-" + name, "border-" + name, fallback: "1px", range: 0...12, step: 0.5)]
        case .borderRadius: [.init("radius-" + name, "rounded-" + name, fallback: "0.5rem", range: 0...5)]
        case .shadows: [.init("box-shadow-" + name, "shadow-" + name, fallback: BootstrapColourCatalogue.declarations["--bs-box-shadow"]!)]
        case .zIndex: [.init("z-" + name, "z-" + name, fallback: "1", range: -10...1100, step: 1)]
        default: []
        }
    }
}
