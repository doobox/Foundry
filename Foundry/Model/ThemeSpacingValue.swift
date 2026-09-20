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
nonisolated struct ThemeEdgeChoice: Identifiable {
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

    /// Top and bottom share a value. Independent of `horizontalLinked` — both can be
    /// true at once (all four edges then move together, since each pair is tied and
    /// setting any edge propagates through both pairs), or either can be toggled off
    /// on its own without disturbing the other axis.
    private(set) var verticalLinked = true
    private(set) var horizontalLinked = true
    private(set) var values = Array(repeating: EdgeValue(), count: 4)

    init() {}

    private enum CodingKeys: String, CodingKey { case verticalLinked, horizontalLinked, values }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verticalLinked = try container.decode(Bool.self, forKey: .verticalLinked)
        horizontalLinked = try container.decode(Bool.self, forKey: .horizontalLinked)
        values = try container.decode([EdgeValue].self, forKey: .values)
        guard values.count == 4,
              values.allSatisfy({ $0.amount.isFinite && (Policy.allowsAutoAndNegative || $0.amount >= 0) && (Policy.allowsAutoAndNegative || $0.token != "auto") && Policy.units.contains($0.unit) }),
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
        if verticalLinked && horizontalLinked {
            values = Array(repeating: value, count: 4)
            return
        }
        values[Edge.allCases.firstIndex(of: edge)!] = value
        if isPairLinked(edge) { values[Edge.allCases.firstIndex(of: edge.partner)!] = value }
    }

    func isPairLinked(_ edge: Edge) -> Bool {
        edge.isVertical ? verticalLinked : horizontalLinked
    }

    mutating func unlinkAll() {
        verticalLinked = false
        horizontalLinked = false
    }

    mutating func linkAll() {
        verticalLinked = true
        horizontalLinked = true
        values = Array(repeating: value(for: .top), count: 4)
    }

    /// Toggles the vertical (top/bottom) or horizontal (left/right) pair. Turning a
    /// pair on syncs its group to that axis's first edge's value — and if *both*
    /// pairs end up linked, the group is all four edges, so completing the second
    /// link cascades that edge's value across everything, not just its own pair.
    mutating func togglePair(using edge: Edge) {
        if edge.isVertical {
            verticalLinked.toggle()
            if verticalLinked { unify(from: .top) }
        } else {
            horizontalLinked.toggle()
            if horizontalLinked { unify(from: .left) }
        }
    }

    private mutating func unify(from edge: Edge) {
        let shared = value(for: edge)
        for target in group(containing: edge) {
            values[target.index] = shared
        }
    }

    private func group(containing edge: Edge) -> [Edge] {
        if verticalLinked && horizontalLinked { return Edge.allCases }
        return edge.isVertical
            ? (verticalLinked ? [.top, .bottom] : [edge])
            : (horizontalLinked ? [.left, .right] : [edge])
    }

    /// Switches every edge between a theme token and a raw custom amount at once —
    /// mode is a single control-wide toggle now, not a per-edge escape hatch, so all
    /// four edges always move together. Going custom→theme snaps each edge to the
    /// nearest token; going theme→custom carries the selected token's own amount.
    mutating func setUsesThemeTokens(_ usesThemeTokens: Bool, theme: Theme) {
        let choices = Policy.choices(in: theme)
        for edge in Edge.allCases {
            var edgeValue = value(for: edge)
            if usesThemeTokens {
                edgeValue.token = Self.nearestToken(toAmount: edgeValue.amount, unit: edgeValue.unit, choices: choices)
                edgeValue.isCustom = false
            } else {
                if let choice = choices.first(where: { $0.id == edgeValue.token }) {
                    edgeValue.amount = choice.amount
                    edgeValue.unit = Policy.themeUnit
                } else if edgeValue.token == "none" {
                    edgeValue.amount = 0
                    edgeValue.unit = Policy.themeUnit
                }
                edgeValue.isCustom = true
            }
            values[edge.index] = edgeValue
        }
    }

    /// A rough px⇄rem/em conversion (assuming a 16px root) purely so "nearest token"
    /// lands somewhere sensible when switching into theme mode — not exact CSS math.
    private static func themeEquivalentAmount(_ amount: Double, unit: String) -> Double {
        switch (unit, Policy.themeUnit) {
        case (Policy.themeUnit, _): amount
        case ("px", "rem"), ("px", "em"): amount / 16
        case ("rem", "px"), ("em", "px"): amount * 16
        default: amount
        }
    }

    private static func nearestToken(toAmount amount: Double, unit: String, choices: [ThemeEdgeChoice]) -> String {
        let target = themeEquivalentAmount(amount, unit: unit)
        var bestID = "none"
        var bestDelta = abs(target)
        for choice in choices where abs(choice.amount - target) < bestDelta {
            bestDelta = abs(choice.amount - target)
            bestID = choice.id
        }
        return bestID
    }
}
