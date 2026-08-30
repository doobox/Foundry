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
        let implicitImageProperties: [ComponentPropertyDefinition] = ComponentTemplateRenderer.hasImagePrimitive(in: package.htmlTemplate) ? [
            ComponentPropertyDefinition(
                key: .source, label: "Image", section: .content,
                control: .asset, defaultValue: .url(""),
                isResponsive: false, isInspectorVisible: false
            )
        ] : []
        return ComponentDefinition(
            type: ComponentType(rawValue: manifest.identifier),
            displayName: manifest.name,
            systemImage: "shippingbox",
            category: ComponentCategory(rawValue: ComponentPackageGroup.resolve(manifest.category).rawValue),
            allowsChildren: !manifest.slots.isEmpty,
            renderKind: .package,
            properties: manifest.properties.flatMap(propertyDefinitions) + implicitTextProperties + implicitImageProperties,
            package: package
        )
    }

    private static func propertyDefinitions(_ property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        if let requestedCount = property.control.count, requestedCount > 1 {
            let count = min(max(requestedCount, 2), 4)
            let defaults: [ComponentPackageValue]
            if case .array(let values) = property.defaultValue {
                defaults = Array(values.prefix(count))
            } else {
                defaults = Array(repeating: property.defaultValue, count: count)
            }
            let paddedDefaults = defaults + Array(repeating: defaults.last ?? .string(""), count: max(0, count - defaults.count))
            return [ComponentPropertyDefinition(
                key: .init(rawValue: property.id),
                label: property.title,
                section: .init(rawValue: property.group),
                control: .array(
                    element: control(property.control),
                    count: count,
                    subtitles: Array(property.subtitles.prefix(count)),
                    help: property.toolTip
                ),
                defaultValue: .array(paddedDefaults.prefix(count).map { value($0, control: property.control.type) }),
                isResponsive: property.responsive
            )]
        }
        if property.control.type == .color { return colorProperties(for: property) }
        if property.control.type == .fontFamily {
            return [ComponentPropertyDefinition(
                key: .init(rawValue: property.id),
                label: property.title,
                section: .init(rawValue: property.group),
                control: .themeFontFamily,
                defaultValue: value(property.defaultValue, control: .select),
                isResponsive: property.responsive
            )]
        }
        if property.control.type == .fontSize { return fontSizeProperties(for: property) }
        return [ComponentPropertyDefinition(
            key: .init(rawValue: property.id),
            label: property.title,
            section: .init(rawValue: property.group),
            control: property.control.type == .details
                ? .details(help: property.toolTip)
                : control(property.control),
            defaultValue: value(property.defaultValue, control: property.control.type),
            isResponsive: property.responsive,
            isInspectorVisible: ![.math, .imageTransform].contains(property.control.type) &&
                (property.control.type != .info || !property.title.isEmpty)
        )]
    }

    private static func fontSizeProperties(for property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        let key = ComponentProperty.Key(rawValue: property.id)
        let customKey = ComponentProperty.Key(rawValue: property.id + "Custom")
        let section = ComponentPropertySection(rawValue: property.group)
        return [
            .init(
                key: key, label: property.title, section: section,
                control: .packageFontSize(
                    themeValues: property.control.themeValues ?? false,
                    customValueKey: customKey
                ),
                defaultValue: value(property.defaultValue, control: .select),
                isResponsive: property.responsive
            ),
            .init(
                key: customKey, label: "Custom value", section: section,
                control: .singleLineText,
                defaultValue: .string("1rem"),
                isResponsive: property.responsive, isInspectorVisible: false
            )
        ]
    }

    private static func colorProperties(for property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        let key = ComponentProperty.Key(rawValue: property.id)
        let section = ComponentPropertySection(rawValue: property.group)
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
        case .link: .link(absoluteURL: control.absoluteURL ?? false)
        case .image: .asset
        case .toggle: .toggle
        case .fontFamily: .themeFontFamily
        case .fontSize: .themeFontSize
        case .lineHeight:
            .lineHeight(fontSizeKey: control.fontSize.map(ComponentProperty.Key.init(rawValue:)))
        case .textAlignment: .textAlignment
        case .divider: .divider
        case .slider:
            .slider(
                range: (control.minimum ?? 0)...(control.maximum ?? 100),
                step: control.step ?? 1,
                tickMarks: control.tickMarks ?? 0,
                restrictsToTickMarks: control.restrictsToTickMarks ?? false
            )
        case .date: .date
        case .details: .details(help: nil)
        case .info: .info
        case .button: .button(systemImage: control.systemImage)
        case .imageTransform, .math: .derived
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
            case .image: .url(value)
            case .link: .link(.init(destination: value.isEmpty ? .none : .url(value)))
            case .color: .color(value)
            case .select, .fontFamily, .fontSize, .lineHeight, .textAlignment: .choice(value)
            case .date: .string(value)
            default: .string(value)
            }
        case .array(let values):
            .array(values.map { self.value($0, control: control) })
        }
    }
}
