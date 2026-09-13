import Foundation

@MainActor
extension ProjectEditor {
    @discardableResult
    func saveGlobalPart(partID: UUID, name: String) -> UUID? {
        guard let source = document.site.part(withID: partID) else { return nil }
        let definition = ReusablePartDefinition(name: name, root: source.duplicatedForReusableDefinition())
        mutate(actionName: "Create Global Part") { site in
            site.globalParts.append(definition)
            site.updatePart(id: partID) { $0.reusableDefinitionID = definition.id }
        }
        return definition.id
    }

    @discardableResult
    func saveGlobalParts(partIDs: [UUID]) -> [UUID] {
        let sources = partIDs.compactMap { id in
            document.site.part(withID: id).map { (id, $0) }
        }
        guard !sources.isEmpty else { return [] }
        let definitions = sources.map { source in
            ReusablePartDefinition(
                name: source.1.name,
                root: source.1.duplicatedForReusableDefinition()
            )
        }
        mutate(actionName: definitions.count == 1 ? "Create Global Part" : "Create Global Parts") { site in
            site.globalParts.append(contentsOf: definitions)
            for (index, source) in sources.enumerated() {
                site.updatePart(id: source.0) {
                    $0.reusableDefinitionID = definitions[index].id
                }
            }
        }
        return definitions.map(\.id)
    }

    @discardableResult
    func insertGlobalPart(definitionID: UUID, on pageID: UUID, placement: PartPlacement) -> UUID? {
        guard let definition = document.site.globalParts.first(where: { $0.id == definitionID }) else { return nil }
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let instance = definition.root.duplicatedAsReusableInstance(of: definitionID)
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var inserted = false
        mutate(actionName: "Add \(definition.name)") { site in
            guard let pageIndex = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            inserted = site.pages[pageIndex].parts.insert(instance, at: placement)
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? instance.id : nil
    }

    func renameGlobalPart(definitionID: UUID, name: String) {
        mutate(actionName: "Rename Global Part") { site in
            guard let index = site.globalParts.firstIndex(where: { $0.id == definitionID }) else { return }
            site.globalParts[index].name = name
            site.globalParts[index].root.name = name
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].parts.renameGlobalInstances(
                    definitionID: definitionID,
                    name: name
                )
            }
        }
    }

    func removeGlobalPart(definitionID: UUID) {
        mutate(actionName: "Delete Global Part") { site in
            site.globalParts.removeAll(where: { $0.id == definitionID })
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].parts.detachGlobalInstances(definitionID: definitionID)
            }
        }
    }
}

nonisolated private extension Array where Element == PartNode {
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
