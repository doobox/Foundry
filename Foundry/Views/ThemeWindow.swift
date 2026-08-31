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
                    systemImage: "paintpalette",
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
                ThemePackageBrowser(document: document, undoManager: session.editor.undoManager)
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
    case page
    case colors
    case fontFamily
    case fontSize
    case spacing
    case shadows
    case borderWidth
    case borderRadius
    case typography

    var id: String { rawValue }

    static let settings: [ThemeWindowSection] = [
        .page,
        .colors,
        .fontFamily,
        .fontSize,
        .spacing,
        .shadows,
        .borderWidth,
        .borderRadius,
        .typography
    ]

    var title: String {
        switch self {
        case .themes: "Theme"
        case .screens: "Screens"
        case .page: "Page"
        case .colors: "Colors"
        case .fontFamily: "Font Family"
        case .fontSize: "Font Size"
        case .spacing: "Spacing"
        case .shadows: "Shadows"
        case .borderWidth: "Border Width"
        case .borderRadius: "Border Radius"
        case .typography: "Typography"
        }
    }

    var systemImage: String {
        switch self {
        case .themes: "paintpalette"
        case .screens: "rectangle.on.rectangle"
        case .page: "doc"
        case .colors: "paintpalette"
        case .fontFamily: "text.alignleft"
        case .fontSize: "textformat.size"
        case .spacing: "arrow.left.and.right"
        case .shadows: "square.stack"
        case .borderWidth: "square"
        case .borderRadius: "circle"
        case .typography: "textformat"
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
    @State private var expandedFontSizeID: String?

    private var editor: ProjectEditor { session.editor }

    var body: some View {
        Group {
            if section == .fontFamily {
                ThemeFontFamilyEditor(theme: theme, assets: assets, session: session)
            } else if section == .fontSize {
                fontSizeSettings
            } else if section == .spacing {
                ThemeSpacingSettings(spacing: theme.spacing, editor: editor)
            } else {
                Form {
                    switch section {
                    case .screens:
                        pendingSettings("Screen-specific theme overrides will live here.")
                    case .page:
                        Section("Canvas") {
                            ColorPicker(
                                "Background",
                                selection: colorBinding(for: .backgroundColor),
                                supportsOpacity: false
                            )
                        }
                    case .colors:
                        Section("Theme Colors") {
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
                        pendingSettings("Reusable shadow styles will be configured here.")
                    case .borderWidth:
                        pendingSettings("The theme border-width scale will be configured here.")
                    case .borderRadius:
                        pendingSettings("The theme corner-radius scale will be configured here.")
                    case .typography:
                        Section("Base Typography") {
                            TextField("Body Font", text: bodyFontBinding)
                        }
                    case .themes, .fontFamily, .fontSize:
                        EmptyView()
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(section.title)
    }

    private var fontSizeSettings: some View {
        List {
            VStack(alignment: .leading, spacing: 14) {
                    Text("Base Font")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text("Root Size")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .leading)
                            .lineLimit(1)
                        Slider(value: baseSizeBinding, in: 10...24, step: 1)
                            .frame(minWidth: 180)
                        TextField(
                            "Root Size",
                            value: baseSizeBinding,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        Text("px")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 12, trailing: 0))
            Section {
                ForEach(theme.typography.customFontSizes) { token in
                    fontSizeEditor(token)
                }
                .onMove(perform: editor.moveThemeFontSizes)
            } header: {
                HStack {
                    Text("Custom Sizes")
                    Spacer()
                    Button("Add Size", systemImage: "plus") {
                        editor.addThemeFontSize()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Add Custom Font Size")
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func pendingSettings(_ message: String) -> some View {
        Section {
            Label(message, systemImage: section.systemImage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func colorBinding(for token: DesignToken) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme.color(for: token) ?? "#FFFFFF") ?? .white },
            set: { editor.setThemeColor(token, value: $0.hexString ?? "#FFFFFF") }
        )
    }

    private var bodyFontBinding: Binding<String> {
        Binding(
            get: { theme.typography.bodyFont.family },
            set: editor.setThemeBodyFont
        )
    }

    private func fontSizeBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { theme.typography.fontSizes.first(where: { $0.id == id })?.size ?? 1 },
            set: { editor.setThemeFontSize(id: id, value: $0) }
        )
    }

    private func pixelSizeBinding(for id: String) -> Binding<Double> {
        Binding(
            get: {
                let rem = theme.typography.fontSizes.first(where: { $0.id == id })?.size ?? 1
                return rem * theme.typography.baseSize
            },
            set: { pixels in
                editor.setThemeFontSize(
                    id: id,
                    value: pixels / max(theme.typography.baseSize, 1)
                )
            }
        )
    }

    private var baseSizeBinding: Binding<Double> {
        Binding(
            get: { theme.typography.baseSize },
            set: editor.setThemeBaseSize
        )
    }

    private func lineHeightBinding(for id: String) -> Binding<Double> {
        Binding(
            get: {
                let lineHeight = theme.typography.customFontSizes
                    .first(where: { $0.id == id })?.lineHeight ?? .normal
                return Double(ThemeLineHeight.allCases.firstIndex(of: lineHeight) ?? 3)
            },
            set: { value in
                let index = min(max(Int(value.rounded()), 0), ThemeLineHeight.allCases.count - 1)
                editor.setThemeFontSizeLineHeight(id: id, value: ThemeLineHeight.allCases[index])
            }
        )
    }

    private func fontSizeTitleBinding(for id: String) -> Binding<String> {
        Binding(
            get: { theme.typography.fontSizes.first(where: { $0.id == id })?.title ?? "" },
            set: { editor.setThemeFontSizeTitle(id: id, value: $0) }
        )
    }

    private func remDescription(_ value: Double) -> String {
        let rem = value.formatted(.number.precision(.fractionLength(0...3)))
        let pixels = (value * theme.typography.baseSize).formatted(
            .number.precision(.fractionLength(0...1))
        )
        return "\(rem) rem (\(pixels) px)"
    }

    @ViewBuilder
    private func fontSizeEditor(_ token: ThemeFontSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        expandedFontSizeID = expandedFontSizeID == token.id ? nil : token.id
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expandedFontSizeID == token.id ? 90 : 0))
                }
                .buttonStyle(.plain)
                .help(expandedFontSizeID == token.id ? "Collapse" : "Expand")

                TextField("Name", text: fontSizeTitleBinding(for: token.id))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, idealWidth: 220, maxWidth: 300)

                Spacer()

                Text(remDescription(token.size))
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    if expandedFontSizeID == token.id {
                        expandedFontSizeID = nil
                    }
                    editor.removeThemeFontSize(id: token.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete Custom Size")
            }

            if expandedFontSizeID == token.id {
                Divider()
                    .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 14) {
                    sizeEditor(token)
                    lineHeightEditor(token)
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }

    private func sizeEditor(_ token: ThemeFontSize) -> some View {
        HStack(spacing: 12) {
            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)
            Slider(value: pixelSizeBinding(for: token.id), in: 8...160, step: 1)
                .frame(minWidth: 180)
            HStack(spacing: 12) {
                TextField(
                    "Rem",
                    value: fontSizeBinding(for: token.id),
                    format: .number.precision(.fractionLength(0...3))
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("rem")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
                TextField(
                    "Pixels",
                    value: pixelSizeBinding(for: token.id),
                    format: .number.precision(.fractionLength(0...1))
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("px")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)
            }
            .frame(width: 228, alignment: .trailing)
        }
    }

    private func lineHeightEditor(_ token: ThemeFontSize) -> some View {
        HStack(spacing: 12) {
            Text("Line Height")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)
            Slider(value: lineHeightBinding(for: token.id), in: 0...5, step: 1)
            .labelsHidden()
            .frame(minWidth: 180)
            Text(token.lineHeight.title)
                .foregroundStyle(.secondary)
                .frame(width: 228, alignment: .leading)
        }
    }
}

private struct ThemeSpacingSettings: View {
    let spacing: SpacingTokens
    let editor: ProjectEditor

    var body: some View {
        List {
            Section {
                ThemePredefinedSpacingRow(token: .extraSmallSpacing, value: spacing.extraSmall, editor: editor)
                ThemePredefinedSpacingRow(token: .smallSpacing, value: spacing.small, editor: editor)
                ThemePredefinedSpacingRow(token: .mediumSpacing, value: spacing.medium, editor: editor)
                ThemePredefinedSpacingRow(token: .largeSpacing, value: spacing.large, editor: editor)
                ThemePredefinedSpacingRow(token: .extraLargeSpacing, value: spacing.extraLarge, editor: editor)
            } header: {
                HStack {
                    Text("Predefined Scale")
                    Spacer()
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        editor.resetThemeSpacingScale()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(spacing.usesStandardPredefinedScale)
                    .help("Reset Predefined Spacing Scale")
                }
            }

            Section {
                ForEach(spacing.custom) { token in
                    ThemeCustomSpacingRow(token: token, editor: editor)
                }
            } header: {
                HStack {
                    Text("Custom Spacings")
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
    let editor: ProjectEditor

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
                editor.removeThemeSpacing(id: token.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Delete Custom Spacing")
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
                                editor.removeThemeCustomFont(id: font.id)
                                selection = .role(.body)
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

private struct ThemePackageBrowser: View {
    @ObservedObject var document: FoundryDocument
    let undoManager: UndoManager?
    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                currentThemeCard
                ForEach(packages, id: \.manifest.identifier) { package in
                    Button {
                        ProjectEditor(document: document, undoManager: undoManager)
                            .applyThemePackage(package)
                    } label: {
                        ThemePackageCard(package: package)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .navigationTitle("Themes")
    }

    private var packages: [LoadedThemePackage] {
        FoundryPackCatalog.shared.themes.values.sorted {
            $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending
        }
    }

    private var currentThemeCard: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: document.site.theme.colors.background) ?? .white)
                .overlay {
                    Text(document.site.theme.typography.bodyFont.family)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color(hex: document.site.theme.colors.text) ?? .primary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.tint, lineWidth: 3)
                }
                .aspectRatio(1.6, contentMode: .fit)
            Text("Current Theme")
                .font(.headline)
        }
    }
}

private struct ThemePackageCard: View {
    let package: LoadedThemePackage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let image = NSImage(contentsOf: package.iconURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
            .aspectRatio(1.6, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(package.manifest.name)
                .font(.headline)
            Text(package.manifest.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
