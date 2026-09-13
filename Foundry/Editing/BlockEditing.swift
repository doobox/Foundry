import Foundation

@MainActor
extension ProjectEditor {
    @discardableResult
    func insertBlock(
        type: BlockType,
        on pageID: UUID,
        placement: BlockPlacement
    ) -> UUID? {
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let block = BlockNode.make(type, theme: document.site.theme)
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var inserted = false
        mutate(actionName: "Add \(type.displayName)") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            inserted = site.pages[index].blocks.insert(block, at: placement)
            if inserted {
                site.blockPackages.append(contentsOf: block.packageLocks.filter {
                    !site.blockPackages.contains($0)
                })
                site.blockPackages.sort { $0.identifier < $1.identifier }
            }
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? block.id : nil
    }

    @discardableResult
    func duplicateBlock(id: UUID, on pageID: UUID) -> UUID? {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let source = page.blocks.node(withID: id) else {
            return nil
        }
        let duplicate = source.duplicated()
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: .after(id))
        var inserted = false
        mutate(actionName: "Duplicate Block") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            inserted = site.pages[index].blocks.insert(duplicate, at: .after(id))
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? duplicate.id : nil
    }

    @discardableResult
    func duplicateBlocks(ids: [UUID], on pageID: UUID) -> [UUID] {
        guard !ids.isEmpty,
              let page = document.site.pages.first(where: { $0.id == pageID }) else { return [] }
        let pairs = ids.compactMap { id in
            page.blocks.node(withID: id).map { (id, $0.duplicated()) }
        }
        guard !pairs.isEmpty else { return [] }
        guard let sharedInsertion = document.site.sharedGlobalInsertions(
            on: page,
            at: pairs.map { .after($0.0) }
        ) else { return [] }
        var insertedIDs: [UUID] = []
        mutate(actionName: pairs.count == 1 ? "Duplicate Block" : "Duplicate Blocks") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            for (sourceID, duplicate) in pairs.reversed() {
                if site.pages[index].blocks.insert(duplicate, at: .after(sourceID)) {
                    insertedIDs.append(duplicate.id)
                }
            }
            if !insertedIDs.isEmpty {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return pairs.compactMap { insertedIDs.contains($0.1.id) ? $0.1.id : nil }
    }

    @discardableResult
    func pasteBlock(
        _ source: BlockNode,
        on pageID: UUID,
        placement: BlockPlacement
    ) -> UUID? {
        let duplicate = source.duplicated()
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var inserted = false
        mutate(actionName: "Paste Block") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            inserted = site.pages[index].blocks.insert(duplicate, at: placement)
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? duplicate.id : nil
    }

    @discardableResult
    func pasteBlocks(
        _ sources: [BlockNode],
        on pageID: UUID,
        placement: BlockPlacement
    ) -> [UUID] {
        guard !sources.isEmpty else { return [] }
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return [] }
        let duplicates = sources.map { $0.duplicated() }
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var insertedIDs: [UUID] = []
        mutate(actionName: duplicates.count == 1 ? "Paste Block" : "Paste Blocks") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            var nextPlacement = placement
            for duplicate in duplicates {
                guard site.pages[index].blocks.insert(duplicate, at: nextPlacement) else { return }
                insertedIDs.append(duplicate.id)
                nextPlacement = .after(duplicate.id)
            }
            site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
        }
        return insertedIDs
    }

    @discardableResult
    func moveBlock(
        id: UUID,
        on pageID: UUID,
        to placement: BlockPlacement
    ) -> Bool {
        moveBlocks(ids: [id], on: pageID, to: placement)
    }

    func canMoveBlocks(
        ids: [UUID],
        on pageID: UUID,
        to placement: BlockPlacement
    ) -> Bool {
        guard !ids.isEmpty,
              let page = document.site.pages.first(where: { $0.id == pageID }),
              document.site.sharedGlobalMove(
                blockIDs: ids,
                on: page,
                to: placement
              ) != nil else { return false }
        var blocks = page.blocks
        var nextPlacement = placement
        for id in ids {
            guard blocks.moveNode(withID: id, to: nextPlacement) else { return false }
            nextPlacement = .after(id)
        }
        return true
    }

    @discardableResult
    func moveBlocks(
        ids: [UUID],
        on pageID: UUID,
        to placement: BlockPlacement
    ) -> Bool {
        guard !ids.isEmpty,
              let page = document.site.pages.first(where: { $0.id == pageID }),
              let sharedMove = document.site.sharedGlobalMove(
                blockIDs: ids,
                on: page,
                to: placement
              ) else { return false }
        var movedAll = false
        mutate(actionName: ids.count == 1 ? "Move Block" : "Move Blocks") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            var blocks = site.pages[index].blocks
            var nextPlacement = placement
            for id in ids {
                guard blocks.moveNode(withID: id, to: nextPlacement) else {
                    return
                }
                nextPlacement = .after(id)
            }
            site.pages[index].blocks = blocks
            site.synchronizeGlobalsAfterStructureMove(sharedMove)
            movedAll = true
        }
        return movedAll
    }

    @discardableResult
    func moveBlockBySiblingOffset(
        id: UUID,
        on pageID: UUID,
        offset: Int
    ) -> Bool {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let location = page.blocks.location(of: id),
              let siblings = page.blocks.children(of: location.parentID) else {
            return false
        }
        let targetIndex = location.index + offset
        guard siblings.indices.contains(targetIndex) else {
            return false
        }
        let targetID = siblings[targetIndex].id
        let placement: BlockPlacement =
            offset < 0 ? .before(targetID) : .after(targetID)
        return moveBlock(id: id, on: pageID, to: placement)
    }

    @discardableResult
    func outdentBlock(id: UUID, on pageID: UUID) -> Bool {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let parentID = page.blocks.location(of: id)?.parentID else {
            return false
        }
        return moveBlock(id: id, on: pageID, to: .after(parentID))
    }
}

