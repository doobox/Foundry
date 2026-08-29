import Foundation

@MainActor
extension ProjectEditor {
    @discardableResult
    func insertComponent(
        type: ComponentType,
        on pageID: UUID,
        placement: ComponentPlacement
    ) -> UUID? {
        let component = ComponentNode.make(type)
        var inserted = false
        mutate(actionName: "Add \(type.displayName)") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            inserted = site.pages[index].components.insert(component, at: placement)
            if inserted, let packageLock = component.packageLock,
               !site.componentPackages.contains(packageLock) {
                site.componentPackages.append(packageLock)
                site.componentPackages.sort { $0.identifier < $1.identifier }
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
        mutate(actionName: "Duplicate Component") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            site.pages[index].components.insert(duplicate, at: .after(id))
        }
        return duplicate.id
    }

    @discardableResult
    func pasteComponent(
        _ source: ComponentNode,
        on pageID: UUID,
        placement: ComponentPlacement
    ) -> UUID? {
        let duplicate = source.duplicated()
        var inserted = false
        mutate(actionName: "Paste Component") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            inserted = site.pages[index].components.insert(duplicate, at: placement)
        }
        return inserted ? duplicate.id : nil
    }

    @discardableResult
    func moveComponent(
        id: UUID,
        on pageID: UUID,
        to placement: ComponentPlacement
    ) -> Bool {
        var moved = false
        mutate(actionName: "Move Component") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            moved = site.pages[index].components.moveNode(withID: id, to: placement)
        }
        return moved
    }

    @discardableResult
    func moveComponents(
        ids: [UUID],
        on pageID: UUID,
        to placement: ComponentPlacement
    ) -> Bool {
        guard !ids.isEmpty else { return false }
        var movedAll = false
        mutate(actionName: ids.count == 1 ? "Move Component" : "Move Components") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            var nextPlacement = placement
            for id in ids {
                guard site.pages[index].components.moveNode(withID: id, to: nextPlacement) else {
                    return
                }
                movedAll = true
                nextPlacement = .after(id)
            }
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

nonisolated extension Array where Element == ComponentNode {
    func children(of parentID: UUID?) -> [ComponentNode]? {
        guard let parentID else {
            return self
        }
        return node(withID: parentID)?.children
    }
}
