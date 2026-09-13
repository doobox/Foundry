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
            case .colors:
                ProjectColourSettings(session: session)
            case .themes:
                ThemeLibraryBrowser(document: document, undoManager: session.editor.undoManager)
            case .fontFamily:
                ThemeFontSettings(theme: document.site.theme, assets: document.site.assets, session: session)
            default:
                ThemeSettingsDetail(
                    section: selectedSection,
                    theme: document.site.theme,
                    assets: document.site.assets,
                    session: session
                )
                .disabled(!session.canEditTheme)
            }
        }
    }

    private var selectedSection: ThemeWindowSection {
        selectedSectionRawValue == "colourPreview" ? .colors : (ThemeWindowSection(rawValue: selectedSectionRawValue) ?? .themes)
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
        case .themes: "Themes"
        case .screens: "Breakpoints"
        case .colors: "Colours"
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
            "Choose a saved theme or create one from System UI."
        case .screens:
            "Define responsive breakpoints and the maximum container width at each size."
        case .colors:
            "Set the core colours shared by pages, components and editable text."
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
            if section == .fontFamily {
                ThemeFontSettings(theme: theme, assets: assets, session: session)
            } else if section == .screens {
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
            ProjectColourSettings(session: session)
        case .themes:
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
        case .themes, .screens, .colors, .fontFamily: nil
        }
    }
}

