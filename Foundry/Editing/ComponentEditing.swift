import Foundation

@MainActor
extension ProjectEditor {
    @discardableResult
    func insertComponent(
        type: ComponentType,
        on pageID: UUID,
        placement: ComponentPlacement
    ) -> UUID? {
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let component = ComponentNode.make(type)
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var inserted = false
        mutate(actionName: "Add \(type.displayName)") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            inserted = site.pages[index].components.insert(component, at: placement)
            if inserted, let packageLock = component.packageLock,
               !site.componentPackages.contains(packageLock) {
                site.componentPackages.append(packageLock)
                site.componentPackages.sort { $0.identifier < $1.identifier }
            }
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? component.id : nil
    }

    @discardableResult
    func duplicateComponent(id: UUID, on pageID: UUID) -> UUID? {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let source = page.components.node(withID: id) else {
            return nil
        }
        let duplicate = source.duplicated()
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: .after(id))
        mutate(actionName: "Duplicate Component") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            site.pages[index].components.insert(duplicate, at: .after(id))
            site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
        }
        return duplicate.id
    }

    @discardableResult
    func duplicateComponents(ids: [UUID], on pageID: UUID) -> [UUID] {
        guard !ids.isEmpty,
              let page = document.site.pages.first(where: { $0.id == pageID }) else { return [] }
        let pairs = ids.compactMap { id in
            page.components.node(withID: id).map { (id, $0.duplicated()) }
        }
        guard !pairs.isEmpty else { return [] }
        guard let sharedInsertion = document.site.sharedGlobalInsertions(
            on: page,
            at: pairs.map { .after($0.0) }
        ) else { return [] }
        mutate(actionName: pairs.count == 1 ? "Duplicate Component" : "Duplicate Components") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            for (sourceID, duplicate) in pairs.reversed() {
                site.pages[index].components.insert(duplicate, at: .after(sourceID))
            }
            site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
        }
        return pairs.map { $0.1.id }
    }

    @discardableResult
    func pasteComponent(
        _ source: ComponentNode,
        on pageID: UUID,
        placement: ComponentPlacement
    ) -> UUID? {
        let duplicate = source.duplicated()
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var inserted = false
        mutate(actionName: "Paste Component") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            inserted = site.pages[index].components.insert(duplicate, at: placement)
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? duplicate.id : nil
    }

    @discardableResult
    func pasteComponents(
        _ sources: [ComponentNode],
        on pageID: UUID,
        placement: ComponentPlacement
    ) -> [UUID] {
        guard !sources.isEmpty else { return [] }
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return [] }
        let duplicates = sources.map { $0.duplicated() }
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var insertedIDs: [UUID] = []
        mutate(actionName: duplicates.count == 1 ? "Paste Component" : "Paste Components") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            var nextPlacement = placement
            for duplicate in duplicates {
                guard site.pages[index].components.insert(duplicate, at: nextPlacement) else { return }
                insertedIDs.append(duplicate.id)
                nextPlacement = .after(duplicate.id)
            }
            site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
        }
        return insertedIDs
    }

    @discardableResult
    func moveComponent(
        id: UUID,
        on pageID: UUID,
        to placement: ComponentPlacement
    ) -> Bool {
        moveComponents(ids: [id], on: pageID, to: placement)
    }

    @discardableResult
    func moveComponents(
        ids: [UUID],
        on pageID: UUID,
        to placement: ComponentPlacement
    ) -> Bool {
        guard !ids.isEmpty,
              let page = document.site.pages.first(where: { $0.id == pageID }),
              let sharedMove = document.site.sharedGlobalMove(
                componentIDs: ids,
                on: page,
                to: placement
              ) else { return false }
        var movedAll = false
        mutate(actionName: ids.count == 1 ? "Move Component" : "Move Components") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            var components = site.pages[index].components
            var nextPlacement = placement
            for id in ids {
                guard components.moveNode(withID: id, to: nextPlacement) else {
                    return
                }
                nextPlacement = .after(id)
            }
            site.pages[index].components = components
            site.synchronizeGlobalsAfterStructureMove(sharedMove)
            movedAll = true
        }
        return movedAll
    }

    @discardableResult
    func moveComponentBySiblingOffset(
        id: UUID,
        on pageID: UUID,
        offset: Int
    ) -> Bool {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let location = page.components.location(of: id),
              let siblings = page.components.children(of: location.parentID) else {
            return false
        }
        let targetIndex = location.index + offset
        guard siblings.indices.contains(targetIndex) else {
            return false
        }
        let targetID = siblings[targetIndex].id
        let placement: ComponentPlacement =
            offset < 0 ? .before(targetID) : .after(targetID)
        return moveComponent(id: id, on: pageID, to: placement)
    }

    @discardableResult
    func outdentComponent(id: UUID, on pageID: UUID) -> Bool {
        guard let page = document.site.pages.first(where: { $0.id == pageID }),
              let parentID = page.components.location(of: id)?.parentID else {
            return false
        }
        return moveComponent(id: id, on: pageID, to: .after(parentID))
    }
}

nonisolated struct SharedGlobalStructureMove {
    let authoritativeInstances: [UUID: UUID]
}

nonisolated extension Site {
    func sharedGlobalInsertion(
        on page: Page,
        at placement: ComponentPlacement
    ) -> SharedGlobalStructureMove {
        guard let parentID = page.components.parentID(for: placement),
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
        at placements: [ComponentPlacement]
    ) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]
        for placement in placements {
            guard let parentID = page.components.parentID(for: placement),
                  let context = globalStructureContext(containing: parentID),
                  !context.isOverridden else { continue }
            instancesByDefinition[context.definitionID, default: []].insert(context.instanceID)
        }
        guard instancesByDefinition.values.allSatisfy({ $0.count == 1 }) else { return nil }
        return SharedGlobalStructureMove(
            authoritativeInstances: instancesByDefinition.compactMapValues(\.first)
        )
    }

    func sharedGlobalRemoval(componentIDs: [UUID]) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]
        for componentID in componentIDs {
            guard let context = globalStructureContext(containing: componentID),
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
        componentIDs: [UUID],
        on page: Page,
        to placement: ComponentPlacement
    ) -> SharedGlobalStructureMove? {
        var instancesByDefinition: [UUID: Set<UUID>] = [:]

        for componentID in componentIDs {
            guard let context = globalStructureContext(containing: componentID) else { continue }
            if !context.path.isEmpty, !context.isOverridden {
                instancesByDefinition[context.definitionID, default: []].insert(context.instanceID)
            }
        }

        if let parentID = page.components.parentID(for: placement),
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
        var templates: [UUID: ComponentNode] = [:]
        for (definitionID, instanceID) in move.authoritativeInstances {
            guard let instance = component(withID: instanceID) else { continue }
            templates[definitionID] = instance.duplicatedForReusableDefinition()
        }

        for (definitionID, template) in templates {
            guard let index = globalComponents.firstIndex(where: { $0.id == definitionID }) else { continue }
            globalComponents[index].root = template
        }

        for (definitionID, template) in templates {
            let authoritativeInstanceID = move.authoritativeInstances[definitionID]
            for pageIndex in pages.indices {
                pages[pageIndex].components.replaceReusableInstances(
                    definitionID: definitionID,
                    with: template,
                    excludingInstanceID: authoritativeInstanceID
                )
            }
        }
    }
}

nonisolated extension Array where Element == ComponentNode {
    func children(of parentID: UUID?) -> [ComponentNode]? {
        guard let parentID else {
            return self
        }
        return node(withID: parentID)?.children
    }

    func parentID(for placement: ComponentPlacement) -> UUID? {
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
