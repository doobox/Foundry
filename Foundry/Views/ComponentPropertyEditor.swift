import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ComponentPropertyEditor: View {
    let definition: ComponentPropertyDefinition
    let component: ComponentNode
    let theme: Theme
    let assets: [ProjectAsset]
    let assetContents: [UUID: ProjectAssetContent]
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint
    let importImage: (URL) -> ProjectAsset?

    init(
        definition: ComponentPropertyDefinition,
        component: ComponentNode,
        theme: Theme,
        assets: [ProjectAsset],
        assetContents: [UUID: ProjectAssetContent],
        pages: [Page],
        folders: [PageFolder],
        publicURL: String,
        editor: ProjectEditor,
        editsSharedDefinition: Bool,
        breakpoint: ResponsiveBreakpoint,
        importImage: @escaping (URL) -> ProjectAsset?
    ) {
        self.definition = definition
        self.component = component
        self.theme = theme
        self.assets = assets
        self.assetContents = assetContents
        self.pages = pages
        self.folders = folders
        self.publicURL = publicURL
        self.editor = editor
        self.editsSharedDefinition = editsSharedDefinition
        self.breakpoint = breakpoint
        self.importImage = importImage
    }

    @ViewBuilder
    var body: some View {
        editorControl
    }

    @ViewBuilder
    private var editorControl: some View {
        switch definition.control {
        case .array(let element, let count, let labels, let subtitles, let units, let help):
            if case .slider = element {
                controlArrayRow(element: element, count: count, labels: labels, subtitles: subtitles, units: units, help: help)
                    .contextMenu {
                        resetButton
                    }
            } else {
                controlArrayRow(element: element, count: count, labels: labels, subtitles: subtitles, units: units, help: help)
            }
        case .singleLineText:
            TextComponentControl(label: definition.label, indicator: responsiveIndicator, text: stringBinding(as: .string))
        case .multilineText:
            TextAreaComponentControl(label: definition.label, indicator: responsiveIndicator, text: stringBinding(as: .string))
        case .link(let absoluteURL):
            LinkComponentControl(
                label: definition.label,
                currentLink: currentLink,
                summary: linkSummary,
                indicator: responsiveIndicator,
                pages: pages,
                folders: folders,
                assets: assets,
                publicURL: publicURL,
                absoluteURL: absoluteURL,
                update: { setProperty(.link($0)) }
            )
        case .number(let range, let step, let unit):
            Group {
                NumberComponentControl(
                    label: definition.label,
                    range: range,
                    step: step,
                    unit: unit,
                    indicator: responsiveIndicator,
                    value: numberBinding
                )
                if supportsSpacingTokens {
                    InspectorRow(title: "Source") {
                        tokenPicker(tokens: DesignToken.spacingTokens, customLabel: "Custom value")
                    }
                }
            }
        case .slider(let range, let step, let ticks, let unit, let showsValueField):
            SliderComponentControl(
                label: definition.label,
                range: range,
                step: step,
                ticks: ticks,
                unit: unit,
                showsValueField: showsValueField,
                indicator: responsiveIndicator,
                value: numberBinding
            )
            .contextMenu {
                resetButton
            }
        case .date:
            DateComponentControl(label: definition.label, indicator: responsiveIndicator, value: dateBinding)
        case .info:
            InfoComponentControl(text: definition.label)
        case .button(let systemImage):
            ButtonComponentControl(
                label: definition.label,
                systemImage: systemImage,
                indicator: responsiveIndicator,
                isActive: booleanBinding
            )
        case .details(let help):
            DetailsComponentControl(
                label: definition.label,
                help: help,
                indicator: responsiveIndicator,
                isPresented: booleanBinding
            )
        case .derived:
            EmptyView()
        case .color:
            BasicColorComponentControl(
                label: definition.label,
                selectedToken: selectedToken,
                indicator: responsiveIndicator,
                color: colorBinding
            ) {
                tokenPicker(tokens: DesignToken.colorTokens, customLabel: "Custom colour")
            }
        case .colorWithOpacity:
            InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                InspectorColorWell(color: colorBinding, supportsAlpha: true)
            }
        case .icon:
            IconComponentControl(label: definition.label, indicator: responsiveIndicator, selection: stringBinding(as: .choice))
        case .packageColor(let themeValues, let colorMath, let opacity):
            ColorComponentControl(
                label: definition.label,
                choices: themeValues ? theme.colorChoices : [],
                theme: theme,
                source: packageColorSourceBinding,
                customColor: packageCustomColorBinding,
                adjustment: colorMath ? packageColorAdjustmentBinding : nil,
                allowsOpacity: opacity,
                indicator: responsiveIndicator
            )
        case .choice(let choices):
            SelectComponentControl(
                label: definition.label,
                options: choiceOptions(choices).map {
                    .init(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
                },
                indicator: responsiveIndicator,
                selection: stringBinding(as: .choice)
            )
        case .themeFontSize:
            SelectComponentControl(
                label: definition.label,
                options: theme.fontSizeChoices.map { .init(title: $0.label, value: $0.value) },
                indicator: responsiveIndicator,
                selection: stringBinding(as: .choice)
            )
        case .packageFontSize(let themeValues):
            ThemeFontSizeComponentControl(
                label: definition.label,
                choices: themeValues ? theme.fontSizeChoices : [],
                source: packageFontSizeSourceBinding,
                customValue: packageFontSizeCustomBinding,
                customLineHeight: packageFontSizeCustomLineHeightBinding,
                indicator: responsiveIndicator
            )
        case .packageShadow:
            ShadowComponentControl(
                label: definition.label,
                choices: theme.shadowChoices,
                source: packageShadowSourceBinding,
                customLayers: packageShadowLayersBinding,
                indicator: responsiveIndicator
            )
        case .textAlignment:
            TextAlignmentComponentControl(
                label: definition.label,
                segments: alignmentSegments,
                indicator: responsiveIndicator,
                selection: stringBinding(as: .choice)
            )
        case .divider:
            DividerComponentControl()
        case .toggle:
            ToggleComponentControl(label: definition.label, indicator: responsiveIndicator, isOn: booleanBinding)
        case .image:
            ImageComponentControl(
                label: definition.label,
                previewImage: previewImage,
                supportsFocalPoint: definition.supportsImageFocalPoint,
                focalPoint: imageFocalPoint,
                focalPointIndicator: imageFocalPointResponsiveIndicator,
                isClearDisabled: displayComponent.propertyValue(definition.key) == definition.defaultValue,
                altText: imageAltBinding,
                chooseImage: chooseImageFromFinder,
                clearImage: { setProperty(definition.defaultValue) },
                importImage: { url in
                    guard let asset = importImage(url) else { return false }
                    setProperty(.url(asset.reference))
                    return true
                },
                setFocalPoint: setImageFocalPoint
            )
        }
    }

    private var previewImage: NSImage? {
        let source = displayComponent.property(definition.key)
        if let id = source.foundryAssetID,
           let data = assetContents[id]?.data {
            return NSImage(data: data)
        }
        guard !source.isEmpty,
              let package = component.type.definition.package,
              package.manifest.assetDeclaration(containing: source) != nil else { return nil }
        return NSImage(contentsOf: package.resourceRootURL.appending(path: source))
    }

    private var imageFocalPoint: CGPoint {
        let point = ComponentImageTemplateValues.focalPoint(
            from: component.propertyValue(imageFocalPointKey, at: effectiveBreakpoint(for: imageFocalPointKey))
        )
        return CGPoint(x: point.x / 100, y: point.y / 100)
    }

    private func setImageFocalPoint(_ point: CGPoint) {
        setProperty(
            .array([
                .number(min(max(point.x * 100, 0), 100)),
                .number(min(max(point.y * 100, 0), 100))
            ]),
            key: imageFocalPointKey
        )
    }

    private var imageFocalPointKey: ComponentProperty.Key {
        ComponentPackageAdapter.imageFocalPointKey(for: definition.key.rawValue)
    }

    private var imageAltKey: ComponentProperty.Key {
        ComponentPackageAdapter.imageAltKey(for: definition.key.rawValue)
    }

    private var imageAltBinding: Binding<String> {
        Binding(
            get: { displayComponent.property(imageAltKey) },
            set: { setProperty(.string($0), key: imageAltKey) }
        )
    }

    private func chooseImageFromFinder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Image"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let asset = importImage(url) else { return }
        setProperty(.url(asset.reference))
    }

    private func choiceOptions(_ declared: [ComponentPropertyChoice]) -> [ComponentPropertyChoice] {
        guard let source = definition.themeValueSource else { return declared }
        let themeChoices = ComponentPackageThemeValueResolver.choices(for: source, theme: theme)
        let themeValues = Set(themeChoices.map(\.value))
        var developerChoices = declared.filter { !themeValues.contains($0.value) && $0.value != "custom" }
        if !themeChoices.isEmpty, !developerChoices.isEmpty {
            developerChoices[0].separatorBefore = true
        }
        var result = themeChoices + developerChoices
        if definition.allowsCustomThemeValue {
            result.append(.init(value: "custom", label: "Custom", separatorBefore: !result.isEmpty))
        }
        return result
    }

    private func themedArrayElement(_ element: ComponentPropertyControl) -> ComponentPropertyControl {
        guard case .choice(let declared) = element else { return element }
        return .choice(choiceOptions(declared))
    }

    private var assetBinding: Binding<UUID?> {
        Binding(
            get: { displayComponent.property(definition.key).foundryAssetID },
            set: { id in
                let reference = id.flatMap { selectedID in
                    assets.first(where: { $0.id == selectedID })?.reference
                } ?? ""
                setProperty(.url(reference))
            }
        )
    }

    private func stringBinding(as kind: StringValueKind) -> Binding<String> {
        Binding(
            get: { displayComponent.property(definition.key) },
            set: { setProperty(kind.value($0)) }
        )
    }

    private var numberBinding: Binding<Double> {
        Binding(
            get: { displayComponent.numberProperty(definition.key, theme: theme) },
            set: { setProperty(.number($0)) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: displayComponent.colorProperty(definition.key, theme: theme)) ?? .white },
            set: { setProperty(.color($0.hexString ?? "#FFFFFF")) }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { displayComponent.propertyValue(definition.key).booleanValue ?? false },
            set: { setProperty(.boolean($0)) }
        )
    }

    private var currentLink: ComponentLink {
        guard case .link(let link) = displayComponent.propertyValue(definition.key) else { return .init() }
        return link
    }

    private var linkSummary: String {
        switch currentLink.destination {
        case .none: "Choose Link…"
        case .url(let value), .plainText(let value): value.isEmpty ? "Choose Link…" : value
        case .page(let id): pages.first(where: { $0.id == id })?.title ?? "Missing Page"
        case .resource(let id): assets.first(where: { $0.id == id })?.filename ?? "Missing Resource"
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { ISO8601DateFormatter().date(from: displayComponent.property(definition.key)) ?? .now },
            set: { setProperty(.string(ISO8601DateFormatter().string(from: $0))) }
        )
    }

    private func arrayElementBinding(_ index: Int) -> Binding<ComponentProperty.Value> {
        arrayElementBinding(index, key: definition.key, fallback: .string(""))
    }

    private func arrayElementBinding(
        _ index: Int,
        key: ComponentProperty.Key,
        fallback: ComponentProperty.Value
    ) -> Binding<ComponentProperty.Value> {
        Binding(
            get: {
                let values = displayComponent.propertyValue(key).arrayValue ?? []
                return values.indices.contains(index) ? values[index] : fallback
            },
            set: { newValue in
                var values = displayComponent.propertyValue(key).arrayValue ?? []
                while values.count <= index { values.append(fallback) }
                values[index] = newValue
                setProperty(.array(values), key: key)
            }
        )
    }

    private var packageColorValue: ComponentPackageColorValue {
        if case .packageColor(let value) = displayComponent.propertyValue(definition.key) { return value }
        if case .packageColor(let value) = definition.defaultValue { return value }
        return .init(source: ComponentThemeValueSelection.manualCustom, customColor: "#000000", adjustment: 0, opacity: 1)
    }

    private var packageColorSourceBinding: Binding<String> {
        Binding(
            get: { packageColorValue.source },
            set: { source in
                var value = packageColorValue
                value.source = source
                setProperty(.packageColor(value))
            }
        )
    }

    private var packageCustomColorBinding: Binding<Color> {
        Binding(
            get: {
                (Color(hex: packageColorValue.customColor) ?? .black)
                    .opacity(packageColorValue.opacity)
            },
            set: { color in
                var value = packageColorValue
                value.customColor = color.hexString ?? "#000000"
                value.opacity = Double(NSColor(color).usingColorSpace(.sRGB)?.alphaComponent ?? 1)
                setProperty(.packageColor(value))
            }
        )
    }

    private var packageColorAdjustmentBinding: Binding<Double> {
        Binding(
            get: { packageColorValue.adjustment },
            set: { adjustment in
                var value = packageColorValue
                value.adjustment = adjustment
                setProperty(.packageColor(value))
            }
        )
    }

    private var packageFontSizeValue: ComponentPackageFontSizeValue {
        if case .packageFontSize(let value) = displayComponent.propertyValue(definition.key) { return value }
        if case .packageFontSize(let value) = definition.defaultValue { return value }
        return .init(source: ComponentThemeValueSelection.manualCustom, customValue: "1rem")
    }

    private var packageShadowValue: ComponentPackageShadowValue {
        if case .packageShadow(let value) = displayComponent.propertyValue(definition.key) { return value }
        if case .packageShadow(let value) = definition.defaultValue { return value }
        return .defaultCustom
    }

    private var packageShadowSourceBinding: Binding<String> {
        Binding(
            get: { packageShadowValue.source },
            set: { source in
                var value = packageShadowValue
                value.source = source
                setProperty(.packageShadow(value))
            }
        )
    }

    private var packageShadowLayersBinding: Binding<[ThemeShadowLayer]> {
        Binding(
            get: { packageShadowValue.customLayers },
            set: { layers in
                var value = packageShadowValue
                value.customLayers = layers
                setProperty(.packageShadow(value))
            }
        )
    }


    private var packageFontSizeSourceBinding: Binding<String> {
        Binding(
            get: { packageFontSizeValue.source },
            set: { source in
                var value = packageFontSizeValue
                value.source = source
                setProperty(.packageFontSize(value))
            }
        )
    }

    private var packageFontSizeCustomBinding: Binding<String> {
        Binding(
            get: { packageFontSizeValue.customValue },
            set: { customValue in
                var value = packageFontSizeValue
                value.customValue = customValue
                setProperty(.packageFontSize(value))
            }
        )
    }

    private var packageFontSizeCustomLineHeightBinding: Binding<String> {
        Binding(
            get: { packageFontSizeValue.customLineHeight },
            set: { customLineHeight in
                var value = packageFontSizeValue
                value.customLineHeight = customLineHeight
                setProperty(.packageFontSize(value))
            }
        )
    }

    @ViewBuilder
    private func controlArrayRow(
        element: ComponentPropertyControl,
        count: Int,
        labels: [String],
        subtitles: [String],
        units: [String],
        help: String?
    ) -> some View {
        if case .slider = element {
            ForEach(0..<count, id: \.self) { index in
                InspectorRow(
                    title: labels[index],
                    indicator: index == 0 ? responsiveIndicator : nil
                ) {
                    InspectorControlArrayItem(
                        title: labels[index],
                        subtitle: subtitles.indices.contains(index) ? subtitles[index] : nil,
                        unit: units.indices.contains(index) ? units[index] : "",
                        help: help,
                        value: arrayElementBinding(index),
                        element: themedArrayElement(element),
                        assets: assets
                    )
                }
            }
        } else {
            InspectorRow(title: definition.label, alignment: .top, indicator: responsiveIndicator) {
                InspectorControlArray(
                    count: count,
                    labels: labels,
                    subtitles: subtitles,
                    units: units,
                    help: help,
                    values: (0..<count).map(arrayElementBinding),
                    element: themedArrayElement(element),
                    assets: assets
                )
            }
        }
    }

    private var resetButton: some View {
        Button("Reset") {
            setProperty(definition.defaultValue)
        }
        .disabled(displayComponent.propertyValue(definition.key) == definition.defaultValue)
    }

    private var responsiveIndicator: InspectorRowIndicator {
        InspectorRowIndicator(
            isVisible: breakpoint != .mobile && definition.isResponsive,
            isOverridden: component.hasResponsiveOverride(definition.key, at: breakpoint),
            breakpointName: breakpoint.displayName,
            toggle: toggleResponsiveOverride
        )
    }

    private var imageFocalPointResponsiveIndicator: InspectorRowIndicator {
        let focalPointDefinition = component.type.definition.properties.first { $0.key == imageFocalPointKey }
        return InspectorRowIndicator(
            isVisible: breakpoint != .mobile && focalPointDefinition?.isResponsive == true,
            isOverridden: component.hasResponsiveOverride(imageFocalPointKey, at: breakpoint),
            breakpointName: breakpoint.displayName,
            toggle: { toggleResponsiveOverride(for: imageFocalPointKey) }
        )
    }


    private var selectedToken: DesignToken? {
        displayComponent.propertyValue(definition.key).tokenValue
    }

    private var supportsSpacingTokens: Bool {
        [.padding, .marginTop, .marginBottom].contains(definition.key)
    }

    private var alignmentSegments: [InspectorSegment<String>] {
        [
            InspectorSegment(value: "start", systemImage: "text.alignleft", accessibilityLabel: "Start", help: "Align text to the start"),
            InspectorSegment(value: "center", systemImage: "text.aligncenter", accessibilityLabel: "Centre", help: "Centre text"),
            InspectorSegment(value: "end", systemImage: "text.alignright", accessibilityLabel: "End", help: "Align text to the end"),
            InspectorSegment(value: "justify", systemImage: "text.justify", accessibilityLabel: "Justify", help: "Justify text")
        ]
    }

    private func tokenPicker(tokens: [DesignToken], customLabel: String) -> some View {
        Picker("", selection: tokenBinding(allowedTokens: tokens)) {
            Text(customLabel).tag(nil as DesignToken?)
            ForEach(tokens) { token in
                Text(token.displayName).tag(token as DesignToken?)
            }
        }
        .labelsHidden()
    }

    private func tokenBinding(allowedTokens: [DesignToken]) -> Binding<DesignToken?> {
        Binding(
            get: {
                guard let token = selectedToken, allowedTokens.contains(token) else { return nil }
                return token
            },
            set: { token in
                if let token {
                    setProperty(.token(token))
                } else if allowedTokens == DesignToken.colorTokens {
                    setProperty(.color(displayComponent.colorProperty(definition.key, theme: theme)))
                } else {
                    setProperty(.number(displayComponent.numberProperty(definition.key, theme: theme)))
                }
            }
        )
    }

    private func setProperty(
        _ value: ComponentProperty.Value,
        key: ComponentProperty.Key? = nil
    ) {
        let key = key ?? definition.key
        let effectiveBreakpoint = effectiveBreakpoint(for: key)
        if effectiveBreakpoint == .mobile {
            if editsSharedDefinition {
                editor.setSharedReusableProperty(componentID: component.id, key: key, value: value)
            } else {
                editor.setProperty(id: component.id, key: key, value: value)
            }
        } else if editsSharedDefinition {
            editor.setSharedReusableResponsiveProperty(
                componentID: component.id,
                key: key,
                value: value,
                breakpoint: effectiveBreakpoint
            )
        } else {
            editor.setResponsiveProperty(id: component.id, key: key, value: value, breakpoint: effectiveBreakpoint)
        }
    }

    private func removeOverride(for key: ComponentProperty.Key) {
        if editsSharedDefinition {
            editor.removeSharedReusableResponsiveOverride(
                componentID: component.id,
                key: key,
                breakpoint: breakpoint
            )
        } else {
            editor.removeResponsiveOverride(id: component.id, key: key, breakpoint: breakpoint)
        }
    }

    private func toggleResponsiveOverride() {
        toggleResponsiveOverride(for: definition.key)
    }

    private func toggleResponsiveOverride(for key: ComponentProperty.Key) {
        if component.hasResponsiveOverride(key, at: breakpoint) {
            removeOverride(for: key)
        } else {
            setProperty(component.propertyValue(key, at: breakpoint), key: key)
        }
    }

    private var displayComponent: ComponentNode {
        component.resolved(at: effectiveBreakpoint)
    }

    private var effectiveBreakpoint: ResponsiveBreakpoint {
        effectiveBreakpoint(for: definition.key)
    }

    private func effectiveBreakpoint(for key: ComponentProperty.Key) -> ResponsiveBreakpoint {
        let propertyDefinition = component.type.definition.properties.first { $0.key == key }
        return propertyDefinition?.isResponsive == true ? breakpoint : .mobile
    }

    private enum StringValueKind {
        case string
        case choice

        func value(_ string: String) -> ComponentProperty.Value {
            switch self {
            case .string: .string(string)
            case .choice: .choice(string)
            }
        }
    }
}

