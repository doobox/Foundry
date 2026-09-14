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
}

nonisolated enum PartPackageSingleSpacingControl {
    static func defaultValue(_ raw: PartPackageValue) -> ThemeSingleSpacingValue? {
        PartPackageThemePaddingControl.edgeDefault(raw).map { .init(selection: $0) }
    }

    static func resolved(_ value: ThemeSingleSpacingValue, theme: Theme) -> PartPackageValue {
        var spacing = ThemePaddingValue()
        spacing.set(value.selection, for: .top)
        guard case .object(let fields) = PartPackageThemePaddingControl.resolved(spacing, theme: theme),
              case .object(let amounts) = fields["values"], case .object(let units) = fields["units"] else {
            return .object(["css": .string("0"), "value": .number(0), "unit": .string("")])
        }
        return .object(["css": fields["top"]!, "value": amounts["top"]!, "unit": units["top"]!])
    }
}
