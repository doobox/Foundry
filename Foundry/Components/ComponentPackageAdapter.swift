import Foundation

nonisolated enum ComponentPackageAdapter {
    static func definition(from package: LoadedComponentPackage) -> ComponentDefinition {
        let manifest = package.manifest
        let type = ComponentType(rawValue: manifest.identifier)
        let implicitTextProperties = ComponentTemplateRenderer.textPrimitives(in: package.htmlTemplate).map { primitive in
            ComponentPropertyDefinition(
                key: ComponentProperty.Key(rawValue: primitive.key),
                label: "Text",
                section: .content,
                control: .multilineText,
                defaultValue: .string(primitive.defaultValue),
                isResponsive: false
            )
        }
        let inlineEditableProperty = manifest.properties.first(where: \.inlineEditable).map {
            ComponentProperty.Key(rawValue: $0.id)
        }
        let themeProperties = manifest.themeControls.map { control in
            switch control.type {
            case .fontFamily:
                ComponentPropertyDefinition(
                    key: .themeFontFamily,
                    label: control.title ?? "Font family",
                    section: ComponentPropertySection(rawValue: control.group ?? "Typography"),
                    control: .themeFontFamily,
                    defaultValue: .choice(control.defaultValue ?? ThemeFontRole.body.rawValue),
                    isResponsive: control.responsive ?? false
                )
            }
        }
        return ComponentDefinition(
            type: type,
            displayName: manifest.name,
            systemImage: "shippingbox",
            category: ComponentCategory(rawValue: manifest.category),
            allowsChildren: !manifest.slots.isEmpty,
            inlineEditableProperty: inlineEditableProperty,
            renderKind: .package,
            properties: manifest.properties.map(propertyDefinition) + themeProperties + implicitTextProperties,
            package: package
        )
    }

    private static func propertyDefinition(_ property: ComponentPackageProperty) -> ComponentPropertyDefinition {
        ComponentPropertyDefinition(
            key: ComponentProperty.Key(rawValue: property.id),
            label: property.title,
            section: ComponentPropertySection(rawValue: property.section),
            control: control(property.control),
            defaultValue: value(property.defaultValue, control: property.control.type),
            isResponsive: property.responsive
        )
    }

    private static func control(_ control: ComponentPackageControl) -> ComponentPropertyControl {
        switch control.type {
        case .text:
            .singleLineText
        case .textArea:
            .multilineText
        case .number:
            .number(
                range: (control.minimum ?? -10_000)...(control.maximum ?? 10_000),
                step: control.step ?? 1,
                unit: control.unit ?? ""
            )
        case .color:
            .color
        case .select:
            .choice((control.options ?? []).map {
                ComponentPropertyChoice(value: $0.value, label: $0.title)
            })
        case .url:
            .url
        case .image:
            .asset
        case .toggle:
            .toggle
        }
    }

    private static func value(
        _ value: ComponentPackageValue,
        control: ComponentPackageControl.Kind
    ) -> ComponentProperty.Value {
        switch value {
        case .number(let value):
            .number(value)
        case .boolean(let value):
            .boolean(value)
        case .string(let value):
            switch control {
            case .url, .image: .url(value)
            case .color: .color(value)
            case .select: .choice(value)
            default: .string(value)
            }
        }
    }
}
