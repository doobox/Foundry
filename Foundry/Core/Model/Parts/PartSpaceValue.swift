import Foundation

/// Preserves both selections when switching between Bootstrap and custom space.
nonisolated struct PartSpaceValue: Equatable, Sendable {
    static let units = ["px", "rem", "em", "vw", "vh"]
    var isCustom = false
    var preset = "inherit"
    var amount: Double = 3.5
    var unit = "rem"

    init(_ value: PartProperty.Value) {
        if let fields = value.objectValue {
            isCustom = fields["custom"] == .boolean(true) || fields["custom"] == nil
            preset = Self.preset(fields["preset"]?.stringValue ?? "inherit") ?? "inherit"
            let number = fields["value"]?.numberValue ?? 3.5
            amount = number.isFinite ? max(0, number) : 3.5
            let selectedUnit = fields["unit"]?.stringValue ?? "rem"
            unit = Self.units.contains(selectedUnit) ? selectedUnit : "px"
            if !isCustom, let legacy = SpacingTokens.legacyAmount(fields["preset"]?.stringValue ?? "") {
                isCustom = true
                amount = legacy
                unit = "rem"
            }
        } else {
            // Older Container instances stored the full Bootstrap class.
            let token = value.stringValue
            let suffix = token.hasPrefix("space-y-") ? String(token.dropFirst(8)) : token
            preset = Self.preset(suffix == "none" ? "inherit" : suffix) ?? "inherit"
            if let legacy = SpacingTokens.legacyAmount(suffix) {
                isCustom = true
                amount = legacy
                unit = "rem"
            }
        }
    }

    static func preset(_ value: String) -> String? {
        value == "inherit" || (0...12).map(String.init).contains(value) ? value : nil
    }

    var storedValue: PartProperty.Value {
        .object(["custom": .boolean(isCustom), "preset": .string(preset),
                 "value": .number(amount), "unit": .string(unit)])
    }

    var cssLength: String {
        let value = amount.isFinite ? max(0, amount) : 3.5
        return String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value)
            + (Self.units.contains(unit) ? unit : "px")
    }
}