nonisolated struct SharedGlobalStructureMove {
    let authoritativeInstances: [UUID: UUID]
}

nonisolated extension Site {
    func sharedGlobalInsertion(
        on page: Page,
        at placement: BlockPlacement
    ) -> SharedGlobalStructureMove {
        guard let parentID = page.blocks.parentID(for: placement),
              let context = globalStructureContext(containing: parentID),
              !context.isOverridden else {
            return SharedGlobalStructureMove(authoritativeInstances: [:])
        }
        return SharedGlobalStructureMove(
            authoritativeInstances: [context.definitionID: context.instanceID]
        )
    }

    func sharedGlobalInsertions(
        on page: Page,
        at placements: [BlockPlacement]
    ) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]
        for placement in placements {
            guard let parentID = page.blocks.parentID(for: placement),
                  let context = globalStructureContext(containing: parentID),
                  !context.isOverridden else { continue }
            instancesByDefinition[context.definitionID, default: []].insert(context.instanceID)
        }
        guard instancesByDefinition.values.allSatisfy({ $0.count == 1 }) else { return nil }
        return SharedGlobalStructureMove(
            authoritativeInstances: instancesByDefinition.compactMapValues(\.first)
        )
    }

    func sharedGlobalRemoval(blockIDs: [UUID]) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]
        for blockID in blockIDs {
            guard let context = globalStructureContext(containing: blockID),
                  !context.path.isEmpty,
                  !context.isOverridden else { continue }
            instancesByDefinition[context.definitionID, default: []].insert(context.instanceID)
        }
        guard instancesByDefinition.values.allSatisfy({ $0.count == 1 }) else { return nil }
        return SharedGlobalStructureMove(
            authoritativeInstances: instancesByDefinition.compactMapValues(\.first)
        )
    }

    func sharedGlobalMove(
        blockIDs: [UUID],
        on page: Page,
        to placement: BlockPlacement
    ) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]

        for blockID in blockIDs {
            guard let context = globalStructureContext(containing: blockID) else { continue }
            if !context.path.isEmpty, !context.isOverridden {
                instancesByDefinition[context.definitionID, default: []].insert(context.instanceID)
            }
        }

        if let parentID = page.blocks.parentID(for: placement),
           let context = globalStructureContext(containing: parentID),
           !context.isOverridden {
            instancesByDefinition[context.definitionID, default: []].insert(context.instanceID)
        }

        guard instancesByDefinition.values.allSatisfy({ $0.count == 1 }) else {
            return nil
        }
        let authoritativeInstances = instancesByDefinition.compactMapValues(\.first)
        return SharedGlobalStructureMove(authoritativeInstances: authoritativeInstances)
    }

    mutating func synchronizeGlobalsAfterStructureMove(_ move: SharedGlobalStructureMove) {
        var templates: [UUID: BlockNode] = [:]
        for (definitionID, instanceID) in move.authoritativeInstances {
            guard let instance = block(withID: instanceID) else { continue }
            templates[definitionID] = instance.duplicatedForReusableDefinition()
        }

        for (definitionID, template) in templates {
            guard let index = globalBlocks.firstIndex(where: { $0.id == definitionID }) else { continue }
            globalBlocks[index].root = template
        }

        for (definitionID, template) in templates {
            let authoritativeInstanceID = move.authoritativeInstances[definitionID]
            for pageIndex in pages.indices {
                pages[pageIndex].blocks.replaceReusableInstances(
                    definitionID: definitionID,
                    with: template,
                    excludingInstanceID: authoritativeInstanceID
                )
            }
        }
    }
}

nonisolated extension Array where Element == BlockNode {
    func children(of parentID: UUID?) -> [BlockNode]? {
        guard let parentID else {
            return self
        }
        return node(withID: parentID)?.children
    }

    func parentID(for placement: BlockPlacement) -> UUID? {
        switch placement {
        case .inside(let parentID), .insideSlot(let parentID, _):
            parentID
        case .before(let targetID), .after(let targetID):
            location(of: targetID)?.parentID
        case .end:
            nil
        }
    }
}
