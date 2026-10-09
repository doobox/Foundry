import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FrameworkWindowRegistry {
    struct Context {
        let session: FrameworkEditorSession
    }

    static let shared = FrameworkWindowRegistry()

    private var contexts: [UUID: Context] = [:]

    func register(id: UUID, document: FoundryDocument, undoManager: UndoManager?) {
        if contexts[id]?.session.document === document { return }
        contexts[id] = Context(
            session: FrameworkEditorSession(document: document, undoManager: undoManager)
        )
    }

    func context(for id: UUID) -> Context? {
        contexts[id]
    }

    func remove(id: UUID) {
        contexts.removeValue(forKey: id)
    }
}

struct FrameworkWindowSceneContent: View {
    let presentationID: UUID?

    var body: some View {
        Group {
            if let presentationID,
               let context = FrameworkWindowRegistry.shared.context(for: presentationID) {
                FrameworkWindowContent(session: context.session)
                    .navigationTitle("\(context.session.document.site.name) – Framework")
            } else {
                ContentUnavailableView(
                    "Framework Unavailable",
                    systemImage: "shippingbox",
                    description: Text("Open the framework editor from a project window.")
                )
            }
        }
        .background(WindowGeometryPersistence(key: "frameworkEditor.windowFrame"))
    }
}

struct FrameworkWindowContent: View {
    let session: FrameworkEditorSession
    @ObservedObject private var document: FoundryDocument
    @AppStorage("frameworkEditor.selectedSection") private var selectedSectionRawValue = FrameworkWindowSection.frameworks.rawValue
    @AppStorage("frameworkEditor.sidebarVisible") private var isSidebarVisible = true