private struct InspectorUnitLabel: View {
    let unit: String

    var body: some View {
        CharacterWidthText(
            value: unit,
            characterCount: 3,
            fontSize: NSFont.smallSystemFontSize
        )
            .foregroundStyle(.secondary)
            .accessibilityHidden(unit.isEmpty)
    }
}

private struct CharacterWidthText: View {
    let value: String
    let characterCount: Int
    let fontSize: CGFloat

    private var reservedWidth: CGFloat {
        let font = NSFont.monospacedSystemFont(
            ofSize: fontSize,
            weight: .regular
        )

        let characterWidth = ("0" as NSString).size(
            withAttributes: [.font: font]
        ).width

        return characterWidth * CGFloat(characterCount)
    }

    var body: some View {
        Text(value)
            .font(
                .system(
                    size: fontSize,
                    design: .monospaced
                )
            )
            .frame(
                width: reservedWidth,
                alignment: .leading
            )
    }
}

private struct InspectorControlArray: View {
    let count: Int
    let labels: [String]
    let subtitles: [String]
    let units: [String]
    let help: String?
    let values: [Binding<ComponentProperty.Value>]
    let element: ComponentPropertyControl
    let assets: [ProjectAsset]

    @ViewBuilder
    var body: some View {
        if case .slider = element {
            VStack(spacing: 8) {
                arrayItems
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                arrayItems
            }
        }
    }

