import Foundation

nonisolated enum ComponentPlacement: Equatable, Sendable {
    case before(UUID)
    case after(UUID)
    case inside(UUID)
    case insideSlot(UUID, String)
    case end

    var targetID: UUID? {
        switch self {
        case .before(let id), .after(let id), .inside(let id), .insideSlot(let id, _): id
        case .end: nil
        }
    }
}

nonisolated struct ComponentLocation: Equatable, Sendable {
    let parentID: UUID?
    let index: Int
}

nonisolated extension Array where Element == ComponentNode {
    func endPlacement(in parentID: UUID) -> ComponentPlacement {
        if let slotID = last?.slotID {
            return .insideSlot(parentID, slotID)
        }
        return .inside(parentID)
    }

    func ancestorIDs(of id: UUID) -> [UUID] {
        for node in self {
            if node.id == id {
                return []
            }
            let childAncestors = node.children.ancestorIDs(of: id)
            if node.children.node(withID: id) != nil {
                return [node.id] + childAncestors
            }
        }
        return []
    }

    func node(withID id: UUID) -> ComponentNode? {
        for node in self {
            if node.id == id {
                return node
            }
            if let match = node.children.node(withID: id) {
                return match
            }
        }
        return nil
    }

    func location(of id: UUID, parentID: UUID? = nil) -> ComponentLocation? {
        for (index, node) in enumerated() {
            if node.id == id {
                return ComponentLocation(parentID: parentID, index: index)
            }
            if let location = node.children.location(of: id, parentID: node.id) {
                return location
            }
        }
        return nil
    }

    @discardableResult
    mutating func updateNode(
        withID id: UUID,
        transform: (inout ComponentNode) -> Void
    ) -> Bool {
        for index in indices {
            if self[index].id == id {
                transform(&self[index])
                return true
            }
            if self[index].children.updateNode(withID: id, transform: transform) {
                return true
            }
        }
        return false
    }

    @discardableResult
    mutating func append(_ node: ComponentNode, to parentID: UUID?) -> Bool {
        guard let parentID else {
            append(node)
            return true
        }
        return updateNode(withID: parentID) { $0.children.append(node) }
    }

    @discardableResult
    mutating func removeNode(withID id: UUID) -> Bool {
        extractNode(withID: id) != nil
    }

    mutating func extractNode(withID id: UUID) -> ComponentNode? {
        if let index = firstIndex(where: { $0.id == id }) {
            return remove(at: index)
        }
        for index in indices {
            if let removed = self[index].children.extractNode(withID: id) {
                return removed
            }
        }
        return nil
    }

    @discardableResult
    mutating func insert(
        _ node: ComponentNode,
        at placement: ComponentPlacement
    ) -> Bool {
        switch placement {
        case .end:
            append(node)
            return true
        case .inside(let parentID):
            guard self.node(withID: parentID)?.type.definition.allowsChildren == true else {
                return false
            }
            var child = node
            child.slotID = nil
            return updateNode(withID: parentID) { $0.children.append(child) }
        case .insideSlot(let parentID, let slotID):
            guard self.node(withID: parentID)?.type.definition.allowsChildren == true else {
                return false
            }
            var slottedNode = node
            slottedNode.slotID = slotID
            return updateNode(withID: parentID) { $0.children.append(slottedNode) }
        case .before(let targetID):
            return insert(node, beside: targetID, offset: 0)
        case .after(let targetID):
            return insert(node, beside: targetID, offset: 1)
        }
    }

    @discardableResult
    mutating func moveNode(
        withID id: UUID,
        to placement: ComponentPlacement
    ) -> Bool {
        guard let source = node(withID: id),
              !placement.references(id),
              !placement.referencesNode(in: source) else {
            return false
        }

        var candidate = self
        guard let removed = candidate.extractNode(withID: id),
              candidate.insert(removed, at: placement) else {
            return false
        }
        self = candidate
        return true
    }

    private mutating func insert(
        _ node: ComponentNode,
        beside targetID: UUID,
        offset: Int
    ) -> Bool {
        if let index = firstIndex(where: { $0.id == targetID }) {
            var sibling = node
            sibling.slotID = self[index].slotID
            insert(sibling, at: index + offset)
            return true
        }
        for index in indices {
            if self[index].children.insert(node, beside: targetID, offset: offset) {
                return true
            }
        }
        return false
    }
}

private nonisolated extension ComponentPlacement {
    func references(_ id: UUID) -> Bool {
        switch self {
        case .before(let target), .after(let target), .inside(let target), .insideSlot(let target, _):
            target == id
        case .end:
            false
        }
    }

    func referencesNode(in node: ComponentNode) -> Bool {
        switch self {
        case .before(let target), .after(let target), .inside(let target), .insideSlot(let target, _):
            node.children.node(withID: target) != nil
        case .end:
            false
        }
    }
}