    init(session: FrameworkEditorSession) {
        self.session = session
        document = session.document
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            List(selection: selection) {
                Section("Project") {
                    FrameworkSidebarRow(section: .frameworks)
                    FrameworkSidebarRow(section: .screens)
                }
                Section("Framework Settings") {
                    ForEach(FrameworkWindowSection.settings) { section in
                        FrameworkSidebarRow(section: section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            switch selectedSection {
            case .colors:
                ProjectColourSettings(session: session)
            case .frameworks:
                FrameworkLibraryBrowser(document: document, undoManager: session.editor.undoManager)
            case .fontFamily:
                FrameworkFontSettings(framework: document.site.framework, assets: document.site.assets, session: session)
            case .fontSize:
                FrameworkFontSizeSettings(framework: document.site.framework, session: session)
            case .spacing:
                FrameworkSpacingSettings(framework: document.site.framework, session: session)
            case .borderWidth:
                FrameworkDimensionSettings(framework: document.site.framework, kind: .borderWidth, session: session)
            case .borderRadius:
                FrameworkDimensionSettings(framework: document.site.framework, kind: .borderRadius, session: session)
            case .zIndex:
                FrameworkDimensionSettings(framework: document.site.framework, kind: .zIndex, session: session)
            default:
                FrameworkSettingsDetail(
                    section: selectedSection,
                    framework: document.site.framework,
                    assets: document.site.assets,
                    session: session
                )
                .disabled(selectedSection != .screens && !session.canEditFramework)
            }
        }
    }

    private var selectedSection: FrameworkWindowSection {
        selectedSectionRawValue == "colourPreview" ? .colors : (FrameworkWindowSection(rawValue: selectedSectionRawValue) ?? .frameworks)
    }

    private var selection: Binding<FrameworkWindowSection> {
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

enum FrameworkWindowSection: String, CaseIterable, Identifiable, Hashable {
    case frameworks
    case screens
    case colors
    case fontFamily
    case fontSize
    case spacing
    case shadows
    case borderWidth
    case borderRadius
    case zIndex

    var id: String { rawValue }

    static let settings: [FrameworkWindowSection] = [
        .colors,
        .fontFamily,
        .fontSize,
        .spacing,
        .shadows,
        .borderWidth,
        .borderRadius,
        .zIndex
    ]

    var title: String {
        switch self {
        case .frameworks: "Frameworks"
        case .screens: "Breakpoints"
        case .colors: "Colours"
        case .fontFamily: "Fonts"
        case .fontSize: "Font Size"
        case .spacing: "Spacing"
        case .shadows: "Shadows"
        case .borderWidth: "Border Width"
        case .borderRadius: "Border Radius"
        case .zIndex: "Stacking Order"
        }
    }

    var systemImage: String {
        switch self {
        case .frameworks: "shippingbox"
        case .screens: "ruler"
        case .colors: "paintpalette"
        case .fontFamily: "text.alignleft"
        case .fontSize: "textformat.size"
        case .spacing: "arrow.left.and.right"
        case .shadows: "square.stack"
        case .borderWidth: "square"
        case .borderRadius: "circle"
        case .zIndex: "square.stack.3d.up"
        }
    }

    var explanation: String {
        switch self {
        case .frameworks:
            "Choose a saved framework or create one from System UI."
        case .screens:
            "Define responsive breakpoints and the maximum container width at each size."
        case .colors:
            "Customize Bootstrap theme roles and adaptive background, foreground and border layers."
        case .fontFamily:
            "Choose the typefaces used for body text, headings and monospaced content."
        case .fontSize:
            "Adjust each framework font size and its line height."
        case .spacing:
            "Adjust the spacing scale used by framework-aware part controls."
        case .shadows:
            "Define reusable shadow styles for depth, elevation and inset effects."
        case .borderWidth:
            "Set the width represented by each framework border token."
        case .borderRadius:
            "Set the corner radius represented by each framework radius token."
        case .zIndex:
            "Set the stacking order represented by each framework layering token."
        }
    }
}

private struct FrameworkSidebarRow: View {
    let section: FrameworkWindowSection

    var body: some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }
}

struct FrameworkSettingsDetail: View {
    let section: FrameworkWindowSection
    let framework: Framework
    let assets: [ProjectAsset]
    let session: FrameworkEditorSession
    @State private var isConfirmingReset = false

    private var editor: ProjectEditor { session.editor }

    var body: some View {
        Group {
            if section == .fontFamily {
                FrameworkFontSettings(framework: framework, assets: assets, session: session)
            } else if section == .fontSize {
                FrameworkFontSizeSettings(framework: framework, session: session)
            } else if section == .spacing {
                FrameworkSpacingSettings(framework: framework, session: session)
            } else if section == .borderWidth {
                FrameworkDimensionSettings(framework: framework, kind: .borderWidth, session: session)
            } else if section == .borderRadius {
                FrameworkDimensionSettings(framework: framework, kind: .borderRadius, session: session)
            } else if section == .zIndex {
                FrameworkDimensionSettings(framework: framework, kind: .zIndex, session: session)
            } else if section == .screens {
                FrameworkBreakpointSettings(screens: framework.screens, editor: editor)
            } else {
                FrameworkEditorPage(title: section.title, subtitle: section.explanation) {
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
            FrameworkBreakpointSettings(screens: framework.screens, editor: editor)
        case .fontFamily:
            FrameworkFontSettings(framework: framework, assets: assets, session: session)
        case .fontSize:
            FrameworkFontSizeSettings(framework: framework, session: session)
        case .spacing:
            FrameworkSpacingSettings(framework: framework, session: session)
        case .shadows:
            FrameworkShadowSettings(shadows: framework.shadows, editor: editor)
        case .borderWidth:
            FrameworkDimensionSettings(framework: framework, kind: .borderWidth, session: session)
        case .borderRadius:
            FrameworkDimensionSettings(framework: framework, kind: .borderRadius, session: session)
        case .zIndex:
            FrameworkDimensionSettings(framework: framework, kind: .zIndex, session: session)
        case .colors:
            ProjectColourSettings(session: session)
        case .frameworks:
            EmptyView()
        }
    }

    private var resetAction: (() -> Void)? {
        switch section {
        case .shadows: editor.resetFrameworkShadowScale
        case .frameworks, .screens, .colors, .fontFamily, .fontSize, .spacing,
             .borderWidth, .borderRadius, .zIndex: nil
        }
    }
}

private struct FrameworkLibraryBrowser: View {
    @ObservedObject var document: FoundryDocument
    let undoManager: UndoManager?
    @State private var library = FrameworkLibrary.shared
    @State private var isCreatingFramework = false
    @State private var frameworkPendingEdit: SavedFramework?
    @State private var frameworkPendingUpdate: SavedFramework?
    @State private var frameworkPendingDeletion: SavedFramework?
    @State private var errorMessage: String?
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 16, alignment: .top)]

    private var activeFramework: SavedFramework? {
        library.frameworks.first { $0.id == document.site.frameworkSourceID }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(library.frameworks) { savedFramework in
                    FrameworkLibraryItem(
                        savedFramework: savedFramework,
                        isSelected: document.site.frameworkSourceID == savedFramework.id,
                        isModified: document.site.frameworkSourceID == savedFramework.id && savedFramework.hasModifiedSettings(in: document.site.framework),
                        createFramework: { isCreatingFramework = true },
                        importFramework: importFramework
                    ) {
                        selectFramework(savedFramework)
                    } reset: {
                        resetFramework(savedFramework)
                    } update: {
                        frameworkPendingUpdate = savedFramework
                    } edit: {
                        frameworkPendingEdit = savedFramework
                    } export: {
                        exportFramework(savedFramework)
                    } delete: {
                        frameworkPendingDeletion = savedFramework
                    }
                }

            }
            .padding(24)
        }
        .accessibilityIdentifier("framework-section-Frameworks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    FrameworkActionCommands(
                        savedFramework: activeFramework,
                        canReset: activeFramework.map { $0.framework.savedSettings != document.site.framework.savedSettings } ?? false,
                        createFramework: { isCreatingFramework = true },
                        importFramework: importFramework,
                        resetFramework: { if let framework = activeFramework { resetFramework(framework) } },
                        updateFramework: { frameworkPendingUpdate = $0 },
                        editFramework: { frameworkPendingEdit = $0 },
                        exportFramework: exportFramework,
                        deleteFramework: { frameworkPendingDeletion = $0 }
                    )
                } label: {
                    Label("Framework Actions", systemImage: "shippingbox")
                }
                .menuIndicator(.hidden)
                .help("Framework Actions")
            }
        }
        .navigationTitle("\(document.site.name) – Framework")
        .onAppear {
            library.reload()
        }
        .sheet(isPresented: $isCreatingFramework) {
            FrameworkCreationSheet { name, preview in
                let savedFramework = try library.create(
                    name: name,
                    preview: preview
                )
                ProjectEditor(document: document, undoManager: undoManager).commitFramework(
                    savedFramework.framework,
                    sourceID: savedFramework.id
                )
            }
        }
        .sheet(item: $frameworkPendingEdit) { savedFramework in
            FrameworkCreationSheet(editing: savedFramework) { name, preview in
                try library.edit(savedFramework, name: name, preview: preview)
            }
        }
        .confirmationDialog(
            "Update \(frameworkPendingUpdate?.metadata.name ?? "Framework")?",
            isPresented: updateConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Update Framework") {
                updatePendingFramework()
            }
            Button("Cancel", role: .cancel) {
                frameworkPendingUpdate = nil
            }
        } message: {
            Text("Replace this framework’s saved settings with the current project framework? Its title will be kept.")
        }
        .confirmationDialog(
            "Delete \(frameworkPendingDeletion?.metadata.name ?? "Framework")?",
            isPresented: frameworkDeletionConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Framework", role: .destructive) {
                guard let framework = frameworkPendingDeletion else { return }
                deleteFramework(framework)
                frameworkPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { frameworkPendingDeletion = nil }
        } message: {
            Text(frameworkPendingDeletion?.id == document.site.frameworkSourceID
                 ? "This removes the saved framework from your library and resets this project to System UI defaults. Project custom values are kept."
                 : "This removes the saved framework from your library. This project’s active framework will not change.")
        }
        .alert("Framework Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The framework operation could not be completed.")
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
            get: { frameworkPendingUpdate != nil },
            set: { if !$0 { frameworkPendingUpdate = nil } }
        )
    }

    private var frameworkDeletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { frameworkPendingDeletion != nil },
            set: { if !$0 { frameworkPendingDeletion = nil } }
        )
    }

    private func updatePendingFramework() {
        guard let savedFramework = frameworkPendingUpdate else { return }
        defer { frameworkPendingUpdate = nil }
        do {
            let updated = try library.update(
                savedFramework,
                from: document.site.framework,
                assetContents: document.assetContents
            )
            ProjectEditor(document: document, undoManager: undoManager).commitFramework(
                updated.framework,
                sourceID: updated.id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFramework() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.foundryPack]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FoundryPackInstaller.install(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectFramework(_ savedFramework: SavedFramework) {
        let framework = projectFramework(from: savedFramework)
        ProjectEditor(document: document, undoManager: undoManager).selectFramework(framework, sourceID: savedFramework.id)
    }

    private func resetFramework(_ savedFramework: SavedFramework) {
        guard !savedFramework.isBuiltIn else { return }
        let framework = projectFramework(from: savedFramework)
        ProjectEditor(document: document, undoManager: undoManager).resetFramework(framework, sourceID: savedFramework.id)
    }

    private func projectFramework(from savedFramework: SavedFramework) -> Framework {
        var assetMapping: [UUID: UUID] = [:]
        for content in savedFramework.resources {
            let newID = document.importAsset(
                data: content.data,
                filename: content.asset.filename,
                mediaType: content.asset.mediaType,
                undoManager: undoManager
            )
            assetMapping[content.asset.id] = newID
        }
        return savedFramework.framework.remappingBundledFontAssets(assetMapping)
    }

    private func exportFramework(_ savedFramework: SavedFramework) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.foundryPack]
        panel.nameFieldStringValue = "\(savedFramework.metadata.name).foundrypack"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FoundryPackLoader.exportFramework(savedFramework, to: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFramework(_ savedFramework: SavedFramework) {
        guard !savedFramework.isBuiltIn else { return }
        do {
            try library.remove(savedFramework)
            ProjectEditor(document: document, undoManager: undoManager).didDeleteFramework(sourceID: savedFramework.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

private struct FrameworkLibraryItem: View {
    let savedFramework: SavedFramework
    let isSelected: Bool
    let isModified: Bool
    let createFramework: () -> Void
    let importFramework: () -> Void
    let apply: () -> Void
    let reset: () -> Void
    let update: () -> Void
    let edit: () -> Void
    let export: () -> Void
    let delete: () -> Void


    var body: some View {
        Button(action: apply) {
            FrameworkArtworkPreview(url: savedFramework.previewURL)
                .id(savedFramework.metadata.modifiedAt)
                .aspectRatio(CGFloat(FrameworkPreviewImage.pixelWidth) / CGFloat(FrameworkPreviewImage.pixelHeight), contentMode: .fit)
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
        .accessibilityLabel("Apply \(savedFramework.metadata.name)")
        .accessibilityValue(isSelected ? (isModified ? "Current framework, modified" : "Current framework") : "")
        .contextMenu { actions }
    }

    private var actions: some View {
        FrameworkActionCommands(
            savedFramework: savedFramework,
            canReset: isSelected && isModified,
            createFramework: createFramework,
            importFramework: importFramework,
            resetFramework: reset,
            updateFramework: { _ in update() },
            editFramework: { _ in edit() },
            exportFramework: { _ in export() },
            deleteFramework: { _ in delete() }
        )
    }
}

private struct FrameworkActionCommands: View {
    let savedFramework: SavedFramework?
    let canReset: Bool
    let createFramework: () -> Void
    let importFramework: () -> Void
    let resetFramework: () -> Void
    let updateFramework: (SavedFramework) -> Void
    let editFramework: (SavedFramework) -> Void
    let exportFramework: (SavedFramework) -> Void
    let deleteFramework: (SavedFramework) -> Void
    var includesCreationActions = true

    var body: some View {
        if includesCreationActions {
            Button("Create New Framework", systemImage: "plus", action: createFramework)
            Button("Import Framework", systemImage: "square.and.arrow.down", action: importFramework)
            Divider()
        }
        if let savedFramework, !savedFramework.isBuiltIn {
            Button("Reset Framework", systemImage: "arrow.counterclockwise", action: resetFramework)
                .disabled(!canReset)
        }
        Button("Export Framework", systemImage: "square.and.arrow.up") {
            if let savedFramework { exportFramework(savedFramework) }
        }
        .disabled(savedFramework == nil)
        if let savedFramework, !savedFramework.isBuiltIn {
            Button("Edit Framework…", systemImage: "pencil") {
                editFramework(savedFramework)
            }
            Button("Update Framework", systemImage: "arrow.triangle.2.circlepath") {
                updateFramework(savedFramework)
            }
            Divider()
            Button("Delete Framework", systemImage: "trash", role: .destructive) {
                deleteFramework(savedFramework)
            }
        }
    }
}


private struct FrameworkCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let create: (String, FrameworkPreviewImage) throws -> Void
    private let isEditing: Bool
    @State private var name = ""
    @State private var preview: FrameworkPreviewImage?
    @State private var previewImage: NSImage?
    @State private var errorMessage: String?
    @State private var isPreviewDropTargeted = false

    init(editing savedFramework: SavedFramework? = nil, create: @escaping (String, FrameworkPreviewImage) throws -> Void) {
        self.create = create
        isEditing = savedFramework != nil
        _name = State(initialValue: savedFramework?.metadata.name ?? "")
        if let savedFramework {
            do {
                let artwork = try FrameworkBundleStore.preview(from: savedFramework.previewURL)
                _preview = State(initialValue: artwork)
                _previewImage = State(initialValue: NSImage(data: artwork.data))
            } catch {
                _errorMessage = State(initialValue: error.localizedDescription)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Edit Framework" : "Create New Framework")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.headline)
                TextField("Framework title", text: $name)
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
                                Text("or click to choose · PNG, JPEG, or WebP · recommended \(FrameworkPreviewImage.pixelWidth) × \(FrameworkPreviewImage.pixelHeight) px (2:1)")
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
                Button(isEditing ? "Save Changes" : "Create Framework") { createFramework() }
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
            preview = try FrameworkBundleStore.preview(from: url)
            previewImage = NSImage(contentsOf: url)
            errorMessage = nil
        } catch {
            preview = nil
            previewImage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func createFramework() {
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
    static let foundryPack = UTType(exportedAs: "uk.co.garysimpson.foundry.pack", conformingTo: .package)
}
