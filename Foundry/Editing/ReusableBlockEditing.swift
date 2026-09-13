import Foundation

@MainActor
extension ProjectEditor {
    func renameReusableBlock(definitionID: UUID, name: String) {
        mutate(actionName: "Rename Reusable Block") { site in
            guard let index = site.reusableBlocks.firstIndex(where: { $0.id == definitionID }) else { return }
            site.reusableBlocks[index].name = name
        }
    }

    func removeReusableBlock(definitionID: UUID) {
        mutate(actionName: "Delete Reusable Block") { site in
            guard site.reusableBlocks.contains(where: { $0.id == definitionID }) else { return }
            site.reusableBlocks.removeAll(where: { $0.id == definitionID })
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].blocks.detachReusableInstances(definitionID: definitionID)
            }
        }
    }

    func renameSharedReusableBlockInstance(blockID: UUID, name: String) {
        editSharedReusableBlock(blockID: blockID, actionName: "Edit Shared Block") {
            $0.name = name
        }
    }

    func setSharedReusableProperty(
        blockID: UUID,
        key: BlockProperty.Key,
        value: BlockProperty.Value
    ) {
        editSharedReusableBlock(blockID: blockID, actionName: "Edit Shared Block") {
            $0.setProperty(key, value: value)
        }
    }

    func setSharedReusableResponsiveProperty(
        blockID: UUID,
        key: BlockProperty.Key,
        value: BlockProperty.Value,
        breakpoint: ResponsiveBreakpoint
    ) {
        editSharedReusableBlock(blockID: blockID, actionName: "Edit Responsive Global") {
            $0.setResponsiveProperty(key, value: value, at: breakpoint)
        }
    }

    func removeSharedReusableResponsiveOverride(
        blockID: UUID,
        key: BlockProperty.Key,
        breakpoint: ResponsiveBreakpoint
    ) {
        editSharedReusableBlock(blockID: blockID, actionName: "Reset Responsive Global") {
            $0.removeResponsiveOverride(key, at: breakpoint)
        }
    }

    func setGlobalBlockLinked(blockID: UUID, isLinked: Bool) {
        guard let context = document.site.globalBlockContext(containing: blockID) else { return }
        let targetID = isLinked ? (context.overrideOwnerID ?? blockID) : blockID
        mutate(actionName: isLinked ? "Relink Global Block" : "Override Global Block") { site in
            site.updateBlock(id: targetID) { $0.overridesGlobalDefinition = !isLinked }
            guard isLinked,
                  let index = site.globalBlocks.firstIndex(where: { $0.id == context.definitionID }) else { return }
            let template = site.globalBlocks[index].root
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].blocks.replaceReusableInstances(
                    definitionID: context.definitionID,
                    with: template
                )
            }
        }
    }

    @discardableResult
    func saveReusableBlock(blockID: UUID, name: String) -> UUID? {
        guard let source = document.site.block(withID: blockID) else { return nil }
        let definition = ReusableBlockDefinition(
            name: name,
            root: source.duplicatedForReusableDefinition()
        )
        mutate(actionName: "Create Reusable Block") { site in
            site.reusableBlocks.append(definition)
        }
        return definition.id
    }

    @discardableResult
    func insertReusableBlock(
        definitionID: UUID,
        on pageID: UUID,
        placement: BlockPlacement
    ) -> UUID? {
        guard let definition = document.site.reusableBlocks.first(where: { $0.id == definitionID }) else {
            return nil
        }
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let instance = definition.root.duplicatedForReusableDefinition()
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var inserted = false
        mutate(actionName: "Add \(definition.name)") { site in
            guard let pageIndex = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            inserted = site.pages[pageIndex].blocks.insert(instance, at: placement)
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? instance.id : nil
    }

    @discardableResult
    func updateReusableBlock(from blockID: UUID) -> Bool {
        guard let source = document.site.block(withID: blockID),
              let definitionID = source.reusableDefinitionID,
              document.site.globalBlocks.contains(where: { $0.id == definitionID }) else {
            return false
        }
        let template = source.duplicatedForReusableDefinition()
        mutate(actionName: "Update Reusable Block") { site in
            guard let index = site.globalBlocks.firstIndex(where: { $0.id == definitionID }) else { return }
            site.globalBlocks[index].root = template
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].blocks.replaceReusableInstances(
                    definitionID: definitionID,
                    with: template
                )
            }
        }
        return true
    }

    func detachReusableBlock(blockID: UUID) {
        mutate(actionName: "Detach Reusable Block") { site in
            site.updateBlock(id: blockID) { $0.reusableDefinitionID = nil }
        }
    }

    func editSharedReusableBlock(
        blockID: UUID,
        actionName: String,
        mutation: (inout BlockNode) -> Void
    ) {
        guard let context = document.site.globalBlockContext(containing: blockID) else { return }
        mutate(actionName: actionName) { site in
            guard let index = site.globalBlocks.firstIndex(where: { $0.id == context.definitionID }) else { return }
            site.globalBlocks[index].root.mutateNode(at: context.path, mutation: mutation)
            let template = site.globalBlocks[index].root
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].blocks.replaceReusableInstances(
                    definitionID: context.definitionID,
                    with: template
                )
            }
        }
    }
}

