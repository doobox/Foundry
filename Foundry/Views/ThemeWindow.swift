import AppKit
import SwiftUI

@MainActor
@Observable
final class ThemeWindowCoordinator {
    private weak var window: NSWindow?

    func show(document: FoundryDocument, undoManager: UndoManager?) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let content = ThemeWindowContent(document: document, undoManager: undoManager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_060, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "\(document.site.name) – Theme"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

private struct ThemeWindowContent: View {
    @ObservedObject var document: FoundryDocument
    let undoManager: UndoManager?
    @State private var selection: ThemeWindowSection = .themes

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
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            switch selection {
            case .themes:
                ThemePackageBrowser(document: document, undoManager: undoManager)
            default:
                ThemeSettingsDetail(
                    section: selection,
                    theme: document.site.theme,
                    editor: ProjectEditor(document: document, undoManager: undoManager)
                )
            }
        }
        .frame(minWidth: 800, minHeight: 520)
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
    let editor: ProjectEditor

    var body: some View {
        Group {
            if section == .fontFamily {
                ThemeFontFamilyEditor(theme: theme, editor: editor)
            } else {
                Form {
            Section {
                Text(section.title)
                    .font(.title2.weight(.semibold))
                Text(sectionDescription)
                    .foregroundStyle(.secondary)
            }

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
                Stepper(value: baseSizeBinding, in: 10...40, step: 1) {
                    LabeledContent("Base Size", value: "\(theme.typography.baseSize.formatted()) px")
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
                    Stepper(value: baseSizeBinding, in: 10...40, step: 1) {
                        LabeledContent("Base Size", value: "\(theme.typography.baseSize.formatted()) px")
                    }
                }
            case .themes:
                EmptyView()
                }
            }
            .formStyle(.grouped)
            }
        }
        .navigationTitle(section.title)
    }

    private var sectionDescription: String {
        switch section {
        case .screens: "Define the screen sizes used by responsive theme values."
        case .page: "Set the default appearance shared by every page."
        case .colors: "Define the reusable colors available throughout the project."
        case .fontFamily: "Choose the font families used by the theme."
        case .fontSize: "Define the theme's type-size scale."
        case .spacing: "Define consistent spacing values for layouts and components."
        case .shadows: "Create reusable elevation and shadow styles."
        case .borderWidth: "Define reusable border thickness values."
        case .borderRadius: "Define reusable corner-radius values."
        case .typography: "Compose the theme's reusable text styles."
        case .themes: "Browse installed themes."
        }
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

    private var baseSizeBinding: Binding<Double> {
        Binding(
            get: { theme.typography.baseSize },
            set: editor.setThemeBaseSize
        )
    }
}

private struct ThemeFontFamilyEditor: View {
    let theme: Theme
    let editor: ProjectEditor
    @State private var selection: ThemeFontReference = .role(.body)
    @State private var search = ""
    @State private var category: ThemeFontCategory = .all

    var body: some View {
        HSplitView {
            themeFontSidebar
                .frame(minWidth: 190, idealWidth: 220, maxWidth: 260)
            fontLibrary
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 360)
            fontInspector
                .frame(minWidth: 360, maxWidth: .infinity)
        }
    }

    private var themeFontSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Theme Fonts")
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
                Section("Roles") {
                    ForEach(ThemeFontRole.allCases) { role in
                        FontAssignmentRow(
                            title: role.title,
                            family: definition(for: .role(role)).family,
                            systemImage: role.systemImage
                        )
                        .tag(ThemeFontReference.role(role))
                    }
                }
                Section("Custom") {
                    ForEach(theme.typography.customFonts) { font in
                        FontAssignmentRow(
                            title: font.name,
                            family: font.font.family,
                            systemImage: "textformat"
                        )
                        .tag(ThemeFontReference.custom(font.id))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                editor.removeThemeCustomFont(id: font.id)
                                selection = .role(.body)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var fontLibrary: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                TextField("Search Fonts", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    ForEach(ThemeFontCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
            }
            .padding(12)

            Divider()

            List(filteredFamilies, id: \.self) { family in
                Button {
                    assign(family)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(family)
                            .font(.custom(family, fixedSize: 19))
                            .foregroundStyle(.primary)
                        Text(fontDescription(family))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    definition(for: selection).family == family
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
            }
            .listStyle(.inset)
        }
    }

    private var fontInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        if case .custom(let id) = selection {
                            TextField("Font Name", text: customNameBinding(for: id))
                                .font(.title2.weight(.semibold))
                                .textFieldStyle(.plain)
                        } else {
                            Text(selectionTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                        Text(definition(for: selection).family)
                            .font(.largeTitle.weight(.bold))
                    }
                    Spacer()
                    if case .custom(let id) = selection {
                        Button("Delete", role: .destructive) {
                            editor.removeThemeCustomFont(id: id)
                            selection = .role(.body)
                        }
                    }
                }

                Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n1234567890 &?!@#")
                    .font(.custom(definition(for: selection).family, fixedSize: 38))
                    .lineSpacing(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

                ThemeFontDefinitionControls(
                    definition: definition(for: selection),
                    reference: selection,
                    editor: editor
                )
            }
            .padding(24)
        }
    }

