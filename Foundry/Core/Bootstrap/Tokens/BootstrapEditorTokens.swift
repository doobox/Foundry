import Foundation

/// Only explicit edits are stored. Defaults are read from the bundled Bootstrap CSS.
nonisolated struct BootstrapEditorTokens: Codable, Equatable, Sendable {
    var values: [String: String] = [:]
    var custom: [String: [String]] = [:]

    init(values: [String: String] = [:], custom: [String: [String]] = [:]) {
        self.values = values
        self.custom = custom
    }

    private enum CodingKeys: String, CodingKey { case values, custom }

    /// Removed global settings are discarded on load and never written back.
    private var supportedValues: [String: String] {
        let ids = Set(BootstrapEditorSection.allCases.flatMap { tokens(in: $0).map(\.id) })
        return values.filter { ids.contains($0.key) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        values = try container.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
        custom = try container.decodeIfPresent([String: [String]].self, forKey: .custom) ?? [:]
        custom = custom.filter { BootstrapEditorSection(rawValue: $0.key)?.allowsCustom == true }
        values = supportedValues
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(supportedValues, forKey: .values)
        try container.encode(custom.filter { BootstrapEditorSection(rawValue: $0.key)?.allowsCustom == true }, forKey: .custom)
    }

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
    /// Only colour tokens and the project's own additions accept edits.
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
    case fontSize, borderWidth, borderRadius, shadows, shadowColours, blackWhite, colourScales, zIndex, linkColours

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
        case .linkColours: "Link Colours"
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
        case .fontSize, .borderWidth, .borderRadius, .shadows, .zIndex:
            return []
        case .shadowColours:
            return [.init("shadow-color", "Shadow")]
        case .blackWhite:
            return [.init("black", "Black"), .init("white", "White")]
        case .colourScales:
            return BootstrapColourCatalogue.hues.flatMap { hue in
                ColourShade.allCases.map { .init("\(hue)-\($0.bootstrapLabel)", $0.bootstrapLabel) }
            }
        case .linkColours:
            return [.init("link-color", "Link"), .init("link-hover-color", "Link hover")]
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
