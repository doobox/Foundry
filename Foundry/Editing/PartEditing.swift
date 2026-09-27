import Foundation

@MainActor
extension ProjectEditor {
    @discardableResult
    func insertPart(
        type: PartType,
        on pageID: UUID,
        placement: PartPlacement
    ) -> UUID? {
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let part = PartNode.make(type, framework: document.site.framework)
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        let ownerID = page.parts.parentID(for: placement)
        let impact: ProjectMutationImpact = sharedInsertion.authoritativeInstances.isEmpty
            ? .partStructure(ownerID: ownerID)
            : .page
        var inserted = false
        mutate(actionName: "Add \(type.displayName)", impact: impact) { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            inserted = site.pages[index].parts.insert(part, at: placement)
            if inserted {
                site.partPackages.append(contentsOf: part.packageLocks.filter {
                    !site.partPackages.contains($0)
                })
                site.partPackages.sort { $0.identifier < $1.identifier }
            }
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? part.id : nil
    }

    @discardableResult
    func duplicatePart(id: UUID, on pageID: UUID) -> UUID? {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let source = page.parts.node(withID: id) else {
            return nil
        }
        let duplicate = source.duplicated()
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: .after(id))
        var inserted = false
        mutate(actionName: "Duplicate Part") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            inserted = site.pages[index].parts.insert(duplicate, at: .after(id))
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? duplicate.id : nil
    }

    @discardableResult
    func duplicateParts(ids: [UUID], on pageID: UUID) -> [UUID] {
        guard !ids.isEmpty,
              let page = document.site.pages.first(where: { $0.id == pageID }) else { return [] }
        let pairs = ids.compactMap { id in
            page.parts.node(withID: id).map { (id, $0.duplicated()) }
        }
        guard !pairs.isEmpty else { return [] }
        guard let sharedInsertion = document.site.sharedGlobalInsertions(
            on: page,
            at: pairs.map { .after($0.0) }
        ) else { return [] }
        var insertedIDs: [UUID] = []
        mutate(actionName: pairs.count == 1 ? "Duplicate Part" : "Duplicate Parts") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            for (sourceID, duplicate) in pairs.reversed() {
                if site.pages[index].parts.insert(duplicate, at: .after(sourceID)) {
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
    func pastePart(
        _ source: PartNode,
        on pageID: UUID,
        placement: PartPlacement
    ) -> UUID? {
        let duplicate = source.duplicated()
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var inserted = false
        mutate(actionName: "Paste Part") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            inserted = site.pages[index].parts.insert(duplicate, at: placement)
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? duplicate.id : nil
    }

    @discardableResult
    func pasteParts(
        _ sources: [PartNode],
        on pageID: UUID,
        placement: PartPlacement
    ) -> [UUID] {
        guard !sources.isEmpty else { return [] }
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return [] }
        let duplicates = sources.map { $0.duplicated() }
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var insertedIDs: [UUID] = []
        mutate(actionName: duplicates.count == 1 ? "Paste Part" : "Paste Parts") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            var nextPlacement = placement
            for duplicate in duplicates {
                guard site.pages[index].parts.insert(duplicate, at: nextPlacement) else { return }
                insertedIDs.append(duplicate.id)
                nextPlacement = .after(duplicate.id)
            }
            site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
        }
        return insertedIDs
    }

    @discardableResult
    func movePart(
        id: UUID,
        on pageID: UUID,
        to placement: PartPlacement
    ) -> Bool {
        moveParts(ids: [id], on: pageID, to: placement)
    }

    func canMoveParts(
        ids: [UUID],
        on pageID: UUID,
        to placement: PartPlacement
    ) -> Bool {
        guard !ids.isEmpty,
              let page = document.site.pages.first(where: { $0.id == pageID }),
              document.site.sharedGlobalMove(
                partIDs: ids,
                on: page,
                to: placement
              ) != nil else { return false }
        var parts = page.parts
        var nextPlacement = placement
        for id in ids {
            guard parts.moveNode(withID: id, to: nextPlacement) else { return false }
            nextPlacement = .after(id)
        }
        return true
    }

    @discardableResult
    func moveParts(
        ids: [UUID],
        on pageID: UUID,
        to placement: PartPlacement
    ) -> Bool {
        guard !ids.isEmpty,
              let page = document.site.pages.first(where: { $0.id == pageID }),
              let sharedMove = document.site.sharedGlobalMove(
                partIDs: ids,
                on: page,
                to: placement
              ) else { return false }
        var movedAll = false
        mutate(actionName: ids.count == 1 ? "Move Part" : "Move Parts") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            var parts = site.pages[index].parts
            var nextPlacement = placement
            for id in ids {
                guard parts.moveNode(withID: id, to: nextPlacement) else {
                    return
                }
                nextPlacement = .after(id)
            }
            site.pages[index].parts = parts
            site.synchronizeGlobalsAfterStructureMove(sharedMove)
            movedAll = true
        }
        return movedAll
    }

