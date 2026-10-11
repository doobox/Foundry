import Foundation

nonisolated enum PartPlacement: Equatable, Sendable {
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

nonisolated struct PartLocation: Equatable, Sendable {
    let parentID: UUID?
    let index: Int
}

nonisolated extension Array where Element == PartNode {
    struct SlotContext: Equatable, Sendable {
        let parentID: UUID
        let slotID: String
    }

    func endPlacement(in parentID: UUID) -> PartPlacement {
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

    func node(withID id: UUID) -> PartNode? {
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

    func location(of id: UUID, parentID: UUID? = nil) -> PartLocation? {
        for (index, node) in enumerated() {
            if node.id == id {
                return PartLocation(parentID: parentID, index: index)
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
        transform: (inout PartNode) -> Void
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
    mutating func append(_ node: PartNode, to parentID: UUID?) -> Bool {
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

    mutating func extractNode(withID id: UUID) -> PartNode? {
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
    mutating func wrapNode(withID id: UUID, in wrapper: PartNode) -> Bool {
        if let index = firstIndex(where: { $0.id == id }) {
            var child = self[index]
            var container = wrapper
            container.slotID = child.slotID
            child.slotID = container.definition.package?.dropZoneNames.first.map {
                container.definition.package?.dropZoneSlotID(for: $0) ?? ""
            } ?? container.definition.package?.manifest.slots.first?.id
            container.children = [child]
            guard [container].accepts(child, at: .inside(container.id)) else { return false }
            self[index] = container
            return true
        }
        for index in indices where self[index].children.wrapNode(withID: id, in: wrapper) {
            return true
        }
        return false
    }

    @discardableResult
    mutating func insert(
        _ node: PartNode,
        at placement: PartPlacement
    ) -> Bool {
        guard accepts(node, at: placement) else { return false }
        switch placement {
        case .end:
            append(node)
            return true
        case .inside(let parentID):
            guard self.node(withID: parentID)?.definition.allowsChildren == true else {
                return false
            }
            var child = node
            let package = self.node(withID: parentID)?.definition.package
            child.slotID = package?.dropZoneNames.first.map { package?.dropZoneSlotID(for: $0) ?? "" }
                ?? package?.manifest.slots.first?.id
            return updateNode(withID: parentID) { $0.children.append(child) }
        case .insideSlot(let parentID, let slotID):
            guard self.node(withID: parentID)?.definition.allowsChildren == true else {
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
        to placement: PartPlacement
    ) -> Bool {
        guard let source = node(withID: id),
              !placement.references(id),
              !placement.referencesNode(in: source),
              permitsRemoving(id, for: placement) else {
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

    func permitsRemoving(_ id: UUID, for destination: PartPlacement? = nil) -> Bool {
        guard let sourceContext = slotContext(of: id),
              let parent = node(withID: sourceContext.parentID),
              let slot = parent.definition.package?.manifest.slots.first(where: { $0.id == sourceContext.slotID }) else {
            return true
        }
        if destination.flatMap(slotContext(for:)) == sourceContext {
            return true
        }
        if destination != nil, slot.containment == .locked {
            return false
        }
        return children(in: sourceContext).count > slot.minimum
    }

    func accepts(_ node: PartNode, at placement: PartPlacement) -> Bool {
        let destinationParentID: UUID? = switch placement {
        case .inside(let parentID), .insideSlot(let parentID, _): parentID
        case .before(let targetID), .after(let targetID): location(of: targetID)?.parentID
        case .end: nil
        }
        let allowedParents = node.definition.package?.manifest.allowedParents ?? []
        if !allowedParents.isEmpty {
            guard let destinationParentID,
                  let parent = self.node(withID: destinationParentID),
                  allowedParents.contains(parent.type.rawValue) else { return false }
        }
        if case .insideSlot(let parentID, let slotID) = placement,
           let package = self.node(withID: parentID)?.definition.package,
           !package.isDropZoneSlotID(slotID),
           !package.manifest.slots.contains(where: { $0.id == slotID }) {
            return false
        }
        guard let context = slotContext(for: placement),
              let parent = self.node(withID: context.parentID),
              let slot = parent.definition.package?.manifest.slots.first(where: { $0.id == context.slotID }) else {
            return true
        }
        guard slot.acceptsPart(node.type) else { return false }
        return slot.maximum.map { children(in: context).count < $0 } ?? true
    }

    func slotContext(of childID: UUID) -> SlotContext? {
        guard let location = location(of: childID),
              let parentID = location.parentID,
              let parent = node(withID: parentID),
              let child = node(withID: childID),
              let package = parent.definition.package,
              let slotID = child.slotID
                ?? package.dropZoneNames.first.map(package.dropZoneSlotID(for:))
                ?? package.manifest.slots.first?.id else {
            return nil
        }
        return SlotContext(parentID: parentID, slotID: slotID)
    }

    func slotContext(for placement: PartPlacement) -> SlotContext? {
        switch placement {
        case .insideSlot(let parentID, let slotID):
            return SlotContext(parentID: parentID, slotID: slotID)
        case .inside(let parentID):
            guard let package = node(withID: parentID)?.definition.package,
                  let slotID = package.dropZoneNames.first.map(package.dropZoneSlotID(for:))
                    ?? package.manifest.slots.first?.id else { return nil }
            return SlotContext(parentID: parentID, slotID: slotID)
        case .before(let targetID), .after(let targetID):
            return slotContext(of: targetID)
        case .end:
            return nil
        }
    }

    func children(in context: SlotContext) -> [PartNode] {
        guard let parent = node(withID: context.parentID) else { return [] }
        let package = parent.definition.package
        let defaultSlotID = package?.dropZoneNames.first.map { package?.dropZoneSlotID(for: $0) ?? "" }
            ?? package?.manifest.slots.first?.id
        return parent.children.filter { ($0.slotID ?? defaultSlotID) == context.slotID }
    }

    private mutating func insert(
        _ node: PartNode,
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

nonisolated extension PartPackageSlot {
    func acceptsPart(_ type: PartType) -> Bool {
        accepts.contains("*") || accepts.contains(type.rawValue)
    }

    func offersInPicker(_ type: PartType) -> Bool {
        acceptsPart(type) && pickerItems.contains(type.rawValue)
    }
}

private nonisolated extension PartPlacement {
    func references(_ id: UUID) -> Bool {
        switch self {
        case .before(let target), .after(let target), .inside(let target), .insideSlot(let target, _):
            target == id
        case .end:
            false
        }
    }

    func referencesNode(in node: PartNode) -> Bool {
        switch self {
        case .before(let target), .after(let target), .inside(let target), .insideSlot(let target, _):
            node.children.node(withID: target) != nil
        case .end:
            false
        }
    }
}
