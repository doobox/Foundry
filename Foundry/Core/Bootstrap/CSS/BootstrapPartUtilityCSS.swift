import Foundation

/// Only explicit, currently used extensions are included in canvas and output.
nonisolated enum BootstrapPartUtilityCSS {
    static func render(node: PartNode, theme: Theme, includeSpace: Bool = true) -> String {
        let styles = node.definition.package?.manifest.resolvedProperties.compactMap { property -> String? in
            if let source = property.controlGroupSource, source.type == .foreground, source.localID == "opacity",
               node.propertyValue(.init(rawValue: source.namespace + ".theme")).stringValue != "inherit",
               let name = BootstrapControlGroupClasses.foregroundOpacityClass(node.propertyValue(.init(rawValue: property.id))),
               name.hasPrefix("fg-opacity--") {
                let amount = name.dropFirst("fg-opacity--".count)
                // Preview/export may load these extensions before Bootstrap itself.
                return ".\(name).\(name){color:color-mix(in oklch,var(--bs-fg) \(amount)%,transparent)}"
            }
            if let source = property.controlGroupSource, source.type == .foreground, source.localID == "theme",
               let token = PartColourToken.parse(node.propertyValue(.init(rawValue: property.id)).stringValue),
               !token.id.hasPrefix("fg-"), !["black", "white"].contains(token.id) {
                if BootstrapControlGroupClasses.customUtilityClass(for: token.id, theme: theme)?.hasPrefix("fg-") == true { return nil }
                return ".fg-token--\(token.id){--bs-fg:\(token.expression)}:where(.fg-token--\(token.id)){color:var(--bs-fg)}"
            }
            guard property.controlGroupSource?.type == .borders,
                  let source = property.controlGroupSource else { return nil }
            if source.localID == "theme",
               node.propertyValue(.init(rawValue: source.namespace + ".colourEnabled")) == .boolean(true),
               let token = PartColourToken.parse(node.propertyValue(.init(rawValue: property.id)).stringValue) {
                if BootstrapControlGroupClasses.customUtilityClass(for: token.id, theme: theme)?.hasPrefix("border-") == true { return nil }
                return ".border-token--\(token.id){--bs-bc:\(token.expression)}:where(.border-token--\(token.id)){border-color:var(--bs-bc)}"
            }
            guard source.localID == "style" else { return nil }
            let value = node.propertyValue(.init(rawValue: property.id)).stringValue
            guard PartPackageThemeBorderControl.styles.contains(value),
                  property.control.options?.contains(where: { $0.value == value }) == true else { return nil }
            return ".border-style-\(value){--bs-border-style:\(value)}"
        } ?? []
        let borderCSS = styles.isEmpty ? "" : "@layer utilities{\(Set(styles).sorted().joined())}"
        let links = node.definition.package?.manifest.controlGroups.filter { $0.type == .linkStyling }.map {
            BootstrapLinkStyling.css(node: node, group: $0, theme: theme)
        }.joined() ?? ""
        var paints: [String] = []
        for definition in node.definition.properties {
            if includeSpace, case .space(let axis) = definition.control {
                paints.append(PartSpaceControl.css(node: node, key: definition.key, axis: axis, screens: theme.screens))
            }
            if let purpose = definition.colourPurpose {
                paints.append(purpose.resolve(node.property(definition.key), theme: theme).css)
            }
            if case .collection(_, let fields) = definition.control,
               case .array(let records) = node.propertyValue(definition.key) {
                for record in records {
                    for field in fields {
                        guard let purpose = field.colourPurpose else { continue }
                        let value = record.objectValue?[field.key.rawValue] ?? field.defaultValue
                        paints.append(purpose.resolve(value.stringValue, theme: theme).css)
                    }
                }
            }
        }
        return borderCSS + links + Set(paints).sorted().joined()
    }
}
