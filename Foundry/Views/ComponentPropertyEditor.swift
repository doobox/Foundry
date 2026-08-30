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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            InspectorResponsiveIndicator(
                isVisible: breakpoint != .mobile && definition.isResponsive,
                isOverridden: component.hasResponsiveOverride(definition.key, at: breakpoint),
                breakpointName: breakpoint.displayName,
                toggle: toggleResponsiveOverride
            )
            .frame(width: 8)
            .padding(.top, 7)

            editorControl
        }
        .controlSize(.small)
        .font(.callout)
    }

    @ViewBuilder
    private var editorControl: some View {
        switch definition.control {
        case .singleLineText:
            InspectorControlRow(definition.label) {
                TextField("", text: stringBinding(as: .string))
                    .labelsHidden()
            }
        case .multilineText:
            InspectorControlRow(definition.label, alignment: .top) {
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
            InspectorControlRow(definition.label, alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("", text: stringBinding(as: .url))
                        .labelsHidden()
                    if !isValidDestination(displayComponent.property(definition.key)) {
                        Text("Enter #, a relative path, or a complete URL.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        case .number(let range, let step, let unit):
            VStack(alignment: .leading, spacing: 8) {
                InspectorControlRow(definition.label) {
                    Stepper(value: numberBinding, in: range, step: step) {
                        Text("\(displayComponent.numberProperty(definition.key, theme: theme).formatted()) \(unit)")
                            .monospacedDigit()
                    }
                }
                if supportsSpacingTokens {
                    InspectorControlRow("Source") {
                        tokenPicker(tokens: DesignToken.spacingTokens, customLabel: "Custom value")
                    }
                }
            }
        case .color:
            VStack(alignment: .leading, spacing: 6) {
                InspectorControlRow("Source") {
                    tokenPicker(tokens: DesignToken.colorTokens, customLabel: "Custom colour")
                }
                if selectedToken == nil {
                    InspectorControlRow(definition.label) {
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
            InspectorControlRow(definition.label) {
                Picker("", selection: stringBinding(as: .choice)) {
                    ForEach(choices) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .labelsHidden()
            }
        case .themeFontFamily:
            InspectorControlRow(definition.label) {
                Picker("", selection: stringBinding(as: .choice)) {
                    ForEach(theme.fontFamilyChoices) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .labelsHidden()
            }
        case .themeFontSize:
            InspectorControlRow(definition.label) {
                Picker("", selection: stringBinding(as: .choice)) {
                    ForEach(theme.fontSizeChoices) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .labelsHidden()
            }
        case .packageFontFamily(let themeValues, let customValueKey):
            PackageThemeValueEditor(
                label: definition.label,
                choices: themeValues ? theme.fontFamilyChoices : [],
                source: stringBinding(as: .choice),
                customValue: stringBinding(for: customValueKey)
            )
        case .packageFontSize(let themeValues, let customValueKey):
            PackageThemeValueEditor(
                label: definition.label,
                choices: themeValues ? theme.fontSizeChoices : [],
                source: stringBinding(as: .choice),
                customValue: stringBinding(for: customValueKey)
            )
        case .textAlignment:
            InspectorControlRow(definition.label) {
                Picker("", selection: stringBinding(as: .choice)) {
                    Label("Start", systemImage: "text.alignleft").labelStyle(.iconOnly).tag("start")
                    Label("Centre", systemImage: "text.aligncenter").labelStyle(.iconOnly).tag("center")
                    Label("End", systemImage: "text.alignright").labelStyle(.iconOnly).tag("end")
                    Label("Justify", systemImage: "text.justify").labelStyle(.iconOnly).tag("justify")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .help(definition.label)
            }
        case .divider:
            Divider()
                .padding(.vertical, 6)
                .accessibilityHidden(true)
        case .toggle:
            InspectorControlRow(definition.label) {
                Toggle("", isOn: booleanBinding)
                    .labelsHidden()
            }
        case .asset:
            assetPicker
        }
    }

    private var assetPicker: some View {
        InspectorControlRow(definition.label, alignment: .top) {
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


    private var selectedToken: DesignToken? {
        displayComponent.propertyValue(definition.key).tokenValue
    }

    private var supportsSpacingTokens: Bool {
        [.padding, .marginTop, .marginBottom].contains(definition.key)
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

private struct PackageColorControlEditor: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    let theme: Theme
    @Binding var source: String
    @Binding var customColor: Color
    let adjustment: Binding<Double>?
    let opacity: Binding<Double>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !choices.isEmpty {
                InspectorControlRow(label) {
                    Picker("", selection: $source) {
                        colorChoiceLabel("Custom", color: customColor)
                            .tag("custom")
                        ForEach(choices) { choice in
                            colorChoiceLabel(choice.label, color: previewColor(for: choice.value))
                                .tag(choice.value)
                        }
                    }
                    .labelsHidden()
                }
            }
            if source == "custom" || choices.isEmpty {
                InspectorControlRow(choices.isEmpty ? label : "Custom colour") {
                    InspectorColorWell(color: $customColor)
                }
            }
            if let adjustment {
                InspectorControlRow("Lighter or darker", alignment: .top) {
                    InspectorSlider(
                        value: adjustment,
                        range: -100...100,
                        step: 1,
                        formattedValue: adjustment.wrappedValue.formatted() + "%"
                    )
                }
            }
            if let opacity {
                InspectorControlRow("Opacity", alignment: .top) {
                    InspectorSlider(
                        value: opacity,
                        range: 0...1,
                        step: 0.01,
                        formattedValue: opacity.wrappedValue.formatted(.percent.precision(.fractionLength(0)))
                    )
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

private struct PackageThemeValueEditor: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    @Binding var source: String
    @Binding var customValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !choices.isEmpty {
                InspectorControlRow(label) {
                    Picker("", selection: $source) {
                        Text("Custom").tag("custom")
                        ForEach(choices) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                    .labelsHidden()
                }
            }
            if source == "custom" || choices.isEmpty {
                InspectorControlRow(choices.isEmpty ? label : "Custom value") {
                    TextField("", text: $customValue)
                        .labelsHidden()
                }
            }
        }
    }
}
