import Foundation

nonisolated struct ReusableComponentDefinition: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var root: ComponentNode

    init(id: UUID = UUID(), name: String, root: ComponentNode) {
        self.id = id
        self.name = name
        self.root = root
    }
}
