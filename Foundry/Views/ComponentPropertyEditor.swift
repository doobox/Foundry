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
        VStack(alignment: .leading, spacing: 6) {
            editorControl
            if breakpoint != .mobile, definition.isResponsive {
                HStack(spacing: 6) {
                    Text(component.hasResponsiveOverride(definition.key, at: breakpoint) ? breakpoint.displayName : "Inherited")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if component.hasResponsiveOverride(definition.key, at: breakpoint) {
                        Button("Reset") { removeOverride() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var editorControl: some View {
        switch definition.control {
        case .singleLineText:
            TextField(definition.label, text: stringBinding(as: .string))
        case .multilineText:
            VStack(alignment: .leading, spacing: 6) {
                Text(definition.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: stringBinding(as: .string))
                    .frame(minHeight: 72)
            }
        case .url:
            VStack(alignment: .leading, spacing: 4) {
                TextField(definition.label, text: stringBinding(as: .url))
                if !isValidDestination(displayComponent.property(definition.key)) {
                    Text("Enter #, a relative path, or a complete URL.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        case .number(let range, let step, let unit):
            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: numberBinding, in: range, step: step) {
                    LabeledContent(
                        definition.label,
                        value: "\(displayComponent.numberProperty(definition.key, theme: theme).formatted()) \(unit)"
                    )
                }
                if supportsSpacingTokens {
                    tokenPicker(tokens: DesignToken.spacingTokens, customLabel: "Custom value")
                }
            }
        case .color:
            VStack(alignment: .leading, spacing: 6) {
                tokenPicker(tokens: DesignToken.colorTokens, customLabel: "Custom color")
                if selectedToken == nil {
                    ColorPicker(
                        definition.label,
                        selection: colorBinding,
                        supportsOpacity: false
                    )
                }
            }
        case .choice(let choices):
            Picker(definition.label, selection: stringBinding(as: .choice)) {
                ForEach(choices) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
        case .themeFontFamily:
            Picker(definition.label, selection: stringBinding(as: .choice)) {
                ForEach(theme.fontFamilyChoices) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
        case .toggle:
            Toggle(definition.label, isOn: booleanBinding)
        case .asset:
            assetPicker
        }
    }

    private var assetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Image", selection: assetBinding) {
                Text("No managed image").tag(nil as UUID?)
                ForEach(assets) { asset in Text(asset.filename).tag(asset.id as UUID?) }
            }
            if let id = component.property(definition.key).foundryAssetID,
               !assets.contains(where: { $0.id == id }) {
                Label("The selected image is missing.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
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

    private var selectedToken: DesignToken? {
        displayComponent.propertyValue(definition.key).tokenValue
    }

    private var supportsSpacingTokens: Bool {
        [.padding, .marginTop, .marginBottom].contains(definition.key)
    }

    private func tokenPicker(tokens: [DesignToken], customLabel: String) -> some View {
        Picker("Source", selection: tokenBinding(allowedTokens: tokens)) {
            Text(customLabel).tag(nil as DesignToken?)
            ForEach(tokens) { token in
                Text(token.displayName).tag(token as DesignToken?)
            }
        }
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

    private func setProperty(_ value: ComponentProperty.Value) {
        if effectiveBreakpoint == .mobile {
            if editsSharedDefinition {
                editor.setSharedReusableProperty(componentID: component.id, key: definition.key, value: value)
            } else {
                editor.setProperty(id: component.id, key: definition.key, value: value)
            }
        } else if editsSharedDefinition {
            editor.setSharedReusableResponsiveProperty(
                componentID: component.id,
                key: definition.key,
                value: value,
                breakpoint: effectiveBreakpoint
            )
        } else {
            editor.setResponsiveProperty(id: component.id, key: definition.key, value: value, breakpoint: effectiveBreakpoint)
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
