import Foundation

/// Only explicit, currently used extensions are included in canvas and output.
nonisolated enum BootstrapPartUtilityCSS {
    static func render(node: PartNode, theme: Theme) -> String {
        let styles = node.type.definition.package?.manifest.resolvedProperties.compactMap { property -> String? in
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
                return ".fg-token--\(token.id){--bs-fg:\(token.expression)}:where(.fg-token--\(token.id)){color:var(--bs-fg)}"
            }
            guard property.controlGroupSource?.type == .borders,
                  let source = property.controlGroupSource else { return nil }
            if source.localID == "theme",
               node.propertyValue(.init(rawValue: source.namespace + ".colourEnabled")) == .boolean(true),
               let token = PartColourToken.parse(node.propertyValue(.init(rawValue: property.id)).stringValue) {
                return ".border-token--\(token.id){--bs-bc:\(token.expression)}:where(.border-token--\(token.id)){border-color:var(--bs-bc)}"
            }
            guard source.localID == "style" else { return nil }
            let value = node.propertyValue(.init(rawValue: property.id)).stringValue
            guard PartPackageThemeBorderControl.styles.contains(value),
                  property.control.options?.contains(where: { $0.value == value }) == true else { return nil }
            return ".border-style-\(value){--bs-border-style:\(value)}"
        } ?? []
        let borderCSS = styles.isEmpty ? "" : "@layer utilities{\(Set(styles).sorted().joined())}"
        let links = node.type.definition.package?.manifest.controlGroups.filter { $0.type == .linkStyling }.map {
            BootstrapLinkStyling.css(node: node, group: $0, theme: theme)
        }.joined() ?? ""
        return borderCSS + links
    }
}
