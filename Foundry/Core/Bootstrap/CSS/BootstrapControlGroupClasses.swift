import Foundation

/// Native utility groups share the same responsive class contract in every renderer.
nonisolated enum BootstrapControlGroupClasses {
    static func resolve(node: PartNode, key: PartProperty.Key, framework: Framework) -> String? {
        guard let property = node.type.definition.package?.manifest.resolvedProperties.first(where: { $0.id == key.rawValue }) else { return nil }
        if property.control.type == .borderSides, case .frameworkBorderWidth(let edges) = node.propertyValue(key) {
            return BootstrapBorderClasses.sides(edges)
        }
        guard let source = property.controlGroupSource, source.type.generatesBootstrapClasses else { return nil }
        if source.type == .linkStyling,
           let group = node.type.definition.package?.manifest.controlGroups.first(where: { $0.namespace == source.namespace }) {
            guard !BootstrapLinkStyling.css(node: node, group: group, framework: framework).isEmpty else { return "" }
            let first = node.type.definition.package?.manifest.resolvedProperties.first { $0.controlGroupSource?.namespace == source.namespace }
            return first?.id == property.id ? BootstrapLinkStyling.className(node: node, group: group) : ""
        }
        if source.type == .spacing {
            return BootstrapSpacingClasses.resolve(node: node, key: key, screens: framework.screens, spacing: framework.spacing)
        }
        func utility(_ value: PartProperty.Value) -> String? {
            if source.type == .borders {
                switch source.localID {
                case "theme":
                    guard node.propertyValue(.init(rawValue: source.namespace + ".colourEnabled")) == .boolean(true) else { return nil }
                    if let token = PartColourToken.parse(value.stringValue) { return "border-token--" + token.id }
                    let theme = BootstrapPaletteTheme.resolve(value.stringValue, framework: framework)
                    guard theme != "theme-reset" else { return nil }
                    let subtle = node.propertyValue(.init(rawValue: source.namespace + ".subtle")) == .boolean(true)
                    return (subtle ? "border-subtle-" : "border-") + theme.dropFirst(6)
                case "colourEnabled", "subtle": return nil
                case "style":
                    let selected = value.stringValue
                    return PartPackageFrameworkBorderControl.styles.contains(selected) && property.control.options?.contains(where: { $0.value == selected }) == true ? "border-style-" + selected : ""
                default: break
                }
            }
            if source.type == .foreground {
                guard node.propertyValue(.init(rawValue: source.namespace + ".theme")).stringValue != "inherit" else { return nil }
                if source.localID == "opacity" {
                    return foregroundOpacityClass(value)
                }
                guard source.localID == "theme", value.stringValue != "inherit" else { return nil }
                if let token = PartColourToken.parse(value.stringValue) {
                    if token.id.hasPrefix("fg-") { return token.id }
                    if ["black", "white"].contains(token.id) { return "fg-" + token.id }
                    return "fg-token--" + token.id
                }
                let theme = BootstrapPaletteTheme.resolve(value.stringValue, framework: framework)
                let variant = node.propertyValue(.init(rawValue: source.namespace + ".variant")).stringValue
                let prefix = ["emphasis", "contrast"].contains(variant) ? "fg-\(variant)-" : "fg-"
                return theme == "theme-reset" ? nil : prefix + theme.dropFirst(6)
            }
            if source.type == .gap {
                guard case .frameworkSpacing(let spacing) = value, !spacing.selection.isCustom,
                      framework.spacing.choices.contains(where: { $0.id == spacing.selection.token }),
                      let prefix = gapPrefix(source.localID) else { return nil }
                return prefix + "-" + spacing.selection.token
            }
            let selected = value.stringValue
            let choices = property.control.options?.map(\.value) ?? []
            guard selected != "none", choices.contains(selected) || BootstrapCustomTokenClasses.choices(existing: choices, framework: framework).contains(selected) else { return nil }
            if source.type == .typography, source.localID == "fontFamily" {
                return BootstrapCustomTokenClasses.fontClasses(framework: framework)[selected] ?? selected
            }
            return selected
        }
        var classes = utility(node.propertyValue(key)).map { [$0] } ?? []
        for (index, id) in BootstrapLayout.ids.enumerated() where property.responsive && framework.screens.screen(id).isEnabled {
            guard let override = node.responsiveOverrides?.first(where: { $0.key == key && $0.breakpoint.screenID == id }),
                  let selected = utility(override.value) else { continue }
            let prefix = BootstrapLayout.classes[index].split(separator: ":")[0]
            classes.append("\(prefix):\(selected)")
        }
        return classes.joined(separator: " ")
    }

    static func gapPrefix(_ localID: String) -> String? {
        switch localID {
        case "gap": "gap"
        case "rowGap": "row-gap"
        case "columnGap": "column-gap"
        default: nil
        }
    }

    static func foregroundOpacityClass(_ value: PartProperty.Value) -> String? {
        guard let number = value.numberValue, number.isFinite else { return nil }
        let amount = Int(min(100, max(0, number)).rounded())
        guard amount < 100 else { return nil }
        return amount > 0 && amount % 10 == 0 ? "fg-\(amount)" : "fg-opacity--\(amount)"
    }
}
