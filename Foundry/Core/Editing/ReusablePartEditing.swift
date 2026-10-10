import Foundation

@MainActor
extension ProjectEditor {
    /// Resets a section in one transaction, including linked global definitions.
    func resetInspectorSection(ids: [UUID], section: PartPropertySection, editsSharedDefinition: Bool = false) {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return }
        mutate(actionName: "Reset \(section.rawValue) Section") { site in
            let theme = site.theme
            for id in ids {
                guard let part = site.part(withID: id) else { continue }
                let state = PartInspectorSectionState(part: part, section: section, theme: theme)
                if let context = site.globalPartContext(containing: id), editsSharedDefinition || !context.isOverridden {
                    var updatedRoot: PartNode?
                    site.globalPartLibrary.mutateDefinition(id: context.definitionID) {
                        $0.root.mutateNode(at: context.path) { state.reset(&$0) }
                        updatedRoot = $0.root
                    }
                    guard let template = updatedRoot else { continue }
                    for pageIndex in site.pages.indices {
                        site.pages[pageIndex].parts.replaceReusableInstances(definitionID: context.definitionID, with: template)
                    }
                } else {
                    site.updatePart(id: id) { state.reset(&$0) }
                }
            }
        }
    }

    /// Stamps a template onto the page: an independent copy with fresh tree
    /// identity, exactly like inserting parts by hand. The definition arrives
    /// already resolved (library entry with assets imported into this project).
    @discardableResult
    func insertTemplate(
        _ definition: ReusablePartDefinition,
        on pageID: UUID,
        placement: PartPlacement
    ) -> UUID? {
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let instance = definition.root.duplicatedForReusableDefinition()
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

    func renameSharedReusablePartInstance(partID: UUID, name: String) {
        editSharedReusablePart(partID: partID, actionName: "Edit Shared Part") {
            $0.name = name
        }
    }

    func setSharedReusableProperty(
        partID: UUID,
        key: PartProperty.Key,
        value: PartProperty.Value
    ) {
        editSharedReusablePart(partID: partID, actionName: "Edit Shared Part") {
            $0.setProperty(key, value: value)
        }
    }

    func setSharedReusableResponsiveProperty(
        partID: UUID,
        key: PartProperty.Key,
        value: PartProperty.Value,
        breakpoint: ResponsiveBreakpoint
    ) {
        editSharedReusablePart(partID: partID, actionName: "Edit Responsive Global") {
            $0.setResponsiveProperty(key, value: value, at: breakpoint)
        }
    }

    func removeSharedReusableResponsiveOverride(
        partID: UUID,
        key: PartProperty.Key,
        breakpoint: ResponsiveBreakpoint
    ) {
        editSharedReusablePart(partID: partID, actionName: "Reset Responsive Global") {
            $0.removeResponsiveOverride(key, at: breakpoint)
        }
    }

    func setGlobalPartLinked(partID: UUID, isLinked: Bool) {
        guard let context = document.site.globalPartContext(containing: partID) else { return }
        let targetID = isLinked ? (context.overrideOwnerID ?? partID) : partID
        mutate(actionName: isLinked ? "Pin to Global" : "Unpin from Global") { site in
            site.updatePart(id: targetID) { $0.overridesGlobalDefinition = !isLinked }
            guard isLinked,
                  case .part(let definition)? = site.globalPartLibrary.node(withID: context.definitionID) else { return }
            let template = definition.root
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].parts.replaceReusableInstances(
                    definitionID: context.definitionID,
                    with: template
                )
            }
        }
    }

    /// Builds a template definition from a part on the page, ready to save to
    /// the shared library. Pure read — the project itself stores nothing.
    func templateDefinition(fromPartID partID: UUID, name: String) -> ReusablePartDefinition? {
        guard let source = document.site.part(withID: partID) else { return nil }
        return ReusablePartDefinition(
            name: name,
            root: source.duplicatedForReusableDefinition()
        )
    }

    // MARK: Project templates

    /// Adds a definition to this project's own template library — the
    /// Templates panel's Project section. Unlike pack templates the project
    /// stores the definition itself, so the save is undoable.
    @discardableResult
    func addProjectTemplate(_ definition: ReusablePartDefinition, at placement: ReusablePartPlacement = .end) -> Bool {
        var added = false
        mutate(actionName: "Save Template") { site in
            added = site.projectTemplateLibrary.insert(.part(definition), at: placement)
        }
        return added
    }

    /// Adds a whole node — a template or a folder tree arriving from a pack —
    /// to the project's template library.
    @discardableResult
    func addProjectTemplateNode(_ node: ReusablePartNode, at placement: ReusablePartPlacement = .end) -> Bool {
        var added = false
        mutate(actionName: "Move Templates") { site in
            added = site.projectTemplateLibrary.insert(node, at: placement)
        }
        return added
    }

    func renameProjectTemplate(id: UUID, to name: String) {
        mutate(actionName: "Rename Template") { site in
            _ = site.projectTemplateLibrary.mutateDefinition(id: id) { $0.name = name }
        }
    }

    func removeProjectTemplate(id: UUID) {
        mutate(actionName: "Delete Template") { site in
            site.projectTemplateLibrary.removeNode(id: id)
        }
    }

    @discardableResult
    func duplicateProjectTemplate(id: UUID) -> UUID? {
        guard case .part(let definition)? = document.site.projectTemplateLibrary.node(withID: id) else {
            return nil
        }
        let copy = ReusablePartDefinition(
            name: definition.name + " Copy",
            root: definition.root.duplicatedForReusableDefinition()
        )
        var duplicated = false
        mutate(actionName: "Duplicate Template") { site in
            duplicated = site.projectTemplateLibrary.insert(.part(copy), at: .after(nodeID: id))
        }
        return duplicated ? copy.id : nil
    }

    @discardableResult
    func createProjectTemplateFolder(named name: String, at placement: ReusablePartPlacement = .end) -> UUID? {
        let folder = ReusablePartFolder(name: name)
        var created = false
        mutate(actionName: "New Folder") { site in
            created = site.projectTemplateLibrary.insert(.folder(folder), at: placement)
        }
        return created ? folder.id : nil
    }

    func renameProjectTemplateFolder(id: UUID, to name: String) {
        mutate(actionName: "Rename Folder") { site in
            _ = site.projectTemplateLibrary.renameFolder(id: id, to: name)
        }
    }

    func deleteProjectTemplateFolder(id: UUID) {
        mutate(actionName: "Delete Folder") { site in
            site.projectTemplateLibrary.removeNode(id: id)
        }
    }

    @discardableResult
    func moveProjectTemplateNode(id: UUID, to placement: ReusablePartPlacement) -> Bool {
        var moved = document.site.projectTemplateLibrary
        guard moved.move(id: id, to: placement) else { return false }
        mutate(actionName: "Move") { site in
            site.projectTemplateLibrary = moved
        }
        return true
    }

    @discardableResult
    func updateReusablePart(from partID: UUID) -> Bool {
        guard let source = document.site.part(withID: partID),
              let definitionID = source.reusableDefinitionID,
              document.site.globalParts.contains(where: { $0.id == definitionID }) else {
            return false
        }
        let template = source.duplicatedForReusableDefinition()
        mutate(actionName: "Update Global Part") { site in
            guard site.globalPartLibrary.mutateDefinition(id: definitionID, mutation: { $0.root = template }) else { return }
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].parts.replaceReusableInstances(
                    definitionID: definitionID,
                    with: template
                )
            }
        }
        return true
    }

    func detachReusablePart(partID: UUID) {
        mutate(actionName: "Detach Template") { site in
            site.updatePart(id: partID) { $0.reusableDefinitionID = nil }
        }
    }

    func editSharedReusablePart(
        partID: UUID,
        actionName: String,
        mutation: (inout PartNode) -> Void
    ) {
        guard let context = document.site.globalPartContext(containing: partID) else { return }
        mutate(actionName: actionName) { site in
            var updatedRoot: PartNode?
            site.globalPartLibrary.mutateDefinition(id: context.definitionID) {
                $0.root.mutateNode(at: context.path, mutation: mutation)
                updatedRoot = $0.root
            }
            guard let template = updatedRoot else { return }
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].parts.replaceReusableInstances(
                    definitionID: context.definitionID,
                    with: template
                )
            }
        }
    }
}

