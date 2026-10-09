import Foundation

/// Native utility groups share the same responsive class contract in every renderer.
nonisolated enum BootstrapControlGroupClasses {
    static func resolve(node: PartNode, key: PartProperty.Key, framework: Framework) -> String? {
        guard let property = node.type.definition.package?.manifest.resolvedProperties.first(where: { $0.id == key.rawValue }),
              let source = property.controlGroupSource, source.type.generatesBootstrapClasses else { return nil }
        if source.type == .spacing {
            return BootstrapSpacingClasses.resolve(node: node, key: key, screens: framework.screens, spacing: framework.spacing)
        }
        func utility(_ value: PartProperty.Value) -> String? {
            if source.type == .foreground {
                guard source.localID == "theme",
                      node.propertyValue(.init(rawValue: source.namespace + ".enabled")) == .boolean(true) else { return nil }
                let theme = BootstrapPaletteTheme.resolve(value.stringValue, framework: framework)
                return theme == "theme-reset" ? nil : "fg-" + theme.dropFirst(6)
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
}