    @discardableResult
    func movePartBySiblingOffset(
        id: UUID,
        on pageID: UUID,
        offset: Int
    ) -> Bool {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let location = page.parts.location(of: id),
              let siblings = page.parts.children(of: location.parentID) else {
            return false
        }
        let targetIndex = location.index + offset
        guard siblings.indices.contains(targetIndex) else {
            return false
        }
        let targetID = siblings[targetIndex].id
        let placement: PartPlacement =
            offset < 0 ? .before(targetID) : .after(targetID)
        return movePart(id: id, on: pageID, to: placement)
    }

    @discardableResult
    func outdentPart(id: UUID, on pageID: UUID) -> Bool {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let parentID = page.parts.location(of: id)?.parentID else {
            return false
        }
        return movePart(id: id, on: pageID, to: .after(parentID))
    }
}

nonisolated struct SharedGlobalStructureMove {
    let authoritativeInstances: [UUID: UUID]
}

nonisolated extension Site {
    func sharedGlobalInsertion(
        on page: Page,
        at placement: PartPlacement
    ) -> SharedGlobalStructureMove {
        guard let parentID = page.parts.parentID(for: placement),
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
        at placements: [PartPlacement]
    ) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]
        for placement in placements {
            guard let parentID = page.parts.parentID(for: placement),
                  let context = globalStructureContext(containing: parentID),
                  !context.isOverridden else { continue }
            instancesByDefinition[context.definitionID, default: []].insert(context.instanceID)
        }
        guard instancesByDefinition.values.allSatisfy({ $0.count == 1 }) else { return nil }
        return SharedGlobalStructureMove(
            authoritativeInstances: instancesByDefinition.compactMapValues(\.first)
        )
    }

    func sharedGlobalRemoval(partIDs: [UUID]) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]
        for partID in partIDs {
            guard let context = globalStructureContext(containing: partID),
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
        partIDs: [UUID],
        on page: Page,
        to placement: PartPlacement
    ) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]

        for partID in partIDs {
            guard let context = globalStructureContext(containing: partID) else { continue }
            if !context.path.isEmpty, !context.isOverridden {
                instancesByDefinition[context.definitionID, default: []].insert(context.instanceID)
            }
        }

        if let parentID = page.parts.parentID(for: placement),
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
        var templates: [UUID: PartNode] = [:]
        for (definitionID, instanceID) in move.authoritativeInstances {
            guard let instance = part(withID: instanceID) else { continue }
            templates[definitionID] = instance.duplicatedForReusableDefinition()
        }

        for (definitionID, template) in templates {
            globalPartLibrary.mutateDefinition(id: definitionID) { $0.root = template }
        }

        for (definitionID, template) in templates {
            let authoritativeInstanceID = move.authoritativeInstances[definitionID]
            for pageIndex in pages.indices {
                pages[pageIndex].parts.replaceReusableInstances(
                    definitionID: definitionID,
                    with: template,
                    excludingInstanceID: authoritativeInstanceID
                )
            }
        }
    }
}

nonisolated extension Array where Element == PartNode {
    func children(of parentID: UUID?) -> [PartNode]? {
        guard let parentID else {
            return self
        }
        return node(withID: parentID)?.children
    }

    func parentID(for placement: PartPlacement) -> UUID? {
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
