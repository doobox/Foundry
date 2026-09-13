import Foundation

@MainActor
extension ProjectEditor {
    @discardableResult
    func saveGlobalBlock(blockID: UUID, name: String) -> UUID? {
        guard let source = document.site.block(withID: blockID) else { return nil }
        let definition = ReusableBlockDefinition(name: name, root: source.duplicatedForReusableDefinition())
        mutate(actionName: "Create Global Block") { site in
            site.globalBlocks.append(definition)
            site.updateBlock(id: blockID) { $0.reusableDefinitionID = definition.id }
        }
        return definition.id
    }

    @discardableResult
    func saveGlobalBlocks(blockIDs: [UUID]) -> [UUID] {
        let sources = blockIDs.compactMap { id in
            document.site.block(withID: id).map { (id, $0) }
        }
        guard !sources.isEmpty else { return [] }
        let definitions = sources.map { source in
            ReusableBlockDefinition(
                name: source.1.name,
                root: source.1.duplicatedForReusableDefinition()
            )
        }
        mutate(actionName: definitions.count == 1 ? "Create Global Block" : "Create Global Blocks") { site in
            site.globalBlocks.append(contentsOf: definitions)
            for (index, source) in sources.enumerated() {
                site.updateBlock(id: source.0) {
                    $0.reusableDefinitionID = definitions[index].id
                }
            }
        }
        return definitions.map(\.id)
    }

    @discardableResult
    func insertGlobalBlock(definitionID: UUID, on pageID: UUID, placement: BlockPlacement) -> UUID? {
        guard let definition = document.site.globalBlocks.first(where: { $0.id == definitionID }) else { return nil }
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let instance = definition.root.duplicatedAsReusableInstance(of: definitionID)
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

    func renameGlobalBlock(definitionID: UUID, name: String) {
        mutate(actionName: "Rename Global Block") { site in
            guard let index = site.globalBlocks.firstIndex(where: { $0.id == definitionID }) else { return }
            site.globalBlocks[index].name = name
            site.globalBlocks[index].root.name = name
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].blocks.renameGlobalInstances(
                    definitionID: definitionID,
                    name: name
                )
            }
        }
    }

    func removeGlobalBlock(definitionID: UUID) {
        mutate(actionName: "Delete Global Block") { site in
            site.globalBlocks.removeAll(where: { $0.id == definitionID })
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].blocks.detachGlobalInstances(definitionID: definitionID)
            }
        }
    }
}

nonisolated private extension Array where Element == BlockNode {
    mutating func renameGlobalInstances(definitionID: UUID, name: String) {
        for index in indices {
            if self[index].reusableDefinitionID == definitionID {
                self[index].name = name
            }
            self[index].children.renameGlobalInstances(definitionID: definitionID, name: name)
        }
    }

    mutating func detachGlobalInstances(definitionID: UUID) {
        for index in indices {
            if self[index].reusableDefinitionID == definitionID {
                self[index].reusableDefinitionID = nil
            }
            self[index].children.detachGlobalInstances(definitionID: definitionID)
        }
    }
}
