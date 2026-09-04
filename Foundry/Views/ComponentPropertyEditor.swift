import AppKit
import SwiftUI

struct ComponentPropertyEditor: View {
    @State private var showsLinkEditor = false
    @State private var linkDraft = ComponentLink()
    let definition: ComponentPropertyDefinition
    let component: ComponentNode
    let theme: Theme
    let assets: [ProjectAsset]
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint

    init(
        definition: ComponentPropertyDefinition,
        component: ComponentNode,
        theme: Theme,
        assets: [ProjectAsset],
        pages: [Page],
        folders: [PageFolder],
        publicURL: String,
        editor: ProjectEditor,
        editsSharedDefinition: Bool,
        breakpoint: ResponsiveBreakpoint
    ) {
        self.definition = definition
        self.component = component
        self.theme = theme
        self.assets = assets
        self.pages = pages
        self.folders = folders
        self.publicURL = publicURL
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
        case .link(let absoluteURL):
            InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                HStack(spacing: 8) {
                    Button(linkSummary) {
                        linkDraft = currentLink
                        showsLinkEditor = true
                    }
                    if currentLink.destination != .none {
                        Button {
                            setProperty(.link(.init()))
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Clear link")
                    }
                }
                .sheet(isPresented: $showsLinkEditor) {
                    ComponentLinkEditor(
                        link: $linkDraft,
                        pages: pages,
                        folders: folders,
                        assets: assets,
                        publicURL: publicURL,
                        absoluteURL: absoluteURL,
                        cancel: { showsLinkEditor = false },
                        apply: {
                            setProperty(.link(linkDraft))
                            showsLinkEditor = false
                        }
                    )
                }
            }
        case .number(let range, let step, let unit):
            Group {
                InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                    HStack(spacing: 6) {
                        InspectorNumberField(
                            value: numberBinding,
                            range: range,
                            accessibilityLabel: definition.label,
                            help: definition.label
                        )
                        InspectorUnitLabel(unit: unit)
                        InspectorStepper(value: numberBinding, range: range, increment: step, accessibilityLabel: definition.label)
                    }
                }
                if supportsSpacingTokens {
                    InspectorRow(title: "Source") {
                        tokenPicker(tokens: DesignToken.spacingTokens, customLabel: "Custom value")
                    }
                }
            }
        case .slider(let range, let step, let ticks, let unit, let showsValueField):
            InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                HStack(spacing: 8) {
                    InspectorSlider(
                        value: numberBinding, range: range, step: step,
                        tickMarkCount: ticks,
                        accessibilityLabel: definition.label, help: definition.label
                    )
                    if showsValueField {
                        InspectorNumberField(
                            value: numberBinding,
                            range: range,
                            step: step,
                            accessibilityLabel: "\(definition.label) value",
                            help: definition.label
                        )
                        .frame(width: 64)
                        InspectorUnitLabel(unit: unit)
                    }
                }
            }
            .contextMenu {
                resetButton
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
        case .button(let systemImage):
            InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                Button {
                    booleanBinding.wrappedValue.toggle()
                } label: {
                    if let systemImage {
                        Label(definition.label, systemImage: systemImage)
                    } else {
                        Text(definition.label)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityValue(booleanBinding.wrappedValue ? "On" : "Off")
            }
        case .details(let help):
            InspectorRow(title: "", alignment: .center, indicator: responsiveIndicator) {
                Button {
                    booleanBinding.wrappedValue.toggle()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help(help ?? definition.label)
                .accessibilityLabel(definition.label.isEmpty ? "Show details" : definition.label)
                .accessibilityValue(booleanBinding.wrappedValue ? "Shown" : "Hidden")
            }
        case .derived:
            EmptyView()
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
        case .icon:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                FoundryIconPicker(
                    selection: stringBinding(as: .choice),
                    accessibilityLabel: definition.label
                )
            }
        case .packageColor(let themeValues, let colorMath, let opacity):
            PackageColorControlEditor(
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
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                InspectorPopup(
                    selection: stringBinding(as: .choice),
                    options: choiceOptions(choices).map {
                        .init(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
                    },
                    accessibilityLabel: definition.label,
                    help: definition.label
                )
            }
        case .themeFontFamily:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                InspectorPopup(selection: stringBinding(as: .choice), options: theme.fontFamilyChoices.map { .init(title: $0.label, value: $0.value) }, accessibilityLabel: definition.label, help: definition.label)
            }
        case .themeFontSize:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                InspectorPopup(selection: stringBinding(as: .choice), options: theme.fontSizeChoices.map { .init(title: $0.label, value: $0.value) }, accessibilityLabel: definition.label, help: definition.label)
            }
        case .packageFontSize(let themeValues):
            PackageThemeValueGridEditor(
                label: definition.label,
                choices: themeValues ? theme.fontSizeChoices : [],
                source: packageFontSizeSourceBinding,
                customValue: packageFontSizeCustomBinding,
                customLineHeight: packageFontSizeCustomLineHeightBinding,
                indicator: responsiveIndicator
            )
        case .packageSpacing(let kind, let range, let step):
            PackageSpacingControlEditor(
                label: definition.label,
                kind: kind,
                themeChoices: theme.spacingChoices,
                sources: (0..<4).map(spacingSourceBinding),
                customValues: (0..<4).map(packageSpacingCustomBinding),
                range: range,
                step: step,
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

    private var packageSpacingValue: ComponentPackageSpacingValue {
        if case .packageSpacing(let value) = displayComponent.propertyValue(definition.key) { return value }
        if case .packageSpacing(let value) = definition.defaultValue { return value }
        return .init(sources: Array(repeating: "none", count: 4), customValues: Array(repeating: 0, count: 4))
    }

    private func spacingSourceBinding(_ index: Int) -> Binding<String> {
        return Binding(
            get: { packageSpacingValue.sources.indices.contains(index) ? packageSpacingValue.sources[index] : "none" },
            set: { source in
                var value = packageSpacingValue
                while value.sources.count <= index { value.sources.append("none") }
                value.sources[index] = source
                setProperty(.packageSpacing(value))
            }
        )
    }

    private func packageSpacingCustomBinding(_ index: Int) -> Binding<Double> {
        return Binding(
            get: { packageSpacingValue.customValues.indices.contains(index) ? packageSpacingValue.customValues[index] : 0 },
            set: { customValue in
                var value = packageSpacingValue
                while value.customValues.count <= index { value.customValues.append(0) }
                value.customValues[index] = customValue
                setProperty(.packageSpacing(value))
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

struct ComponentLinkEditor: View {
    @Binding var link: ComponentLink
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let publicURL: String
    let absoluteURL: Bool
    var remove: (() -> Void)? = nil
    let cancel: () -> Void
    let apply: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Form {
                Picker("Type", selection: kindBinding) {
                    Text("URL").tag(LinkKind.url)
                    Text("Plain Text").tag(LinkKind.plainText)
                    Text("Page").tag(LinkKind.page)
                    Text("Resource").tag(LinkKind.resource)
                }
                destinationEditor
                TextField("Anchor", text: $link.anchor, prompt: Text("Optional anchor"))
                Toggle("Open in New Window", isOn: $link.opensInNewWindow)
                if absoluteURL && publicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isInternalLink {
                    Label("Set the Site URL in Project Settings to produce an absolute URL.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Section("Custom Attributes") {
                    ForEach($link.attributes) { $attribute in
                        HStack {
                            TextField("Name", text: $attribute.name)
                            TextField("Value", text: $attribute.value)
                            Button(role: .destructive) {
                                link.attributes.removeAll { $0.id == attribute.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Attribute", systemImage: "plus") {
                        link.attributes.append(.init())
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if let remove {
                    Button("Remove", role: .destructive, action: remove)
                }
                Spacer()
                Button("Cancel", action: cancel)
                Button("Set Link", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 680, height: 500)
    }

    @ViewBuilder
    private var destinationEditor: some View {
        switch link.destination {
        case .url(let value):
            TextField("URL", text: destinationTextBinding(value, kind: .url), prompt: Text("https://example.com"))
        case .plainText(let value):
            TextField("Text", text: destinationTextBinding(value, kind: .plainText))
        case .page(let id):
            Picker("Page", selection: destinationIDBinding(id, kind: .page)) {
                Text("Choose a page").tag(nil as UUID?)
                ForEach(pages) { page in Text(page.title).tag(page.id as UUID?) }
            }
        case .resource(let id):
            Picker("Resource", selection: destinationIDBinding(id, kind: .resource)) {
                Text("Choose a resource").tag(nil as UUID?)
                ForEach(assets) { asset in Text(asset.filename).tag(asset.id as UUID?) }
            }
        case .none:
            EmptyView()
        }
    }

    private var kindBinding: Binding<LinkKind> {
        Binding(get: {
            switch link.destination {
            case .url: .url
            case .plainText: .plainText
            case .page: .page
            case .resource: .resource
            case .none: .url
            }
        }, set: { kind in
            switch kind {
            case .url: link.destination = .url("")
            case .plainText: link.destination = .plainText("")
            case .page: link.destination = .page(pages.first?.id ?? UUID())
            case .resource: link.destination = .resource(assets.first?.id ?? UUID())
            }
        })
    }

    private func destinationTextBinding(_ value: String, kind: LinkKind) -> Binding<String> {
        Binding(get: {
            switch link.destination {
            case .url(let value), .plainText(let value): value
            default: value
            }
        }, set: { link.destination = kind == .url ? .url($0) : .plainText($0) })
    }

    private func destinationIDBinding(_ value: UUID, kind: LinkKind) -> Binding<UUID?> {
        Binding(get: {
            switch link.destination {
            case .page(let id), .resource(let id): id
            default: value
            }
        }, set: { id in
            guard let id else { link.destination = .none; return }
            link.destination = kind == .page ? .page(id) : .resource(id)
        })
    }

    private var isInternalLink: Bool {
        if case .page = link.destination { return true }
        if case .resource = link.destination { return true }
        return false
    }

    private var isValid: Bool {
        switch link.destination {
        case .none: false
        case .url(let value), .plainText(let value): !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .page(let id): pages.contains { $0.id == id }
        case .resource(let id): assets.contains { $0.id == id }
        }
    }

    private enum LinkKind: Hashable { case url, plainText, page, resource }
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
        case .asset:
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
    @Binding var customLineHeight: String
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

        if ComponentThemeValueSelection.isManualCustom(source, themeChoices: choices) || choices.isEmpty {
            InspectorRow(
                title: "Size",
                indicator: choices.isEmpty ? indicator : nil
            ) {
                InspectorTextField(text: $customValue, accessibilityLabel: "Size")
            }
            InspectorRow(title: "Line Height") {
                InspectorTextField(text: $customLineHeight, accessibilityLabel: "Line Height")
            }
        }
    }

    private var popupOptions: [InspectorPopupOption<String>] {
        choices.map {
            InspectorPopupOption(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
        } + [InspectorPopupOption(
            title: "Custom",
            value: ComponentThemeValueSelection.manualCustom,
            separatorBefore: !choices.isEmpty
        )]
    }
}

private struct PackageSpacingControlEditor: View {
    let label: String
    let kind: ComponentSpacingKind
    let themeChoices: [ComponentPropertyChoice]
    let sources: [Binding<String>]
    let customValues: [Binding<Double>]
    let range: ClosedRange<Double>
    let step: Double
    let indicator: InspectorRowIndicator

    private let sides = ["Top", "Right", "Bottom", "Left"]

    var body: some View {
        InspectorRow(title: label, alignment: .top, indicator: indicator) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    sideEditor(index)
                }
            }
        }
    }

    @ViewBuilder
    private func sideEditor(_ index: Int) -> some View {
        let source = sources[index]
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(sides[index])
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                InspectorPopup(
                    selection: source,
                    options: popupOptions(for: source.wrappedValue),
                    accessibilityLabel: "\(label) \(sides[index])",
                    help: "Choose theme or custom \(kind.rawValue) for the \(sides[index].lowercased()) side"
                )
            }
            if source.wrappedValue == "custom" {
                HStack(spacing: 4) {
                    Color.clear.frame(width: 44, height: 0)
                    InspectorNumberField(
                        value: customValues[index],
                        range: range,
                        step: step,
                        accessibilityLabel: "Custom \(label) \(sides[index])"
                    )
                    InspectorUnitLabel(unit: "px")
                    InspectorStepper(
                        value: customValues[index],
                        range: range,
                        increment: step,
                        accessibilityLabel: "Custom \(label) \(sides[index])"
                    )
                }
            }
        }
    }

    private func popupOptions(for source: String) -> [InspectorPopupOption<String>] {
        var options = themeChoices.map {
            InspectorPopupOption(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
        }
        options.append(.init(title: "None", value: "none", separatorBefore: !options.isEmpty))
        if kind.permitsAuto {
            options.append(.init(title: "Auto", value: "auto"))
        }
        options.append(.init(
            title: "Custom",
            value: ComponentThemeValueSelection.manualCustom,
            separatorBefore: true
        ))
        if !options.contains(where: { $0.value == source }) {
            options.insert(.init(title: "Missing Theme Spacing", value: source), at: 0)
        }
        return options
    }
}

private struct PackageColorControlEditor: View {
    let label: String
    let choices: [ComponentPropertyChoice]
    let theme: Theme
    @Binding var source: String
    @Binding var customColor: Color
    let adjustment: Binding<Double>?
    let allowsOpacity: Bool
    let indicator: InspectorRowIndicator

    var body: some View {
        Group {
            if !choices.isEmpty {
                InspectorRow(title: label, indicator: indicator) {
                    InspectorPopup(
                        selection: $source,
                        options: choices.map {
                            .init(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
                        } + [InspectorPopupOption(
                            title: "Custom",
                            value: ComponentThemeValueSelection.manualCustom,
                            separatorBefore: !choices.isEmpty
                        )],
                        accessibilityLabel: label,
                        help: label
                    )
                }
            }
            if ComponentThemeValueSelection.isManualCustom(source, themeChoices: choices) || choices.isEmpty {
                InspectorRow(
                    title: choices.isEmpty ? label : "Colour",
                    alignment: .center,
                    indicator: choices.isEmpty ? indicator : nil
                ) {
                    InspectorColorWell(color: $customColor, supportsAlpha: allowsOpacity)
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
