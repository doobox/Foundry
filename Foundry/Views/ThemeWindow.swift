import SwiftUI
import WebKit

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
}

private struct ThemeWindowContent: View {
    let session: ThemeEditorSession
    @ObservedObject private var document: FoundryDocument
    @State private var selection: ThemeWindowSection = .themes

    init(session: ThemeEditorSession) {
        self.session = session
        document = session.document
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
            switch selection {
            case .themes:
                ThemePackageBrowser(document: document, undoManager: session.editor.undoManager)
            default:
                ThemeSettingsDetail(
                    section: selection,
                    theme: document.site.theme,
                    assets: document.site.assets,
                    session: session
                )
            }
        }
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
            } else {
                List {
            switch section {
            case .screens:
                pendingSettings("Screen-specific theme overrides will live here.")
            case .page:
                ColorPicker(
                    "Background",
                    selection: colorBinding(for: .backgroundColor),
                    supportsOpacity: false
                )
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
            case .fontFamily:
                EmptyView()
            case .fontSize:
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
            case .spacing:
                Section("Spacing Scale") {
                    ForEach(DesignToken.spacingTokens) { token in
                        Stepper(value: spacingBinding(for: token), in: 0...160, step: 1) {
                            LabeledContent(
                                token.displayName,
                                value: "\((theme.number(for: token) ?? 0).formatted()) px"
                            )
                        }
                    }
                }
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
            case .themes:
                EmptyView()
                }
            }
            .listStyle(.inset)
            }
        }
        .navigationTitle(section.title)
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

    private func spacingBinding(for token: DesignToken) -> Binding<Double> {
        Binding(
            get: { theme.number(for: token) ?? 0 },
            set: { editor.setThemeSpacing(token, value: $0) }
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
    @State private var googleFonts = GoogleFontCatalog.fallback
    @State private var search = ""
    @State private var category = GoogleFontCategory.all
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
        .task {
            if let loaded = try? await GoogleFontCatalog.load(), !loaded.isEmpty {
                googleFonts = loaded
            }
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
                    Button("Revert") {
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

            googleFontList
        }
    }

    private var googleFontList: some View {
        List(filteredGoogleFonts) { font in
            Button {
                session.previewGoogleFont(font.family, for: reference)
            } label: {
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
                    }
                }
                .contentShape(Rectangle())
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
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
        return VStack(spacing: 20) {
            if selectedAssets.isEmpty {
                VStack(spacing: 28) {
                    Text("First, add fonts to your project resources")
                    Text("Then drag and drop the resources here")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { values, _ in
            let droppedAssets = values.compactMap(Self.assetID(from:))
                .compactMap { id in assets.first(where: { $0.id == id && $0.isFontResource }) }
            guard !droppedAssets.isEmpty else { return false }
            editor.setThemeFontResources(
                Array(Set(files + droppedAssets.map(\.reference))),
                reference: reference
            )
            if files.isEmpty, let first = droppedAssets.first {
                editor.setThemeFontFamily(
                    (first.filename as NSString).deletingPathExtension,
                    reference: reference
                )
            }
            return true
        }
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
                case .system: editor.setThemeFontSource(.system, reference: reference)
                case .bundled: editor.setThemeFontSource(.bundled(files: []), reference: reference)
                case .remote:
                    editor.setThemeGoogleFont(definition.family, reference: reference)
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

    nonisolated private static func assetID(from value: String) -> UUID? {
        if let id = value.foundryAssetID { return id }
        let prefixes = ["foundry-asset-node:", "foundry-image-asset:"]
        guard let prefix = prefixes.first(where: value.hasPrefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }
}

private struct GoogleFontSpecimenView: NSViewRepresentable {
    let family: String
    let stylesheetURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        webView.setAccessibilityLabel("\(family) font preview")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let key = family + "|" + (stylesheetURL?.absoluteString ?? "")
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        webView.setAccessibilityLabel("\(family) font preview")
        webView.loadHTMLString(html, baseURL: nil)
    }

    private var html: String {
        let escapedFamily = family.htmlEscaped
        let stylesheet = stylesheetURL.map {
            "<link rel=\"stylesheet\" href=\"\($0.absoluteString.htmlEscaped)\">"
        } ?? ""
        return """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="color-scheme" content="light dark">
            \(stylesheet)
            <style>
                * { box-sizing: border-box; }
                html, body { margin: 0; min-height: 100%; background: transparent; }
                body {
                    color: CanvasText;
                    font-family: '\(escapedFamily)', sans-serif;
                    padding: 28px;
                }
                h1 { font-size: 32px; margin: 0 0 34px; }
                .label { font: 13px system-ui; margin-bottom: 8px; }
                .specimen {
                    border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
                    border-radius: 8px;
                    font-size: 36px;
                    line-height: 1.22;
                    padding: 12px;
                    overflow-wrap: anywhere;
                }
            </style>
        </head>
        <body>
            <h1>\(escapedFamily)</h1>
            <div class="label">Normal</div>
            <div class="specimen">ABCDEFGHIJKLMNOPQRSTUVWXYZ<br>abcdefghijklmnopqrstuvwxyz<br>1234567890</div>
        </body>
        </html>
        """
    }

    final class Coordinator {
        var loadedKey: String?
    }
}

private struct GoogleFontFamily: Identifiable, Sendable {
    let family: String
    let category: String
    let styleCount: Int
    var id: String { family }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private enum GoogleFontCategory: String, CaseIterable, Identifiable {
    case all
    case sansSerif = "Sans Serif"
    case serif = "Serif"
    case display = "Display"
    case handwriting = "Handwriting"
    case monospace = "Monospace"

    var id: String { rawValue }
    var title: String { self == .all ? "All fonts" : rawValue }

    func includes(_ value: String) -> Bool {
        self == .all || value.caseInsensitiveCompare(rawValue) == .orderedSame
    }
}

private enum GoogleFontCatalog {
    static let fallback = [
        GoogleFontFamily(family: "ABeeZee", category: "Sans Serif", styleCount: 2),
        GoogleFontFamily(family: "ADLaM Display", category: "Display", styleCount: 1),
        GoogleFontFamily(family: "AR One Sans", category: "Sans Serif", styleCount: 4),
        GoogleFontFamily(family: "Abel", category: "Sans Serif", styleCount: 1),
        GoogleFontFamily(family: "Abhaya Libre", category: "Serif", styleCount: 5)
    ]

    static func load() async throws -> [GoogleFontFamily] {
        let url = URL(string: "https://fonts.google.com/metadata/fonts")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let prefix = Data(")]}'".utf8)
        let jsonData = data.starts(with: prefix) ? data.dropFirst(prefix.count) : data[...]
        guard let root = try JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any],
              let entries = root["familyMetadataList"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let family = entry["family"] as? String else { return nil }
            let category = (entry["category"] as? String ?? "Sans Serif")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            let count = (entry["fonts"] as? [String: Any])?.count ?? 1
            return GoogleFontFamily(family: family, category: category, styleCount: count)
        }
        .sorted { $0.family.localizedStandardCompare($1.family) == .orderedAscending }
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
