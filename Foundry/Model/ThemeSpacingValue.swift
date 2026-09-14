import Foundation

nonisolated protocol ThemeSpacingPolicy: Sendable {
    static var allowsAutoAndNegative: Bool { get }
    static var label: String { get }
    static var isRadius: Bool { get }
    static var units: [String] { get }
    static var themeUnit: String { get }
    static var tokens: [String] { get }
    static func choices(in theme: Theme) -> [ThemeEdgeChoice]
}
nonisolated struct ThemeEdgeChoice {
    let id: String
    let label: String
    let amount: Double
    let css: String
}
nonisolated extension ThemeSpacingPolicy {
    static var isRadius: Bool { false }
    static var units: [String] { ["px", "rem", "em", "%"] }
    static var themeUnit: String { "rem" }
    static var tokens: [String] { ["none", "3xs", "2xs", "xs", "sm", "md", "lg", "xl", "2xl", "3xl"] + (allowsAutoAndNegative ? ["auto"] : []) }
    static func choices(in theme: Theme) -> [ThemeEdgeChoice] {
        let spacing = theme.spacing
        let multipliers = [spacing.threeExtraSmall, spacing.doubleExtraSmall, spacing.extraSmall,
                           spacing.small, spacing.medium, spacing.large, spacing.extraLarge,
                           spacing.doubleExtraLarge, spacing.threeExtraLarge] + spacing.custom.map(\.value)
        return zip(theme.spacingChoices, multipliers).map {
            ThemeEdgeChoice(id: $0.0.value, label: $0.0.label,
                            amount: $0.1 * SpacingTokens.baseRem,
                            css: theme.spacingCSSVariable(for: $0.0.value) ?? "0")
        }
    }
}
nonisolated enum BorderWidthPolicy: ThemeSpacingPolicy {
    static let allowsAutoAndNegative = false
    static let label = "Border width"
    static let units = ["px", "rem", "em"]
    static let themeUnit = "px"
    static var tokens: [String] { ThemeDimensionTokens.standardBorderWidths.predefined.map(\.id) }
    static func choices(in theme: Theme) -> [ThemeEdgeChoice] {
        theme.borderWidths.predefined.filter { $0.id != "none" }.map {
            ThemeEdgeChoice(id: $0.id, label: $0.title, amount: $0.value, css: "var(--foundry-border-width-\($0.id))")
        }
    }
}
nonisolated enum RadiusPolicy: ThemeSpacingPolicy {
    static let allowsAutoAndNegative = false
    static let label = "Radius"
    static let isRadius = true
    static let themeUnit = "px"
    static var tokens: [String] { ThemeDimensionTokens.standardBorderRadii.predefined.map(\.id) }
    static func choices(in theme: Theme) -> [ThemeEdgeChoice] {
        theme.borderRadii.predefined.filter { $0.id != "none" }.map {
            ThemeEdgeChoice(id: $0.id, label: $0.title, amount: $0.value, css: "var(--foundry-border-radius-\($0.id))")
        }
    }
}
nonisolated enum PaddingPolicy: ThemeSpacingPolicy {
    static let allowsAutoAndNegative = false
    static let label = "Padding"
}
nonisolated enum MarginPolicy: ThemeSpacingPolicy {
    static let allowsAutoAndNegative = true
    static let label = "Margin"
}
typealias ThemeBorderWidthValue = ThemeSpacingValue<BorderWidthPolicy>
typealias ThemeRadiusValue = ThemeSpacingValue<RadiusPolicy>
typealias ThemePaddingValue = ThemeSpacingValue<PaddingPolicy>
typealias ThemeMarginValue = ThemeSpacingValue<MarginPolicy>

/// Persisted four-edge spacing selection and inspector linking state.
nonisolated struct ThemeSpacingValue<Policy: ThemeSpacingPolicy>: Codable, Equatable, Sendable {
    struct EdgeValue: Codable, Equatable, Sendable {
        var token = "sm"
        var isCustom = false
        var amount = 0.0
        var unit = Policy.themeUnit
    }

    enum Edge: String, CaseIterable, Identifiable {
        case top = "Top", bottom = "Bottom", left = "Left", right = "Right"
        var id: String { rawValue }
        var index: Int { Self.allCases.firstIndex(of: self)! }
        var title: String { Policy.isRadius ? ["Top Left", "Top Right", "Bottom Left", "Bottom Right"][index] : rawValue }
        var key: String { Policy.isRadius ? ["topLeft", "topRight", "bottomLeft", "bottomRight"][index] : rawValue.lowercased() }
        var isVertical: Bool { self == .top || self == .bottom }
        var partner: Edge {
            switch self {
            case .top: .bottom
            case .bottom: .top
            case .left: .right
            case .right: .left
            }
        }
    }

    var linked = true
    private(set) var verticalLinked = false
    private(set) var horizontalLinked = false
    private(set) var values = Array(repeating: EdgeValue(), count: 4)

    init() {}

    private enum CodingKeys: String, CodingKey { case linked, verticalLinked, horizontalLinked, values }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linked = try container.decode(Bool.self, forKey: .linked)
        verticalLinked = try container.decode(Bool.self, forKey: .verticalLinked)
        horizontalLinked = try container.decode(Bool.self, forKey: .horizontalLinked)
        values = try container.decode([EdgeValue].self, forKey: .values)
        guard values.count == 4,
              values.allSatisfy({ $0.amount.isFinite && (Policy.allowsAutoAndNegative || $0.amount >= 0) && (Policy.allowsAutoAndNegative || $0.token != "auto") && Policy.units.contains($0.unit) }),
              !(verticalLinked && horizontalLinked),
              (!linked || (!verticalLinked && !horizontalLinked && allEqual)),
              (!verticalLinked || values[0] == values[1]),
              (!horizontalLinked || values[2] == values[3]) else {
            throw DecodingError.dataCorruptedError(forKey: .values, in: container, debugDescription: "Invalid four-value selections or link state.")
        }
    }

    mutating func replaceReference(_ reference: String, with replacement: String) {
        for index in values.indices where values[index].token == reference {
            values[index].token = replacement
        }
    }

    func value(for edge: Edge) -> EdgeValue { values[Edge.allCases.firstIndex(of: edge)!] }
    var allEqual: Bool { values.dropFirst().allSatisfy { $0 == values[0] } }

    mutating func set(_ value: EdgeValue, for edge: Edge) {
        if linked { values = Array(repeating: value, count: 4) }
        else {
            values[Edge.allCases.firstIndex(of: edge)!] = value
            if isPairLinked(edge) { values[Edge.allCases.firstIndex(of: edge.partner)!] = value }
        }
    }

    func isPairLinked(_ edge: Edge) -> Bool {
        linked || (edge.isVertical ? verticalLinked : horizontalLinked)
    }

    mutating func unlinkAll() {
        linked = false
        verticalLinked = false
        horizontalLinked = false
    }

    mutating func togglePair(using edge: Edge) {
        let wasLinked = isPairLinked(edge)
        if linked {
            linked = false
            verticalLinked = true
            horizontalLinked = true
        }
        if edge.isVertical { verticalLinked = !wasLinked }
        else { horizontalLinked = !wasLinked }
        if !wasLinked {
            let first: Edge = edge.isVertical ? .top : .left
            set(value(for: first), for: first)
        }
        if verticalLinked && horizontalLinked { linkAll() }
    }

    mutating func linkAll() {
        let shared = value(for: .top)
        linked = true
        verticalLinked = false
        horizontalLinked = false
        values = Array(repeating: shared, count: 4)
    }
}
