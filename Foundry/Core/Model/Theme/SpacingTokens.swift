import Foundation

/// Bootstrap's native steps 0–12 and previously saved project-named additions.
///
/// The thirteen Bootstrap steps are fixed: Bootstrap bakes their values into its
/// utilities, so Foundry offers them as they ship.
nonisolated struct SpacingTokens: Codable, Equatable, Sendable {
    static let standard = SpacingTokens()
    static let multipliers: [Double] = [0, 0.25, 0.375, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3]
    static func legacyAmount(_ token: String) -> Double? {
        guard let step = Int(token), String(step) == token, (13...24).contains(step) else { return nil }
        return [3.5, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16][step - 13]
    }
    var custom: [CustomSpacingToken] = []
    var choices: [ThemeEdgeChoice] {
        Self.multipliers.enumerated().filter { index, _ in !custom.contains(where: { $0.name == String(index) }) }.map {
            ThemeEdgeChoice(id: String($0.offset), label: String($0.offset), amount: $0.element, css: "var(--bs-spacer-\($0.offset))")
        } + custom.map {
            ThemeEdgeChoice(id: $0.name, label: $0.name, amount: $0.value, css: "var(--bs-spacer-\($0.name))")
        }
    }
    static func validName(_ name: String) -> Bool {
        !(["none", "auto", "inherit", "initial", "unset", "revert"] + (0...24).map(String.init)).contains(name)
            && name.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]*$", options: .regularExpression) != nil
    }
    init(custom: [CustomSpacingToken] = []) { self.custom = custom }
    private enum CodingKeys: String, CodingKey { case custom }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        custom = try values.decodeIfPresent([CustomSpacingToken].self, forKey: .custom) ?? []
        guard Set(custom.map(\.name)).count == custom.count,
              Set(custom.map(\.id)).count == custom.count,
              custom.allSatisfy({ (Self.validName($0.name) || (13...24).map(String.init).contains($0.name)) && $0.value.isFinite && $0.value >= 0 }) else {
            throw DecodingError.dataCorruptedError(forKey: .custom, in: values, debugDescription: "Spacing names must be unique CSS suffixes and values must be finite, nonnegative rem lengths.")
        }
    }
}
