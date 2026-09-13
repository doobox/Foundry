import Foundation
import Synchronization

nonisolated enum BlockRegistry {
    static func definition(for type: BlockType) -> BlockDefinition {
        packageDefinitions.withLock { $0[type] } ?? unavailableDefinition(for: type)
    }

    static var availableTypes: [BlockType] {
        packageDefinitions.withLock { definitions in
            definitions.keys.sorted { $0.rawValue < $1.rawValue }
        }
    }

    static func register(_ package: LoadedBlockPackage) {
        let definition = BlockPackageAdapter.definition(from: package)
        packageDefinitions.withLock { $0[definition.type] = definition }
    }

    static func replaceDefinitions(_ definitions: [BlockType: BlockDefinition]) {
        packageDefinitions.withLock { $0 = definitions }
    }

    static func replacePackage(_ package: LoadedBlockPackage, removing identifiers: [String]) {
        let definition = BlockPackageAdapter.definition(from: package)
        packageDefinitions.withLock { definitions in
            for identifier in identifiers {
                definitions.removeValue(forKey: BlockType(rawValue: identifier))
            }
            definitions[definition.type] = definition
        }
    }

    static func unregisterPackage(identifier: String) {
        _ = packageDefinitions.withLock { $0.removeValue(forKey: BlockType(rawValue: identifier)) }
    }

    private static let packageDefinitions = Mutex<[BlockType: BlockDefinition]>([:])

    private static func definition(
        _ type: BlockType,
        _ name: String,
        _ icon: String,
        _ category: BlockCategory,
        children: Bool = false,
        render: BlockRenderKind,
        properties: [BlockPropertyDefinition]
    ) -> BlockDefinition {
        BlockDefinition(
            type: type,
            displayName: name,
            systemImage: icon,
            category: category,
            allowsChildren: children,
            renderKind: render,
            properties: properties
        )
    }

    private static func unavailableDefinition(for type: BlockType) -> BlockDefinition {
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
