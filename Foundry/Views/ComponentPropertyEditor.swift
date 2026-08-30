import AppKit
import SwiftUI

struct ComponentPropertyEditor: View {
    let definition: ComponentPropertyDefinition
    let component: ComponentNode
    let theme: Theme
    let assets: [ProjectAsset]
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint

    init(
        definition: ComponentPropertyDefinition,
        component: ComponentNode,
        theme: Theme,
        assets: [ProjectAsset],
        editor: ProjectEditor,
        editsSharedDefinition: Bool,
        breakpoint: ResponsiveBreakpoint
    ) {
        self.definition = definition
        self.component = component
        self.theme = theme
        self.assets = assets
        self.editor = editor
        self.editsSharedDefinition = editsSharedDefinition
        self.breakpoint = breakpoint
    }

    @ViewBuilder
    var body: some View {
        editorControl
    }

    @ViewBuilder
    private var editorControl: some View {
        switch definition.control {
        case .array(let element, let count, let subtitles, let help):
            InspectorRow(title: definition.label, alignment: .top, indicator: responsiveIndicator) {
                InspectorControlArray(
                    count: count,
                    subtitles: subtitles,
                    help: help,
                    values: (0..<count).map(arrayElementBinding),
                    element: element,
                    assets: assets
                )
            }
        case .singleLineText:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                InspectorTextField(text: stringBinding(as: .string), accessibilityLabel: definition.label, help: definition.label)
            }
        case .multilineText:
            InspectorRow(title: definition.label, alignment: .top, indicator: responsiveIndicator) {
                TextEditor(text: stringBinding(as: .string))
                    .frame(minHeight: 72)
                    .padding(4)
                    .background(.background, in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }
            }
        case .url:
            InspectorRow(title: definition.label, alignment: .top, indicator: responsiveIndicator) {
                VStack(alignment: .leading, spacing: 4) {
                    InspectorTextField(text: stringBinding(as: .url), accessibilityLabel: definition.label, help: definition.label)
                    if !isValidDestination(displayComponent.property(definition.key)) {
                        Text("Enter #, a relative path, or a complete URL.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        case .number(let range, let step, let unit):
            Group {
                InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                    HStack {
                        Text("\(displayComponent.numberProperty(definition.key, theme: theme).formatted()) \(unit)")
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        InspectorStepper(value: numberBinding, range: range, increment: step, accessibilityLabel: definition.label)
                    }
                }
                if supportsSpacingTokens {
                    InspectorRow(title: "Source") {
                        tokenPicker(tokens: DesignToken.spacingTokens, customLabel: "Custom value")
                    }
                }
            }
        case .slider(let range, let step, let tickMarks, let restrictsToTickMarks):
            InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                HStack {
                    InspectorSlider(
                        value: numberBinding, range: range, step: step,
                        tickMarkCount: tickMarks, restrictsToTickMarks: restrictsToTickMarks,
                        accessibilityLabel: definition.label, help: definition.label
                    )
                    Text(numberBinding.wrappedValue.formatted()).monospacedDigit().frame(minWidth: 36, alignment: .trailing)
                }
            }
        case .date:
            InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                DatePicker("", selection: dateBinding, displayedComponents: [.date])
                    .labelsHidden()
            }
        case .info:
            InspectorRow(title: "", alignment: .top) {
                Text(definition.label).font(.caption).foregroundStyle(.secondary)
            }
        case .button:
            InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                Toggle(definition.label, isOn: booleanBinding)
                    .labelsHidden()
                    .toggleStyle(.button)
            }
        case .color:
            Group {
                InspectorRow(title: "Source") {
                    tokenPicker(tokens: DesignToken.colorTokens, customLabel: "Custom colour")
                }
                if selectedToken == nil {
                    InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                        InspectorColorWell(color: colorBinding)
                    }
                }
            }
        case .packageColor(let themeValues, let customColorKey, let colorMathKey, let opacityKey):
            PackageColorControlEditor(
                label: definition.label,
                choices: themeValues ? theme.colorChoices : [],
                theme: theme,
                source: stringBinding(as: .choice),
                customColor: colorBinding(for: customColorKey),
                adjustment: colorMathKey.map(numberBinding(for:)),
                opacity: opacityKey.map(numberBinding(for:))
            )
        case .choice(let choices):
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                InspectorPopup(selection: stringBinding(as: .choice), options: choices.map { .init(title: $0.label, value: $0.value) }, accessibilityLabel: definition.label, help: definition.label)
            }
        case .themeFontFamily:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                InspectorPopup(selection: stringBinding(as: .choice), options: theme.fontFamilyChoices.map { .init(title: $0.label, value: $0.value) }, accessibilityLabel: definition.label, help: definition.label)
            }
        case .themeFontSize:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                InspectorPopup(selection: stringBinding(as: .choice), options: theme.fontSizeChoices.map { .init(title: $0.label, value: $0.value) }, accessibilityLabel: definition.label, help: definition.label)
            }
        case .packageFontFamily(let themeValues, let customValueKey):
            PackageThemeValueGridEditor(
                label: definition.label,
                choices: themeValues ? theme.fontFamilyChoices : [],
                source: stringBinding(as: .choice),
                customValue: stringBinding(for: customValueKey),
                indicator: responsiveIndicator
            )
        case .packageFontSize(let themeValues, let customValueKey):
            PackageThemeValueGridEditor(
                label: definition.label,
                choices: themeValues ? theme.fontSizeChoices : [],
                source: stringBinding(as: .choice),
                customValue: stringBinding(for: customValueKey),
                indicator: responsiveIndicator
            )
        case .textAlignment:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                InspectorSegmentedControl(selection: stringBinding(as: .choice), segments: alignmentSegments)
            }
        case .divider:
            Divider()
                .padding(.vertical, 6)
                .accessibilityHidden(true)
        case .toggle:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                Toggle("", isOn: booleanBinding)
                    .labelsHidden()
            }
        case .asset:
            assetPicker
        }
    }

    private var assetPicker: some View {
        InspectorRow(title: definition.label, alignment: .top, indicator: responsiveIndicator) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: assetBinding) {
                    Text("No managed image").tag(nil as UUID?)
                    ForEach(assets) { asset in Text(asset.filename).tag(asset.id as UUID?) }
                }
                .labelsHidden()
                if let id = component.property(definition.key).foundryAssetID,
                   !assets.contains(where: { $0.id == id }) {
                    Label("The selected image is missing.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
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

    private func stringBinding(for key: ComponentProperty.Key) -> Binding<String> {
        Binding(
            get: { displayComponent.property(key) },
            set: { setProperty(.string($0), key: key) }
        )
    }

    private var numberBinding: Binding<Double> {
        Binding(
            get: { displayComponent.numberProperty(definition.key, theme: theme) },
            set: { setProperty(.number($0)) }
        )
    }

    private func numberBinding(for key: ComponentProperty.Key) -> Binding<Double> {
        Binding(
            get: { displayComponent.numberProperty(key, theme: theme) },
            set: { setProperty(.number($0), key: key) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: displayComponent.colorProperty(definition.key, theme: theme)) ?? .white },
            set: { setProperty(.color($0.hexString ?? "#FFFFFF")) }
        )
    }

    private func colorBinding(for key: ComponentProperty.Key) -> Binding<Color> {
        Binding(
            get: { Color(hex: displayComponent.colorProperty(key, theme: theme)) ?? .black },
            set: { setProperty(.color($0.hexString ?? "#000000"), key: key) }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { displayComponent.propertyValue(definition.key).booleanValue ?? false },
            set: { setProperty(.boolean($0)) }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { ISO8601DateFormatter().date(from: displayComponent.property(definition.key)) ?? .now },
            set: { setProperty(.string(ISO8601DateFormatter().string(from: $0))) }
        )
    }

    private func arrayElementBinding(_ index: Int) -> Binding<ComponentProperty.Value> {
        Binding(
            get: {
                let values = displayComponent.propertyValue(definition.key).arrayValue ?? []
                return values.indices.contains(index) ? values[index] : .string("")
            },
            set: { newValue in
                var values = displayComponent.propertyValue(definition.key).arrayValue ?? []
                while values.count <= index { values.append(.string("")) }
                values[index] = newValue
                setProperty(.array(values))
            }
        )
    }

    private var responsiveIndicator: InspectorRowIndicator {
        InspectorRowIndicator(
            isVisible: breakpoint != .mobile && definition.isResponsive,
            isOverridden: component.hasResponsiveOverride(definition.key, at: breakpoint),
            breakpointName: breakpoint.displayName,
            toggle: toggleResponsiveOverride
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

    private func removeOverride() {
        if editsSharedDefinition {
            editor.removeSharedReusableResponsiveOverride(
                componentID: component.id,
                key: definition.key,
                breakpoint: breakpoint
            )
        } else {
            editor.removeResponsiveOverride(id: component.id, key: definition.key, breakpoint: breakpoint)
        }
    }

    private func toggleResponsiveOverride() {
        if component.hasResponsiveOverride(definition.key, at: breakpoint) {
            removeOverride()
        } else {
            setProperty(displayComponent.propertyValue(definition.key))
        }
    }

    private var displayComponent: ComponentNode {
        component.resolved(at: effectiveBreakpoint)
    }

    private var effectiveBreakpoint: ResponsiveBreakpoint {
        definition.isResponsive ? breakpoint : .mobile
    }

    private func isValidDestination(_ value: String) -> Bool {
        value == "#" || value.hasPrefix("/") || URL(string: value)?.scheme != nil
    }

    private enum StringValueKind {
        case string
        case url
        case choice

        func value(_ string: String) -> ComponentProperty.Value {
            switch self {
            case .string: .string(string)
            case .url: .url(string)
            case .choice: .choice(string)
            }
        }
    }
}

private struct InspectorControlArray: View {
    let count: Int
    let subtitles: [String]
    let help: String?
    let values: [Binding<ComponentProperty.Value>]
    let element: ComponentPropertyControl
    let assets: [ProjectAsset]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                InspectorControlArrayItem(
                    subtitle: subtitles.indices.contains(index) ? subtitles[index] : nil,
                    help: help,
                    value: values[index],
                    element: element,
                    assets: assets
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct InspectorControlArrayItem: View {
    let subtitle: String?
    let help: String?
    @Binding var value: ComponentProperty.Value
    let element: ComponentPropertyControl
    let assets: [ProjectAsset]

    var body: some View {
        VStack(spacing: 4) {
            control
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(subtitle)
            }
        }
        .help(help ?? subtitle ?? "")
    }

    @ViewBuilder
    private var control: some View {
        switch element {
        case .color:
            InspectorColorWell(color: colorBinding)
        case .singleLineText, .url:
            InspectorTextField(text: stringBinding, accessibilityLabel: subtitle ?? "Text value", help: help)
        case .number(let range, let step, let unit):
            HStack(spacing: 2) {
                Text(numberBinding.wrappedValue.formatted() + unit).monospacedDigit().lineLimit(1)
                InspectorStepper(value: numberBinding, range: range, increment: step, accessibilityLabel: subtitle ?? "Number value")
            }
        case .slider(let range, let step, let tickMarks, let restrictsToTickMarks):
            InspectorSlider(value: numberBinding, range: range, step: step, tickMarkCount: tickMarks, restrictsToTickMarks: restrictsToTickMarks, accessibilityLabel: subtitle ?? "Slider", help: help)
        case .date:
            DatePicker("", selection: dateBinding, displayedComponents: [.date]).labelsHidden()
        case .button:
            Toggle(subtitle ?? "", isOn: booleanBinding).labelsHidden().toggleStyle(.button)
        case .toggle:
            Toggle("", isOn: booleanBinding).labelsHidden()
        case .choice(let choices):
            InspectorPopup(selection: stringBinding, options: choices.map { .init(title: $0.label, value: $0.value) }, accessibilityLabel: subtitle ?? "Choice", help: help)
        case .asset:
            InspectorPopup(selection: assetBinding, options: [InspectorPopupOption(title: "None", value: nil)] + assets.map { .init(title: $0.filename, value: $0.id as UUID?) }, accessibilityLabel: subtitle ?? "Image", help: help)
        default:
            Text("Unsupported")
                .foregroundStyle(.secondary)
        }
    }

    private var stringBinding: Binding<String> {
        Binding(get: { value.stringValue }, set: { value = .string($0) })
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
            set: { value = .color($0.hexString ?? "#000000") }
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

private struct PackageThemeValueGridEditor: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    @Binding var source: String
    @Binding var customValue: String
    let indicator: InspectorRowIndicator

    var body: some View {
        if !choices.isEmpty {
            InspectorRow(title: label, indicator: indicator) {
                InspectorPopup(
                    selection: $source,
                    options: popupOptions,
                    accessibilityLabel: label,
                    help: label
                )
            }
        }

        if source == "custom" || choices.isEmpty {
            InspectorRow(
                title: choices.isEmpty ? label : "Custom value",
                indicator: choices.isEmpty ? indicator : nil
            ) {
                InspectorTextField(text: $customValue, accessibilityLabel: choices.isEmpty ? label : "Custom value")
            }
        }
    }

    private var popupOptions: [InspectorPopupOption<String>] {
        [InspectorPopupOption(title: "Custom", value: "custom")] + choices.map {
            InspectorPopupOption(title: $0.label, value: $0.value)
        }
    }
}

private struct PackageColorControlEditor: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    let theme: Theme
    @Binding var source: String
    @Binding var customColor: Color
    let adjustment: Binding<Double>?
    let opacity: Binding<Double>?

    var body: some View {
        Group {
            if !choices.isEmpty {
                InspectorRow(title: label) {
                    InspectorPopup(
                        selection: $source,
                        options: [InspectorPopupOption(title: "Custom", value: "custom")] + choices.map { .init(title: $0.label, value: $0.value) },
                        accessibilityLabel: label,
                        help: label
                    )
                }
            }
            if source == "custom" || choices.isEmpty {
                InspectorRow(title: choices.isEmpty ? label : "Custom colour", alignment: .center) {
                    InspectorColorWell(color: $customColor)
                }
            }
            if let adjustment {
                InspectorRow(title: "Lighter or darker", alignment: .center) {
                    HStack {
                        InspectorSlider(value: adjustment, range: -100...100, step: 1, accessibilityLabel: "Lighter or darker", help: "Adjust the selected colour")
                        Text(adjustment.wrappedValue.formatted() + "%").monospacedDigit().frame(minWidth: 42, alignment: .trailing)
                    }
                }
            }
            if let opacity {
                InspectorRow(title: "Opacity", alignment: .center) {
                    HStack {
                        InspectorSlider(value: opacity, range: 0...1, step: 0.1, tickMarkCount: 11, restrictsToTickMarks: true, accessibilityLabel: "Opacity", help: "Set opacity from zero to one hundred percent")
                        Text(opacity.wrappedValue.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().frame(minWidth: 42, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func colorChoiceLabel(_ title: String, color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(nsImage: colorDotImage(color))
                .renderingMode(.original)
        }
    }

    private func colorDotImage(_ color: Color) -> NSImage {
        let image = NSImage(size: NSSize(width: 15, height: 11))
        image.lockFocus()

        let dotRect = NSRect(x: 0.5, y: 0.5, width: 10, height: 10)
        let dot = NSBezierPath(ovalIn: dotRect)
        NSColor(color).setFill()
        dot.fill()
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        dot.lineWidth = 0.75
        dot.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func previewColor(for value: String) -> Color {
        guard let role = ThemeColorRole(rawValue: value) else { return .clear }
        return Color(hex: theme.color(for: role)) ?? .clear
    }
}
