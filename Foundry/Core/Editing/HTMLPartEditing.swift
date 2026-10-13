import Foundation

extension ProjectEditor {
    func setHTMLPrototype(id: UUID, source: HTMLPartSource) {
        guard HTMLPartPrototype.compile(source: source).definition != nil else { return }
        if let context = document.site.globalPartContext(containing: id), !context.isOverridden {
            editSharedReusablePart(partID: id, actionName: "Edit HTML Part") { $0.applyHTMLPrototype(source) }
        } else {
            mutate(actionName: "Edit HTML Part") { site in
                site.updatePart(id: id) { $0.applyHTMLPrototype(source) }
            }
        }
    }
}

nonisolated extension PartNode {
    mutating func applyHTMLPrototype(_ source: HTMLPartSource) {
        guard type == .html,
              let updated = HTMLPartPrototype.compile(source: source).definition else { return }
        let previous = definition
        let oldKeys = Set(previous.properties.map(\.key))
        let oldControls = previous.package?.renderDefinition.propertiesByID ?? [:]
        let newControls = updated.package?.renderDefinition.propertiesByID ?? [:]
        let changedKeys = Set(updated.properties.compactMap { property -> PartProperty.Key? in
            guard let old = oldControls[property.key.rawValue], let new = newControls[property.key.rawValue],
                  old.control.type != new.control.type || old.control.count != new.control.count else { return nil }
            return property.key
        })
        setProperty(HTMLPartPrototype.contentKey, value: .string(source.html))
        setProperty(PartPackageAdapter.htmlCSSKey(for: "content"), value: .string(source.css))
        setProperty(PartPackageAdapter.htmlJavaScriptKey(for: "content"), value: .string(source.javaScript))
        setProperty(HTMLPartPrototype.controlsKey, value: .string(source.controls ?? "[]"))
        setProperty(HTMLPartPrototype.pageCSSKey, value: .string(source.pageCSS))
        setProperty(HTMLPartPrototype.siteCSSKey, value: .string(source.siteCSS))
        setProperty(HTMLPartPrototype.pageJavaScriptKey, value: .string(source.pageJavaScript))
        let newKeys = Set(updated.properties.map(\.key)).union(HTMLPartPrototype.sourceKeys)
        properties.removeAll { oldKeys.contains($0.key) && !newKeys.contains($0.key) }
        responsiveOverrides?.removeAll { !newKeys.contains($0.key) || changedKeys.contains($0.key) }
        for property in updated.properties where !oldKeys.contains(property.key) || changedKeys.contains(property.key) {
            setProperty(property.key, value: property.defaultValue)
            for (breakpoint, value) in property.breakpointDefaults {
                setResponsiveProperty(property.key, value: value, at: breakpoint)
            }
        }
        let oldSlots = Set(previous.package?.manifest.slots.map(\.id) ?? [])
        for slot in updated.package?.manifest.slots ?? [] where !oldSlots.contains(slot.id) {
            for identifier in slot.initial {
                let childType = PartType(rawValue: identifier)
                guard slot.acceptsPart(childType),
                      childType.definition.package?.manifest.permits(parent: type) != false else { continue }
                var child = PartNode.make(childType)
                child.slotID = slot.id
                children.append(child)
            }
        }
    }
}
