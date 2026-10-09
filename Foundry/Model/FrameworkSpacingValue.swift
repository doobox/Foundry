import Foundation

nonisolated protocol FrameworkSpacingPolicy: Sendable {
    static var allowsAutoAndNegative: Bool { get }
    static var label: String { get }
    static var isRadius: Bool { get }
    static var linksByDefault: Bool { get }
    static var units: [String] { get }
    static var frameworkUnit: String { get }
    static var tokens: [String] { get }
    static func choices(in framework: Framework) -> [FrameworkEdgeChoice]
}
nonisolated struct FrameworkEdgeChoice: Identifiable {
    let id: String
    let label: String
    let amount: Double
    let css: String
}
nonisolated extension FrameworkSpacingPolicy {
    static var isRadius: Bool { false }
    // Uniform values are the norm for radii and border widths; padding and
    // margin are directional, so they start with every edge independent.
    static var linksByDefault: Bool { true }
    static var units: [String] { ["px", "rem", "em", "%"] }
    static var frameworkUnit: String { "rem" }
    static var tokens: [String] { ["none"] + (0...12).map(String.init) + (allowsAutoAndNegative ? ["auto"] : []) }
    static func choices(in framework: Framework) -> [FrameworkEdgeChoice] {
        framework.spacing.choices
    }
}
nonisolated enum BorderWidthPolicy: FrameworkSpacingPolicy {
    static let allowsAutoAndNegative = false
    static let label = "Border width"
    static let units = ["px", "rem", "em"]
    static let frameworkUnit = "px"
    static var tokens: [String] { FrameworkDimensionTokens.standardBorderWidths.predefined.map(\.id) }
    static func choices(in framework: Framework) -> [FrameworkEdgeChoice] {
        framework.borderWidths.predefined.filter { $0.id != "none" }.map {
            FrameworkEdgeChoice(id: $0.id, label: $0.title, amount: $0.value, css: "var(--foundry-border-width-\($0.id))")
        } + framework.borderWidths.custom.map {
            FrameworkEdgeChoice(id: $0.reference, label: $0.name, amount: $0.value, css: "var(\($0.cssVariable(prefix: "border-width")))")
        }
    }
}
nonisolated enum RadiusPolicy: FrameworkSpacingPolicy {
    static let allowsAutoAndNegative = false
    static let label = "Radius"
    static let isRadius = true
    static let frameworkUnit = "px"
    static var tokens: [String] { FrameworkDimensionTokens.standardBorderRadii.predefined.map(\.id) }
    static func choices(in framework: Framework) -> [FrameworkEdgeChoice] {
        framework.borderRadii.predefined.filter { $0.id != "none" }.map {
            FrameworkEdgeChoice(id: $0.id, label: $0.title, amount: $0.value, css: "var(--foundry-border-radius-\($0.id))")
        } + framework.borderRadii.custom.map {
            FrameworkEdgeChoice(id: $0.reference, label: $0.name, amount: $0.value, css: "var(\($0.cssVariable(prefix: "border-radius")))")
        }
    }
}
nonisolated enum PaddingPolicy: FrameworkSpacingPolicy {
    static let allowsAutoAndNegative = false
    static let label = "Padding"
    static let linksByDefault = false
}
nonisolated enum MarginPolicy: FrameworkSpacingPolicy {
    static let allowsAutoAndNegative = true
    static let label = "Margin"
    static let linksByDefault = false
}
typealias FrameworkBorderWidthValue = FrameworkSpacingValue<BorderWidthPolicy>
typealias FrameworkRadiusValue = FrameworkSpacingValue<RadiusPolicy>
typealias FrameworkPaddingValue = FrameworkSpacingValue<PaddingPolicy>
typealias FrameworkMarginValue = FrameworkSpacingValue<MarginPolicy>

/// Persisted four-edge spacing selection and inspector linking state.
nonisolated struct FrameworkSpacingValue<Policy: FrameworkSpacingPolicy>: Codable, Equatable, Sendable {
    struct EdgeValue: Codable, Equatable, Sendable {
        var token = "none"
        var isCustom = false
        var amount = 0.0
        var unit = "px"

        /// The framework's None: no length chosen at all.
        var isNone: Bool { !isCustom && token == "none" }
    }

    /// Every edge is None, so the value contributes no length anywhere.
    var isNone: Bool { values.allSatisfy(\.isNone) }

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

    /// Top and bottom share a value, left and right share a value — always as
    /// independent pairs. Even with both links on, edges only follow their own
    /// axis; corners are the exception, where one nominal "link" ties all four.
    private(set) var verticalLinked = Policy.linksByDefault
    private(set) var horizontalLinked = Policy.linksByDefault
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

    /// Converts every edge using `reference` into a raw custom length, so a
    /// deleted framework value keeps its exact size without a stand-in token.
    mutating func bakeReference(_ reference: String, amount: Double, unit: String, fallbackToken: String) {
        for index in values.indices where values[index].token == reference {
            values[index].token = fallbackToken
            values[index].isCustom = true
            values[index].amount = amount
            values[index].unit = unit
        }
    }

    func value(for edge: Edge) -> EdgeValue { values[Edge.allCases.firstIndex(of: edge)!] }
    var allEqual: Bool { values.dropFirst().allSatisfy { $0 == values[0] } }

    mutating func set(_ value: EdgeValue, for edge: Edge) {
        for target in group(containing: edge) {
            values[target.index] = value
        }
    }

    /// Sets every edge to one value without consulting link state — used when
    /// seeding uniform defaults; the link flags keep their policy defaults.
    mutating func setAll(_ value: EdgeValue) {
        values = Array(repeating: value, count: 4)
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

    /// Toggles the vertical (top/bottom) or horizontal (left/right) pair.
    /// Turning a pair on syncs it to that axis's first edge's value; the other
    /// axis is never disturbed.
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
        // Corners are one nominal link across all four; edges stay pairwise
        // even when both axis links are on.
        if Policy.isRadius, verticalLinked, horizontalLinked { return Edge.allCases }
        return edge.isVertical
            ? (verticalLinked ? [.top, .bottom] : [edge])
            : (horizontalLinked ? [.left, .right] : [edge])
    }

    /// Switches every edge between framework tokens and raw custom lengths —
    /// mode is a single control-wide toggle, so all four edges move together.
    /// Each mode keeps its own last state: the custom amount/unit (0px until
    /// the user types) and the selected token both survive round trips
    /// untouched; nothing is converted or snapped.
    mutating func setUsesFrameworkTokens(_ usesFrameworkTokens: Bool) {
        for index in values.indices {
            values[index].isCustom = !usesFrameworkTokens
        }
    }
}
