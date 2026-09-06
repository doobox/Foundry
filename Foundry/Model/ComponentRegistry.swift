import Foundation
import Synchronization

nonisolated enum ComponentRegistry {
    static func definition(for type: ComponentType) -> ComponentDefinition {
        packageDefinitions.withLock { $0[type] } ?? unavailableDefinition(for: type)
    }

    static var availableTypes: [ComponentType] {
        packageDefinitions.withLock { definitions in
            definitions.keys.sorted { $0.rawValue < $1.rawValue }
        }
    }

    static func register(_ package: LoadedComponentPackage) {
        let definition = ComponentPackageAdapter.definition(from: package)
        packageDefinitions.withLock { $0[definition.type] = definition }
    }

    static func replacePackages(_ packages: [LoadedComponentPackage]) {
        let definitions = Dictionary(
            packages.map(ComponentPackageAdapter.definition).map { ($0.type, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        packageDefinitions.withLock { $0 = definitions }
    }

    static func replacePackage(_ package: LoadedComponentPackage, removing identifiers: [String]) {
        let definition = ComponentPackageAdapter.definition(from: package)
        packageDefinitions.withLock { definitions in
            for identifier in identifiers {
                definitions.removeValue(forKey: ComponentType(rawValue: identifier))
            }
            definitions[definition.type] = definition
        }
    }

    static func unregisterPackage(identifier: String) {
        _ = packageDefinitions.withLock { $0.removeValue(forKey: ComponentType(rawValue: identifier)) }
    }

    private static let packageDefinitions = Mutex<[ComponentType: ComponentDefinition]>([:])

    private static func definition(
        _ type: ComponentType,
        _ name: String,
        _ icon: String,
        _ category: ComponentCategory,
        children: Bool = false,
        render: ComponentRenderKind,
        properties: [ComponentPropertyDefinition]
    ) -> ComponentDefinition {
        ComponentDefinition(
            type: type,
            displayName: name,
            systemImage: icon,
            category: category,
            allowsChildren: children,
            renderKind: render,
            properties: properties
        )
    }

    private static func unavailableDefinition(for type: ComponentType) -> ComponentDefinition {
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
