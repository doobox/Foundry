import Foundation

nonisolated enum BlockPackageAdapter {
    static func definition(from package: LoadedBlockPackage) -> BlockDefinition {
        let manifest = package.manifest
        let implicitTextProperties = package.preparedPrimitives.text.map { primitive in
            BlockPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "Text", section: .content,
                control: .multilineText,
                defaultValue: primitive.isRepeated ? .array([]) : .string(primitive.defaultValue),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let implicitHTMLProperties = package.preparedPrimitives.html.map { primitive in
            BlockPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "HTML", section: .content,
                control: .multilineText,
                defaultValue: primitive.isRepeated ? .array([]) : .string(primitive.defaultValue),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let implicitHTMLArtifactProperties = package.preparedPrimitives.html.flatMap { primitive in
            [
                (htmlCSSKey(for: primitive.key), "CSS"),
                (htmlJavaScriptKey(for: primitive.key), "JavaScript")
            ].map { key, label in
                BlockPropertyDefinition(
                    key: key, label: label, section: .content, control: .multilineText,
                    defaultValue: primitive.isRepeated ? .array([]) : .string(""),
                    isResponsive: false, isInspectorVisible: false
                )
            }
        }
        let implicitImageProperties = package.preparedPrimitives.images.map { primitive in
            BlockPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "Image", section: .content,
                control: .image,
                defaultValue: primitive.isRepeated ? .array([]) : .url(""),
                isResponsive: false, isInspectorVisible: false
            )
        }
        return BlockDefinition(
            type: BlockType(rawValue: manifest.identifier),
            displayName: manifest.name,
            systemImage: BlockDefinition.genericSystemImage,
            category: BlockCategory(rawValue: BlockPackageGroup.resolve(manifest.category).rawValue),
            allowsChildren: package.hasDropZone || !manifest.slots.isEmpty,
            renderKind: .package,
            properties: manifest.properties.filter { $0.control.type != .childPicker }.flatMap(propertyDefinitions) + implicitTextProperties + implicitHTMLProperties + implicitHTMLArtifactProperties + implicitImageProperties,
            package: package
        )
    }

    private static func propertyDefinitions(_ property: BlockPackageProperty) -> [BlockPropertyDefinition] {
        if property.control.type == .image {
            var definitions = [
                BlockPropertyDefinition(
                    key: .init(rawValue: property.id),
                    label: property.label,
                    section: .init(rawValue: property.group),
                    control: .image,
                    defaultValue: value(property.defaultValue, control: .image),
                    isResponsive: false,
                    visibleWhen: property.visibleWhen,
                    supportsImageFocalPoint: property.focalPoint
                ),
                BlockPropertyDefinition(
                    key: imageAltKey(for: property.id),
                    label: "Alt",
                    section: .init(rawValue: property.group),
                    control: .singleLineText,
                    defaultValue: .string(property.alt),
                    isResponsive: false,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                )
            ]
            if property.focalPoint {
                definitions.append(BlockPropertyDefinition(
                    key: imageFocalPointKey(for: property.id),
                    label: "Focal point",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .array([.number(50), .number(50)]),
                    isResponsive: property.responsive,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                ))
            }
            return definitions
        }
        if let requestedCount = property.control.count, requestedCount > 1 {
            let count = min(max(requestedCount, 2), 4)
            let defaults: [BlockPackageValue]
            if case .array(let values) = property.defaultValue {
                defaults = Array(values.prefix(count))
            } else {
                defaults = Array(repeating: property.defaultValue, count: count)
            }
            let paddedDefaults = defaults + Array(repeating: defaults.last ?? .string(""), count: max(0, count - defaults.count))
            let buttonTexts = Array(property.buttonTexts.prefix(count))
            let paddedButtonTexts = buttonTexts + Array(repeating: "", count: max(0, count - buttonTexts.count))
            let buttonIcons = Array(property.buttonIcons.prefix(count))
            let activeButtonTexts = Array(property.activeButtonTexts.prefix(count))
            let activeButtonIcons = Array(property.activeButtonIcons.prefix(count))
            return [BlockPropertyDefinition(
                key: .init(rawValue: property.id),
                label: property.label,
                section: .init(rawValue: property.group),
                control: .array(
                    element: property.control.type == .color
                        ? .literalColor(allowsOpacity: property.control.opacity == true)
                        : control(property.control, unit: ""),
                    count: count,
                    subtitles: Array(property.subtitles.prefix(count)),
                    buttonTexts: Array(paddedButtonTexts.prefix(count)),
                    buttonIcons: buttonIcons,
                    activeButtonTexts: activeButtonTexts,
                    activeButtonIcons: activeButtonIcons,
                    buttonSelectionMode: property.control.selectionMode ?? .multiple,
                    units: Array(property.units.prefix(count)),
                    help: property.tooltip
                ),
                defaultValue: .array(paddedDefaults.prefix(count).map {
                    value($0, control: property.control.type)
                }),
                isResponsive: property.responsive,
                visibleWhen: property.visibleWhen,
                themeValueSource: property.control.themeValueSource,
                allowsCustomThemeValue: property.control.allowsCustom == true,
                dateMinimum: property.control.minimumDate.flatMap(BlockDateValue.init).map(\.date),
                dateMaximum: property.control.maximumDate.flatMap(BlockDateValue.init)
                    .map(\.date)
            )]
        }
        if property.control.type == .themeColor { return themeColorProperties(for: property) }
        if property.control.type == .themeFont { return BlockPackageFontControl.properties(property) }
        if property.control.type == .shadow { return shadowProperties(for: property) }
        return [BlockPropertyDefinition(
            key: .init(rawValue: property.id),
            label: property.control.type == .note ? property.noteTitle ?? "" : property.label,
            subtitle: property.control.type == .note ? property.noteBody : property.subtitles.first,
            section: .init(rawValue: property.group),
            control: property.control.type == .note
                ? .note(systemImage: property.noteSystemImage)
                : property.control.type == .button
                    ? .button(
                        icon: property.buttonIcons.first,
                        text: property.buttonTexts.first ?? "",
                        activeIcon: property.activeButtonIcons.first,
                        activeText: property.activeButtonTexts.first
                    )
                    : control(property.control, unit: property.units.first ?? ""),
            defaultValue: value(property.defaultValue, control: property.control.type),
            isResponsive: property.control.type != .note && property.responsive,
            isInspectorVisible: property.control.type != .math &&
                (property.control.type != .note || !property.noteBody.isEmpty),
            visibleWhen: property.visibleWhen,
            themeValueSource: property.control.themeValueSource,
            allowsCustomThemeValue: property.control.allowsCustom == true
                && property.control.themeValueSource != .fontFamilies,
            dateMinimum: property.control.minimumDate.flatMap(BlockDateValue.init).map(\.date),
            dateMaximum: property.control.maximumDate.flatMap(BlockDateValue.init).map(\.date)
        )]
    }

    static func imageAltKey(for propertyID: String) -> BlockProperty.Key {
        .init(rawValue: "__foundry_image_alt_\(propertyID)")
    }

    static func htmlCSSKey(for name: String) -> BlockProperty.Key {
        .init(rawValue: "__foundry_html_css_\(name)")
    }

    static func htmlJavaScriptKey(for name: String) -> BlockProperty.Key {
        .init(rawValue: "__foundry_html_javascript_\(name)")
    }

    static func imageFocalPointKey(for propertyID: String) -> BlockProperty.Key {
        .init(rawValue: "__foundry_image_focal_point_\(propertyID)")
    }

    private static func themeColorProperties(for property: BlockPackageProperty) -> [BlockPropertyDefinition] {
        let key = BlockProperty.Key(rawValue: property.id)
        let section = BlockPropertySection(rawValue: property.group)
        guard case .object(let initial) = property.defaultValue else { return [] }
        let lightShade = initial["lightShade"]?.numberValue.flatMap { Int(exactly: $0) }.flatMap(ColourShade.init(rawValue:))
        let darkShade = initial["darkShade"]?.numberValue.flatMap { Int(exactly: $0) }.flatMap(ColourShade.init(rawValue:))
        return [
            BlockPropertyDefinition(
                key: key, label: property.label, section: section,
                control: .packageColor(
                    themeValues: true,
                    opacity: property.control.opacity ?? false,
                    initialLightShade: lightShade,
                    initialDarkShade: darkShade
                ),
                defaultValue: .packageColor(.init(
                    source: BlockThemeValueSelection.storedSource(
                        forManifestValue: initial["palette"]?.stringValue ?? ""
                    ),
                    customColor: property.control.customColor ?? "#000000",
                    opacity: 1,
                    shade: lightShade,
                    darkShade: darkShade
                )),
                isResponsive: property.responsive,
                visibleWhen: property.visibleWhen,
                themeValueSource: property.control.themeValueSource,
                allowsCustomThemeValue: property.control.allowsCustom == true
            )
        ]
    }

    private static func shadowProperties(for property: BlockPackageProperty) -> [BlockPropertyDefinition] {
        let source = BlockThemeValueSelection.storedSource(
            forManifestValue: property.defaultValue.stringValue
        )
        return [BlockPropertyDefinition(
            key: .init(rawValue: property.id),
            label: property.label,
            section: .init(rawValue: property.group),
            control: .packageShadow,
            defaultValue: .packageShadow(.init(
                source: source,
                customLayers: BlockPackageShadowValue.defaultCustom.customLayers
            )),
            isResponsive: property.responsive,
            visibleWhen: property.visibleWhen,
            themeValueSource: .shadows,
            allowsCustomThemeValue: property.control.allowsCustom == true
        )]
    }

    private static func control(_ control: BlockPackageControl, unit: String) -> BlockPropertyControl {
        switch control.type {
        case .text: .singleLineText
        case .textArea: .multilineText
        case .number:
            .number(
                range: (control.minimum ?? -10_000)...(control.maximum ?? 10_000),
                step: control.step ?? 1, unit: unit
            )
        case .color: .literalColor(allowsOpacity: control.opacity == true)
        case .themeColor: .derived
        case .themeFont: .themeFont
        case .fontWeight: .fontWeight(font: control.font)
        case .fontStyle: .fontStyle(font: control.font)
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
        case .note: .note(systemImage: nil)
        case .button: .button(icon: nil, text: "Button", activeIcon: nil, activeText: nil)
        case .image: .image
        case .math: .derived
        case .shadow: .packageShadow
        case .childPicker: .derived
        }
    }

    private static func value(
        _ value: BlockPackageValue,
        control: BlockPackageControl.Kind
    ) -> BlockProperty.Value {
        switch value {
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .string(let value):
            switch control {
            case .link: .link(.init(destination: value.isEmpty ? .none : .url(value)))
            case .color: .color(value)
            case .themeColor: .choice(value)
            case .icon, .select, .themeFont, .fontStyle, .textAlignment, .shadow: .choice(value)
            case .date: .string(value)
            case .image: .url(value)
            default: .string(value)
            }
        case .array(let values):
            .array(values.map { self.value($0, control: control) })
        case .object:
            .string("")
        }
    }
}
