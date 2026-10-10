import Foundation

/// Bootstrap's spacing scale plus project-named additions.
///
/// The thirteen Bootstrap steps are fixed: Bootstrap bakes their values into its
/// utilities, so Foundry offers them as they ship. Custom entries extend the scale
/// with new names and are emitted as additional utilities.
nonisolated struct SpacingTokens: Codable, Equatable, Sendable {
    static let standard = SpacingTokens()
    static let multipliers: [Double] = [0, 0.25, 0.375, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3]
    var custom: [CustomSpacingToken] = []
    var choices: [FrameworkEdgeChoice] {
        Self.multipliers.enumerated().map {
            FrameworkEdgeChoice(id: String($0.offset), label: String($0.offset), amount: $0.element, css: "var(--bs-spacer-\($0.offset))")
        } + custom.map {
            FrameworkEdgeChoice(id: $0.name, label: $0.name, amount: $0.value, css: "var(--bs-spacer-\($0.name))")
        }
    }
    static func validName(_ name: String) -> Bool {
        !(["none", "auto", "inherit", "initial", "unset", "revert"] + (0...12).map(String.init)).contains(name)
            && name.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]*$", options: .regularExpression) != nil
    }
    init(custom: [CustomSpacingToken] = []) { self.custom = custom }
    private enum CodingKeys: String, CodingKey { case custom }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        custom = try values.decodeIfPresent([CustomSpacingToken].self, forKey: .custom) ?? []
        guard Set(custom.map(\.name)).count == custom.count,
              Set(custom.map(\.id)).count == custom.count,
              custom.allSatisfy({ Self.validName($0.name) && $0.value.isFinite && $0.value >= 0 }) else {
            throw DecodingError.dataCorruptedError(forKey: .custom, in: values, debugDescription: "Spacing names must be unique CSS suffixes and values must be finite, nonnegative rem lengths.")
        }
    }
}
