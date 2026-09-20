import Foundation

@MainActor
extension ProjectEditor {
    @discardableResult
    func saveGlobalPart(partID: UUID, name: String) -> UUID? {
        guard let source = document.site.part(withID: partID) else { return nil }
        let definition = ReusablePartDefinition(name: name, root: source.duplicatedForReusableDefinition())
        mutate(actionName: "Create Global Part") { site in
            site.globalPartLibrary.append(.part(definition))
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
            site.globalPartLibrary.append(contentsOf: definitions.map(ReusablePartNode.part))
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
            let renamed = site.globalPartLibrary.mutateDefinition(id: definitionID) {
                $0.name = name
                $0.root.name = name
            }
            guard renamed else { return }
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
            site.globalPartLibrary.removeNode(id: definitionID)
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].parts.detachGlobalInstances(definitionID: definitionID)
            }
        }
    }

    /// Adds an independent copy of the definition beside the original — new
    /// identity throughout, so instances of the original stay untouched.
    @discardableResult
    func duplicateGlobalPart(definitionID: UUID) -> UUID? {
        guard case .part(let definition)? = document.site.globalPartLibrary.node(withID: definitionID) else {
            return nil
        }
        let copy = ReusablePartDefinition(
            name: definition.name + " Copy",
            root: definition.root.duplicatedForReusableDefinition()
        )
        var duplicated = false
        mutate(actionName: "Duplicate Global Part") { site in
            duplicated = site.globalPartLibrary.insert(.part(copy), at: .after(nodeID: definitionID))
        }
        return duplicated ? copy.id : nil
    }

    // MARK: Folders and ordering

    @discardableResult
    func createGlobalPartFolder(named name: String, at placement: ReusablePartPlacement = .end) -> UUID? {
        let folder = ReusablePartFolder(name: name)
        var created = false
        mutate(actionName: "New Folder") { site in
            created = site.globalPartLibrary.insert(.folder(folder), at: placement)
        }
        return created ? folder.id : nil
    }

    func renameGlobalPartFolder(id: UUID, to name: String) {
        mutate(actionName: "Rename Folder") { site in
            _ = site.globalPartLibrary.renameFolder(id: id, to: name)
        }
    }

    /// Deletes a folder and every global part inside it; instances on pages
    /// detach and keep their content.
    func deleteGlobalPartFolder(id: UUID) {
        guard case .folder(let folder)? = document.site.globalPartLibrary.node(withID: id) else { return }
        let definitionIDs = folder.children.allDefinitions.map(\.id)
        mutate(actionName: "Delete Folder") { site in
            site.globalPartLibrary.removeNode(id: id)
            for definitionID in definitionIDs {
                for pageIndex in site.pages.indices {
                    site.pages[pageIndex].parts.detachGlobalInstances(definitionID: definitionID)
                }
            }
        }
    }

    @discardableResult
    func moveGlobalPartNode(id: UUID, to placement: ReusablePartPlacement) -> Bool {
        var moved = document.site.globalPartLibrary
        guard moved.move(id: id, to: placement) else { return false }
        mutate(actionName: "Move") { site in
            site.globalPartLibrary = moved
        }
        return true
    }
}

nonisolated extension Array where Element == PartNode {
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
