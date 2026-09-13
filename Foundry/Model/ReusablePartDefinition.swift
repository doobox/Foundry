import Foundation

nonisolated struct ReusablePartDefinition: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var root: PartNode

    init(id: UUID = UUID(), name: String, root: PartNode) {
        self.id = id
        self.name = name
        self.root = root
    }
}
