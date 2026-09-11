import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ThemeWindowRegistry {
    struct Context {
        let session: ThemeEditorSession
    }

    static let shared = ThemeWindowRegistry()

    private var contexts: [UUID: Context] = [:]

    func register(id: UUID, document: FoundryDocument, undoManager: UndoManager?) {
        if contexts[id]?.session.document === document { return }
        contexts[id] = Context(
            session: ThemeEditorSession(document: document, undoManager: undoManager)
        )
    }

    func context(for id: UUID) -> Context? {
        contexts[id]
    }

    func remove(id: UUID) {
        contexts.removeValue(forKey: id)
    }
}

struct ThemeWindowSceneContent: View {
    let presentationID: UUID?

    var body: some View {
        Group {
            if let presentationID,
               let context = ThemeWindowRegistry.shared.context(for: presentationID) {
                ThemeWindowContent(session: context.session)
                    .navigationTitle("\(context.session.document.site.name) – Theme")
            } else {
                ContentUnavailableView(
                    "Theme Unavailable",
                    systemImage: "theatermask.and.paintbrush",
                    description: Text("Open the theme editor from a project window.")
                )
            }
        }
        .background(WindowGeometryPersistence(key: "themeEditor.windowFrame"))
    }
}

private struct ThemeWindowContent: View {
    let session: ThemeEditorSession
    @ObservedObject private var document: FoundryDocument
    @AppStorage("themeEditor.selectedSection") private var selectedSectionRawValue = ThemeWindowSection.themes.rawValue
    @AppStorage("themeEditor.sidebarVisible") private var isSidebarVisible = true

    init(session: ThemeEditorSession) {
        self.session = session
        document = session.document
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            List(selection: selection) {
                Section("Project") {
                    ThemeSidebarRow(section: .themes)
                    ThemeSidebarRow(section: .screens)
                }
                Section("Theme Settings") {
                    ForEach(ThemeWindowSection.settings) { section in
                        ThemeSidebarRow(section: section)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            switch selectedSection {
            case .themes:
                ThemeLibraryBrowser(document: document, undoManager: session.editor.undoManager)
            default:
                ThemeSettingsDetail(
                    section: selectedSection,
                    theme: document.site.theme,
                    assets: document.site.assets,
                    session: session
                )
            }
        }
    }

    private var selectedSection: ThemeWindowSection {
        ThemeWindowSection(rawValue: selectedSectionRawValue) ?? .themes
    }

    private var selection: Binding<ThemeWindowSection> {
        Binding(
            get: { selectedSection },
            set: { selectedSectionRawValue = $0.rawValue }
        )
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isSidebarVisible ? .all : .detailOnly },
            set: { isSidebarVisible = $0 != .detailOnly }
        )
    }
}

private enum ThemeWindowSection: String, CaseIterable, Identifiable, Hashable {
    case themes
    case screens
    case colors
    case fontFamily
    case fontSize
    case spacing
    case shadows
    case borderWidth
    case borderRadius

    var id: String { rawValue }

    static let settings: [ThemeWindowSection] = [
        .colors,
        .fontFamily,
        .fontSize,
        .spacing,
        .shadows,
        .borderWidth,
        .borderRadius
    ]

    var title: String {
        switch self {
        case .themes: "Theme"
        case .screens: "Breakpoints"
        case .colors: "Colours"
        case .fontFamily: "Font Family"
        case .fontSize: "Type Scale"
        case .spacing: "Spacing"
        case .shadows: "Shadows"
        case .borderWidth: "Border Width"
        case .borderRadius: "Border Radius"
        }
    }

    var systemImage: String {
        switch self {
        case .themes: "theatermask.and.paintbrush"
        case .screens: "rectangle.on.rectangle"
        case .colors: "paintpalette"
        case .fontFamily: "text.alignleft"
        case .fontSize: "textformat.size"
        case .spacing: "arrow.left.and.right"
        case .shadows: "square.stack"
        case .borderWidth: "square"
        case .borderRadius: "circle"
        }
    }
}

private struct ThemeSidebarRow: View {
    let section: ThemeWindowSection

    var body: some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }
}

private struct ThemeSettingsDetail: View {
    let section: ThemeWindowSection
    let theme: Theme
    let assets: [ProjectAsset]
    let session: ThemeEditorSession
    @State private var selectedFontSizeID: String?
    @State private var fontSizePendingDeletion: ThemeFontSize?
    private var editor: ProjectEditor { session.editor }

