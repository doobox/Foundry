import Foundation

nonisolated enum ComponentPackageAdapter {
    static func definition(from package: LoadedComponentPackage) -> ComponentDefinition {
        let manifest = package.manifest
        let repeatMaximums = package.repeatMaximums
        let implicitTextProperties = ComponentTemplateRenderer.textPrimitives(in: package.htmlTemplate, repeatMaximums: repeatMaximums).map { primitive in
            ComponentPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "Text", section: .content,
                control: .multilineText, defaultValue: .string(primitive.defaultValue),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let implicitHTMLProperties = ComponentTemplateRenderer.htmlPrimitives(in: package.htmlTemplate, repeatMaximums: repeatMaximums).map { primitive in
            ComponentPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "HTML", section: .content,
                control: .multilineText, defaultValue: .string(primitive.defaultValue),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let implicitHTMLArtifactProperties = ComponentTemplateRenderer.htmlPrimitives(in: package.htmlTemplate, repeatMaximums: repeatMaximums).flatMap { primitive in
            ["CSS", "JavaScript"].map { suffix in
                ComponentPropertyDefinition(
                    key: .init(rawValue: primitive.key + suffix), label: suffix, section: .content,
                    control: .multilineText, defaultValue: .string(""),
                    isResponsive: false, isInspectorVisible: false
                )
            }
        }
        let repeatedImageKeys = ComponentTemplateRenderer.repeatedImageKeys(in: package.htmlTemplate, repeatMaximums: repeatMaximums)
        let implicitImageProperties: [ComponentPropertyDefinition] = repeatedImageKeys.isEmpty
            ? (ComponentTemplateRenderer.hasImagePrimitive(in: package.htmlTemplate) ? [ComponentPropertyDefinition(
                key: .source, label: "Image", section: .content,
                control: .asset, defaultValue: .url(""),
                isResponsive: false, isInspectorVisible: false
            )] : [])
            : repeatedImageKeys.map { key in
                ComponentPropertyDefinition(
                    key: .init(rawValue: key), label: "Image", section: .content,
                    control: .asset, defaultValue: .url(""),
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
        if property.control.type == .padding { return spacingProperties(for: property, kind: .padding) }
        if property.control.type == .margin { return spacingProperties(for: property, kind: .margin) }
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
                    element: control(property.control, unit: ""),
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

    private static func spacingProperties(
        for property: ComponentPackageProperty,
        kind: ComponentSpacingKind
    ) -> [ComponentPropertyDefinition] {
        let key = ComponentProperty.Key(rawValue: property.id)
        let section = ComponentPropertySection(rawValue: property.group)
        let defaultSources: [String]
        if case .array(let values) = property.defaultValue {
            defaultSources = Array(values.prefix(4)).map(\.stringValue)
        } else {
            defaultSources = []
        }
        let paddedSources = Array(
            (defaultSources + Array(repeating: "none", count: 4)).prefix(4)
        ).map(ComponentThemeValueSelection.storedSource)
        let declaredCustomValues: [Double]
        if case .array(let values) = property.control.customValue {
            declaredCustomValues = values.compactMap(\.numberValue)
        } else {
            declaredCustomValues = []
        }
        let customValues = Array(
            (declaredCustomValues + Array(repeating: 0, count: 4)).prefix(4)
        )
        let range: ClosedRange<Double> = kind == .padding
            ? (property.control.minimum ?? 0)...(property.control.maximum ?? 640)
            : (property.control.minimum ?? -640)...(property.control.maximum ?? 640)

        return [
            .init(
                key: key,
                label: property.label,
                section: section,
                control: .packageSpacing(
                    kind: kind,
                    range: range,
                    step: property.control.step ?? 1
                ),
                defaultValue: .packageSpacing(.init(
                    sources: paddedSources,
                    customValues: customValues
                )),
                isResponsive: property.responsive,
                enable: property.enable,
                themeValueSource: property.control.themeValueSource,
                allowsCustomThemeValue: property.control.allowsCustom == true
            )
        ]
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
        case .margin, .padding: .derived
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
        case .math: .derived
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
            case .icon, .select, .margin, .padding, .textAlignment: .choice(value)
            case .date: .string(value)
            default: .string(value)
            }
        case .array(let values):
            .array(values.map { self.value($0, control: control) })
        }
    }
}
