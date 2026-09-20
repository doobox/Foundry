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

nonisolated struct ReusablePartFolder: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var children: [ReusablePartNode]

    init(id: UUID = UUID(), name: String, children: [ReusablePartNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

/// The reusable-part panel's ordered tree: folders and definitions, organized
/// exactly like the asset library.
nonisolated indirect enum ReusablePartNode: Codable, Equatable, Identifiable, Sendable {
    case folder(ReusablePartFolder)
    case part(ReusablePartDefinition)

    var id: UUID {
        switch self {
        case .folder(let folder): folder.id
        case .part(let definition): definition.id
        }
    }

    var allDefinitions: [ReusablePartDefinition] {
        switch self {
        case .folder(let folder): folder.children.flatMap(\.allDefinitions)
        case .part(let definition): [definition]
        }
    }
}

nonisolated enum ReusablePartPlacement: Equatable, Sendable {
    case end
    case inside(folderID: UUID)
    case before(nodeID: UUID)
    case after(nodeID: UUID)

    func targets(_ id: UUID) -> Bool {
        switch self {
        case .end: false
        case .inside(let folderID): folderID == id
        case .before(let nodeID), .after(let nodeID): nodeID == id
        }
    }
}

nonisolated extension Array where Element == ReusablePartNode {
    var allDefinitions: [ReusablePartDefinition] { flatMap(\.allDefinitions) }

    func node(withID id: UUID) -> ReusablePartNode? {
        for node in self {
            if node.id == id { return node }
            if case .folder(let folder) = node,
               let match = folder.children.node(withID: id) {
                return match
            }
        }
        return nil
    }

    mutating func insert(_ node: ReusablePartNode, at placement: ReusablePartPlacement) -> Bool {
        switch placement {
        case .end:
            append(node)
            return true
        case .inside(let folderID):
            return mutateFolder(id: folderID) { $0.children.append(node) }
        case .before(let nodeID):
            return insert(node, adjacentTo: nodeID, offset: 0)
        case .after(let nodeID):
            return insert(node, adjacentTo: nodeID, offset: 1)
        }
    }

    mutating func move(id: UUID, to placement: ReusablePartPlacement) -> Bool {
        guard !placement.targets(id),
              let node = node(withID: id),
              !node.containsTargetFolder(for: placement) else { return false }
        var copy = self
        guard let removed = copy.removeNode(id: id), copy.insert(removed, at: placement) else { return false }
        self = copy
        return true
    }

    @discardableResult
    mutating func removeNode(id: UUID) -> ReusablePartNode? {
        if let index = firstIndex(where: { $0.id == id }) {
            return remove(at: index)
        }
        for index in indices {
            guard case .folder(var folder) = self[index],
                  let removed = folder.children.removeNode(id: id) else { continue }
            self[index] = .folder(folder)
            return removed
        }
        return nil
    }

    mutating func renameFolder(id: UUID, to name: String) -> Bool {
        mutateFolder(id: id) { $0.name = name }
    }

    @discardableResult
    mutating func mutateDefinition(id: UUID, mutation: (inout ReusablePartDefinition) -> Void) -> Bool {
        for index in indices {
            switch self[index] {
            case .part(var definition) where definition.id == id:
                mutation(&definition)
                self[index] = .part(definition)
                return true
            case .folder(var folder):
                if folder.children.mutateDefinition(id: id, mutation: mutation) {
                    self[index] = .folder(folder)
                    return true
                }
            case .part:
                continue
            }
        }
        return false
    }

    mutating func updateAllDefinitions(_ mutation: (inout ReusablePartDefinition) -> Void) {
        for index in indices {
            switch self[index] {
            case .part(var definition):
                mutation(&definition)
                self[index] = .part(definition)
            case .folder(var folder):
                folder.children.updateAllDefinitions(mutation)
                self[index] = .folder(folder)
            }
        }
    }

    private mutating func insert(_ node: ReusablePartNode, adjacentTo targetID: UUID, offset: Int) -> Bool {
        if let index = firstIndex(where: { $0.id == targetID }) {
            insert(node, at: index + offset)
            return true
        }
        for index in indices {
            guard case .folder(var folder) = self[index],
                  folder.children.insert(node, adjacentTo: targetID, offset: offset) else { continue }
            self[index] = .folder(folder)
            return true
        }
        return false
    }

    private mutating func mutateFolder(id: UUID, mutation: (inout ReusablePartFolder) -> Void) -> Bool {
        for index in indices {
            switch self[index] {
            case .part:
                continue
            case .folder(var folder):
                if folder.id == id {
                    mutation(&folder)
                    self[index] = .folder(folder)
                    return true
                }
                if folder.children.mutateFolder(id: id, mutation: mutation) {
                    self[index] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }
}

nonisolated private extension ReusablePartNode {
    func containsTargetFolder(for placement: ReusablePartPlacement) -> Bool {
        guard case .folder(let folder) = self,
              case .inside(let targetID) = placement else { return false }
        return folder.id == targetID || folder.children.node(withID: targetID) != nil
    }
}