    private var filteredFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
            .filter(category.includes)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectionTitle: String {
        guard case .role(let role) = selection else { return "Custom Font" }
        return role.title
    }

    private func definition(for reference: ThemeFontReference) -> ThemeFontDefinition {
        return switch reference {
        case .role(.body): theme.typography.bodyFont
        case .role(.headings): theme.typography.headingFont
        case .role(.monospaced): theme.typography.monospacedFont
        case .custom(let id):
            theme.typography.customFonts.first(where: { $0.id == id })?.font
                ?? .system(family: "system-ui", weights: [400])
        }
    }

    private func assign(_ family: String) {
        switch selection {
        case .role(let role):
            editor.setThemeFont(family, for: role)
        case .custom(let id):
            editor.setThemeCustomFontFamily(id: id, value: family)
        }
        editor.setThemeFontSource(.system, reference: selection)
    }

    private func customNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { theme.typography.customFonts.first(where: { $0.id == id })?.name ?? "" },
            set: { editor.setThemeCustomFontName(id: id, value: $0) }
        )
    }

    private func fontDescription(_ family: String) -> String {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family) else {
            return "System font"
        }
        return "\(members.count) style\(members.count == 1 ? "" : "s")"
    }
}

private struct FontAssignmentRow: View {
    let title: String
    let family: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(family)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

private enum ThemeFontCategory: String, CaseIterable, Identifiable {
    case all
    case sansSerif
    case serif
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Fonts"
        case .sansSerif: "Sans Serif"
        case .serif: "Serif"
        case .monospaced: "Monospaced"
        }
    }

    func includes(_ family: String) -> Bool {
        let font = NSFont(name: family, size: 14)
        let isMonospaced = font?.isFixedPitch == true
        let lowercaseName = family.lowercased()
        let isSerif = ["serif", "times", "georgia", "baskerville", "didot", "palatino"]
            .contains(where: lowercaseName.contains)
        return switch self {
        case .all: true
        case .sansSerif: !isMonospaced && !isSerif
        case .serif: isSerif
        case .monospaced: isMonospaced
        }
    }
}

private struct ThemeFontDefinitionControls: View {
    let definition: ThemeFontDefinition
    let reference: ThemeFontReference
    let editor: ProjectEditor

    var body: some View {
        DisclosureGroup("Font Details") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Fallbacks (comma separated)", text: fallbacksBinding)

                Picker("Source", selection: sourceKindBinding) {
                    ForEach(ThemeFontSourceKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if case .remote = definition.source {
                    TextField("Stylesheet URL", text: remoteURLBinding)
                } else if case .bundled(let files) = definition.source {
                    LabeledContent("Bundled Files", value: files.isEmpty ? "None" : files.joined(separator: ", "))
                }

                Text("Weights")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Grid(horizontalSpacing: 14, verticalSpacing: 8) {
                    ForEach(Array(Self.availableWeights.enumerated()), id: \.element) { index, weight in
                        if index.isMultiple(of: 3) {
                            GridRow {
                                weightToggle(Self.availableWeights[index])
                                weightToggle(Self.availableWeights[index + 1])
                                weightToggle(Self.availableWeights[index + 2])
                            }
                        }
                    }
                }

                HStack(spacing: 18) {
                    ForEach(ThemeFontStyle.allCases) { style in
                        Toggle(style.rawValue.capitalized, isOn: styleBinding(style))
                            .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.caption)
    }

    private static let availableWeights = [100, 200, 300, 400, 500, 600, 700, 800, 900]

    private func weightToggle(_ weight: Int) -> some View {
        Toggle("\(weight)", isOn: weightBinding(weight))
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fallbacksBinding: Binding<String> {
        Binding(
            get: { definition.fallbacks.joined(separator: ", ") },
            set: { editor.setThemeFontFallbacks($0, reference: reference) }
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
                    if let placeholderURL = URL(string: "https://example.com/fonts.css") {
                        editor.setThemeFontSource(.remote(stylesheetURL: placeholderURL), reference: reference)
                    }
                }
            }
        )
    }

    private var remoteURLBinding: Binding<String> {
        Binding(
            get: {
                guard case .remote(let url) = definition.source else { return "" }
                return url.absoluteString
            },
            set: {
                guard let url = URL(string: $0) else { return }
                editor.setThemeFontSource(.remote(stylesheetURL: url), reference: reference)
            }
        )
    }

    private func weightBinding(_ weight: Int) -> Binding<Bool> {
        Binding(
            get: { definition.weights.contains(weight) },
            set: { isEnabled in
                var weights = definition.weights
                if isEnabled {
                    weights.append(weight)
                } else {
                    weights.removeAll(where: { $0 == weight })
                }
                editor.setThemeFontWeights(weights, reference: reference)
            }
        )
    }

    private func styleBinding(_ style: ThemeFontStyle) -> Binding<Bool> {
        Binding(
            get: { definition.styles.contains(style) },
            set: { isEnabled in
                var styles = definition.styles
                if isEnabled {
                    styles.append(style)
                } else {
                    styles.removeAll(where: { $0 == style })
                }
                editor.setThemeFontStyles(styles, reference: reference)
            }
        )
    }
}

private enum ThemeFontSourceKind: String, CaseIterable, Identifiable {
    case system
    case bundled
    case remote

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

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