    @ViewBuilder
    private var arrayItems: some View {
        ForEach(0..<count, id: \.self) { index in
            InspectorControlArrayItem(
                title: labels[index],
                subtitle: subtitles.indices.contains(index) ? subtitles[index] : nil,
                unit: units.indices.contains(index) ? units[index] : "",
                help: help,
                value: values[index],
                element: element,
                assets: assets
            )
            .frame(maxWidth: .infinity)
        }
    }
}

private struct InspectorControlArrayItem: View {
    let title: String
    let subtitle: String?
    let unit: String
    let help: String?
    @Binding var value: ComponentProperty.Value
    let element: ComponentPropertyControl
    let assets: [ProjectAsset]

    @ViewBuilder
    var body: some View {
        if case .slider(let range, let step, let ticks, let fallbackUnit, let showsValueField) = element {
            sliderGrid(
                range: range,
                step: step,
                ticks: ticks,
                unit: unit.isEmpty ? fallbackUnit : unit,
                showsValueField: showsValueField
            )
            .controlSize(.small)
            .help(help ?? subtitle ?? "")
        } else {
            VStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .help(title)
                control
                if let subtitle, !subtitle.isEmpty {
                    subtitleText(subtitle)
                }
            }
            .controlSize(.small)
            .help(help ?? subtitle ?? "")
        }
    }

    private func sliderGrid(
        range: ClosedRange<Double>,
        step: Double,
        ticks: Int,
        unit: String,
        showsValueField: Bool
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            GridRow {
                InspectorSlider(
                    value: numberBinding,
                    range: range,
                    step: step,
                    tickMarkCount: ticks,
                    accessibilityLabel: subtitle ?? "Slider",
                    help: help
                )
                .frame(maxWidth: .infinity)

                if showsValueField {
                    InspectorNumberField(
                        value: numberBinding,
                        range: range,
                        step: step,
                        accessibilityLabel: "\(subtitle ?? "Slider") value",
                        help: help
                    )
                    .frame(width: 64)
                    InspectorUnitLabel(unit: unit)
                }
            }

            if let subtitle, !subtitle.isEmpty {
                GridRow {
                    subtitleText(subtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsValueField {
                        Color.clear.frame(width: 64, height: 0)
                        InspectorUnitLabel(unit: "").hidden()
                    }
                }
            }
        }
    }

    private func subtitleText(_ subtitle: String) -> some View {
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(subtitle)
    }

    @ViewBuilder
    private var control: some View {
        switch element {
        case .color:
            InspectorColorWell(color: colorBinding)
        case .colorWithOpacity:
            InspectorColorWell(color: colorBinding, supportsAlpha: true)
        case .icon:
            FoundryIconPicker(
                selection: iconBinding,
                accessibilityLabel: subtitle ?? title
            )
        case .singleLineText:
            InspectorTextField(text: stringBinding, accessibilityLabel: subtitle ?? "Text value", help: help)
        case .number(let range, let step, let unit):
            HStack(spacing: 4) {
                InspectorNumberField(
                    value: numberBinding,
                    range: range,
                    accessibilityLabel: subtitle ?? "Number value",
                    help: help
                )
                InspectorStepper(value: numberBinding, range: range, increment: step, accessibilityLabel: subtitle ?? "Number value")
                InspectorUnitLabel(unit: self.unit.isEmpty ? unit : self.unit)
            }
        case .slider(let range, let step, let ticks, let unit, let showsValueField):
            HStack(spacing: 8) {
                InspectorSlider(value: numberBinding, range: range, step: step, tickMarkCount: ticks, accessibilityLabel: subtitle ?? "Slider", help: help)
                if showsValueField {
                    InspectorNumberField(
                        value: numberBinding,
                        range: range,
                        step: step,
                        accessibilityLabel: "\(subtitle ?? "Slider") value",
                        help: help
                    )
                    .frame(width: 64)
                    InspectorUnitLabel(unit: self.unit.isEmpty ? unit : self.unit)
                }
            }
        case .date:
            DatePicker("", selection: dateBinding, displayedComponents: [.date]).labelsHidden()
        case .button(let systemImage):
            Button {
                booleanBinding.wrappedValue.toggle()
            } label: {
                if let systemImage { Image(systemName: systemImage) } else { Text(subtitle ?? "Button") }
            }
            .buttonStyle(.bordered)
        case .details:
            Button { booleanBinding.wrappedValue.toggle() } label: { Image(systemName: "ellipsis.circle") }
                .buttonStyle(.borderless)
        case .toggle:
            Toggle("", isOn: booleanBinding).labelsHidden()
        case .choice(let choices):
            InspectorPopup(
                selection: stringBinding,
                options: choices.map {
                    .init(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
                },
                accessibilityLabel: subtitle ?? "Choice",
                help: help
            )
        case .image:
            InspectorPopup(selection: assetBinding, options: [InspectorPopupOption(title: "None", value: nil)] + assets.map { .init(title: $0.filename, value: $0.id as UUID?) }, accessibilityLabel: subtitle ?? "Image", help: help)
        default:
            Text("Unsupported")
                .foregroundStyle(.secondary)
        }
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { value.stringValue },
            set: { newValue in
                if case .choice = element {
                    value = .choice(newValue)
                } else {
                    value = .string(newValue)
                }
            }
        )
    }

    private var iconBinding: Binding<String> {
        Binding(get: { value.stringValue }, set: { value = .choice($0) })
    }

    private var numberBinding: Binding<Double> {
        Binding(get: { value.numberValue ?? 0 }, set: { value = .number($0) })
    }

    private var booleanBinding: Binding<Bool> {
        Binding(get: { value.booleanValue ?? false }, set: { value = .boolean($0) })
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: value.stringValue) ?? .black },
            set: {
                value = .color(
                    element.isColorWithOpacity
                        ? ($0.cssStringWithAlpha ?? "rgb(0 0 0 / 1)")
                        : ($0.hexString ?? "#000000")
                )
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { ISO8601DateFormatter().date(from: value.stringValue) ?? .now },
            set: { value = .string(ISO8601DateFormatter().string(from: $0)) }
        )
    }

    private var assetBinding: Binding<UUID?> {
        Binding(
            get: { value.stringValue.foundryAssetID },
            set: { id in
                let reference = id.flatMap { selectedID in assets.first(where: { $0.id == selectedID })?.reference } ?? ""
                value = .url(reference)
            }
        )
    }
}

private extension ComponentPropertyControl {
    var isColorWithOpacity: Bool {
        if case .colorWithOpacity = self { true } else { false }
    }
}