    var body: some View {
        Group {
            if section == .screens {
                ThemeScreenSettings(screens: theme.screens, editor: editor)
            } else if section == .fontFamily {
                ThemeFontFamilyEditor(theme: theme, assets: assets, session: session)
            } else if section == .fontSize {
                fontSizeSettings
            } else if section == .spacing {
                ThemeSpacingSettings(spacing: theme.spacing, editor: editor)
            } else if section == .shadows {
                ThemeShadowSettings(shadows: theme.shadows, editor: editor)
            } else if section == .borderWidth {
                ThemeDimensionSettings(
                    title: "Border Width",
                    explanation: "Set the width represented by each theme border token.",
                    tokens: theme.borderWidths,
                    range: 0...20,
                    reset: editor.resetThemeBorderWidths,
                    setValue: editor.setThemeBorderWidth
                )
            } else if section == .borderRadius {
                ThemeDimensionSettings(
                    title: "Border Radius",
                    explanation: "Set the corner radius represented by each theme radius token.",
                    tokens: theme.borderRadii,
                    range: 0...100,
                    reset: editor.resetThemeBorderRadii,
                    setValue: editor.setThemeBorderRadius
                )
            } else {
                Form {
                    switch section {
                    case .screens:
                        EmptyView()
                    case .colors:
                        Section("Theme Colours") {
                            ForEach(DesignToken.colorTokens) { token in
                                ColorPicker(
                                    token.displayName,
                                    selection: colorBinding(for: token),
                                    supportsOpacity: false
                                )
                            }
                        }
                    case .spacing:
                        EmptyView()
                    case .shadows:
                        EmptyView()
                    case .borderWidth, .borderRadius:
                        EmptyView()
                    case .themes, .fontFamily, .fontSize:
                        EmptyView()
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(section.title)
        .confirmationDialog(
            "Choose a replacement for \(fontSizePendingDeletion?.title ?? "this custom size")",
            isPresented: fontSizeDeletionPresented,
            titleVisibility: .visible
        ) {
            ForEach(theme.typography.fontSizes.filter { $0.id != fontSizePendingDeletion?.id }) { replacement in
                Button("Replace with \(replacement.title)") {
                    guard let pending = fontSizePendingDeletion else { return }
                    editor.removeThemeFontSize(id: pending.id, replacingWith: replacement.id)
                    fontSizePendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { fontSizePendingDeletion = nil }
        } message: {
            Text("Foundry will update every component using this size before deleting it.")
        }
    }

    private var fontSizeSettings: some View {
        HStack(spacing: 0) {
            fontSizeStyleList
                .frame(width: 250)

            Divider()

            Group {
                if let selectedFontSize {
                    fontSizeEditor(
                        selectedFontSize,
                        isCustom: theme.typography.customFontSizes.contains { $0.id == selectedFontSize.id }
                    )
                } else {
                    ContentUnavailableView(
                        "Select a Size",
                        systemImage: "textformat.size",
                        description: Text("Choose a theme or custom size to edit its size and line height.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: selectInitialFontSizeIfNeeded)
        .onChange(of: theme.typography.fontSizes.map(\.id)) { _, _ in
            selectInitialFontSizeIfNeeded()
        }
    }

    private var fontSizeStyleList: some View {
        ScrollView {
            VStack(spacing: 0) {
                fontSizeListHeader("Custom Sizes") {
                    let id = editor.addThemeFontSize()
                    selectedFontSizeID = id
                }
                fontSizeRows(theme.typography.customFontSizes, allowsDeletion: true)

                fontSizeListHeader("Theme Scale") {
                    editor.resetThemeFontSizeScale()
                } actionLabel: {
                    Label("Reset Theme Scale", systemImage: "arrow.counterclockwise")
                }
                fontSizeRows(theme.typography.predefinedFontSizes, allowsDeletion: false)
            }
        }
        .background(.background)
    }

    private func fontSizeListHeader(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void,
        @ViewBuilder actionLabel: () -> some View = {
            Label("Add Custom Size", systemImage: "plus")
        }
    ) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Button(action: action, label: actionLabel)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func fontSizeRows(
        _ tokens: [ThemeFontSize],
        allowsDeletion: Bool
    ) -> some View {
        ForEach(tokens) { token in
            HStack(spacing: 4) {
                Button {
                    selectedFontSizeID = token.id
                } label: {
                    Text(token.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if allowsDeletion {
                    Button(role: .destructive) {
                        fontSizePendingDeletion = token
                    } label: {
                        Label("Delete Custom Size", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 38)
            .background(
                selectedFontSizeID == token.id ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(selectedFontSizeID == token.id ? .white : .primary)
            .padding(.horizontal, 8)

            Divider()
                .padding(.leading, 14)
        }
    }

    private var selectedFontSize: ThemeFontSize? {
        guard let selectedFontSizeID else { return nil }
        return theme.typography.fontSizes.first { $0.id == selectedFontSizeID }
    }

    private var fontSizeDeletionPresented: Binding<Bool> {
        Binding(
            get: { fontSizePendingDeletion != nil },
            set: { if !$0 { fontSizePendingDeletion = nil } }
        )
    }

    private func selectInitialFontSizeIfNeeded() {
        guard theme.typography.fontSizes.contains(where: { $0.id == selectedFontSizeID }) == false else { return }
        selectedFontSizeID = theme.typography.customFontSizes.first?.id
            ?? theme.typography.predefinedFontSizes.first?.id
    }

    private func colorBinding(for token: DesignToken) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme.color(for: token) ?? "#FFFFFF") ?? .white },
            set: { editor.setThemeColor(token, value: $0.hexString ?? "#FFFFFF") }
        )
    }

    private func pixelSizeBinding(for id: String) -> Binding<Double> {
        Binding(
            get: {
                let rem = theme.typography.fontSizes.first(where: { $0.id == id })?.size ?? 1
                return rem * TypographyTokens.rootSize
            },
            set: { pixels in
                editor.setThemeFontSize(
                    id: id,
                    value: pixels / TypographyTokens.rootSize
                )
            }
        )
    }

    private func fontSizeTitleBinding(for id: String) -> Binding<String> {
        Binding(
            get: { theme.typography.fontSizes.first(where: { $0.id == id })?.title ?? "" },
            set: { editor.setThemeFontSizeTitle(id: id, value: $0) }
        )
    }

    private func fontSizeLineHeightBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { theme.typography.fontSizes.first(where: { $0.id == id })?.lineHeight ?? 1.5 },
            set: { editor.setThemeFontSizeLineHeight(id: id, value: $0) }
        )
    }

    @ViewBuilder
    private func fontSizeEditor(_ token: ThemeFontSize, isCustom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: fontSizeEditorColumns, alignment: .leading, spacing: 16) {
                fontSizeGridLabel("Name")
                Group {
                    if isCustom {
                        TextField("Size Name", text: fontSizeTitleBinding(for: token.id))
                            .frame(maxWidth: 200)
                    } else {
                        Text(token.title)
                            .frame(maxWidth: 200, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(height: 1)

                fontSizeGridLabel("Size")
                Slider(value: pixelSizeBinding(for: token.id), in: 8...160, step: 1)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    TextField(
                        "Pixels",
                        value: pixelSizeBinding(for: token.id),
                        format: .number.precision(.fractionLength(0))
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 82)
                    Text("px · \(token.size.formatted(.number.precision(.fractionLength(0...3)))) rem")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                fontSizeGridLabel("Line Height")
                Slider(
                    value: fontSizeLineHeightBinding(for: token.id),
                    in: 0.8...2.5,
                    step: 0.01
                )
                .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    TextField(
                        "Multiplier",
                        value: fontSizeLineHeightBinding(for: token.id),
                        format: .number.precision(.fractionLength(0...3))
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 82)
                    Text("× · \(lineHeightPixels(for: token).formatted(.number.precision(.fractionLength(0...1)))) px")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 42)

            Spacer(minLength: 24)
        }
    }

    private var fontSizeEditorColumns: [GridItem] {
        [
            GridItem(.fixed(92), spacing: 14, alignment: .trailing),
            GridItem(.flexible(minimum: 0), spacing: 14, alignment: .leading),
            GridItem(.fixed(205), spacing: 0, alignment: .leading)
        ]
    }

    private func fontSizeGridLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .frame(width: 92, alignment: .trailing)
    }

    private func lineHeightPixels(for token: ThemeFontSize) -> Double {
        token.size * TypographyTokens.rootSize * token.lineHeight
    }
}

private struct ThemeDimensionSettings: View {
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    let tokens: ThemeDimensionTokens
    let range: ClosedRange<Double>
    let reset: () -> Void
    let setValue: (String, Double) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ThemeSettingsHeader(
                    title: title,
                    explanation: explanation,
                    reset: reset
                )

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    ForEach(tokens.predefined) { token in
                        GridRow {
                            Text(token.title)
                                .frame(width: 64, alignment: .trailing)
                            Slider(value: valueBinding(for: token), in: range, step: 0.5)
                            TextField(
                                "Pixels",
                                value: valueBinding(for: token),
                                format: .number.precision(.fractionLength(0...1))
                            )
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 76)
                            Text("px")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 720)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }

    private func valueBinding(for token: ThemeDimensionToken) -> Binding<Double> {
        Binding(
            get: { token.value },
            set: { setValue(token.id, $0) }
        )
    }
}

private struct ThemeSettingsHeader: View {
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    let reset: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                Text(explanation)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
        }
    }
}

private struct ThemeShadowSettings: View {
    let shadows: ShadowTokens
    let editor: ProjectEditor
    @State private var selectedShadowID: String?
    @State private var shadowPendingDeletion: ThemeShadow?

    var body: some View {
        HStack(spacing: 0) {
            shadowList
                .frame(width: 250)
            Divider()
            Group {
                if let selectedShadow {
                    ThemeShadowEditor(
                        shadow: selectedShadow,
                        isCustom: shadows.custom.contains { $0.id == selectedShadow.id },
                        editor: editor
                    )
                } else {
                    ContentUnavailableView(
                        "Select a Shadow",
                        systemImage: "square.stack",
                        description: Text("Choose a theme or custom shadow to edit it.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: selectInitialShadowIfNeeded)
        .onChange(of: shadows.shadows.map(\.id)) { _, _ in selectInitialShadowIfNeeded() }
        .confirmationDialog(
            "Choose a replacement for \(shadowPendingDeletion?.title ?? "this custom shadow")",
            isPresented: shadowDeletionPresented,
            titleVisibility: .visible
        ) {
            ForEach(shadows.shadows.filter { $0.id != shadowPendingDeletion?.id }) { replacement in
                Button("Replace with \(replacement.title)") {
                    guard let pending = shadowPendingDeletion else { return }
                    editor.removeThemeShadow(id: pending.id, replacingWith: replacement.id)
                    shadowPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { shadowPendingDeletion = nil }
        } message: {
            Text("Foundry will update every component using this shadow before deleting it.")
        }
    }

    private var shadowList: some View {
        ScrollView {
            VStack(spacing: 0) {
                listHeader("Custom Shadows") {
                    selectedShadowID = editor.addThemeShadow()
                } label: {
                    Label("Add Custom Shadow", systemImage: "plus")
                }
                rows(shadows.custom, allowsDeletion: true)

                listHeader("Theme Shadows") {
                    editor.resetThemeShadowScale()
                } label: {
                    Label("Reset Theme Shadows", systemImage: "arrow.counterclockwise")
                }
                rows(shadows.predefined, allowsDeletion: false)
            }
        }
        .background(.background)
    }

    private func listHeader(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(action: action, label: label)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func rows(_ values: [ThemeShadow], allowsDeletion: Bool) -> some View {
        ForEach(values) { shadow in
            HStack(spacing: 6) {
                Button {
                    selectedShadowID = shadow.id
                } label: {
                    HStack {
                        Text(shadow.title)
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if allowsDeletion {
                    Button("Delete Custom Shadow", systemImage: "trash", role: .destructive) {
                        shadowPendingDeletion = shadow
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(
                selectedShadowID == shadow.id ? Color.accentColor : Color.clear,
                in: .rect(cornerRadius: 7)
            )
            .foregroundStyle(selectedShadowID == shadow.id ? .white : .primary)
            .padding(.horizontal, 8)
            Divider().padding(.leading, 14)
        }
    }

    private var selectedShadow: ThemeShadow? {
        shadows.shadows.first { $0.id == selectedShadowID }
    }

    private var shadowDeletionPresented: Binding<Bool> {
        Binding(
            get: { shadowPendingDeletion != nil },
            set: { if !$0 { shadowPendingDeletion = nil } }
        )
    }

    private func selectInitialShadowIfNeeded() {
        guard shadows.shadows.contains(where: { $0.id == selectedShadowID }) == false else { return }
        selectedShadowID = shadows.custom.first?.id
            ?? shadows.predefined.first(where: { $0.id == "sm" })?.id
            ?? shadows.predefined.first?.id
    }
}

private struct ThemeShadowEditor: View {
    let shadow: ThemeShadow
    let isCustom: Bool
    let editor: ProjectEditor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Name")
                    if isCustom {
                        TextField("Shadow Name", text: titleBinding)
                            .frame(maxWidth: 220)
                    } else {
                        Text(shadow.title)
                    }
                    Spacer()
                }

                ShadowControl(layers: layersBinding, presentation: .expanded)
                    .frame(maxWidth: .infinity)
            }
            .padding(32)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { shadow.title },
            set: { editor.setThemeShadowTitle(id: shadow.id, value: $0) }
        )
    }

    private var layersBinding: Binding<[ThemeShadowLayer]> {
        Binding(
            get: { shadow.layers },
            set: { editor.setThemeShadowLayers(shadowID: shadow.id, layers: $0) }
        )
    }
}

private struct ThemeScreenSettings: View {
    let screens: ScreenTokens
    let editor: ProjectEditor

    var body: some View {
        List {
            Section {
                ForEach(ThemeScreenID.allCases) { id in
                    ThemeScreenRow(screen: screens.screen(id), editor: editor)
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Responsive Breakpoints")
                        .font(.headline)
                    Text("Define when responsive layouts activate and how wide theme containers can grow.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .padding(.bottom, 8)
            }
        }
        .listStyle(.inset)
    }
}

private struct ThemeScreenRow: View {
    let screen: ThemeScreen
    let editor: ProjectEditor

    var body: some View {
        HStack(spacing: 16) {
            Text(screen.id.shortTitle)
                .font(.headline)
                .frame(width: 58, alignment: .trailing)

            Image(systemName: screen.id.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            if screen.id == .mobile {
                Text("Below \(ThemeScreenID.small.shortTitle)")
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    TextField("Breakpoint", value: minimumWidthBinding, format: .number.precision(.fractionLength(0...2)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("px")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 150, alignment: .leading)
                .disabled(!screen.isEnabled)
            }

            Text("Container")
                .font(.headline)

            HStack(spacing: 6) {
                TextField("Width", value: containerWidthBinding, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .disabled(screen.container.unit == .auto)

                Text(containerSuffix)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)

                Picker("Container Unit", selection: containerUnitBinding) {
                    ForEach(ThemeContainerUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }
            .disabled(!screen.isEnabled)

            Spacer()

            if screen.id != .mobile {
                Toggle("Enable \(screen.id.shortTitle)", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .controlSize(.large)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { screen.isEnabled },
            set: { editor.setThemeScreenEnabled(screen.id, value: $0) }
        )
    }

    private var minimumWidthBinding: Binding<Double> {
        Binding(
            get: { screen.minimumWidth },
            set: { editor.setThemeScreenMinimumWidth(screen.id, value: $0) }
        )
    }

    private var containerWidthBinding: Binding<Double> {
        Binding(
            get: { screen.container.unit == .auto ? screen.minimumWidth : screen.container.value },
            set: { editor.setThemeScreenContainerWidth(screen.id, value: $0) }
        )
    }

    private var containerUnitBinding: Binding<ThemeContainerUnit> {
        Binding(
            get: { screen.container.unit },
            set: { editor.setThemeScreenContainerUnit(screen.id, value: $0) }
        )
    }

    private var containerSuffix: String {
        switch screen.container.unit {
        case .auto, .pixels: "px"
        case .viewportWidth: "vw"
        case .percent: "%"
        }
    }
}

private struct ThemeSpacingSettings: View {
    let spacing: SpacingTokens
    let editor: ProjectEditor

    var body: some View {
        List {
            Section {
                ThemePredefinedSpacingRow(token: .threeExtraSmallSpacing, value: spacing.threeExtraSmall, editor: editor)
                ThemePredefinedSpacingRow(token: .doubleExtraSmallSpacing, value: spacing.doubleExtraSmall, editor: editor)
                ThemePredefinedSpacingRow(token: .extraSmallSpacing, value: spacing.extraSmall, editor: editor)
                ThemePredefinedSpacingRow(token: .smallSpacing, value: spacing.small, editor: editor)
                ThemePredefinedSpacingRow(token: .mediumSpacing, value: spacing.medium, editor: editor)
                ThemePredefinedSpacingRow(token: .largeSpacing, value: spacing.large, editor: editor)
                ThemePredefinedSpacingRow(token: .extraLargeSpacing, value: spacing.extraLarge, editor: editor)
                ThemePredefinedSpacingRow(token: .doubleExtraLargeSpacing, value: spacing.doubleExtraLarge, editor: editor)
                ThemePredefinedSpacingRow(token: .threeExtraLargeSpacing, value: spacing.threeExtraLarge, editor: editor)
            } header: {
                HStack {
                    Text("Predefined Scale")
                    Spacer()
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        editor.resetThemeSpacingScale()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Reset Predefined Spacing Scale")
                }
            }

            Section {
                ForEach(spacing.custom) { token in
                    ThemeCustomSpacingRow(
                        token: token,
                        replacements: spacingReplacementChoices(excluding: token.id),
                        editor: editor
                    )
                }
            } header: {
                HStack {
                    Text("Custom Values")
                    Spacer()
                    Button("Add Spacing", systemImage: "plus") {
                        editor.addThemeSpacing()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Add Custom Spacing")
                }
            } footer: {
                if spacing.custom.isEmpty {
                    Text("Add project-specific spacing values to extend the predefined scale.")
                }
            }
        }
        .listStyle(.inset)
    }

    private func spacingReplacementChoices(excluding id: UUID) -> [ComponentPropertyChoice] {
        let standardIDs = ["3xs", "2xs", "xs", "sm", "md", "lg", "xl", "2xl", "3xl"]
        let standard = zip(standardIDs, DesignToken.spacingTokens).map {
            ComponentPropertyChoice(value: $0.0, label: $0.1.displayName)
        }
        return standard + spacing.custom.filter { $0.id != id }.map {
            ComponentPropertyChoice(
                value: "custom:\($0.id.uuidString.lowercased())",
                label: $0.name
            )
        }
    }
}

private struct ThemePredefinedSpacingRow: View {
    let token: DesignToken
    let value: Double
    let editor: ProjectEditor

    var body: some View {
        ThemeSpacingValueRow(
            name: token.displayName,
            value: binding,
            accessibilityLabel: "\(token.displayName) Spacing"
        )
    }

    private var binding: Binding<Double> {
        Binding(
            get: { value },
            set: { editor.setThemeSpacing(token, value: $0) }
        )
    }
}

private struct ThemeCustomSpacingRow: View {
    let token: ThemeSpacing
    let replacements: [ComponentPropertyChoice]
    let editor: ProjectEditor
    @State private var isChoosingReplacement = false

    var body: some View {
        HStack(spacing: 12) {
            TextField("Spacing Name", text: nameBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            ThemeSpacingValueRow(
                name: nil,
                value: valueBinding,
                accessibilityLabel: token.name
            )
            Button("Delete Spacing", systemImage: "trash", role: .destructive) {
                isChoosingReplacement = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Delete Custom Spacing")
        }
        .confirmationDialog(
            "Choose a replacement for \(token.name)",
            isPresented: $isChoosingReplacement,
            titleVisibility: .visible
        ) {
            ForEach(replacements) { replacement in
                Button("Replace with \(replacement.label)") {
                    editor.removeThemeSpacing(id: token.id, replacingWith: replacement.value)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Foundry will update every component using this spacing before deleting it.")
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { token.name },
            set: { editor.setThemeSpacingName(id: token.id, value: $0) }
        )
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { token.value },
            set: { editor.setThemeSpacingValue(id: token.id, value: $0) }
        )
    }
}

private struct ThemeSpacingValueRow: View {
    let name: String?
    @Binding var value: Double
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 12) {
            if let name {
                Text(name)
                    .frame(width: 82, alignment: .leading)
                    .lineLimit(1)
            }
            Slider(value: $value, in: 0...40, step: 0.5)
                .frame(minWidth: 140)
                .accessibilityLabel(accessibilityLabel)
            TextField(
                accessibilityLabel,
                value: $value,
                format: .number.precision(.fractionLength(0...2))
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
            Text("×")
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .leading)
            Text("\(value * SpacingTokens.baseRem, format: .number.precision(.fractionLength(0...3))) rem · \(value * 4, format: .number.precision(.fractionLength(0...1))) px")
                .foregroundStyle(.secondary)
                .frame(width: 124, alignment: .leading)
        }
    }
}

private struct ThemeFontFamilyEditor: View {
    let theme: Theme
    let assets: [ProjectAsset]
    let session: ThemeEditorSession
    @State private var selection: ThemeFontReference = .role(.body)
    @State private var fontPendingDeletion: ThemeCustomFont?
    @AppStorage("themeEditor.fontAssignmentRatio") private var assignmentRatio = 0.28

    private var editor: ProjectEditor { session.editor }

    var body: some View {
        ProportionalSplitView(
            leadingRatio: $assignmentRatio,
            minimumLeadingWidth: 180,
            minimumTrailingWidth: 520
        ) {
            themeFontSidebar
        } trailing: {
            ThemeFontDefinitionEditor(
                title: selectionTitle,
                definition: definition(for: selection),
                reference: selection,
                assets: assets,
                name: customNameBinding,
                session: session
            )
        }
        .onChange(of: selection) {
            session.discardFontPreview()
        }
        .onDisappear {
            session.discardFontPreview()
        }
        .confirmationDialog(
            "Choose a replacement for \(fontPendingDeletion?.name ?? "this custom font")",
            isPresented: fontDeletionPresented,
            titleVisibility: .visible
        ) {
            ForEach(fontReplacementChoices) { replacement in
                Button("Replace with \(replacement.label)") {
                    guard let pending = fontPendingDeletion else { return }
                    editor.removeThemeCustomFont(id: pending.id, replacingWith: replacement.value)
                    selection = .role(.body)
                    fontPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { fontPendingDeletion = nil }
        } message: {
            Text("Foundry will update every component using this font before deleting it.")
        }
    }

    private var themeFontSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Fonts")
                    .font(.headline)
                Spacer()
                Button {
                    selection = .custom(editor.addThemeCustomFont())
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Custom Font")
            }
            .padding(12)

            Divider()

            List(selection: $selection) {
                ForEach(theme.typography.customFonts) { font in
                    Text(font.name)
                        .tag(ThemeFontReference.custom(font.id))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                fontPendingDeletion = font
                            }
                        }
                }
                Section("Theme Fonts") {
                    ForEach(ThemeFontRole.allCases) { role in
                        Text(role.rawValue)
                            .tag(ThemeFontReference.role(role))
                    }
                }
            }
            .listStyle(.inset)
        }
        .background(.background)
    }

    private var selectionTitle: String {
        guard case .role(let role) = selection else { return "Custom Font" }
        return role.title
    }

    private var fontReplacementChoices: [ComponentPropertyChoice] {
        let pendingReference = fontPendingDeletion.map { "custom:\($0.id.uuidString.lowercased())" }
        return theme.fontFamilyChoices.filter { $0.value != pendingReference }
    }

    private var fontDeletionPresented: Binding<Bool> {
        Binding(
            get: { fontPendingDeletion != nil },
            set: { if !$0 { fontPendingDeletion = nil } }
        )
    }

    private func definition(for reference: ThemeFontReference) -> ThemeFontDefinition {
        session.font(for: reference)
    }

    private var customNameBinding: Binding<String>? {
        guard case .custom(let id) = selection else { return nil }
        return Binding(
            get: { theme.typography.customFonts.first(where: { $0.id == id })?.name ?? "" },
            set: { editor.setThemeCustomFontName(id: id, value: $0) }
        )
    }
}

private struct ThemeFontDefinitionEditor: View {
    let title: String
    let definition: ThemeFontDefinition
    let reference: ThemeFontReference
    let assets: [ProjectAsset]
    let name: Binding<String>?
    let session: ThemeEditorSession
    @State private var googleFonts = GoogleFontsService.fallback
    @State private var search = ""
    @State private var category = GoogleFontCategory.all
    @State private var isLoadingGoogleFonts = false
    @State private var googleFontsError: String?
    @State private var googleFontsReloadID = 0
    @State private var selectedGoogleFamily: String?
    @State private var isFontDropTargeted = false
    @FocusState private var isSearchFocused: Bool
    @AppStorage("themeEditor.googleBrowserRatio") private var googleBrowserRatio = 0.46

    private var editor: ProjectEditor { session.editor }

    var body: some View {
        VStack(spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Name")
                        .font(.headline)
                    if let name {
                        TextField("Name", text: name)
                    } else {
                        TextField("Name", text: .constant(title.lowercased()))
                            .disabled(true)
                    }
                }
                GridRow {
                    Text("Kind")
                        .font(.headline)
                    Picker("Kind", selection: sourceKindBinding) {
                        ForEach(ThemeFontSourceKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden()
                }
            }
            .controlSize(.large)
            .frame(maxWidth: 560, alignment: .leading)
            .padding(32)

            Divider()

            Group {
                switch definition.source {
                case .system:
                    fontNamesEditor
                case .remote:
                    googleFontEditor
                case .bundled(let files):
                    fontResourcesEditor(files: files)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: googleFontsReloadID) {
            await loadGoogleFonts()
        }
        .onAppear {
            selectedGoogleFamily = definition.family
        }
        .onChange(of: selectedGoogleFamily) { _, family in
            guard let family, family != definition.family else { return }
            session.previewGoogleFont(family, for: reference)
        }
    }

    private var fontNamesEditor: some View {
        Grid(alignment: .leading, horizontalSpacing: 14) {
            GridRow(alignment: .firstTextBaseline) {
                Text("Font Names")
                    .font(.headline)
                TextField("system-ui, sans-serif", text: fontNamesBinding)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var googleFontEditor: some View {
        ProportionalSplitView(
            leadingRatio: $googleBrowserRatio,
            minimumLeadingWidth: 260,
            minimumTrailingWidth: 300
        ) {
            googleFontBrowserColumn
        } trailing: {
            VStack(spacing: 0) {
                GoogleFontSpecimenView(
                    family: definition.family,
                    stylesheetURL: googleStylesheetURL
                )

                Divider()

                HStack {
                    Button("Cancel") {
                        session.discardFontPreview()
                    }
                    .disabled(!session.hasUncommittedFontPreview)

                    Spacer()

                    Button("Use Font") {
                        session.commitFontPreview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.hasUncommittedFontPreview)
                }
                .padding(16)
            }
        }
    }

    private var googleFontBrowserColumn: some View {
        VStack(spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow(alignment: .firstTextBaseline) {
                    Text("Search")
                        .font(.headline)
                    TextField("Search", text: $search)
                        .focused($isSearchFocused)
                        .onSubmit {
                            selectedGoogleFamily = filteredGoogleFonts.first?.family
                        }
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("Category")
                        .font(.headline)
                    Picker("Category", selection: $category) {
                        ForEach(GoogleFontCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(32)

            Divider()

            if isLoadingGoogleFonts {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading Google Fonts…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if let googleFontsError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(googleFontsError)
                        .lineLimit(2)
                    Spacer()
                    Button("Retry") {
                        googleFontsReloadID += 1
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            googleFontList
        }
    }

    private var googleFontList: some View {
        List(filteredGoogleFonts, selection: $selectedGoogleFamily) { font in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(font.family)
                        .font(.title3.weight(.semibold))
                    Text("\(font.styleCount) style\(font.styleCount == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if definition.family == font.family {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Current preview")
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .tag(font.family)
            .accessibilityElement(children: .combine)
        }
        .listStyle(.inset)
    }

    private var googleStylesheetURL: URL? {
        guard case .remote(let stylesheetURL) = definition.source else { return nil }
        return stylesheetURL
    }

    private func fontResourcesEditor(files: [String]) -> some View {
        let selectedAssets = files.compactMap { reference in
            assets.first(where: { $0.id == reference.foundryAssetID })
        }
        let availableAssets = assets.filter { asset in
            asset.isFontResource && !files.contains(asset.reference)
        }
        return VStack(spacing: 0) {
            HStack {
                Text("Font Resources")
                    .font(.headline)
                Spacer()
                Menu("Add Font Resource", systemImage: "plus") {
                    ForEach(availableAssets) { asset in
                        Button(asset.filename) {
                            addFontResource(asset, to: files)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(availableAssets.isEmpty)
                .help(availableAssets.isEmpty
                      ? "Add a font file to Project Resources first"
                      : "Add a font from Project Resources")
            }
            .padding(16)

            Divider()

            if selectedAssets.isEmpty {
                ContentUnavailableView(
                    "No Font Resources",
                    systemImage: "textformat",
                    description: Text("Add a font from Project Resources, or drag a font resource here.")
                )
            } else {
                List(selectedAssets) { asset in
                    HStack {
                        Image(systemName: "textformat")
                        Text(asset.filename)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            editor.setThemeFontResources(
                                files.filter { $0.foundryAssetID != asset.id },
                                reference: reference
                            )
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $isFontDropTargeted) { providers in
            acceptFontProviders(providers)
        }
        .overlay {
            if isFontDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.tint, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private func addFontResource(_ asset: ProjectAsset, to files: [String]) {
        editor.setThemeFontResources(files + [asset.reference], reference: reference)
        if files.isEmpty {
            editor.setThemeFontFamily(
                (asset.filename as NSString).deletingPathExtension,
                reference: reference
            )
        }
    }

    private func importFontData(_ data: Data, filename: String) {
        let fontExtensions = Set(["otf", "ttf", "woff", "woff2"])
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        guard fontExtensions.contains(pathExtension) else { return }

        let undoManager = editor.undoManager
        undoManager?.beginUndoGrouping()
        defer {
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Import Font Resources")
        }

        let type = UTType(filenameExtension: pathExtension)
        let id = session.document.importAsset(
            data: data,
            filename: filename,
            mediaType: type?.preferredMIMEType ?? "application/octet-stream",
            undoManager: undoManager
        )
        let existingFiles = currentBundledFiles
        editor.setThemeFontResources(existingFiles + ["foundry-asset:\(id.uuidString)"], reference: reference)
        if existingFiles.isEmpty {
            editor.setThemeFontFamily(
                (filename as NSString).deletingPathExtension,
                reference: reference
            )
        }
    }

    private func acceptFontProviders(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    guard let data = try? Data(contentsOf: url) else { return }
                    let filename = Self.preferredFilename(provider.suggestedName, sourceURL: url)
                    Task { @MainActor in
                        importFontData(data, filename: filename)
                    }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                accepted = true
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    guard let value, let id = Self.assetID(from: value) else { return }
                Task { @MainActor in
                        guard let asset = assets.first(where: { $0.id == id && $0.isFontResource }) else { return }
                        addFontResource(asset, to: currentBundledFiles)
                    }
                }
            }
        }
        return accepted
    }

    nonisolated private static func preferredFilename(_ suggestedName: String?, sourceURL: URL) -> String {
        guard let suggestedName, !suggestedName.isEmpty else { return sourceURL.lastPathComponent }
        if !(suggestedName as NSString).pathExtension.isEmpty { return suggestedName }
        let pathExtension = sourceURL.pathExtension
        return pathExtension.isEmpty ? suggestedName : "\(suggestedName).\(pathExtension)"
    }

    private var currentBundledFiles: [String] {
        guard case .bundled(let files) = session.font(for: reference).source else { return [] }
        return files
    }

    private var fontNamesBinding: Binding<String> {
        Binding(
            get: { definition.cssFamily },
            set: { editor.setThemeFontNames($0, reference: reference) }
        )
    }

    private var sourceKindBinding: Binding<ThemeFontSourceKind> {
        Binding(
            get: { ThemeFontSourceKind(definition.source) },
            set: { kind in
                switch kind {
                case .system: editor.restoreThemeFontNames(reference: reference)
                case .bundled: editor.setThemeFontSource(.bundled(files: []), reference: reference)
                case .remote:
                    let initialFamily = GoogleFontsService.fallback.first?.family ?? "ABeeZee"
                    editor.setThemeGoogleFont(initialFamily, reference: reference)
                }
            }
        )
    }

    private var filteredGoogleFonts: [GoogleFontFamily] {
        googleFonts.filter { font in
            (search.isEmpty || font.family.localizedCaseInsensitiveContains(search)) &&
                category.includes(font.category)
        }
    }

    private func loadGoogleFonts() async {
        isLoadingGoogleFonts = true
        googleFontsError = nil
        defer { isLoadingGoogleFonts = false }
        do {
            googleFonts = try await GoogleFontsService.shared.families()
        } catch is CancellationError {
            return
        } catch {
            googleFontsError = "The complete catalogue is unavailable. Showing a limited offline list."
        }
    }

    nonisolated private static func assetID(from value: String) -> UUID? {
        if let id = value.foundryAssetID { return id }
        let prefixes = ["foundry-asset-node:", "foundry-image-asset:"]
        guard let prefix = prefixes.first(where: value.hasPrefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }
}

private extension ProjectAsset {
    var isFontResource: Bool {
        let fontExtensions = Set(["otf", "ttf", "woff", "woff2"])
        return fontExtensions.contains((filename as NSString).pathExtension.lowercased()) ||
            mediaType.lowercased().contains("font")
    }
}

private enum ThemeFontSourceKind: String, CaseIterable, Identifiable {
    case system
    case bundled
    case remote

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Font Names"
        case .remote: "Google Font"
        case .bundled: "Font Resources"
        }
    }

    init(_ source: ThemeFontSource) {
        switch source {
        case .system: self = .system
        case .bundled: self = .bundled
        case .remote: self = .remote
        }
    }
}

private struct ThemeLibraryBrowser: View {
    @ObservedObject var document: FoundryDocument
    let undoManager: UndoManager?
    @State private var library = ThemeLibrary.shared
    @State private var isCreatingTheme = false
    @State private var selectedThemeID: UUID?
    @State private var themePendingUpdate: SavedTheme?
    @State private var themePendingDeletion: SavedTheme?
    @State private var errorMessage: String?
    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            ThemeLibraryToolbar()
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(library.themes) { savedTheme in
                        ThemeLibraryItem(
                            savedTheme: savedTheme,
                            isSelected: selectedThemeID == savedTheme.id,
                            isModified: selectedThemeID == savedTheme.id && savedTheme.theme != document.site.theme,
                            createTheme: { isCreatingTheme = true },
                            importTheme: importTheme
                        ) {
                            selectTheme(savedTheme)
                        } reset: {
                            resetTheme(savedTheme)
                        } update: {
                            themePendingUpdate = savedTheme
                        } export: {
                            exportTheme(savedTheme)
                        } delete: {
                            themePendingDeletion = savedTheme
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Themes")
        .onAppear {
            library.reload()
            selectedThemeID = document.site.themeSourceID
        }
        .sheet(isPresented: $isCreatingTheme) {
            ThemeCreationSheet { name, preview in
                let savedTheme = try library.create(
                    name: name,
                    from: document.site.theme,
                    preview: preview,
                    assetContents: document.assetContents
                )
                ProjectEditor(document: document, undoManager: undoManager).commitTheme(
                    savedTheme.theme,
                    sourceID: savedTheme.id
                )
                selectedThemeID = savedTheme.id
            }
        }
        .confirmationDialog(
            "Update \(themePendingUpdate?.metadata.name ?? "Theme")?",
            isPresented: updateConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Update Theme") {
                updatePendingTheme()
            }
            Button("Cancel", role: .cancel) {
                themePendingUpdate = nil
            }
        } message: {
            Text("Replace this theme’s saved settings with the current project theme? Its title and preview image will be kept.")
        }
        .confirmationDialog(
            "Delete \(themePendingDeletion?.metadata.name ?? "Theme")?",
            isPresented: themeDeletionConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Theme", role: .destructive) {
                guard let theme = themePendingDeletion else { return }
                deleteTheme(theme)
                themePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { themePendingDeletion = nil }
        } message: {
            Text("This removes the saved theme from your library. Projects already using it keep their current theme values.")
        }
        .alert("Theme Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The theme operation could not be completed.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var updateConfirmationBinding: Binding<Bool> {
        Binding(
            get: { themePendingUpdate != nil },
            set: { if !$0 { themePendingUpdate = nil } }
        )
    }

    private var themeDeletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { themePendingDeletion != nil },
            set: { if !$0 { themePendingDeletion = nil } }
        )
    }

    private func updatePendingTheme() {
        guard let savedTheme = themePendingUpdate else { return }
        defer { themePendingUpdate = nil }
        do {
            let updated = try library.update(
                savedTheme,
                from: document.site.theme,
                assetContents: document.assetContents
            )
            ProjectEditor(document: document, undoManager: undoManager).commitTheme(
                updated.theme,
                sourceID: updated.id
            )
            selectedThemeID = updated.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.foundryTheme]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try library.install(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectTheme(_ savedTheme: SavedTheme) {
        let theme = projectTheme(from: savedTheme)
        ProjectEditor(document: document, undoManager: undoManager).selectTheme(theme, sourceID: savedTheme.id)
        selectedThemeID = savedTheme.id
    }

    private func resetTheme(_ savedTheme: SavedTheme) {
        let theme = projectTheme(from: savedTheme)
        ProjectEditor(document: document, undoManager: undoManager).resetTheme(theme, sourceID: savedTheme.id)
        selectedThemeID = savedTheme.id
    }

    private func projectTheme(from savedTheme: SavedTheme) -> Theme {
        var assetMapping: [UUID: UUID] = [:]
        for content in savedTheme.resources {
            let newID = document.importAsset(
                data: content.data,
                filename: content.asset.filename,
                mediaType: content.asset.mediaType,
                undoManager: undoManager
            )
            assetMapping[content.asset.id] = newID
        }
        return savedTheme.theme.remappingBundledFontAssets(assetMapping)
    }

    private func exportTheme(_ savedTheme: SavedTheme) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.foundryTheme]
        panel.nameFieldStringValue = "\(savedTheme.metadata.name).foundrytheme"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: savedTheme.bundleURL, to: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTheme(_ savedTheme: SavedTheme) {
        do {
            try library.remove(savedTheme)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

private struct ThemeLibraryToolbar: View {
    var body: some View {
        HStack {
            Text("Theme Library")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

private struct ThemeLibraryItem: View {
    let savedTheme: SavedTheme
    let isSelected: Bool
    let isModified: Bool
    let createTheme: () -> Void
    let importTheme: () -> Void
    let apply: () -> Void
    let reset: () -> Void
    let update: () -> Void
    let export: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: apply) {
                ThemeCardPreview(imageURL: savedTheme.previewURL, isSelected: isSelected, isModified: isModified)
            }
            .buttonStyle(.plain)
            HStack {
                Button(action: apply) {
                    Text(savedTheme.metadata.name)
                        .font(.headline)
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    ThemeActionCommands(
                        savedTheme: savedTheme,
                        createTheme: createTheme,
                        importTheme: importTheme,
                        resetTheme: reset,
                        updateTheme: { _ in update() },
                        exportTheme: { _ in export() },
                        deleteTheme: { _ in delete() }
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Theme Actions")
            }
        }
        .contextMenu {
            ThemeActionCommands(
                savedTheme: savedTheme,
                createTheme: createTheme,
                importTheme: importTheme,
                resetTheme: reset,
                updateTheme: { _ in update() },
                exportTheme: { _ in export() },
                deleteTheme: { _ in delete() }
            )
        }
    }
}

private struct ThemeActionCommands: View {
    let savedTheme: SavedTheme?
    let createTheme: () -> Void
    let importTheme: () -> Void
    let resetTheme: () -> Void
    let updateTheme: (SavedTheme) -> Void
    let exportTheme: (SavedTheme) -> Void
    let deleteTheme: (SavedTheme) -> Void

    var body: some View {
        Button("Create New Theme", systemImage: "plus", action: createTheme)
        Button("Import Theme", systemImage: "square.and.arrow.down", action: importTheme)
        Divider()
        Button("Reset Theme", systemImage: "arrow.counterclockwise", action: resetTheme)
            .disabled(savedTheme == nil)
        Button("Export Theme", systemImage: "square.and.arrow.up") {
            if let savedTheme { exportTheme(savedTheme) }
        }
        .disabled(savedTheme == nil)
        if let savedTheme, !savedTheme.isBuiltIn {
            Button("Update Theme", systemImage: "arrow.triangle.2.circlepath") {
                updateTheme(savedTheme)
            }
            Divider()
            Button("Delete Theme", systemImage: "trash", role: .destructive) {
                deleteTheme(savedTheme)
            }
        }
    }
}

private struct ThemeCardPreview: View {
    let imageURL: URL
    let isSelected: Bool
    let isModified: Bool

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay { Image(systemName: "photo") }
            }
        }
            .aspectRatio(0.625, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isModified ? Color.orange : Color.accentColor, lineWidth: 3)
                }
            }
    }
}

private struct ThemeCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let create: (String, ThemePreviewImage) throws -> Void
    @State private var name = ""
    @State private var preview: ThemePreviewImage?
    @State private var previewImage: NSImage?
    @State private var errorMessage: String?
    @State private var isPreviewDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create New Theme")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.headline)
                TextField("Theme title", text: $name)
                    .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview Image")
                    .font(.headline)
                Button(action: choosePreview) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isPreviewDropTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isPreviewDropTargeted ? Color.accentColor : Color.secondary.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                            )
                        if let previewImage {
                            Image(nsImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 30))
                                Text("Drop a Preview Image Here")
                                    .font(.headline)
                                Text("or click to choose · PNG, JPEG, or WebP · exactly 1000 × 1600 px")
                                    .foregroundStyle(.secondary)
                            }
                            .multilineTextAlignment(.center)
                            .padding(24)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onDrop(of: [.fileURL], isTargeted: $isPreviewDropTargeted, perform: acceptPreviewDrop)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Create Theme") { createTheme() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && preview != nil
    }

    private func choosePreview() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadPreview(from: url)
    }

    private func acceptPreviewDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadObject(ofClass: NSURL.self) { item, error in
            let url = (item as? NSURL).map { $0 as URL }
            Task { @MainActor in
                if let url {
                    loadPreview(from: url)
                } else {
                    preview = nil
                    previewImage = nil
                    errorMessage = error?.localizedDescription ?? "The dropped item is not a readable image file."
                }
            }
        }
        return true
    }

    private func loadPreview(from url: URL) {
        do {
            preview = try ThemeBundleStore.preview(from: url)
            previewImage = NSImage(contentsOf: url)
            errorMessage = nil
        } catch {
            preview = nil
            previewImage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func createTheme() {
        guard let preview else { return }
        do {
            try create(name, preview)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension UTType {
    static let foundryTheme = UTType(exportedAs: "uk.co.garysimpson.foundry.theme", conformingTo: .package)
}
