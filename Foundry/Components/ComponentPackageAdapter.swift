import Foundation

nonisolated enum ComponentPackageAdapter {
    static func definition(from package: LoadedComponentPackage) -> ComponentDefinition {
        let manifest = package.manifest
        let implicitTextProperties = ComponentTemplateRenderer.textPrimitives(in: package.htmlTemplate).map { primitive in
            ComponentPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "Text", section: .content,
                control: .multilineText, defaultValue: .string(primitive.defaultValue),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let inlineEditableProperty = manifest.properties.first(where: \.inlineEditable).map {
            ComponentProperty.Key(rawValue: $0.id)
        } ?? implicitTextProperties.first?.key
        return ComponentDefinition(
            type: ComponentType(rawValue: manifest.identifier),
            displayName: manifest.name,
            systemImage: "shippingbox",
            category: ComponentCategory(rawValue: ComponentPackageGroup.resolve(manifest.category).rawValue),
            allowsChildren: !manifest.slots.isEmpty,
            inlineEditableProperty: inlineEditableProperty,
            renderKind: .package,
            properties: manifest.properties.flatMap(propertyDefinitions) + implicitTextProperties,
            package: package
        )
    }

    private static func propertyDefinitions(_ property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        if property.control.type == .color { return colorProperties(for: property) }
        if property.control.type == .fontFamily { return fontProperties(for: property, isFamily: true) }
        if property.control.type == .fontSize { return fontProperties(for: property, isFamily: false) }
        return [ComponentPropertyDefinition(
            key: .init(rawValue: property.id),
            label: property.title,
            section: .init(rawValue: property.section),
            control: control(property.control),
            defaultValue: value(property.defaultValue, control: property.control.type),
            isResponsive: property.responsive
        )]
    }

    private static func fontProperties(
        for property: ComponentPackageProperty,
        isFamily: Bool
    ) -> [ComponentPropertyDefinition] {
        let key = ComponentProperty.Key(rawValue: property.id)
        let customKey = ComponentProperty.Key(rawValue: property.id + "Custom")
        let section = ComponentPropertySection(rawValue: property.section)
        return [
            .init(
                key: key, label: property.title, section: section,
                control: isFamily
                    ? .packageFontFamily(themeValues: property.control.themeValues ?? false, customValueKey: customKey)
                    : .packageFontSize(themeValues: property.control.themeValues ?? false, customValueKey: customKey),
                defaultValue: value(property.defaultValue, control: .select),
                isResponsive: property.responsive
            ),
            .init(
                key: customKey, label: "Custom value", section: section,
                control: .singleLineText,
                defaultValue: .string(isFamily ? "system-ui" : "1rem"),
                isResponsive: property.responsive, isInspectorVisible: false
            )
        ]
    }

    private static func colorProperties(for property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        let key = ComponentProperty.Key(rawValue: property.id)
        let section = ComponentPropertySection(rawValue: property.section)
        let customColorKey = ComponentProperty.Key(rawValue: property.id + "Custom")
        let colorMathKey = property.control.colorMath == true
            ? ComponentProperty.Key(rawValue: property.id + "ColorMath") : nil
        let opacityKey = property.control.opacity == true
            ? ComponentProperty.Key(rawValue: property.id + "Opacity") : nil
        var definitions = [
            ComponentPropertyDefinition(
                key: key, label: property.title, section: section,
                control: .packageColor(
                    themeValues: property.control.themeValues ?? false,
                    customColorKey: customColorKey,
                    colorMathKey: colorMathKey,
                    opacityKey: opacityKey
                ),
                defaultValue: value(property.defaultValue, control: .select),
                isResponsive: property.responsive
            ),
            ComponentPropertyDefinition(
                key: customColorKey, label: "Custom colour", section: section,
                control: .color, defaultValue: .color(property.control.customColor ?? "#000000"),
                isResponsive: property.responsive, isInspectorVisible: false
            )
        ]
        if let colorMathKey {
            definitions.append(.init(
                key: colorMathKey, label: "Lighter or darker", section: section,
                control: .number(range: -100...100, step: 1, unit: "%"),
                defaultValue: .number(0), isResponsive: property.responsive,
                isInspectorVisible: false
            ))
        }
        if let opacityKey {
            definitions.append(.init(
                key: opacityKey, label: "Opacity", section: section,
                control: .number(range: 0...1, step: 0.01, unit: ""),
                defaultValue: .number(1), isResponsive: property.responsive,
                isInspectorVisible: false
            ))
        }
        return definitions
    }

    private static func control(_ control: ComponentPackageControl) -> ComponentPropertyControl {
        switch control.type {
        case .text: .singleLineText
        case .textArea: .multilineText
        case .number:
            .number(
                range: (control.minimum ?? -10_000)...(control.maximum ?? 10_000),
                step: control.step ?? 1, unit: control.unit ?? ""
            )
        case .color: .color
        case .select:
            .choice((control.options ?? []).map { .init(value: $0.value, label: $0.title) })
        case .url: .url
        case .image: .asset
        case .toggle: .toggle
        case .fontFamily: .themeFontFamily
        case .fontSize: .themeFontSize
        }
    }

    private static func value(
        _ value: ComponentPackageValue,
        control: ComponentPackageControl.Kind
    ) -> ComponentProperty.Value {
        switch value {
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .string(let value):
            switch control {
            case .url, .image: .url(value)
            case .color: .color(value)
            case .select, .fontFamily, .fontSize: .choice(value)
            default: .string(value)
            }
        }
    }
}
