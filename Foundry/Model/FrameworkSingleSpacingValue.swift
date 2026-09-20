import Foundation

nonisolated struct FrameworkSingleSpacingValue: Codable, Equatable, Sendable {
    var selection: FrameworkPaddingValue.EdgeValue

    init(selection: FrameworkPaddingValue.EdgeValue = .init()) { self.selection = selection }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        selection = try container.decode(FrameworkPaddingValue.EdgeValue.self)
        guard selection.amount.isFinite, selection.amount >= 0,
              PaddingPolicy.units.contains(selection.unit), selection.token != "auto" else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid spacing selection")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(selection)
    }

    /// Switches between a framework token and a raw custom amount, matching the
    /// four-edge controls: going custom carries the selected token's own amount,
    /// going back to framework snaps to the nearest token.
    mutating func setUsesFrameworkTokens(_ usesFrameworkTokens: Bool, framework: Framework) {
        var spacing = FrameworkPaddingValue()
        spacing.set(selection, for: .top)
        spacing.setUsesFrameworkTokens(usesFrameworkTokens, framework: framework)
        selection = spacing.value(for: .top)
    }
}

nonisolated enum PartPackageSingleSpacingControl {
    static func defaultValue(_ raw: PartPackageValue) -> FrameworkSingleSpacingValue? {
        PartPackageFrameworkPaddingControl.edgeDefault(raw).map { .init(selection: $0) }
    }

    static func resolved(_ value: FrameworkSingleSpacingValue, framework: Framework) -> PartPackageValue {
        var spacing = FrameworkPaddingValue()
        spacing.set(value.selection, for: .top)
        guard case .object(let fields) = PartPackageFrameworkPaddingControl.resolved(spacing, framework: framework),
              case .object(let amounts) = fields["values"], case .object(let units) = fields["units"] else {
            return .object(["css": .string("0"), "value": .number(0), "unit": .string("")])
        }
        return .object(["css": fields["top"]!, "value": amounts["top"]!, "unit": units["top"]!])
    }
}
