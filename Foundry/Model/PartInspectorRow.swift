import Foundation

/// Child pickers participate in the same declaration order as ordinary controls.
nonisolated enum PartInspectorRow: Identifiable, Sendable {
    case controls(PartInspectorControlGroup)
    case childPicker(PartPackageSlot)

    var id: String {
        switch self {
        case .controls(let group): "property:" + group.id.rawValue
        case .childPicker(let slot): "slot:" + slot.id
        }
    }

    var section: PartPropertySection {
        switch self {
        case .controls(let group): group.properties[0].section
        case .childPicker(let slot): .init(rawValue: slot.group)
        }
    }

    var membershipIDs: [String] {
        switch self {
        case .controls(let group): group.properties.map { "property:" + $0.id.rawValue }
        case .childPicker: [id]
        }
    }

    func filtered(
        properties: (PartPropertyDefinition) -> Bool,
        childPickers: (PartPackageSlot) -> Bool
    ) -> Self? {
        switch self {
        case .controls(let group):
            let remaining = group.properties.filter(properties)
            guard let first = remaining.first else { return nil }
            return .controls(.init(id: first.key, properties: remaining))
        case .childPicker(let slot):
            return childPickers(slot) ? self : nil
        }
    }
}
