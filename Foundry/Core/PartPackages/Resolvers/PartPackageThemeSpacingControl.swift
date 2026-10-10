import Foundation

typealias PartPackageThemeBorderWidthControl = PartPackageThemeSpacingControl<BorderWidthPolicy>
typealias PartPackageThemeRadiusControl = PartPackageThemeSpacingControl<RadiusPolicy>
typealias PartPackageThemePaddingControl = PartPackageThemeSpacingControl<PaddingPolicy>
typealias PartPackageThemeMarginControl = PartPackageThemeSpacingControl<MarginPolicy>

nonisolated enum PartPackageThemeSpacingControl<Policy: ThemeSpacingPolicy> {
    static var tokens: [String] { Policy.tokens }
    static var units: [String] { Policy.units }

    static func edgeDefault(_ value: PartPackageValue) -> ThemeSpacingValue<Policy>.EdgeValue? {
        if case .string(let token) = value, tokens.contains(token) {
            var result = ThemeSpacingValue<Policy>.EdgeValue()
            result.token = token
            return result
        }
        if case .object(let fields) = value, Set(fields.keys) == ["value", "unit"],
           case .number(let amount) = fields["value"], amount.isFinite, (Policy.allowsAutoAndNegative || amount >= 0),
           case .string(let unit) = fields["unit"], units.contains(unit) {
            var result = ThemeSpacingValue<Policy>.EdgeValue()
            result.token = "none"
            result.isCustom = true
            result.amount = amount
            result.unit = unit
            return result
        }
        return nil
    }

    static func defaultValue(_ raw: PartPackageValue) -> ThemeSpacingValue<Policy>? {
        convertedDefault(raw, edgeDefault: edgeDefault)
    }

    /// Defaults for the generic edges/corners controls: raw lengths only — no theme
    /// tokens, since those controls never consult the theme. The declared `units`
    /// list additionally restricts which units the manifest may use.
    static func customDefaultValue(_ raw: PartPackageValue, units allowedUnits: [String]) -> ThemeSpacingValue<Policy>? {
        convertedDefault(raw) { value in
            guard let custom = edgeDefault(value), custom.isCustom, allowedUnits.contains(custom.unit) else { return nil }
            return custom
        }
    }

    /// A zero length in the first permitted unit, for value bindings that need a
    /// custom-only fallback.
    static func customZero(units allowedUnits: [String]) -> ThemeSpacingValue<Policy> {
        var zero = ThemeSpacingValue<Policy>.EdgeValue()
        zero.token = "none"
        zero.isCustom = true
        zero.amount = 0
        zero.unit = allowedUnits.first ?? Policy.units[0]
        var result = ThemeSpacingValue<Policy>()
        result.setAll(zero)
        return result
    }

    private static func convertedDefault(
        _ raw: PartPackageValue,
        edgeDefault: (PartPackageValue) -> ThemeSpacingValue<Policy>.EdgeValue?
    ) -> ThemeSpacingValue<Policy>? {
        var result = ThemeSpacingValue<Policy>()
        if let shared = edgeDefault(raw) {
            // A uniform default fills every edge but never activates links;
            // link state stays at the policy's default.
            result.setAll(shared)
            return result
        }
        guard case .object(let fields) = raw,
              Set(fields.keys) == Set(ThemeSpacingValue<Policy>.Edge.allCases.map(\.key)) else { return nil }
        result.unlinkAll()
        for edge in ThemeSpacingValue<Policy>.Edge.allCases {
            guard let rawEdge = fields[edge.key], let value = edgeDefault(rawEdge) else { return nil }
            result.set(value, for: edge)
        }
        if result.allEqual, Policy.linksByDefault { result.linkAll() }
        return result
    }

    static func resolved(_ value: ThemeSpacingValue<Policy>, theme: Theme) -> PartPackageValue {
        var result: [String: PartPackageValue] = [:]
        var amounts: [String: PartPackageValue] = [:]
        var resolvedUnits: [String: PartPackageValue] = [:]
        let choices = Policy.choices(in: theme)
        for edge in ThemeSpacingValue<Policy>.Edge.allCases {
            let selection = value.value(for: edge)
            if !selection.isCustom && selection.token == "auto" && Policy.allowsAutoAndNegative {
                let key = edge.key
                result[key] = .string("auto")
                resolvedUnits[key] = .string("")
                continue // No numeric entry: auto is not a measurement.
            }
            let css: String
            let amount: Double
            let unit: String
            if selection.isCustom {
                css = String(selection.amount) + selection.unit
                amount = selection.amount
                unit = selection.unit
            } else if selection.token == "none" {
                css = "0"
                amount = 0
                unit = ""
            } else {
                let choice = choices.first { $0.id == selection.token }
                css = choice?.css ?? "0"
                amount = choice?.amount ?? 0
                unit = choice == nil ? "" : Policy.themeUnit
            }
            let key = edge.key
            result[key] = .string(css)
            amounts[key] = .number(amount)
            resolvedUnits[key] = .string(unit)
        }
        result["values"] = .object(amounts)
        result["units"] = .object(resolvedUnits)
        let edges = ThemeSpacingValue<Policy>.Edge.allCases
        let order = Policy.isRadius ? [0, 1, 3, 2] : [0, 3, 1, 2]
        result["css"] = .string(order.map { result[edges[$0].key]!.stringValue }.joined(separator: " "))
        return .object(result)
    }
}
