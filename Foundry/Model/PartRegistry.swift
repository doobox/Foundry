import Foundation
import Synchronization

nonisolated enum PartRegistry {
    static func definition(for type: PartType) -> PartDefinition {
        packageDefinitions.withLock { $0[type] } ?? unavailableDefinition(for: type)
    }

    static var availableTypes: [PartType] {
        packageDefinitions.withLock { definitions in
            definitions.keys.sorted { $0.rawValue < $1.rawValue }
        }
    }

    static func register(_ package: LoadedPartPackage) {
        let definition = PartPackageAdapter.definition(from: package)
        packageDefinitions.withLock { $0[definition.type] = definition }
    }

    static func replaceDefinitions(_ definitions: [PartType: PartDefinition]) {
        packageDefinitions.withLock { $0 = definitions }
    }

    static func replacePackage(_ package: LoadedPartPackage, removing identifiers: [String]) {
        let definition = PartPackageAdapter.definition(from: package)
        packageDefinitions.withLock { definitions in
            for identifier in identifiers {
                definitions.removeValue(forKey: PartType(rawValue: identifier))
            }
            definitions[definition.type] = definition
        }
    }

    static func unregisterPackage(identifier: String) {
        _ = packageDefinitions.withLock { $0.removeValue(forKey: PartType(rawValue: identifier)) }
    }

    private static let packageDefinitions = Mutex<[PartType: PartDefinition]>([:])

    private static func definition(
        _ type: PartType,
        _ name: String,
        _ icon: String,
        _ category: PartCategory,
        children: Bool = false,
        render: PartRenderKind,
        properties: [PartPropertyDefinition]
    ) -> PartDefinition {
        PartDefinition(
            type: type,
            displayName: name,
            systemImage: icon,
            category: category,
            allowsChildren: children,
            renderKind: render,
            properties: properties
        )
    }

    private static func unavailableDefinition(for type: PartType) -> PartDefinition {
        definition(
            type,
            type.rawValue.split(separator: ".").last.map(String.init) ?? "Unavailable",
            "questionmark.square.dashed",
            .unavailable,
            render: .unavailable,
            properties: []
        )
    }
}
