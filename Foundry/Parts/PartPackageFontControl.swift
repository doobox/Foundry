import Foundation

nonisolated enum PartPackageFontControl {
    static func fieldKey(_ id: String, _ field: String) -> PartProperty.Key {
        // Dots cannot occur in public control IDs, so these keys cannot collide.
        .init(rawValue: "\(id).\(field)")
    }

    static func defaults(_ value: PartPackageValue) -> [String: PartPackageValue] {
        if case .object(let fields) = value { return fields }
        return ["family": value]
    }

    static func properties(_ property: PartPackageProperty) -> [PartPropertyDefinition] {
        let fields = defaults(property.defaultValue)
        var result = [PartPropertyDefinition(
            key: .init(rawValue: property.id), label: property.label,
            subtitle: property.subtitles.first, section: .init(rawValue: property.group), control: .frameworkFont,
            defaultValue: .choice(fields["family"]?.stringValue ?? "body"),
            isResponsive: property.responsive && property.control.showsFamily != false,
            isInspectorVisible: property.control.showsFamily != false, visibleWhen: property.visibleWhen)]
        if property.control.showsWeight == true {
            result.append(PartPropertyDefinition(
                key: fieldKey(property.id, "weight"), label: "Weight", section: .init(rawValue: property.group),
                control: .fontWeight(font: property.id), defaultValue: .number(fields["weight"]?.numberValue ?? 400),
                isResponsive: property.responsive, visibleWhen: property.visibleWhen))
        }
        if property.control.showsStyle == true {
            result.append(PartPropertyDefinition(
                key: fieldKey(property.id, "style"), label: "Style", section: .init(rawValue: property.group),
                control: .fontStyle(font: property.id), defaultValue: .choice(fields["style"]?.stringValue ?? "normal"),
                isResponsive: property.responsive, visibleWhen: property.visibleWhen))
        }
        if property.control.showsSize == true {
            result.append(PartPropertyDefinition(
                key: fieldKey(property.id, "size"), label: "Size", section: .init(rawValue: property.group),
                control: .frameworkFontSize, defaultValue: .choice(fields["size"]?.stringValue ?? "base"),
                isResponsive: property.responsive, visibleWhen: property.visibleWhen))
        }
        for index in result.indices {
            result[index].inspectorControlID = property.id
        }
        return result
    }

    static func familyReference(_ id: String, node: PartNode) -> String {
        let key = PartProperty.Key(rawValue: id)
        if let definition = node.type.definition.properties.first(where: { $0.key == key }), !definition.isInspectorVisible {
            return definition.defaultValue.stringValue
        }
        return node.propertyValue(key).stringValue
    }

    static func resolved(_ id: String, node: PartNode, framework: Framework) -> PartPackageValue {
        let family = familyReference(id, node: node)
        var fields: [String: PartPackageValue] = ["family": .string(PartPackageFrameworkValueResolver.resolve(family, from: .fontFamilies, framework: framework) ?? "inherit")]
        let definitions = node.type.definition.properties
        let weightKey = fieldKey(id, "weight")
        if definitions.contains(where: { $0.key == weightKey }) {
            fields["weight"] = .number(node.propertyValue(weightKey).numberValue ?? 400)
        }
        let styleKey = fieldKey(id, "style")
        if definitions.contains(where: { $0.key == styleKey }) {
            fields["style"] = .string(node.propertyValue(styleKey).stringValue)
        }
        let sizeKey = fieldKey(id, "size")
        if definitions.contains(where: { $0.key == sizeKey }) {
            let size = node.propertyValue(sizeKey).stringValue
            fields["size"] = .string(PartPackageFrameworkValueResolver.resolve(size, from: .fontSizes, framework: framework) ?? "inherit")
        }
        return .object(fields)
    }
}
