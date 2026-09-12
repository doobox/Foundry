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

struct ThemeWindowContent: View {
    let session: ThemeEditorSession
    @ObservedObject private var document: FoundryDocument
    @AppStorage("themeEditor.selectedSection") private var selectedSectionRawValue = ThemeWindowSection.themes.rawValue
    @AppStorage("themeEditor.sidebarVisible") private var isSidebarVisible = true
    @State private var colourPreview = ThemeColourPreviewModel()

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
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background {
                SidebarMaterialBackground()
                    .ignoresSafeArea()
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            switch selectedSection {
            case .colourPreview:
                ThemeColoursPreview(model: colourPreview)
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

enum ThemeWindowSection: String, CaseIterable, Identifiable, Hashable {
    case themes
    case screens
    case colors
    case colourPreview
    case fontFamily
    case fontSize
    case spacing
    case shadows
    case borderWidth
    case borderRadius

    var id: String { rawValue }

    static let settings: [ThemeWindowSection] = [
        .colors,
        .colourPreview,
        .fontFamily,
        .fontSize,
        .spacing,
        .shadows,
        .borderWidth,
        .borderRadius
    ]

    var title: String {
        switch self {
        case .themes: "Themes"
        case .screens: "Breakpoints"
        case .colors: "Colours"
        case .colourPreview: "Colours Preview"
        case .fontFamily: "Fonts"
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
        case .screens: "ruler"
        case .colors: "paintpalette"
        case .colourPreview: "paintpalette"
        case .fontFamily: "text.alignleft"
        case .fontSize: "textformat.size"
        case .spacing: "arrow.left.and.right"
        case .shadows: "square.stack"
        case .borderWidth: "square"
        case .borderRadius: "circle"
        }
    }

    var explanation: String {
        switch self {
        case .themes:
            "Choose a saved theme or create one from the current project settings."
        case .screens:
            "Define responsive breakpoints and the maximum container width at each size."
        case .colors:
            "Set the core colours shared by pages, components and editable text."
        case .colourPreview:
            "A colour editor prototype. Changes stay in this window only."
        case .fontFamily:
            "Choose the typefaces used for body text, headings and monospaced content."
        case .fontSize:
            "Adjust the theme type scale and its corresponding line heights."
        case .spacing:
            "Adjust the spacing scale used by theme-aware component controls."
        case .shadows:
            "Define reusable shadow styles for depth, elevation and inset effects."
        case .borderWidth:
            "Set the width represented by each theme border token."
        case .borderRadius:
            "Set the corner radius represented by each theme radius token."
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

struct ThemeSettingsDetail: View {
    let section: ThemeWindowSection
    let theme: Theme
    let assets: [ProjectAsset]
    let session: ThemeEditorSession
    @State private var isConfirmingReset = false

    private var editor: ProjectEditor { session.editor }

    var body: some View {
        Group {
            if section == .screens {
                ThemeBreakpointSettings(screens: theme.screens, editor: editor)
            } else {
                ThemeEditorPage(title: section.title, subtitle: section.explanation) {
                    if resetAction != nil {
                        Button("Reset Scale…", systemImage: "arrow.counterclockwise") {
                            isConfirmingReset = true
                        }
                        .help("Restore the preset values in this section")
                    }
                } content: {
                    settingsContent
                }
            }
        }
        .confirmationDialog(
            "Reset \(section.title)?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Scale") { resetAction?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore the preset values in this section. Custom styles are kept. You can undo this change.")
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch section {
        case .screens:
            ThemeBreakpointSettings(screens: theme.screens, editor: editor)
        case .fontFamily:
            ThemeFontSettings(theme: theme, assets: assets, session: session)
        case .fontSize:
            ThemeTypeScaleSettings(theme: theme, editor: editor)
        case .spacing:
            ThemeSpacingSettings(theme: theme, editor: editor)
        case .shadows:
            ThemeShadowSettings(shadows: theme.shadows, editor: editor)
        case .borderWidth:
            ThemeDimensionSettings(tokens: theme.borderWidths, isRadius: false, setValue: editor.setThemeBorderWidth)
        case .borderRadius:
            ThemeDimensionSettings(tokens: theme.borderRadii, isRadius: true, setValue: editor.setThemeBorderRadius)
        case .colors:
            ThemeColourSettings(theme: theme, editor: editor)
        case .themes, .colourPreview:
            EmptyView()
        }
    }

    private var resetAction: (() -> Void)? {
        switch section {
        case .fontSize: editor.resetThemeFontSizeScale
        case .spacing: editor.resetThemeSpacingScale
        case .shadows: editor.resetThemeShadowScale
        case .borderWidth: editor.resetThemeBorderWidths
        case .borderRadius: editor.resetThemeBorderRadii
        case .themes, .screens, .colors, .colourPreview, .fontFamily: nil
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
    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 24, alignment: .top)]

    private var currentTheme: SavedTheme? { library.themes.first { $0.id == document.site.themeSourceID } }
    private var isCurrentThemeModified: Bool {
        currentTheme.map { $0.theme != document.site.theme } ?? true
    }

    var body: some View {
        ThemeEditorPage(title: "Themes", subtitle: ThemeWindowSection.themes.explanation) {
            Menu {
                Button("Create Theme…", systemImage: "plus") { isCreatingTheme = true }
                Button("Import Theme…", systemImage: "square.and.arrow.down", action: importTheme)
            } label: {
                Label("Add Theme", systemImage: "plus")
            }
            .fixedSize()
        } content: {
            ThemeEditorCard(title: "Current theme") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentTheme?.metadata.name ?? "Project Theme").font(.title3.weight(.semibold))
                        Text(isCurrentThemeModified ? "Modified for this project" : "Changes you make apply to this project.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        ForEach(DesignToken.colorTokens) { token in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(hex: document.site.theme.color(for: token) ?? "#FFFFFF") ?? .white)
                                .frame(width: 20, height: 28)
                                .overlay { RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3), lineWidth: 0.5) }
                                .help(token.displayName)
                                .accessibilityLabel(token.displayName)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("Saved themes").font(.headline)
                if library.themes.isEmpty {
                    ContentUnavailableView("No Saved Themes", systemImage: "theatermask.and.paintbrush",
                        description: Text("Create a theme from this project, or import one to get started."))
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
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
                }
            }
        }
        .navigationTitle("\(document.site.name) – Theme")
        .onAppear {
            library.reload()
            selectedThemeID = document.site.themeSourceID
        }
        .onChange(of: document.site.themeSourceID) { _, id in selectedThemeID = id }
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
            .accessibilityLabel("Apply \(savedTheme.metadata.name)")
            .accessibilityValue(isSelected ? (isModified ? "Current theme, modified" : "Current theme") : "")
            HStack {
                Button(action: apply) {
                    Text(savedTheme.metadata.name)
                        .font(.headline)
                        .lineLimit(2)
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
            if isSelected {
                Label(isModified ? "Modified for this project" : "Current theme",
                      systemImage: isModified ? "circle.lefthalf.filled" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .textFieldStyle(.roundedBorder)
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
        .controlSize(.regular)
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
