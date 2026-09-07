import Foundation

nonisolated enum ComponentPackageAdapter {
    static func definition(from package: LoadedComponentPackage) -> ComponentDefinition {
        let manifest = package.manifest
        let implicitTextProperties = package.preparedPrimitives.text.map { primitive in
            ComponentPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "Text", section: .content,
                control: .multilineText,
                defaultValue: primitive.isRepeated ? .array([]) : .string(primitive.defaultValue),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let implicitHTMLProperties = package.preparedPrimitives.html.map { primitive in
            ComponentPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "HTML", section: .content,
                control: .multilineText,
                defaultValue: primitive.isRepeated ? .array([]) : .string(primitive.defaultValue),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let implicitHTMLArtifactProperties = package.preparedPrimitives.html.flatMap { primitive in
            ["CSS", "JavaScript"].map { suffix in
                ComponentPropertyDefinition(
                    key: .init(rawValue: primitive.key + suffix), label: suffix, section: .content,
                    control: .multilineText,
                    defaultValue: primitive.isRepeated ? .array([]) : .string(""),
                    isResponsive: false, isInspectorVisible: false
                )
            }
        }
        let implicitImageProperties = package.preparedPrimitives.images.map { primitive in
            ComponentPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "Image", section: .content,
                control: .image,
                defaultValue: primitive.isRepeated ? .array([]) : .url(""),
                isResponsive: false, isInspectorVisible: false
            )
        }
        return ComponentDefinition(
            type: ComponentType(rawValue: manifest.identifier),
            displayName: manifest.name,
            systemImage: "shippingbox",
            category: ComponentCategory(rawValue: ComponentPackageGroup.resolve(manifest.category).rawValue),
            allowsChildren: !manifest.slots.isEmpty,
            renderKind: .package,
            properties: manifest.properties.flatMap(propertyDefinitions) + implicitTextProperties + implicitHTMLProperties + implicitHTMLArtifactProperties + implicitImageProperties,
            package: package
        )
    }

    private static func propertyDefinitions(_ property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        if property.control.type == .image {
            var definitions = [
                ComponentPropertyDefinition(
                    key: .init(rawValue: property.id),
                    label: property.label,
                    section: .init(rawValue: property.group),
                    control: .image,
                    defaultValue: value(property.defaultValue, control: .image),
                    isResponsive: false,
                    enable: property.enable,
                    supportsImageFocalPoint: property.focalPoint
                ),
                ComponentPropertyDefinition(
                    key: imageAltKey(for: property.id),
                    label: "Alt",
                    section: .init(rawValue: property.group),
                    control: .singleLineText,
                    defaultValue: .string(property.alt),
                    isResponsive: false,
                    isInspectorVisible: false,
                    enable: property.enable
                )
            ]
            if property.focalPoint {
                definitions.append(ComponentPropertyDefinition(
                    key: imageFocalPointKey(for: property.id),
                    label: "Focal point",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .array([.number(50), .number(50)]),
                    isResponsive: property.responsive,
                    isInspectorVisible: false,
                    enable: property.enable
                ))
            }
            return definitions
        }
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
                label: property.label,
                section: .init(rawValue: property.group),
                control: .array(
                    element: property.control.type == .color && property.control.opacity == true
                        ? .colorWithOpacity
                        : control(property.control, unit: ""),
                    count: count,
                    labels: Array(property.labels.prefix(count)),
                    subtitles: Array(property.subtitles.prefix(count)),
                    units: Array(property.units.prefix(count)),
                    help: property.toolTip
                ),
                defaultValue: .array(paddedDefaults.prefix(count).map {
                    value($0, control: property.control.type)
                }),
                isResponsive: property.responsive,
                enable: property.enable,
                themeValueSource: property.control.themeValueSource,
                allowsCustomThemeValue: property.control.allowsCustom == true
            )]
        }
        if property.control.type == .color { return colorProperties(for: property) }
        if property.control.type == .shadow { return shadowProperties(for: property) }
        if property.control.type == .select,
           property.control.themeValueSource == .fontSizes,
           property.control.allowsCustom == true {
            return fontSizeProperties(for: property)
        }
        return [ComponentPropertyDefinition(
            key: .init(rawValue: property.id),
            label: property.label,
            section: .init(rawValue: property.group),
            control: property.control.type == .details
                ? .details(help: property.toolTip)
                : control(property.control, unit: property.units.first ?? ""),
            defaultValue: value(property.defaultValue, control: property.control.type),
            isResponsive: property.responsive,
            isInspectorVisible: property.control.type != .math &&
                (property.control.type != .info || !property.label.isEmpty),
            enable: property.enable,
            themeValueSource: property.control.themeValueSource,
            allowsCustomThemeValue: property.control.allowsCustom == true
                && property.control.themeValueSource != .fontFamilies
        )]
    }

    static func imageAltKey(for propertyID: String) -> ComponentProperty.Key {
        .init(rawValue: "__foundry_image_alt_\(propertyID)")
    }

    static func imageFocalPointKey(for propertyID: String) -> ComponentProperty.Key {
        .init(rawValue: "__foundry_image_focal_point_\(propertyID)")
    }

    private static func fontSizeProperties(for property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        let key = ComponentProperty.Key(rawValue: property.id)
        let section = ComponentPropertySection(rawValue: property.group)
        let source = ComponentThemeValueSelection.storedSource(forManifestValue: property.defaultValue.stringValue)
        return [
            .init(
                key: key, label: property.label, section: section,
                control: .packageFontSize(
                    themeValues: property.control.themeValueSource == .fontSizes
                ),
                defaultValue: .packageFontSize(.init(source: source, customValue: "1rem")),
                isResponsive: property.responsive,
                enable: property.enable,
                themeValueSource: property.control.themeValueSource,
                allowsCustomThemeValue: property.control.allowsCustom == true
            )
        ]
    }

    private static func colorProperties(for property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        let key = ComponentProperty.Key(rawValue: property.id)
        let section = ComponentPropertySection(rawValue: property.group)
        return [
            ComponentPropertyDefinition(
                key: key, label: property.label, section: section,
                control: .packageColor(
                    themeValues: property.control.themeValueSource == .colors,
                    colorMath: property.control.colorMath ?? false,
                    opacity: property.control.opacity ?? false
                ),
                defaultValue: .packageColor(.init(
                    source: ComponentThemeValueSelection.storedSource(
                        forManifestValue: property.control.themeValueDefault ?? property.defaultValue.stringValue
                    ),
                    customColor: property.control.customColor ?? "#000000",
                    adjustment: 0,
                    opacity: 1
                )),
                isResponsive: property.responsive,
                enable: property.enable,
                themeValueSource: property.control.themeValueSource,
                allowsCustomThemeValue: property.control.allowsCustom == true
            )
        ]
    }

    private static func shadowProperties(for property: ComponentPackageProperty) -> [ComponentPropertyDefinition] {
        let source = ComponentThemeValueSelection.storedSource(
            forManifestValue: property.defaultValue.stringValue
        )
        return [ComponentPropertyDefinition(
            key: .init(rawValue: property.id),
            label: property.label,
            section: .init(rawValue: property.group),
            control: .packageShadow,
            defaultValue: .packageShadow(.init(
                source: source,
                customLayers: ComponentPackageShadowValue.defaultCustom.customLayers
            )),
            isResponsive: property.responsive,
            enable: property.enable,
            themeValueSource: .shadows,
            allowsCustomThemeValue: property.control.allowsCustom == true
        )]
    }

    private static func control(_ control: ComponentPackageControl, unit: String) -> ComponentPropertyControl {
        switch control.type {
        case .text: .singleLineText
        case .textArea: .multilineText
        case .number:
            .number(
                range: (control.minimum ?? -10_000)...(control.maximum ?? 10_000),
                step: control.step ?? 1, unit: unit
            )
        case .color: .color
        case .icon: .icon
        case .select:
            .choice((control.options ?? []).map { .init(value: $0.value, label: $0.title) })
        case .link: .link(absoluteURL: control.absoluteURL ?? false)
        case .toggle: .toggle
        case .textAlignment: .textAlignment
        case .divider: .divider
        case .slider:
            .slider(
                range: (control.minimum ?? 0)...(control.maximum ?? 100),
                step: control.step ?? 0,
                ticks: control.ticks ?? 0,
                unit: unit,
                showsValueField: control.showsValueField ?? true
            )
        case .date: .date
        case .details: .details(help: nil)
        case .info: .info
        case .button: .button(systemImage: control.systemImage)
        case .image: .image
        case .math: .derived
        case .shadow: .packageShadow
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
            case .link: .link(.init(destination: value.isEmpty ? .none : .url(value)))
            case .color: .color(value)
            case .icon, .select, .textAlignment, .shadow: .choice(value)
            case .date: .string(value)
            case .image: .url(value)
            default: .string(value)
            }
        case .array(let values):
            .array(values.map { self.value($0, control: control) })
        }
    }
}
