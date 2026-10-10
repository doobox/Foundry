import Foundation

nonisolated struct ThemeSingleSpacingValue: Codable, Equatable, Sendable {
    var selection: ThemePaddingValue.EdgeValue

    init(selection: ThemePaddingValue.EdgeValue = .init()) { self.selection = selection }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        selection = try container.decode(ThemePaddingValue.EdgeValue.self)
        guard selection.amount.isFinite, selection.amount >= 0,
              PaddingPolicy.units.contains(selection.unit), selection.token != "auto" else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid spacing selection")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(selection)
    }

    /// Switches between a theme token and a raw custom amount, matching
    /// the four-edge controls: each mode keeps its own last state, nothing is
    /// converted or snapped.
    mutating func setUsesThemeTokens(_ usesThemeTokens: Bool) {
        selection.isCustom = !usesThemeTokens
    }
}

nonisolated enum PartPackageSingleSpacingControl {
    static func defaultValue(_ raw: PartPackageValue) -> ThemeSingleSpacingValue? {
        PartPackageThemePaddingControl.edgeDefault(raw).map { .init(selection: $0) }
    }

    /// `noneValue` lets a control say what CSS its `none` token should emit —
    /// `0` for a minimum, `none` for a maximum — so templates can interpolate
    /// the value unconditionally instead of guarding it.
    static func resolved(
        _ value: ThemeSingleSpacingValue,
        theme: Theme,
        noneValue: String? = nil
    ) -> PartPackageValue {
        var spacing = ThemePaddingValue()
        spacing.set(value.selection, for: .top)
        guard case .object(let fields) = PartPackageThemePaddingControl.resolved(spacing, theme: theme),
              case .object(let amounts) = fields["values"], case .object(let units) = fields["units"] else {
            return .object(["css": .string(noneValue ?? "0"), "value": .number(0), "unit": .string("")])
        }
        let isNone = !value.selection.isCustom && value.selection.token == "none"
        let css = isNone ? PartPackageValue.string(noneValue ?? "0") : fields["top"]!
        return .object(["css": css, "value": amounts["top"]!, "unit": units["top"]!])
    }
}
