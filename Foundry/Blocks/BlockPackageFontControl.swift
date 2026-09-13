import Foundation

nonisolated enum BlockPackageFontControl {
    static func fieldKey(_ id: String, _ field: String) -> BlockProperty.Key {
        // Dots cannot occur in public control IDs, so these keys cannot collide.
        .init(rawValue: "\(id).\(field)")
    }

    static func defaults(_ value: BlockPackageValue) -> [String: BlockPackageValue] {
        if case .object(let fields) = value { return fields }
        return ["family": value]
    }

    static func properties(_ property: BlockPackageProperty) -> [BlockPropertyDefinition] {
        let fields = defaults(property.defaultValue)
        var result = [BlockPropertyDefinition(
            key: .init(rawValue: property.id), label: property.label,
            subtitle: property.subtitles.first, section: .init(rawValue: property.group), control: .themeFont,
            defaultValue: .choice(fields["family"]?.stringValue ?? "body"),
            isResponsive: property.responsive && property.control.showsFamily != false,
            isInspectorVisible: property.control.showsFamily != false, visibleWhen: property.visibleWhen)]
        if property.control.showsWeight == true {
            result.append(BlockPropertyDefinition(
                key: fieldKey(property.id, "weight"), label: "Weight", section: .init(rawValue: property.group),
                control: .fontWeight(font: property.id), defaultValue: .number(fields["weight"]?.numberValue ?? 400),
                isResponsive: property.responsive, visibleWhen: property.visibleWhen))
        }
        if property.control.showsStyle == true {
            result.append(BlockPropertyDefinition(
                key: fieldKey(property.id, "style"), label: "Style", section: .init(rawValue: property.group),
                control: .fontStyle(font: property.id), defaultValue: .choice(fields["style"]?.stringValue ?? "normal"),
                isResponsive: property.responsive, visibleWhen: property.visibleWhen))
        }
        for index in result.indices {
            result[index].inspectorControlID = property.id
        }
        return result
    }

    static func familyReference(_ id: String, node: BlockNode) -> String {
        let key = BlockProperty.Key(rawValue: id)
        if let definition = node.type.definition.properties.first(where: { $0.key == key }), !definition.isInspectorVisible {
            return definition.defaultValue.stringValue
        }
        return node.propertyValue(key).stringValue
    }

    static func resolved(_ id: String, node: BlockNode, theme: Theme) -> BlockPackageValue {
        let family = familyReference(id, node: node)
        var fields: [String: BlockPackageValue] = ["family": .string(BlockPackageThemeValueResolver.resolve(family, from: .fontFamilies, theme: theme) ?? "inherit")]
        let definitions = node.type.definition.properties
        let weightKey = fieldKey(id, "weight")
        if definitions.contains(where: { $0.key == weightKey }) {
            fields["weight"] = .number(node.propertyValue(weightKey).numberValue ?? 400)
        }
        let styleKey = fieldKey(id, "style")
        if definitions.contains(where: { $0.key == styleKey }) {
            fields["style"] = .string(node.propertyValue(styleKey).stringValue)
        }
        return .object(fields)
    }
}
