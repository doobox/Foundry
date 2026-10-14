import Foundation

nonisolated enum PartPackageAdapter {
    static func definition(from package: LoadedPartPackage) -> PartDefinition {
        let manifest = package.manifest
        // Expand each declaration once. Child pickers retain their actual place
        // in this list instead of being extracted and sorted back in by the UI.
        let inspectorRows = manifest.resolvedProperties.flatMap { property -> [PartInspectorRow] in
            if let slot = property.childSlot { return [.childPicker(slot)] }
            return PartInspectorControlGroup.groups(for: propertyDefinitions(property)).map(PartInspectorRow.controls)
        }
        let declaredProperties = inspectorRows.flatMap { row -> [PartPropertyDefinition] in
            if case .controls(let group) = row { return group.properties }
            return []
        }
        let implicitTextProperties = package.preparedPrimitives.text.map { primitive in
            PartPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "Text", section: .content,
                control: .multilineText,
                defaultValue: primitive.isRepeated ? .array([]) : .string(primitive.defaultValue),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let implicitHTMLProperties = package.preparedPrimitives.html.map { primitive in
            PartPropertyDefinition(
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
                PartPropertyDefinition(
                    key: key, label: label, section: .content, control: .multilineText,
                    defaultValue: primitive.isRepeated ? .array([]) : .string(""),
                    isResponsive: false, isInspectorVisible: false
                )
            }
        }
        let implicitImageProperties = package.preparedPrimitives.images.map { primitive in
            PartPropertyDefinition(
                key: .init(rawValue: primitive.key), label: primitive.isSVG ? "SVG" : "Image", section: .content,
                control: primitive.isSVG ? .svg : .image,
                defaultValue: primitive.isRepeated ? .array([]) : .url(""),
                isResponsive: false, isInspectorVisible: false
            )
        }
        let implicitVideoProperties = package.preparedPrimitives.videos.map { primitive in
            PartPropertyDefinition(
                key: .init(rawValue: primitive.key), label: "Video", section: .content,
                control: .video,
                defaultValue: primitive.isRepeated ? .array([]) : .url(""),
                isResponsive: false, isInspectorVisible: false
            )
        }
        return PartDefinition(
            type: PartType(rawValue: manifest.identifier),
            displayName: manifest.name,
            systemImage: PartDefinition.genericSystemImage,
            category: PartCategory(rawValue: PartPackageGroup.resolve(manifest.category).rawValue),
            allowsChildren: package.hasDropZone || !manifest.slots.isEmpty,
            renderKind: .package,
            properties: declaredProperties + implicitTextProperties + implicitHTMLProperties + implicitHTMLArtifactProperties + implicitImageProperties + implicitVideoProperties,
            package: package,
            inspectorRows: inspectorRows
        )
    }

    private static func propertyDefinitions(_ property: PartPackageProperty) -> [PartPropertyDefinition] {
        var definitions = basePropertyDefinitions(property)
        for index in definitions.indices {
            definitions[index].outputWhenHidden = property.outputWhenHidden
        }
        for (name, value) in property.breakpointDefaults {
            guard let breakpoint = ResponsiveBreakpoint(manifestKey: name), breakpoint != .mobile else { continue }
            var variant = property
            variant.defaultValue = value
            variant.breakpointDefaults = [:]
            let rows = basePropertyDefinitions(variant)
            for index in definitions.indices where definitions[index].isResponsive {
                definitions[index].breakpointDefaults[breakpoint] = rows.first { $0.key == definitions[index].key }?.defaultValue
            }
        }
        return definitions
    }

    private static func basePropertyDefinitions(_ property: PartPackageProperty) -> [PartPropertyDefinition] {
        if property.control.type == .collection {
            let fields = property.collectionFields.flatMap { collectionFieldDefinitions($0) }
            return [PartPropertyDefinition(
                key: .init(rawValue: property.id),
                label: property.label,
                subtitle: property.subtitles.first,
                section: .init(rawValue: property.group),
                control: .collection(
                    itemLabel: property.itemLabel,
                    fields: fields
                ),
                defaultValue: collectionDefaultValue(for: property),
                isResponsive: false,
                visibleWhen: property.visibleWhen
            )]
        }
        if property.control.type == .video {
            return [
                PartPropertyDefinition(
                    key: .init(rawValue: property.id),
                    label: property.label,
                    section: .init(rawValue: property.group),
                    control: .video,
                    defaultValue: value(property.defaultValue, control: .video),
                    isResponsive: false,
                    visibleWhen: property.visibleWhen
                ),
                PartPropertyDefinition(
                    key: PartVideoTemplateValues.posterPropertyKey(for: property.id),
                    label: "Poster",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .url(""),
                    isResponsive: false,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                ),
                PartPropertyDefinition(
                    key: PartVideoTemplateValues.autoplayPropertyKey(for: property.id),
                    label: "Autoplay",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .choice("never"),
                    isResponsive: false,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                ),
                PartPropertyDefinition(
                    key: PartVideoTemplateValues.posterFirstPropertyKey(for: property.id),
                    label: "Show poster first",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .boolean(true),
                    isResponsive: false,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                ),
                PartPropertyDefinition(
                    key: PartVideoTemplateValues.mutedPropertyKey(for: property.id),
                    label: "Muted",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .boolean(false),
                    isResponsive: false,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                ),
                PartPropertyDefinition(
                    key: PartVideoTemplateValues.controlsPropertyKey(for: property.id),
                    label: "Controls",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .boolean(true),
                    isResponsive: false,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                ),
                PartPropertyDefinition(
                    key: PartVideoTemplateValues.loopPropertyKey(for: property.id),
                    label: "Loop",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .boolean(false),
                    isResponsive: false,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                ),
                PartPropertyDefinition(
                    key: PartVideoTemplateValues.startAtPropertyKey(for: property.id),
                    label: "Time (seconds)",
                    section: .init(rawValue: property.group),
                    control: .derived,
                    defaultValue: .number(0),
                    isResponsive: false,
                    isInspectorVisible: false,
                    visibleWhen: property.visibleWhen
                )
            ]
        }
        if property.control.type == .image || property.control.type == .svg {
            var definitions = [
                PartPropertyDefinition(
                    key: .init(rawValue: property.id),
                    label: property.label,
                    section: .init(rawValue: property.group),
                    control: property.control.type == .svg ? .svg : .image,
                    defaultValue: value(property.defaultValue, control: .image),
                    isResponsive: property.responsive,
                    visibleWhen: property.visibleWhen,
                    supportsImageFocalPoint: property.focalPoint
                ),
                PartPropertyDefinition(
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
                definitions.append(PartPropertyDefinition(
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
            let defaults: [PartPackageValue]
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
            return [PartPropertyDefinition(
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
                dateMinimum: property.control.minimumDate.flatMap(PartDateValue.init).map(\.date),
                dateMaximum: property.control.maximumDate.flatMap(PartDateValue.init).map(\.date),
                presentation: property.control.presentation
            )]
        }
        if property.control.type == .themeBorder { return PartPackageThemeBorderControl.properties(property) }
        if property.control.type == .themeFont { return PartPackageFontControl.properties(property) }
        if property.control.type == .themeShadow { return shadowProperties(for: property) }
        if property.control.type == .edges || property.control.type == .corners { return boxLengthProperties(for: property) }
        return [PartPropertyDefinition(
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
            defaultValue: defaultValue(for: property),
            isResponsive: property.control.type != .note && property.responsive,
            isInspectorVisible: property.control.type != .math &&
                (property.control.type != .note || !property.noteBody.isEmpty),
            visibleWhen: property.visibleWhen,
            themeValueSource: property.control.themeValueSource,
            allowsCustomThemeValue: property.control.allowsCustom == true
                && property.control.themeValueSource != .fontFamilies,
            dateMinimum: property.control.minimumDate.flatMap(PartDateValue.init).map(\.date),
            dateMaximum: property.control.maximumDate.flatMap(PartDateValue.init).map(\.date),
            presentation: property.control.presentation,
            colourSections: property.control.effectiveColourSections,
            colourPurpose: property.control.type.colourPurpose
        )]
    }

    /// Manifest keys are value strings; the schema has already rejected any
    /// that are not numbers.
    private static func sliderValueLabels(_ labels: [String: String]?) -> [SliderOptions.ValueLabel] {
        (labels ?? [:])
            .compactMap { key, text in Double(key).map { SliderOptions.ValueLabel(value: $0, text: text) } }
            .sorted { $0.value < $1.value }
    }

    static func imageAltKey(for propertyID: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_image_alt_\(propertyID)")
    }

    static func htmlCSSKey(for name: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_html_css_\(name)")
    }

    static func htmlJavaScriptKey(for name: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_html_javascript_\(name)")
    }

    static func imageFocalPointKey(for propertyID: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_image_focal_point_\(propertyID)")
    }

    /// The generic edges/corners controls: raw four-length inputs with the box-model
    /// editor but no theme tokens. They reuse the margin/radius storage (linking,
    /// persistence, resolution) with custom-only values.
    private static func boxLengthProperties(for property: PartPackageProperty) -> [PartPropertyDefinition] {
        let isCorners = property.control.type == .corners
        let units = normalizedBoxUnits(property.units, isCorners: isCorners)
        let defaultValue: PartProperty.Value
        if isCorners {
            var value = PartPackageThemeRadiusControl.customDefaultValue(property.defaultValue, units: units)
                ?? PartPackageThemeRadiusControl.customZero(units: units)
            if property.control.linked == false { value.unlinkAll() }
            defaultValue = .themeRadius(value)
        } else {
            var value = PartPackageThemeMarginControl.customDefaultValue(property.defaultValue, units: units)
                ?? PartPackageThemeMarginControl.customZero(units: units)
            if property.control.linked == false { value.unlinkAll() }
            defaultValue = .themeMargin(value)
        }
        return [PartPropertyDefinition(
            key: .init(rawValue: property.id),
            label: property.label,
            subtitle: property.subtitles.first,
            section: .init(rawValue: property.group),
            control: isCorners ? .corners(units: units) : .edges(units: units),
            defaultValue: defaultValue,
            isResponsive: property.responsive,
            visibleWhen: property.visibleWhen
        )]
    }

    private static func normalizedBoxUnits(_ declared: [String], isCorners: Bool) -> [String] {
        let allowed = isCorners ? RadiusPolicy.units : MarginPolicy.units
        let filtered = declared.filter(allowed.contains)
        return filtered.isEmpty ? allowed : filtered
    }

    private static func shadowProperties(for property: PartPackageProperty) -> [PartPropertyDefinition] {
        let source = PartThemeValueSelection.storedSource(
            forManifestValue: property.defaultValue.stringValue
        )
        return [PartPropertyDefinition(
            key: .init(rawValue: property.id),
            label: property.label,
            section: .init(rawValue: property.group),
            control: .packageShadow,
            defaultValue: .packageShadow(.init(
                source: source,
                customLayers: PartPackageShadowValue.defaultCustom.customLayers
            )),
            isResponsive: property.responsive,
            visibleWhen: property.visibleWhen,
            themeValueSource: .shadows,
            allowsCustomThemeValue: property.control.allowsCustom == true
        )]
    }

    private static func control(_ control: PartPackageControl, unit: String) -> PartPropertyControl {
        switch control.type {
        case .text: .singleLineText
        case .textArea: .multilineText
        case .number:
            .number(
                range: (control.minimum ?? -10_000)...(control.maximum ?? 10_000),
                step: control.step ?? 1, unit: unit
            )
        case .color: .literalColor(allowsOpacity: control.opacity == true)
        case .themeColors, .backgroundColor, .foregroundColor, .borderColor, .linkColor: .themeColors
        case .themeFont: .themeFont
        case .themeFontSize: .themeFontSize
        case .themeStackingOrder: .themeStackingOrder
        case .pageFolder: .pageFolder
        case .themePadding: .themePadding
        case .themeMargin: .themeMargin
        case .themeSpacing: .themeSpacing
        case .themeBorder: .derived
        case .borderSides: .themeBorderWidth
        case .themeRadius: .themeRadius
        case .edges, .corners: .derived // Unreachable: boxLengthProperties handles these first.
        case .fontWeight: .fontWeight(font: control.font)
        case .fontStyle: .fontStyle(font: control.font)
        case .icon: .icon
        case .select:
            .choice((control.options ?? []).map { .init(value: $0.value, label: $0.title, systemImage: $0.systemImage) })
        case .space: .space(axis: control.axis == "x" ? "x" : "y")
        case .link: .link(absoluteURL: control.absoluteURL ?? false)
        case .toggle: .toggle
        case .textAlignment: .textAlignment
        case .divider: .divider
        case .spacer: .spacer(height: control.height ?? PartPackageControl.defaultSpacerHeight)
        case .slider:
            .slider(SliderOptions(
                range: (control.minimum ?? 0)...(control.maximum ?? 100),
                step: control.step ?? 0,
                ticks: control.ticks ?? 0,
                unit: unit,
                editableValue: control.editableValue ?? false,
                tickLabels: sliderValueLabels(control.tickLabels),
                valueLabels: sliderValueLabels(control.valueLabels),
                minimumLabel: control.minimumLabel.map { .init(title: $0.title, systemImage: $0.systemImage) },
                maximumLabel: control.maximumLabel.map { .init(title: $0.title, systemImage: $0.systemImage) },
                neutralValue: control.neutralValue
            ))
        case .date: .date
        case .note: .note(systemImage: nil)
        case .button: .button(icon: nil, text: "Button", activeIcon: nil, activeText: nil)
        case .image: .image
        case .svg: .svg
        case .video: .video
        case .math: .derived
        case .themeShadow: .packageShadow
        case .childPicker: .derived
        case .collection: .derived
        }
    }

    static func defaultValue(for property: PartPackageProperty) -> PartProperty.Value {
        let resolved = value(property.defaultValue, control: property.control.type)
        guard let source = property.controlGroupSource, source.type == .sizing,
              case .themeSpacing(var spacing) = resolved,
              !spacing.selection.isCustom else { return resolved }
        // Seed the inactive Custom mode without enabling a maximum constraint.
        // Switching modes already preserves the user's last amount and unit.
        switch source.localID {
        case "maxWidth": spacing.selection.amount = 1200
        case "maxHeight": spacing.selection.amount = 800
        default: return resolved
        }
        spacing.selection.unit = "px"
        return .themeSpacing(spacing)
    }

    private static func value(
        _ value: PartPackageValue,
        control: PartPackageControl.Kind
    ) -> PartProperty.Value {
        if control == .themeSpacing, let value = PartPackageSingleSpacingControl.defaultValue(value) {
            return .themeSpacing(value)
        }
        if control == .themeRadius, let value = PartPackageThemeRadiusControl.defaultValue(value) {
            return .themeRadius(value)
        }
        if control == .borderSides, let borders = BootstrapBorderClasses.defaultValue(value) {
            return .themeBorderWidth(borders)
        }
        if control == .themeMargin, let margin = PartPackageThemeMarginControl.defaultValue(value) {
            return .themeMargin(margin)
        }
        if control == .themePadding, let padding = PartPackageThemePaddingControl.defaultValue(value) {
            return .themePadding(padding)
        }
        return convertedValue(value, control: control)
    }

    private static func convertedValue(_ value: PartPackageValue, control: PartPackageControl.Kind) -> PartProperty.Value {
        switch value {
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .string(let value):
            switch control {
            case .link: .link(.init(destination: value.isEmpty ? .none : .url(value)))
            case .color: .color(value)
            case .themeColors, .backgroundColor, .foregroundColor, .borderColor, .linkColor: .choice(value)
            case .icon, .select, .themeFont, .themeFontSize, .themeStackingOrder, .pageFolder, .fontStyle, .textAlignment, .themeShadow: .choice(value)
            case .date: .string(value)
            case .image, .svg, .video: .url(value)
            default: .string(value)
            }
        case .array(let values):
            .array(values.map { self.value($0, control: control) })
        case .object(let values):
            .object(values.mapValues { convertedValue($0, control: control) })
        }
    }

    private static func collectionFieldDefinitions(_ property: PartPackageProperty) -> [PartPropertyDefinition] {
        guard property.control.type != .collection,
              property.control.type != .childPicker,
              property.control.type != .math else { return [] }
        return propertyDefinitions(property)
    }

    private static func collectionDefaultValue(for property: PartPackageProperty) -> PartProperty.Value {
        guard case .array(let records) = property.defaultValue else { return .array([]) }
        let fields = property.collectionFields.flatMap { collectionFieldDefinitions($0) }
        return .array(records.compactMap { record in
            guard case .object(let declaredValues) = record else { return nil }
            let values = Dictionary(uniqueKeysWithValues: property.collectionFields.map { field in
                let declared = declaredValues[field.id] ?? field.defaultValue
                return (field.id, value(declared, control: field.control.type))
            })
            let id = declaredValues[PartCollectionValue.identityKey]?.stringValue.nonEmpty
                .flatMap(UUID.init(uuidString:)) ?? UUID()
            return PartCollectionValue.record(fields: fields, overriding: values, id: id)
        })
    }
}

private nonisolated extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