private struct ThemeLibraryBrowser: View {
    @ObservedObject var document: FoundryDocument
    let undoManager: UndoManager?
    @State private var library = ThemeLibrary.shared
    @State private var isCreatingTheme = false
    @State private var themePendingEdit: SavedTheme?
    @State private var themePendingUpdate: SavedTheme?
    @State private var themePendingDeletion: SavedTheme?
    @State private var errorMessage: String?
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 16, alignment: .top)]

    private var activeTheme: SavedTheme? {
        library.themes.first { $0.id == document.site.themeSourceID }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(library.themes) { savedTheme in
                    ThemeLibraryItem(
                        savedTheme: savedTheme,
                        isSelected: document.site.themeSourceID == savedTheme.id,
                        isModified: document.site.themeSourceID == savedTheme.id && savedTheme.theme.savedSettings != document.site.theme.savedSettings,
                        createTheme: { isCreatingTheme = true },
                        importTheme: importTheme
                    ) {
                        selectTheme(savedTheme)
                    } reset: {
                        resetTheme(savedTheme)
                    } update: {
                        themePendingUpdate = savedTheme
                    } edit: {
                        themePendingEdit = savedTheme
                    } export: {
                        exportTheme(savedTheme)
                    } delete: {
                        themePendingDeletion = savedTheme
                    }
                }

            }
            .padding(24)
        }
        .accessibilityIdentifier("theme-section-Themes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ThemeActionCommands(
                        savedTheme: activeTheme,
                        canReset: activeTheme.map { $0.theme.savedSettings != document.site.theme.savedSettings } ?? false,
                        createTheme: { isCreatingTheme = true },
                        importTheme: importTheme,
                        resetTheme: { if let theme = activeTheme { resetTheme(theme) } },
                        updateTheme: { themePendingUpdate = $0 },
                        editTheme: { themePendingEdit = $0 },
                        exportTheme: exportTheme,
                        deleteTheme: { themePendingDeletion = $0 }
                    )
                } label: {
                    Label("Theme Actions", systemImage: "theatermask.and.paintbrush")
                }
                .menuIndicator(.hidden)
                .help("Theme Actions")
            }
        }
        .navigationTitle("\(document.site.name) – Theme")
        .onAppear {
            library.reload()
        }
        .sheet(isPresented: $isCreatingTheme) {
            ThemeCreationSheet { name, preview in
                let savedTheme = try library.create(
                    name: name,
                    preview: preview
                )
                ProjectEditor(document: document, undoManager: undoManager).commitTheme(
                    savedTheme.theme,
                    sourceID: savedTheme.id
                )
            }
        }
        .sheet(item: $themePendingEdit) { savedTheme in
            ThemeCreationSheet(editing: savedTheme) { name, preview in
                try library.edit(savedTheme, name: name, preview: preview)
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
            Text("Replace this theme’s saved settings with the current project theme? Its title will be kept.")
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
            Text(themePendingDeletion?.id == document.site.themeSourceID
                 ? "This removes the saved theme from your library and resets this project to System UI defaults. Project custom values are kept."
                 : "This removes the saved theme from your library. This project’s active theme will not change.")
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
    }

    private func resetTheme(_ savedTheme: SavedTheme) {
        guard !savedTheme.isBuiltIn else { return }
        let theme = projectTheme(from: savedTheme)
        ProjectEditor(document: document, undoManager: undoManager).resetTheme(theme, sourceID: savedTheme.id)
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
        guard !savedTheme.isBuiltIn else { return }
        do {
            try library.remove(savedTheme)
            ProjectEditor(document: document, undoManager: undoManager).didDeleteTheme(sourceID: savedTheme.id)
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
    let edit: () -> Void
    let export: () -> Void
    let delete: () -> Void


    var body: some View {
        Button(action: apply) {
            ThemeArtworkPreview(url: savedTheme.previewURL)
                .id(savedTheme.metadata.modifiedAt)
                .aspectRatio(CGFloat(ThemePreviewImage.pixelWidth) / CGFloat(ThemePreviewImage.pixelHeight), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
                .allowsHitTesting(false)
                .overlay(alignment: .bottomLeading) {
                    if isSelected && isModified {
                        Text("Modified")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .padding(10)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                                      lineWidth: isSelected ? 3 : 0.5)
                }
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply \(savedTheme.metadata.name)")
        .accessibilityValue(isSelected ? (isModified ? "Current theme, modified" : "Current theme") : "")
        .contextMenu { actions }
    }

    private var actions: some View {
        ThemeActionCommands(
            savedTheme: savedTheme,
            canReset: isSelected && isModified,
            createTheme: createTheme,
            importTheme: importTheme,
            resetTheme: reset,
            updateTheme: { _ in update() },
            editTheme: { _ in edit() },
            exportTheme: { _ in export() },
            deleteTheme: { _ in delete() }
        )
    }
}

private struct ThemeActionCommands: View {
    let savedTheme: SavedTheme?
    let canReset: Bool
    let createTheme: () -> Void
    let importTheme: () -> Void
    let resetTheme: () -> Void
    let updateTheme: (SavedTheme) -> Void
    let editTheme: (SavedTheme) -> Void
    let exportTheme: (SavedTheme) -> Void
    let deleteTheme: (SavedTheme) -> Void
    var includesCreationActions = true

    var body: some View {
        if includesCreationActions {
            Button("Create New Theme", systemImage: "plus", action: createTheme)
            Button("Import Theme", systemImage: "square.and.arrow.down", action: importTheme)
            Divider()
        }
        if let savedTheme, !savedTheme.isBuiltIn {
            Button("Reset Theme", systemImage: "arrow.counterclockwise", action: resetTheme)
                .disabled(!canReset)
        }
        Button("Export Theme", systemImage: "square.and.arrow.up") {
            if let savedTheme { exportTheme(savedTheme) }
        }
        .disabled(savedTheme == nil)
        if let savedTheme, !savedTheme.isBuiltIn {
            Button("Edit Theme…", systemImage: "pencil") {
                editTheme(savedTheme)
            }
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


private struct ThemeCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let create: (String, ThemePreviewImage) throws -> Void
    private let isEditing: Bool
    @State private var name = ""
    @State private var preview: ThemePreviewImage?
    @State private var previewImage: NSImage?
    @State private var errorMessage: String?
    @State private var isPreviewDropTargeted = false

    init(editing savedTheme: SavedTheme? = nil, create: @escaping (String, ThemePreviewImage) throws -> Void) {
        self.create = create
        isEditing = savedTheme != nil
        _name = State(initialValue: savedTheme?.metadata.name ?? "")
        if let savedTheme {
            do {
                let artwork = try ThemeBundleStore.preview(from: savedTheme.previewURL)
                _preview = State(initialValue: artwork)
                _previewImage = State(initialValue: NSImage(data: artwork.data))
            } catch {
                _errorMessage = State(initialValue: error.localizedDescription)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Edit Theme" : "Create New Theme")
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
                                Text("or click to choose · PNG, JPEG, or WebP · recommended \(ThemePreviewImage.pixelWidth) × \(ThemePreviewImage.pixelHeight) px (2:1)")
                                    .foregroundStyle(.secondary)
                            }
                            .multilineTextAlignment(.center)
                            .padding(24)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
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
                Button(isEditing ? "Save Changes" : "Create Theme") { createTheme() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 460)
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
