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
                isResponsive: false,
                isInspectorVisible: false
            )
        }
        let inlineEditableProperty = manifest.properties.first(where: \.inlineEditable).map {
            ComponentProperty.Key(rawValue: $0.id)
        } ?? implicitTextProperties.first?.key
        let themeProperties = manifest.themeControls.flatMap { control -> [ComponentPropertyDefinition] in
            switch control.type {
            case .fontFamily:
                [ComponentPropertyDefinition(
                    key: .themeFontFamily,
                    label: control.title ?? "Font family",
                    section: ComponentPropertySection(rawValue: control.group ?? "Typography"),
                    control: .themeFontFamily,
                    defaultValue: .choice(control.defaultValue ?? ThemeFontRole.body.rawValue),
                    isResponsive: control.responsive ?? false
                )]
            case .fontSize:
                typographyProperties(for: control)
            case .color:
                colorProperties(for: control)
            }
        }
        return ComponentDefinition(
            type: type,
            displayName: manifest.name,
            systemImage: "shippingbox",
            category: ComponentCategory(rawValue: ComponentPackageGroup.resolve(manifest.category).rawValue),
            allowsChildren: !manifest.slots.isEmpty,
            inlineEditableProperty: inlineEditableProperty,
            renderKind: .package,
            properties: manifest.properties.map(propertyDefinition) + themeProperties + implicitTextProperties,
            package: package
        )
    }

    private static func colorProperties(
        for control: ComponentPackageThemeControl
    ) -> [ComponentPropertyDefinition] {
        let section = ComponentPropertySection(rawValue: control.group ?? "Colour")
        let role = ThemeColorRole(rawValue: control.defaultValue ?? "text") ?? .text
        let shade = ThemeColorScale.nearestShade(to: control.shade ?? 500)
        return [
            ComponentPropertyDefinition(
                key: .themeColor,
                label: control.title ?? "Colour",
                section: section,
                control: .themeColor,
                defaultValue: .choice(role.rawValue),
                isResponsive: control.responsive ?? false
            ),
            ComponentPropertyDefinition(
                key: .themeColorShade,
                label: "Shade",
                section: section,
                control: .number(range: 50...950, step: 50, unit: ""),
                defaultValue: .number(Double(shade)),
                isResponsive: control.responsive ?? false,
                isInspectorVisible: false
            )
        ]
    }

    private static func typographyProperties(
        for control: ComponentPackageThemeControl
    ) -> [ComponentPropertyDefinition] {
        let section = ComponentPropertySection(rawValue: control.group ?? "Typography")
        let responsive = control.responsive ?? false
        func choice(
            _ key: ComponentProperty.Key,
            _ label: String,
            _ defaultValue: String,
            _ values: [(String, String)]
        ) -> ComponentPropertyDefinition {
            ComponentPropertyDefinition(
                key: key,
                label: label,
                section: section,
                control: .choice(values.map { .init(value: $0.0, label: $0.1) }),
                defaultValue: .choice(defaultValue),
                isResponsive: responsive
            )
        }

        return [
            ComponentPropertyDefinition(
                key: .themeFontSize,
                label: control.title ?? "Font size",
                section: section,
                control: .themeFontSize,
                defaultValue: .choice(control.defaultValue ?? "base"),
                isResponsive: responsive
            ),
            choice(.themeTextAlignment, "Alignment", "left", [
                ("left", "Left"), ("center", "Centre"), ("right", "Right"), ("justify", "Justify")
            ]),
            choice(.themeFontWeight, "Weight", "400", [
                ("100", "Thin"), ("200", "Extra Light"), ("300", "Light"),
                ("400", "Normal"), ("500", "Medium"), ("600", "Semibold"),
                ("700", "Bold"), ("800", "Extra Bold"), ("900", "Black")
            ]),
            choice(.themeLineHeight, "Line height", "theme", [
                ("theme", "Theme Default")
            ] + ThemeLineHeight.allCases.map { ($0.rawValue, $0.title) }),
            choice(.themeLetterSpacing, "Spacing", "normal", [
                ("tighter", "Tighter"), ("tight", "Tight"), ("normal", "Normal"),
                ("wide", "Wide"), ("wider", "Wider"), ("widest", "Widest")
            ]),
            ComponentPropertyDefinition(
                key: .themeItalic,
                label: "Italic",
                section: section,
                control: .toggle,
                defaultValue: .boolean(false),
                isResponsive: responsive
            ),
            choice(.themeTextShadow, "Text shadow", "none", [
                ("none", "None"), ("small", "Small"), ("medium", "Medium"), ("large", "Large")
            ]),
            choice(.themeTextCase, "Case", "none", [
                ("none", "None"), ("uppercase", "Uppercase"),
                ("lowercase", "Lowercase"), ("capitalize", "Capitalize")
            ]),
            choice(.themeWhitespace, "Whitespace", "normal", [
                ("normal", "Normal"), ("nowrap", "No Wrap"), ("pre", "Preserve"),
                ("pre-line", "Preserve Lines"), ("pre-wrap", "Preserve and Wrap")
            ]),
            choice(.themeUnderline, "Underline", "none", [
                ("none", "No Underline"), ("underline", "Underline"),
                ("overline", "Overline"), ("line-through", "Strikethrough")
            ])
        ]
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
