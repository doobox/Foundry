import Foundation

@MainActor
extension ProjectEditor {
    func renameReusableComponent(definitionID: UUID, name: String) {
        mutate(actionName: "Rename Reusable Component") { site in
            guard let index = site.reusableComponents.firstIndex(where: { $0.id == definitionID }) else { return }
            site.reusableComponents[index].name = name
        }
    }

    func removeReusableComponent(definitionID: UUID) {
        mutate(actionName: "Delete Reusable Component") { site in
            guard site.reusableComponents.contains(where: { $0.id == definitionID }) else { return }
            site.reusableComponents.removeAll(where: { $0.id == definitionID })
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].components.detachReusableInstances(definitionID: definitionID)
            }
        }
    }

    func renameSharedReusableComponentInstance(componentID: UUID, name: String) {
        editSharedReusableComponent(componentID: componentID, actionName: "Edit Shared Component") {
            $0.name = name
        }
    }

    func setSharedReusableProperty(
        componentID: UUID,
        key: ComponentProperty.Key,
        value: ComponentProperty.Value
    ) {
        editSharedReusableComponent(componentID: componentID, actionName: "Edit Shared Component") {
            $0.setProperty(key, value: value)
        }
    }

    func setSharedReusableResponsiveProperty(
        componentID: UUID,
        key: ComponentProperty.Key,
        value: ComponentProperty.Value,
        breakpoint: ResponsiveBreakpoint
    ) {
        editSharedReusableComponent(componentID: componentID, actionName: "Edit Responsive Global") {
            $0.setResponsiveProperty(key, value: value, at: breakpoint)
        }
    }

    func removeSharedReusableResponsiveOverride(
        componentID: UUID,
        key: ComponentProperty.Key,
        breakpoint: ResponsiveBreakpoint
    ) {
        editSharedReusableComponent(componentID: componentID, actionName: "Reset Responsive Global") {
            $0.removeResponsiveOverride(key, at: breakpoint)
        }
    }

    func setGlobalComponentLinked(componentID: UUID, isLinked: Bool) {
        guard let context = document.site.globalComponentContext(containing: componentID) else { return }
        let targetID = isLinked ? (context.overrideOwnerID ?? componentID) : componentID
        mutate(actionName: isLinked ? "Relink Global Component" : "Override Global Component") { site in
            site.updateComponent(id: targetID) { $0.overridesGlobalDefinition = !isLinked }
            guard isLinked,
                  let index = site.globalComponents.firstIndex(where: { $0.id == context.definitionID }) else { return }
            let template = site.globalComponents[index].root
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].components.replaceReusableInstances(
                    definitionID: context.definitionID,
                    with: template
                )
            }
        }
    }

    @discardableResult
    func saveReusableComponent(componentID: UUID, name: String) -> UUID? {
        guard let source = document.site.component(withID: componentID) else { return nil }
        let definition = ReusableComponentDefinition(
            name: name,
            root: source.duplicatedForReusableDefinition()
        )
        mutate(actionName: "Create Reusable Component") { site in
            site.reusableComponents.append(definition)
        }
        return definition.id
    }

    @discardableResult
    func insertReusableComponent(
        definitionID: UUID,
        on pageID: UUID,
        placement: ComponentPlacement
    ) -> UUID? {
        guard let definition = document.site.reusableComponents.first(where: { $0.id == definitionID }) else {
            return nil
        }
        guard let page = document.site.pages.first(where: { $0.id == pageID }) else { return nil }
        let instance = definition.root.duplicatedForReusableDefinition()
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

    @discardableResult
    func updateReusableComponent(from componentID: UUID) -> Bool {
        guard let source = document.site.component(withID: componentID),
              let definitionID = source.reusableDefinitionID,
              document.site.globalComponents.contains(where: { $0.id == definitionID }) else {
            return false
        }
        let template = source.duplicatedForReusableDefinition()
        mutate(actionName: "Update Reusable Component") { site in
            guard let index = site.globalComponents.firstIndex(where: { $0.id == definitionID }) else { return }
            site.globalComponents[index].root = template
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].components.replaceReusableInstances(
                    definitionID: definitionID,
                    with: template
                )
            }
        }
        return true
    }

    func detachReusableComponent(componentID: UUID) {
        mutate(actionName: "Detach Reusable Component") { site in
            site.updateComponent(id: componentID) { $0.reusableDefinitionID = nil }
        }
    }

    func editSharedReusableComponent(
        componentID: UUID,
        actionName: String,
        mutation: (inout ComponentNode) -> Void
    ) {
        guard let context = document.site.globalComponentContext(containing: componentID) else { return }
        mutate(actionName: actionName) { site in
            guard let index = site.globalComponents.firstIndex(where: { $0.id == context.definitionID }) else { return }
            site.globalComponents[index].root.mutateNode(at: context.path, mutation: mutation)
            let template = site.globalComponents[index].root
            for pageIndex in site.pages.indices {
                site.pages[pageIndex].components.replaceReusableInstances(
                    definitionID: context.definitionID,
                    with: template
                )
            }
        }
    }
}

nonisolated extension Site {
    func globalComponentContext(containing componentID: UUID) -> (definitionID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        guard let context = globalStructureContext(containing: componentID) else { return nil }
        return (context.definitionID, context.path, context.isOverridden, context.overrideOwnerID)
    }

    func globalStructureContext(containing componentID: UUID) -> (definitionID: UUID, instanceID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        for page in pages {
            for component in page.components {
                if let context = component.globalComponentContext(containing: componentID) {
                    return context
                }
            }
        }
        return nil
    }
}

nonisolated private extension ComponentNode {
    func globalComponentContext(containing componentID: UUID) -> (definitionID: UUID, instanceID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        if let definitionID = reusableDefinitionID,
           let path = path(to: componentID) {
            let overrideOwnerID = overrideOwnerID(at: path)
            return (definitionID, id, path, overrideOwnerID != nil, overrideOwnerID)
        }
        for child in children {
            if let context = child.globalComponentContext(containing: componentID) {
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

    func path(to componentID: UUID) -> [Int]? {
        if id == componentID { return [] }
        for (index, child) in children.enumerated() {
            if let childPath = child.path(to: componentID) {
                return [index] + childPath
            }
        }
        return nil
    }

    mutating func mutateNode(at path: [Int], mutation: (inout ComponentNode) -> Void) {
        guard let index = path.first else {
            mutation(&self)
            return
        }
        guard children.indices.contains(index) else { return }
        children[index].mutateNode(at: Array(path.dropFirst()), mutation: mutation)
    }
}

nonisolated extension Array where Element == ComponentNode {
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
        with template: ComponentNode,
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
