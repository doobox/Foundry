import Foundation

nonisolated struct ReusableBlockDefinition: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var root: BlockNode

    init(id: UUID = UUID(), name: String, root: BlockNode) {
        self.id = id
        self.name = name
        self.root = root
    }
}
