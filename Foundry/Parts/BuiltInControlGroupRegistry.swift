import Foundation

/// Loads Foundry's editable built-in control-group definitions once and exposes
/// their ordinary `PartPackageProperty` controls to manifest expansion.
nonisolated enum BuiltInControlGroupRegistry {
    struct Definition: Decodable, Sendable {
        let type: PartPackageControlGroup.Kind
        let name: String
        let systemImage: String
        let controls: [PartPackageProperty]
    }

    private static let definitions: [PartPackageControlGroup.Kind: Definition] = {
        var result: [PartPackageControlGroup.Kind: Definition] = [:]
        let decoder = PropertyListDecoder()

        for kind in PartPackageControlGroup.Kind.allCases {
            let resourceName = "\(kind.rawValue)-control-group"
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "plist") else {
                preconditionFailure("Missing built-in control-group resource: \(resourceName).plist")
            }

            do {
                let data = try Data(contentsOf: url)
                let definition = try decoder.decode(Definition.self, from: data)
                try validate(definition, expectedKind: kind)
                try validateControls(in: data, definition: definition)
                result[kind] = definition
            } catch {
                preconditionFailure("Invalid built-in control-group resource \(resourceName).plist: \(error)")
            }
        }

        return result
    }()

    static func definition(for kind: PartPackageControlGroup.Kind) -> Definition {
        guard let definition = definitions[kind] else {
            preconditionFailure("No built-in definition registered for control group '\(kind.rawValue)'.")
        }
        return definition
    }

    private static func validate(
        _ definition: Definition,
        expectedKind: PartPackageControlGroup.Kind
    ) throws {
        guard definition.type == expectedKind else {
            throw DefinitionError.wrongType(expected: expectedKind.rawValue, actual: definition.type.rawValue)
        }
        guard !definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DefinitionError.emptyName
        }
        guard !definition.systemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DefinitionError.emptySystemImage
        }
        guard !definition.controls.isEmpty else {
            throw DefinitionError.emptyControls
        }

        var identifiers: Set<String> = []
        for control in definition.controls {
            guard identifiers.insert(control.id).inserted else {
                throw DefinitionError.duplicateControlID(control.id)
            }
            guard control.group == definition.name else {
                throw DefinitionError.wrongInspectorGroup(
                    controlID: control.id,
                    expected: definition.name,
                    actual: control.group
                )
            }
        }
    }

    private static func validateControls(
        in data: Data,
        definition: Definition
    ) throws {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let resource = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any],
              let controls = resource["controls"] as? [[String: Any]] else {
            throw DefinitionError.invalidControls
        }

        let manifest: [String: Any] = [
            "minimumAPIVersion": 1,
            "id": "foundry.internal.control-group.\(definition.type.rawValue)",
            "title": definition.name,
            "version": "1.0.0",
            "controls": controls,
            "templates": ["html": "part.html"]
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .xml,
            options: 0
        )
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: manifestData)
        guard diagnostics.isEmpty else {
            throw DefinitionError.controlDiagnostics(
                diagnostics.map { "\($0.location): \($0.message)" }.joined(separator: "; ")
            )
        }
    }

    private enum DefinitionError: LocalizedError {
        case wrongType(expected: String, actual: String)
        case emptyName
        case emptySystemImage
        case emptyControls
        case invalidControls
        case controlDiagnostics(String)
        case duplicateControlID(String)
        case wrongInspectorGroup(controlID: String, expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .wrongType(let expected, let actual):
                "Expected type '\(expected)', found '\(actual)'."
            case .emptyName:
                "The Inspector group name is empty."
            case .emptySystemImage:
                "The Inspector group system image is empty."
            case .emptyControls:
                "The definition contains no controls."
            case .invalidControls:
                "The controls entry is not an array of dictionaries."
            case .controlDiagnostics(let message):
                "The controls failed manifest validation: \(message)"
            case .duplicateControlID(let id):
                "Control ID '\(id)' is declared more than once."
            case .wrongInspectorGroup(let controlID, let expected, let actual):
                "Control '\(controlID)' uses Inspector group '\(actual)' instead of '\(expected)'."
            }
        }
    }
}
