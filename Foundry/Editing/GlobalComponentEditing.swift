import Foundation

@MainActor
extension ProjectEditor {
    @discardableResult
    func saveGlobalComponent(componentID: UUID, name: String) -> UUID? {
        guard let source = document.site.component(withID: componentID) else { return nil }
        let definition = ReusableComponentDefinition(name: name, root: source.duplicatedForReusableDefinition())
        mutate(actionName: "Create Global Component") { site in
            site.globalComponents.append(definition)
            site.updateComponent(id: componentID) { $0.reusableDefinitionID = definition.id }
        }
        return definition.id
    }

    @discardableResult
    func saveGlobalComponents(componentIDs: [UUID]) -> [UUID] {
        let sources = componentIDs.compactMap { id in
            document.site.component(withID: id).map { (id, $0) }
        }
        guard !sources.isEmpty else { return [] }
        let definitions = sources.map { source in
            ReusableComponentDefinition(
                name: source.1.name,
                root: source.1.duplicatedForReusableDefinition()
            )
        }
        mutate(actionName: definitions.count == 1 ? "Create Global Component" : "Create Global Components") { site in
            site.globalComponents.append(contentsOf: definitions)
            for (index, source) in sources.enumerated() {
                site.updateComponent(id: source.0) {
                    $0.reusableDefinitionID = definitions[index].id
                }
            }
        }
        return definitions.map(\.id)
    }

    @discardableResult
    func insertGlobalComponent(definitionID: UUID, on pageID: UUID, placement: ComponentPlacement) -> UUID? {
        guard let definition = document.site.globalComponents.first(where: { $0.id == definitionID }) else { return nil }
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let instance = definition.root.duplicatedAsReusableInstance(of: definitionID)
        let sharedInsertion = document.site.sharedGlobalInsertion(on: page, at: placement)
        var inserted = false
        mutate(actionName: "Add \(definition.name)") { site in
            guard let pageIndex = site.pages.firstIndex(where: { $0.id == pageID }) else { return }
            inserted = site.pages[pageIndex].components.insert(instance, at: placement)
            if inserted {
                site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
            }
        }
        return inserted ? instance.id : nil
    }

    func renameGlobalComponent(definitionID: UUID, name: String) {
        mutate(actionName: "Rename Global Component") { site in
            guard let index = site.globalComponents.firstIndex(where: { $0.id == definitionID }) else { return }
            site.globalComponents[index].name = name
        }
    }

    func removeGlobalComponent(definitionID: UUID) {
        mutate(actionName: "Delete Global Component") { site in
            site.globalComponents.removeAll(where: { $0.id == definitionID })
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].components.detachGlobalInstances(definitionID: definitionID)
            }
        }
    }
}

nonisolated private extension Array where Element == ComponentNode {
    mutating func detachGlobalInstances(definitionID: UUID) {
        for index in indices {
            if self[index].reusableDefinitionID == definitionID {
                self[index].reusableDefinitionID = nil
            }
            self[index].children.detachGlobalInstances(definitionID: definitionID)
        }
    }
}