nonisolated extension Site {
    func globalPartContext(containing partID: UUID) -> (definitionID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        guard let context = globalStructureContext(containing: partID) else { return nil }
        return (context.definitionID, context.path, context.isOverridden, context.overrideOwnerID)
    }

    func globalStructureContext(containing partID: UUID) -> (definitionID: UUID, instanceID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        for page in pages {
            for part in page.parts {
                if let context = part.globalPartContext(containing: partID) {
                    return context
                }
            }
        }
        return nil
    }
}

nonisolated private extension PartNode {
    func globalPartContext(containing partID: UUID) -> (definitionID: UUID, instanceID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        if let definitionID = reusableDefinitionID,
           let path = path(to: partID) {
            let overrideOwnerID = overrideOwnerID(at: path)
            return (definitionID, id, path, overrideOwnerID != nil, overrideOwnerID)
        }
        for child in children {
            if let context = child.globalPartContext(containing: partID) {
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

    func path(to partID: UUID) -> [Int]? {
        if id == partID { return [] }
        for (index, child) in children.enumerated() {
            if let childPath = child.path(to: partID) {
                return [index] + childPath
            }
        }
        return nil
    }

    mutating func mutateNode(at path: [Int], mutation: (inout PartNode) -> Void) {
        guard let index = path.first else {
            mutation(&self)
            return
        }
        guard children.indices.contains(index) else { return }
        children[index].mutateNode(at: Array(path.dropFirst()), mutation: mutation)
    }
}

nonisolated extension Array where Element == PartNode {
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
        with template: PartNode,
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