nonisolated extension Site {
    func globalBlockContext(containing blockID: UUID) -> (definitionID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        guard let context = globalStructureContext(containing: blockID) else { return nil }
        return (context.definitionID, context.path, context.isOverridden, context.overrideOwnerID)
    }

    func globalStructureContext(containing blockID: UUID) -> (definitionID: UUID, instanceID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        for page in pages {
            for block in page.blocks {
                if let context = block.globalBlockContext(containing: blockID) {
                    return context
                }
            }
        }
        return nil
    }
}

nonisolated private extension BlockNode {
    func globalBlockContext(containing blockID: UUID) -> (definitionID: UUID, instanceID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        if let definitionID = reusableDefinitionID,
           let path = path(to: blockID) {
            let overrideOwnerID = overrideOwnerID(at: path)
            return (definitionID, id, path, overrideOwnerID != nil, overrideOwnerID)
        }
        for child in children {
            if let context = child.globalBlockContext(containing: blockID) {
                return context
            }
        }
        return nil
    }

    func isOverridden(at path: [Int]) -> Bool {
        if overridesGlobalDefinition == true { return true }
        guard let index = path.first, children.indices.contains(index) else { return false }
        return children[index].isOverridden(at: Array(path.dropFirst()))
    }

    func overrideOwnerID(at path: [Int]) -> UUID? {
        if overridesGlobalDefinition == true { return id }
        guard let index = path.first, children.indices.contains(index) else { return nil }
        return children[index].overrideOwnerID(at: Array(path.dropFirst()))
    }

    func path(to blockID: UUID) -> [Int]? {
        if id == blockID { return [] }
        for (index, child) in children.enumerated() {
            if let childPath = child.path(to: blockID) {
                return [index] + childPath
            }
        }
        return nil
    }

    mutating func mutateNode(at path: [Int], mutation: (inout BlockNode) -> Void) {
        guard let index = path.first else {
            mutation(&self)
            return
        }
        guard children.indices.contains(index) else { return }
        children[index].mutateNode(at: Array(path.dropFirst()), mutation: mutation)
    }
}

nonisolated extension Array where Element == BlockNode {
    mutating func detachReusableInstances(definitionID: UUID) {
        for index in indices {
            if self[index].reusableDefinitionID == definitionID {
                self[index].reusableDefinitionID = nil
            }
            self[index].children.detachReusableInstances(definitionID: definitionID)
        }
    }

    mutating func replaceReusableInstances(
        definitionID: UUID,
        with template: BlockNode,
        excludingInstanceID: UUID? = nil
    ) {
        for index in indices {
            if self[index].reusableDefinitionID == definitionID {
                if self[index].id != excludingInstanceID {
                    self[index] = template.duplicatedAsReusableInstance(
                        of: definitionID,
                        preservingIDsFrom: self[index]
                    )
                }
            } else {
                self[index].children.replaceReusableInstances(
                    definitionID: definitionID,
                    with: template,
                    excludingInstanceID: excludingInstanceID
                )
            }
        }
    }
}
