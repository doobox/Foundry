import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @State private var partGroupExpansion: [UUID: PartInspectorExpansion] = [:]
    let page: Page?
    let currentPage: Page?
    let folder: PageFolder?
    let asset: ProjectAsset?
    let assetLibraryNode: ProjectAssetNode?
    let assetLibrary: [ProjectAssetNode]
    let assetContents: ProjectAssetContents
    let folders: [PageFolder]
    let pages: [Page]
    let publicURL: String
    let part: PartNode?
    let selectedParts: [PartNode]
    let selectedPrimitive: CanvasPrimitiveSelection?
    let selectPrimitive: (CanvasPrimitiveSelection?) -> Void
    let allowsMultiPartEditing: Bool
    let libraryPartType: PartType?
    let assetCollectionSelection: AssetCollectionInspectorSelection?
    let importCollectionFiles: ([AssetCollectionFile]) -> Void
    let templateContext: TemplateInspectorContext?
    let insertTemplate: (UUID) -> Void
    let globalDefinition: ReusablePartDefinition?
    let insertGlobalPart: (UUID) -> Void
    let framework: Framework
    let assets: [ProjectAsset]
    let editor: ProjectEditor
    let reusableDefinition: ReusablePartDefinition?
    let isGlobalOverride: Bool
    let setGlobalOverride: (Bool) -> Void
    let selectInsertedPart: (UUID) -> Void
    let breakpoint: ResponsiveBreakpoint
    let assetUsageCount: (UUID) -> Int
    let renameAsset: (UUID, String) -> Void
    let renameAssetFolder: (UUID, String) -> Void
    let importMedia: (URL, UTType) -> ProjectAsset?
    @Binding var editsSharedDefinition: Bool

    /// The header names what the Inspector is currently showing, mirroring the
    /// branch order of the content below.
    private var headerTitle: String {
        if part != nil, selectedParts.count == 1 || allowsMultiPartEditing {
            return "Part Inspector"
        }
        if selectedParts.count > 1 { return "Multiple Parts Selected" }
        if let assetLibraryNode {
            if case .folder = assetLibraryNode { return "Asset Folder Info" }
            return "Asset Info"
        }
        if let assetCollectionSelection {
            switch assetCollectionSelection {
            case .collection: return "Collection Info"
            case .folder: return "Folder Info"
            case .file: return "Asset Info"
            }
        }
        if templateContext != nil { return "Template Info" }
        if globalDefinition != nil { return "Global Info" }
        if folder != nil { return "Page Folder Info" }
        if asset != nil { return "Asset Info" }
        if page != nil { return "Page Info" }
        if libraryPartType != nil { return "Part Info" }
        return "Inspector"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(headerTitle)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            Divider()
            content
        }
        .navigationTitle("Inspector")
    }

    private var content: some View {
        Group {
            if let part,
               selectedParts.count == 1 || allowsMultiPartEditing {
                PartInspector(
                    part: part,
                    selectedParts: selectedParts,
                    selectedPrimitive: selectedPrimitive,
                    selectPrimitive: selectPrimitive,
                    currentPage: currentPage,
                    framework: framework,
                    assets: assets,
                    assetContents: assetContents,
                    pages: pages,
                    folders: folders,
                    publicURL: publicURL,
                    editor: editor,
                    reusableDefinition: reusableDefinition,
                    isGlobalOverride: isGlobalOverride,
                    setGlobalOverride: setGlobalOverride,
                    selectInsertedPart: selectInsertedPart,
                    breakpoint: breakpoint,
                    importMedia: importMedia,
                    editsSharedDefinition: $editsSharedDefinition,
                    groupExpansion: $partGroupExpansion
                )
                .id(part.id)
            } else if selectedParts.isEmpty,
                      page == nil,
                      folder == nil,
                      asset == nil,
                      assetLibraryNode == nil,
                      assetCollectionSelection == nil,
                      templateContext == nil,
                      globalDefinition == nil,
                      let libraryPartType {
                PartLibraryInspector(type: libraryPartType)
            } else {
                if let page {
                    // Hand-rolled labelled form: bordered boxes and native
                    // controls read as editable at a glance, unlike the inset
                    // grouped style where every row looks like plain text.
                    Form {
                        PageInspector(
                            page: page,
                            pages: pages,
                            folders: folders,
                            publicURL: publicURL,
                            assets: assets,
                            assetContents: assetContents,
                            editor: editor
                        )
                    }
                    .formStyle(.grouped)
                } else {
                    Form {
                        inspectorFormContent
                    }
                    .formStyle(.grouped)
                }
            }
        }
    }

    @ViewBuilder
    private var inspectorFormContent: some View {
        if selectedParts.count > 1 {
                Section("Multiple Selection") {
                    LabeledContent("Parts", value: selectedParts.count.formatted())
                    Text("Select instances of the same local component to edit their settings together.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        } else if let assetLibraryNode {
            AssetLibraryNodeInspector(
                node: assetLibraryNode,
                library: assetLibrary,
                contents: assetContents,
                usageCount: assetUsageCount,
                renameAsset: renameAsset,
                renameFolder: renameAssetFolder
            )
        } else if let assetCollectionSelection {
            AssetCollectionInspector(
                selection: assetCollectionSelection,
                importFiles: importCollectionFiles
            )
        } else if let templateContext {
            TemplateInspector(
                context: templateContext,
                editor: editor,
                assetContents: assetContents,
                currentPage: currentPage,
                insertTemplate: insertTemplate
            )
        } else if let globalDefinition {
            GlobalPartInspector(
                definition: globalDefinition,
                pages: pages,
                currentPage: currentPage,
                editor: editor,
                assetContents: assetContents,
                insertGlobalPart: insertGlobalPart
            )
        } else if let folder {
            PageFolderInspector(folder: folder, folders: folders, editor: editor)
        } else if let asset {
            PageAssetInspector(asset: asset, content: assetContents[asset.id], folders: folders)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "info.circle",
                description: Text("Select a page, folder, or part to edit it.")
            )
        }
    }
}

private struct PartLibraryInspector: View {
    let type: PartType
    @AppStorage(AppPreferenceKey.showsDeveloperPanel) private var enablesDeveloperTools = false

    var body: some View {
        let package = type.definition.package
        Form {
            Section {
                PartLibraryInspectorHeader(
                    type: type,
                    description: type.libraryDescription,
                    isDevelopmentPack: package?.isDevelopmentPack == true
                )
            }

            Section("Part") {
                PartLibraryInspectorMetadata(
                    identifier: type.rawValue,
                    developer: package?.manifest.author,
                    version: package.flatMap(displayVersion),
                    category: type.definition.category.rawValue,
                    helpURL: package?.manifest.helpURL
                )
            }

            if let tags = package?.manifest.tags, !tags.isEmpty {
                Section("Tags") {
                    PartLibraryInspectorTags(tags: tags)
                }
            }

            if let updateSourceURL = package?.updateSourceURL {
                Section("Updates") {
                    PartLibraryUpdateControls(sourceURL: updateSourceURL)
                }
            }

            if enablesDeveloperTools, let package, !package.isBuiltIn {
                PartPackConversionControls(package: package)
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .font(.callout)
    }

    private func displayVersion(for package: LoadedPartPackage) -> String? {
        let metadataSourceURL = package.developmentPackRootURL ?? package.updateSourceURL
        guard let metadataSourceURL,
              let metadataPack = try? FoundryPackLoader.load(from: metadataSourceURL) else {
            return package.manifest.version
        }
        return metadataPack.metadata.version ?? package.manifest.version
    }
}

private struct PartPackConversionControls: View {
    let package: LoadedPartPackage
    @State private var convertedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Section(conversionTitle) {
            Button("Click to Convert", systemImage: "arrow.triangle.2.circlepath") {
                convert()
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var packURL: URL {
        convertedURL ?? PartPackageCatalog.shared.conversionRootURL(for: package)
    }

    private var isDevelopmentPack: Bool {
        packURL.pathExtension.caseInsensitiveCompare("foundrydevpack") == .orderedSame
    }

    private var conversionTitle: String {
        isDevelopmentPack ? "Convert to .foundrypack" : "Convert to .foundrydevpack"
    }

    private func convert() {
        errorMessage = nil
        let destinationExtension = isDevelopmentPack ? "foundrypack" : "foundrydevpack"
        do {
            convertedURL = try PartPackageCatalog.shared.convertPack(
                at: packURL,
                toExtension: destinationExtension
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PartLibraryUpdateControls: View {
    let sourceURL: URL
    @State private var isChecking = false
    @State private var status: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Check for Updates", systemImage: "arrow.triangle.2.circlepath") {
                checkForUpdates()
            }
            .disabled(isChecking)
            if isChecking {
                ProgressView("Checking…")
                    .controlSize(.small)
            }
            if let status {
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkForUpdates() {
        isChecking = true
        status = nil
        errorMessage = nil
        Task {
            do {
                let version = try await FoundryPackUpdater.checkAndInstallUpdate(for: sourceURL)
                status = "Updated to version \(version)."
            } catch FoundryPackUpdateError.noCompatibleRelease {
                status = "This pack is up to date."
            } catch {
                errorMessage = error.localizedDescription
            }
            isChecking = false
        }
    }
}

private struct PartLibraryInspectorHeader: View {
    let type: PartType
    let description: String
    let isDevelopmentPack: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PartSquareIcon(type: type, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isDevelopmentPack {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(type.displayName)
                        .font(.headline)
                }
                Text(description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct PartLibraryInspectorMetadata: View {
    let identifier: String
    let developer: String?
    let version: String?
    let category: String
    let helpURL: URL?

    var body: some View {
        row("Developer") { Text(normalizedDeveloper) }
        row("Version") { Text(version ?? "—") }
        row("Category") { Text(category) }
        row("Identifier") {
            Text(identifier)
                .monospaced()
                .textSelection(.enabled)
        }
        if let helpURL {
            row("Help") {
                Link("Open Documentation", destination: helpURL)
                    .help(helpURL.absoluteString)
            }
        }
    }

    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        LabeledContent {
            value()
        } label: {
            Text("\(label):")
                .foregroundStyle(.secondary)
        }
    }

    private var normalizedDeveloper: String {
        developer.flatMap { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        } ?? "Unknown Developer"
    }
}

private struct PartLibraryInspectorTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 64), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

private struct AssetLibraryNodeInspector: View {
    let node: ProjectAssetNode
    let library: [ProjectAssetNode]
    let contents: ProjectAssetContents
    let usageCount: (UUID) -> Int
    let renameAsset: (UUID, String) -> Void
    let renameFolder: (UUID, String) -> Void

    var body: some View {
        switch node {
        case .asset(let asset):
            if let content = contents[asset.id], NSImage(data: content.data) != nil {
                Section("Preview") {
                    AssetImagePreview(data: content.data, filename: asset.filename)
                }
            }
            Section("File") {
                TextField(
                    "Filename",
                    text: Binding(
                        get: { asset.filename },
                        set: { renameAsset(asset.id, $0) }
                    )
                )
                LabeledContent("Type", value: asset.mediaType)
                LabeledContent("Size", value: asset.byteCount.formatted(.byteCount(style: .file)))
                LabeledContent("Uses", value: usageCount(asset.id).formatted())
                LabeledContent("Library Path", value: libraryPath(to: asset.id))
                LabeledContent("Managed Path", value: "/\(library.managedExportPath(for: asset))")
            }
            if asset.mediaType.hasPrefix("font/") || ["ttf", "otf", "woff", "woff2", "ttc"].contains((asset.filename as NSString).pathExtension.lowercased()) {
                Section("Font") {
                    if let content = contents[asset.id], let metadata = FontFileMetadata.read(content) {
                        LabeledContent("Family", value: metadata.family)
                        LabeledContent("Face", value: metadata.face)
                        LabeledContent("Weight", value: metadata.weight == metadata.maximumWeight
                            ? String(metadata.weight)
                            : "\(metadata.weight)–\(metadata.maximumWeight)")
                        LabeledContent("Style", value: metadata.italic ? "Italic" : "Normal")
                    } else {
                        Text("Font metadata is unavailable for this file.")
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
                if let content = contents[asset.id], let metadata = FontFileMetadata.read(content) {
                    Section("Preview") {
                        GoogleFontSpecimenView(
                            family: metadata.family,
                            stylesheetURL: nil,
                            fontContent: content
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .id(asset.id)
                    }
                }
            }
        case .folder(let folder):
            Section("Asset Folder") {
                TextField(
                    "Name",
                    text: Binding(
                        get: { folder.name },
                        set: { renameFolder(folder.id, $0) }
                    )
                )
                LabeledContent("Path", value: libraryPath(to: folder.id))
                LabeledContent("Items", value: folder.children.count.formatted())
                LabeledContent("Files", value: fileCount(in: folder.children).formatted())
            }
        }
    }

    private func libraryPath(to id: UUID) -> String {
        func find(_ nodes: [ProjectAssetNode], parts: [String]) -> [String]? {
            for node in nodes {
                switch node {
                case .asset(let asset):
                    if asset.id == id { return parts + [asset.filename] }
                case .folder(let folder):
                    let path = parts + [folder.name]
                    if folder.id == id { return path }
                    if let match = find(folder.children, parts: path) { return match }
                }
            }
            return nil
        }
        return "/" + (find(library, parts: []) ?? []).joined(separator: "/")
    }

    private func fileCount(in nodes: [ProjectAssetNode]) -> Int {
        nodes.reduce(into: 0) { count, node in
            switch node {
            case .asset:
                count += 1
            case .folder(let folder):
                count += fileCount(in: folder.children)
            }
        }
    }
}

private struct PageAssetInspector: View {
    let asset: ProjectAsset
    let content: ProjectAssetContent?
    let folders: [PageFolder]

    var body: some View {
        if let content, NSImage(data: content.data) != nil {
            Section("Preview") {
                AssetImagePreview(data: content.data, filename: asset.filename)
            }
        }
        Section("File") {
            LabeledContent("Filename", value: asset.filename)
            LabeledContent("Type", value: asset.mediaType)
            LabeledContent("Size", value: asset.byteCount.formatted(.byteCount(style: .file)))
            LabeledContent("Path", value: exportPath)
            Text("This file is exported only at the path above. Part references follow that path.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var exportPath: String {
        let filename = (asset.filename as NSString).lastPathComponent
        switch asset.exportDirectory {
        case .root:
            return "/\(filename)"
        case .folder(let folderID):
            return "/\(folderPath(folderID))/\(filename)"
        case nil:
            return "/\(asset.exportPath)"
        }
    }

    private func folderPath(_ folderID: UUID) -> String {
        var currentID: UUID? = folderID
        var slugs: [String] = []
        var visited = Set<UUID>()
        while let id = currentID,
              visited.insert(id).inserted,
              let folder = folders.first(where: { $0.id == id }) {
            slugs.insert(folder.slug, at: 0)
            currentID = folder.parentID
        }
        return slugs.joined(separator: "/")
    }
}

private struct AssetImagePreview: View {
    let data: Data
    let filename: String

    var body: some View {
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 240)
                .accessibilityLabel("Preview of \(filename)")
        }
    }
}

private struct PageFolderInspector: View {
    let folder: PageFolder
    let folders: [PageFolder]
    let editor: ProjectEditor

    var body: some View {
        Section("Folder") {
            TextField(
                "Name",
                text: Binding(
                    get: { folder.name },
                    set: { editor.renamePageFolder(id: folder.id, name: $0) }
                )
            )
            TextField(
                "URL Name",
                text: Binding(
                    get: { folder.slug },
                    set: { editor.setPageFolderSlug(id: folder.id, slug: $0) }
                )
            )
            LabeledContent("Path", value: "/\(path)/")
            Text("This folder becomes a directory when the site is exported.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Include in Navigation", isOn: Binding(
                get: { folder.includeInNavigation },
                set: { editor.setPageFolderIncludeInNavigation(id: folder.id, value: $0) }
            ))
            Text("Shows this folder in site menus as a group containing its pages.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var path: String {
        var current: PageFolder? = folder
        var slugs: [String] = []
        var visited = Set<UUID>()
        while let value = current, visited.insert(value.id).inserted {
            slugs.insert(value.slug, at: 0)
            current = value.parentID.flatMap { id in folders.first { $0.id == id } }
        }
        return slugs.joined(separator: "/")
    }
}

/// A text field that commits on Return or focus loss, then snaps its text to
/// the normalized value the editor actually stored — so typing a path like
/// photos/2026 isn't fought character-by-character by normalization.
private struct DeferredTextField: View {
    let label: String
    let prompt: String
    let value: String
    let commit: (String) -> String
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(label, text: $text, prompt: Text(prompt))
            .focused($isFocused)
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in
                if !isFocused { text = newValue }
            }
            .onSubmit { text = commit(text) }
            .onChange(of: isFocused) { _, focused in
                if !focused { text = commit(text) }
            }
    }
}

private struct PageInspector: View {
    @Environment(\.canvasAppearance) private var appearance
    @Environment(\.openURL) private var openURL
    let page: Page
    let pages: [Page]
    let folders: [PageFolder]
    /// Passed in rather than read off the editor so the view re-renders when
    /// the Project Settings address changes.
    let publicURL: String
    let assets: [ProjectAsset]
    let assetContents: ProjectAssetContents
    let editor: ProjectEditor
    // Mirrors page.language for the picker: "" inherits, a curated code
    // selects directly, and the custom sentinel reveals the tag field.
    @State private var languageSelection = ""
    @State private var customLanguage = ""

    var body: some View {
        Section{
            labelledField("Browser Title", text: metadataBinding(\.browserTitle), prompt: page.title)
        }
        .textFieldStyle(.roundedBorder)


        Section {
            VStack(spacing: 12) {
                labelledField(
                    "Page Title",
                    text: Binding(
                        get: { page.title },
                        set: { editor.renamePage(id: page.id, title: $0) }
                    )
                )

                labelledField(
                    "Search Description",
                    text: metadataBinding(\.description),
                    prompt: "A short description of the page — ideally about 155 characters",
                    lines: 3...6,
                    limit: 155
                )
            }
            .listRowSeparator(.hidden)
        }
        .textFieldStyle(.roundedBorder)


        Section {
            VStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Published URL").font(.callout)
                    HStack{
                        TextField("", text: .constant(""), prompt: Text(publicURL + urlPath))
                            .allowsHitTesting(false)
                            .focusable(false)
                            .labelsHidden()

                        Button("Open Page", systemImage: "link") {
                            if let liveURL {
                                openURL(liveURL)
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .contentShape(.rect)
                        .disabled(liveURL == nil)
                        .help(liveURL?.absoluteString ?? "Set the website address in Project Settings to open the live page")
                    }
                }
                
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 15) {
                    GridRow {
                        Text("Folder").font(.callout)
                        DeferredTextField(
                            label: "Folder",
                            prompt: isHome ? "/" : derivedFolderPlaceholder,
                            value: page.folderOverride ?? ""
                        ) { editor.setPageFolderOverride(id: page.id, value: $0) ?? "" }
                            .labelsHidden()
                            .disabled(isHome)
                    }
                    GridRow {
                        Text("Filename").font(.callout)
                        DeferredTextField(
                            label: "Filename",
                            prompt: defaultFilenamePlaceholder,
                            value: page.filenameOverride ?? ""
                        ) { editor.setPageFilename(id: page.id, value: $0) ?? "" }
                            .labelsHidden()
                    }
                    if isHome {
                        GridRow {
                            Color.clear.frame(width: 0, height: 0)
                            // The setter silently keeps the old value for
                            // anything else, so say what it will take.
                            Text("The home page is always index. Type index.html or index.php to choose its extension.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .listRowSeparator(.hidden)
        }
        .textFieldStyle(.roundedBorder)


        Section {
            VStack(spacing: 12) {
                Toggle(
                    "Include in Navigation",
                    isOn: Binding(
                        get: { page.includeInNavigation },
                        set: { editor.setPageIncludedInNavigation(id: page.id, included: $0) }
                    )
                )
                Toggle(
                    "Include in Search",
                    isOn: Binding(
                        get: { page.includeInSearch },
                        set: { editor.setPageIncludedInSearch(id: page.id, included: $0) }
                    )
                )
                Toggle(
                    "Include in Sitemap",
                    isOn: Binding(
                        get: { page.includeInSitemap },
                        set: { editor.setPageIncludedInSitemap(id: page.id, included: $0) }
                    )
                )
            }
            .listRowSeparator(.hidden)
        }
        .textFieldStyle(.roundedBorder)


        Section {
            VStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Page Background").font(.callout)
                    if page.backgroundOverride == nil {
                        Text("Using Bootstrap body background. Choosing a colour below creates a page override.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    FrameworkColorControlContent(
                        label: "Background",
                        choices: framework.colorChoices,
                        allowsCustom: true,
                        framework: framework,
                        source: backgroundSource,
                        shade: backgroundShade,
                        customColor: backgroundCustomColour,
                        allowsOpacity: false,
                        resetToFramework: { editor.setPageBackground(id: page.id, value: nil) },
                        canResetToFramework: page.backgroundOverride != nil
                    )
                }
            }
            .listRowSeparator(.hidden)
        }
        .textFieldStyle(.roundedBorder)


        Section {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 15) {
                GridRow {
                    Text("Language").font(.callout)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Language", selection: Binding(
                            get: { languageSelection },
                            set: { code in
                                languageSelection = code
                                if code == Self.customLanguageCode {
                                    editor.setPageLanguage(id: page.id, language: customLanguage.isEmpty ? nil : customLanguage)
                                } else {
                                    editor.setPageLanguage(id: page.id, language: code.isEmpty ? nil : code)
                                }
                            }
                        )) {
                            Text("Inherit Site Language").tag("")
                            Divider()
                            ForEach(SiteLanguageOption.common) { language in
                                Text("\(language.name) — \(language.code)").tag(language.code)
                            }
                            Divider()
                            Text("Custom…").tag(Self.customLanguageCode)
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if languageSelection == Self.customLanguageCode {
                            TextField(
                                "Language Tag",
                                text: Binding(
                                    get: { customLanguage },
                                    set: { value in
                                        customLanguage = value
                                        editor.setPageLanguage(id: page.id, language: value.isEmpty ? nil : value)
                                    }
                                ),
                                prompt: Text("e.g. cy or zh-Hant-TW").foregroundStyle(.secondary)
                            )
                            .labelsHidden()
                            if !customLanguage.isEmpty, !SiteLanguageOption.isValidTag(customLanguage) {
                                Text("Enter a valid language tag, such as en, en-GB, or zh-Hant.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .listRowSeparator(.hidden)
            .onChange(of: page.id, initial: true) { _, _ in
                syncLanguageState()
            }
            .onChange(of: page.language) { _, _ in
                syncLanguageState()
            }
        }

        Section {
            VStack(spacing: 12) {
                labelledField("Social Title", text: metadataBinding(\.socialTitle), prompt: "Uses the browser title")
                labelledField("Social Description", text: metadataBinding(\.socialDescription), prompt: "Uses the search description", lines: 3...6, limit: 200)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Social Image").font(.callout)
                    SiteLogoImageWell(
                        selection: metadataBinding(\.socialImage),
                        assets: imageAssets,
                        assetContents: assetContents,
                        imageName: "Social Image",
                        importImage: importSocialImage
                    )
                    Text("Shown when this page is shared; leave empty to use the site-wide social image. Use a landscape image — 1200 × 630 pixels is the usual sharing size.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowSeparator(.hidden)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var imageAssets: [ProjectAsset] {
        assets
            .filter { $0.mediaType.hasPrefix("image/") }
            .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    private func importSocialImage(_ data: Data, filename: String, mediaType: String) {
        let undoManager = editor.undoManager
        undoManager?.beginUndoGrouping()
        let id = editor.document.importAsset(
            data: data,
            filename: filename,
            mediaType: mediaType,
            undoManager: undoManager
        )
        metadataBinding(\.socialImage).wrappedValue = "foundry-asset:\(id.uuidString)"
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Set Social Image")
    }

    /// An Elements-style labelled input: the label sits above a full-width
    /// bordered field.
    private func labelledField(
        _ label: String,
        text: Binding<String>,
        prompt: String? = nil,
        lines: ClosedRange<Int>? = nil,
        limit: Int? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout)
                if let limit {
                    Spacer()
                    let count = text.wrappedValue.count
                    Text("\(count)/\(limit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(count > limit ? Color.red : count > limit - 20 ? Color.orange : Color.secondary)
                        .help("Search engines and link previews usually truncate after about \(limit) characters.")
                }
            }
            TextField(label, text: text, prompt: prompt.map(Text.init), axis: lines == nil ? .horizontal : .vertical)
                .labelsHidden()
                .lineLimit(lines ?? 1...1)
        }
    }

    private var isHome: Bool { page.slug == "index" }

    private var urlPath: String {
        StaticSiteRenderer.urlPath(for: page, pages: pages, folders: folders)
    }

    /// The page's live address: the site's public URL joined with this page's
    /// path. Nil while Project Settings has no complete http(s) address, so
    /// the link button can disable itself.
    private var liveURL: URL? {
        guard let url = URL(string: publicURL + urlPath),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil else { return nil }
        return url
    }

    /// The folder the page tree would publish to, shown while no override is set.
    private var derivedFolderPlaceholder: String {
        var derived = page
        derived.folderOverride = nil
        let segments = PageRouteResolver.pathSegments(for: derived, pages: pages, folders: folders)
        return segments.isEmpty ? "/" : segments.joined(separator: "/")
    }

    private var defaultFilenamePlaceholder: String {
        var derived = page
        derived.filenameOverride = nil
        return StaticSiteRenderer.filename(for: derived)
    }

    private static let customLanguageCode = "__custom__"

    private func syncLanguageState() {
        let value = page.language ?? ""
        if value.isEmpty {
            languageSelection = ""
            customLanguage = ""
        } else if SiteLanguageOption.common.contains(where: { $0.code == value }) {
            languageSelection = value
            customLanguage = ""
        } else {
            languageSelection = Self.customLanguageCode
            customLanguage = value
        }
    }

    private var framework: Framework { editor.document.site.framework }
    private var background: PartPackageColorValue { page.backgroundSelection(framework: framework) }

    private var backgroundSource: Binding<String> {
        Binding(get: { background.source }, set: { source in
            var value = background
            value.source = source
            if let palette = framework.colourPalettes.resolvedPalette(id: value.paletteID) {
                value.shade = palette.lightDefaultShade
                value.darkShade = palette.darkDefaultShade
            }
            editor.setPageBackground(id: page.id, value: value)
        })
    }

    private var backgroundShade: Binding<ColourShade> {
        Binding(get: { appearance == .light ? background.shade : background.darkShade }, set: { shade in
            var value = background
            if appearance == .light { value.shade = shade } else { value.darkShade = shade }
            editor.setPageBackground(id: page.id, value: value)
        })
    }

    private var backgroundCustomColour: Binding<Color> {
        Binding(get: { Color(hex: appearance == .light ? background.customColor : background.darkCustomColor) ?? .black }, set: { colour in
            guard let hex = colour.hexString else { return }
            var value = background
            if appearance == .light { value.customColor = hex } else { value.darkCustomColor = hex }
            editor.setPageBackground(id: page.id, value: value)
        })
    }

    private func metadataBinding(
        _ keyPath: WritableKeyPath<PageMetadata, String>
    ) -> Binding<String> {
        Binding(
            get: { page.metadata[keyPath: keyPath] },
            set: { value in
                editor.setPageMetadata(id: page.id) {
                    $0[keyPath: keyPath] = value
                }
            }
        )
    }
}

private struct PartInspectorExpansion {
    var groups: [PartPropertySection] = []
}

private struct PartInspector: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPreferenceKey.inspectorAccordion) private var usesAccordion = true
    @State private var hoversGlobalChildToggle = false
    @State private var hoversExplodeGlobal = false
    let part: PartNode
    let selectedParts: [PartNode]
    let selectedPrimitive: CanvasPrimitiveSelection?
    let selectPrimitive: (CanvasPrimitiveSelection?) -> Void
    let currentPage: Page?
    let framework: Framework
    let assets: [ProjectAsset]
    let assetContents: ProjectAssetContents
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let reusableDefinition: ReusablePartDefinition?
    let isGlobalOverride: Bool
    let setGlobalOverride: (Bool) -> Void
    let selectInsertedPart: (UUID) -> Void
    let breakpoint: ResponsiveBreakpoint
    let importMedia: (URL, UTType) -> ProjectAsset?
    @Binding var editsSharedDefinition: Bool
    @Binding var groupExpansion: [UUID: PartInspectorExpansion]
    /// The section a click just opened, cleared once it has been scrolled
    /// into view.
    @State private var revealedGroup: PartPropertySection?
    // Model updates arrive through the workspace's AppKit hosting controller.
    // Keep displayed membership local so insertions/removals happen in an
    // explicit SwiftUI animation transaction, like disclosure expansion.
    @State private var displayedInspectorIDs: [[String]]?

    private var expandedGroups: [PartPropertySection] {
        groupExpansion[part.id]?.groups ?? []
    }

    /// Whether the part's manifest opts into the Advanced section — the HTML
    /// ID, classes, and custom-attribute fields.
    private var declaresAdvanced: Bool {
        part.type.definition.package?.manifest.controlGroups.contains { $0.type == .advanced } == true
    }

    private var advancedSection: PartPropertySection {
        PartPropertySection(rawValue: "Advanced")
    }

    /// The Inspector never starts fully collapsed: whenever a part arrives
    /// with no group open — never remembered, or remembered as all closed —
    /// its first group opens. Closing every group stays possible within the
    /// current appearance.
    private func openFirstGroupIfAllClosed() {
        guard expandedGroups.isEmpty, let first = visibleInspectorIDs.first?.first else { return }
        groupExpansion[part.id] = PartInspectorExpansion(groups: [.init(rawValue: first)])
    }

    private func setExpanded(_ expanded: Bool, group: PartPropertySection) {
        var groups = expandedGroups.filter { $0 != group }
        if expanded {
            groups = usesAccordion ? [group] : groups + [group]
        }
        groupExpansion[part.id] = PartInspectorExpansion(groups: groups)
        // Opening a section near the bottom would otherwise reveal its
        // controls below the fold, looking like nothing happened.
        if expanded { revealedGroup = group }
    }

    var body: some View {
        // Deliberately not a Form: the control groups size their label column
        // through onGeometryChange, which feedback-loops against a List-backed
        // Form's row measurement and beachballs. A plain scroll view keeps
        // the geometry stable.
        let visibleIDs = visibleInspectorIDs
        let displayedIDs = displayedInspectorIDs ?? visibleIDs
        let rows = part.type.definition.inspectorRows
        let displayedSections = displayedIDs.compactMap { ids -> (section: PartPropertySection, rows: [PartInspectorRow])? in
            guard let name = ids.first else { return nil }
            let membership = Set(ids.dropFirst())
            return (.init(rawValue: name), rows.compactMap { row in
                guard row.section.rawValue == name else { return nil }
                return row.filtered(
                    properties: { membership.contains("property:" + $0.id.rawValue) },
                    childPickers: { membership.contains("slot:" + $0.id) }
                )
            })
        }
        ScrollViewReader { proxy in
            ScrollView {
                // Section heights participate in visibility animations. Keep
                // neighbouring sections in layout rather than lazily estimated.
                VStack(spacing: 0) {
                partIdentityHeader
                    .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))

                if selectedParts.count == 1, let snippets = part.type.definition.package?.showcaseSnippets, !snippets.isEmpty {
                    Divider()
                    PartShowcaseSnippetsSection(snippets: snippets)
                }

                ForEach(displayedSections, id: \.section.rawValue) { section in
                    let group = section.section
                    Divider()
                    PartInspectorGroup(
                        group: group,
                        rows: section.rows,
                        identityFields: declaresAdvanced && group == advancedSection && selectedParts.count == 1
                            ? PartIdentityContext(
                                anchor: partAnchorBinding,
                                classes: partClassesBinding,
                                customCSS: partCustomCSSBinding,
                                attributes: partAttributesBinding,
                                isDuplicateAnchor: partAnchorIsDuplicate
                            )
                            : nil,
                        part: part,
                        selectedParts: selectedParts,
                        selectedPrimitive: selectedPrimitive,
                        selectPrimitive: selectPrimitive,
                        currentPage: currentPage,
                        framework: framework,
                        assets: assets,
                        assetContents: assetContents,
                        pages: pages,
                        folders: folders,
                        publicURL: publicURL,
                        editor: editor,
                        editsSharedDefinition: reusableDefinition != nil && !isGlobalOverride,
                        breakpoint: breakpoint,
                        importMedia: importMedia,
                        selectInsertedPart: selectInsertedPart,
                        isExpanded: Binding(
                            get: { expandedGroups.contains(group) },
                            set: { setExpanded($0, group: group) }
                        ),
                        usesAccordion: $usesAccordion,
                        openAll: {
                            groupExpansion[part.id] = PartInspectorExpansion(groups: visibleIDs.compactMap { $0.first.map { .init(rawValue: $0) } })
                        },
                        closeAll: {
                            groupExpansion[part.id] = PartInspectorExpansion()
                        }
                    )
                    .id(group)
                    .transition(.opacity)
                }
                }
            }
            .onChange(of: revealedGroup) { _, group in
                guard let group else { return }
                // Wait for the disclosure content to enter the layout, then
                // move its header to the top so the revealed controls are
                // visibly connected to the section the user clicked.
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(group, anchor: .top)
                    }
                    revealedGroup = nil
                }
            }
        }
        .controlSize(.small)
        .font(.callout)
        .onChange(of: visibleIDs, initial: true) { _, updated in
            let animation: Animation? = displayedInspectorIDs == nil || reduceMotion
                ? nil : .easeInOut(duration: 0.15)
            withAnimation(animation) {
                displayedInspectorIDs = updated
            }
        }
        .onChange(of: usesAccordion, initial: true) { _, enabled in
            if enabled {
                // Keep the most recently opened group for every remembered part.
                groupExpansion = groupExpansion.mapValues {
                    PartInspectorExpansion(groups: Array($0.groups.suffix(1)))
                }
            }
        }
        .onChange(of: part.id, initial: true) { _, _ in
            openFirstGroupIfAllClosed()
        }
    }

    /// Animate membership changes across the whole stack so neighbouring
    /// sections move too. Ordinary value edits leave this signature unchanged.
    private var visibleInspectorIDs: [[String]] {
        var sections: [[String]] = []
        var indices: [PartPropertySection: Int] = [:]
        for row in part.type.definition.inspectorRows {
            guard PartPackageVisibilityEvaluator.isVisible(
                part.type.definition.visibilityCondition(for: row.section),
                for: part,
                at: breakpoint,
                screens: framework.screens
            ) else { continue }
            guard let visible = row.filtered(
                properties: { isVisible($0) },
                childPickers: { selectedParts.count == 1 && isVisible($0) }
            ) else { continue }
            let index: Int
            if let existing = indices[visible.section] {
                index = existing
            } else {
                index = sections.count
                indices[visible.section] = index
                sections.append([visible.section.rawValue])
            }
            sections[index].append(contentsOf: visible.membershipIDs)
        }
        if declaresAdvanced, indices[advancedSection] == nil {
            sections.append([advancedSection.rawValue])
        }
        return sections
    }

    private func isVisible(_ slot: PartPackageSlot) -> Bool {
        PartPackageVisibilityEvaluator.isVisible(slot.visibleWhen, for: part, at: breakpoint, screens: framework.screens)
    }

    private func isVisible(_ property: PartPropertyDefinition) -> Bool {
        property.isInspectorVisible && PartPackageVisibilityEvaluator.isVisible(
            property.visibleWhen,
            for: part,
            at: property.isResponsive ? breakpoint : .mobile,
            screens: framework.screens
        )
    }

    private var partIdentityHeader: some View {
        // Mirrors the Part Info header card exactly: same icon size, text
        // styles and spacing — only the subtitle rows differ.
        HStack(alignment: .top, spacing: 12) {
            PartSquareIcon(type: part.type, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if part.type.definition.package?.isDevelopmentPack == true {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(partHeaderTitle)
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(partTypeAndVersion)
                    Text(partDeveloper)
                    if selectedParts.count == 1, reusableDefinition != nil {
                        if isGlobalRoot {
                            // Reads like the status line but acts: exploding
                            // is the root's only global affordance.
                            Button {
                                editor.explodeGlobalPart(partID: part.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "burst")
                                    Text("Explode Global")
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .fontWeight(.medium)
                            .foregroundStyle(hoversExplodeGlobal ? Color.blue : Color.green)
                            .padding(.top, 4)
                            .help("Disconnect this instance from its global; the parts stay on the page.")
                            .onHover { hovering in
                                hoversExplodeGlobal = hovering
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                        } else {
                            // The status line is also the switch: clicking
                            // toggles the child's local override, and hovering
                            // previews the icon of the state a click produces.
                            Button {
                                setGlobalOverride(!isGlobalOverride)
                            } label: {
                                HStack(spacing: 4) {
                                    // Hovering previews the state a click
                                    // produces: linked shows the slashed pin,
                                    // unlinked shows the plain pin.
                                    Image(systemName: isGlobalOverride != hoversGlobalChildToggle
                                        ? "pin.slash"
                                        : "pin")
                                    Text(globalIndicatorLabel)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .fontWeight(.medium)
                            // Hover previews the destination state's colour
                            // along with the icon: pinned goes blue, unpinned
                            // goes green.
                            .foregroundStyle(isGlobalOverride != hoversGlobalChildToggle ? Color.blue : Color.green)
                            .padding(.top, 4)
                            .help(isGlobalOverride
                                ? "Re-link this child; it follows the global's values again."
                                : "Override this child locally; it stops following the global's values.")
                            .onHover { hovering in
                                hoversGlobalChildToggle = hovering
                                // set() rather than push/pop: the hover also
                                // rebuilds this view, which unbalances a
                                // pushed cursor stack.
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // A showcase is a demo of one control; its reference page is the
            // next thing a developer wants, so it sits right by the title.
            if let package = part.type.definition.package, package.isControlShowcase,
               let helpURL = package.manifest.helpURL {
                Link(destination: helpURL) {
                    Label("API Docs", systemImage: "book")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(helpURL.absoluteString)
            }
        }
        .padding(.vertical, 2)
    }

    private var partTypeAndVersion: String {
        let name = part.type.displayName
        guard let version = part.type.definition.package?.manifest.version else { return name }
        return "\(name) v\(version)"
    }

    private var partDeveloper: String {
        part.type.definition.package?.manifest.author.flatMap { author in
            author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : author
        } ?? "Unknown Developer"
    }

    private var partHeaderTitle: String {
        // Children inside a global keep their own identity; only the global's
        // root instance wears the definition's name, matching the type icon.
        let name = part.reusableDefinitionID == reusableDefinition?.id
            ? (reusableDefinition?.name ?? part.type.displayName)
            : part.type.displayName
        return selectedParts.count > 1 ? "\(name) · \(selectedParts.count) selected" : name
    }

    private var isGlobalRoot: Bool {
        reusableDefinition != nil && part.reusableDefinitionID != nil
    }

    private var globalIndicatorColor: Color {
        isGlobalOverride && !isGlobalRoot ? .blue : .green
    }

    private var globalIndicatorLabel: String {
        if isGlobalRoot { return "Global" }
        return isGlobalOverride ? "Pin to Global" : "Unpin from Global"
    }


    private var partAnchorBinding: Binding<String> {
        Binding(
            get: { part.anchor ?? "" },
            set: { editor.setPartAnchor(id: part.id, anchor: $0) }
        )
    }

    private var partClassesBinding: Binding<String> {
        Binding(
            get: { part.customClasses ?? "" },
            set: { editor.setPartClasses(id: part.id, classes: $0) }
        )
    }

    private var partCustomCSSBinding: Binding<String> {
        Binding(
            get: { part.customCSS ?? "" },
            set: { editor.setPartCustomCSS(id: part.id, css: $0) }
        )
    }

    private var partAttributesBinding: Binding<[PartHTMLAttribute]> {
        Binding(
            get: { part.rootAttributes ?? [] },
            set: { editor.setPartRootAttributes(id: part.id, attributes: $0) }
        )
    }

    private var partAnchorIsDuplicate: Bool {
        guard let anchor = part.anchor, !anchor.isEmpty, let currentPage else { return false }
        return currentPage.parts.reduce(0) { $0 + anchorCount(anchor, in: $1) } > 1
    }

    private func anchorCount(_ anchor: String, in node: PartNode) -> Int {
        let matches = node.anchor == anchor
        return (matches ? 1 : 0) + node.children.reduce(0) { $0 + anchorCount(anchor, in: $1) }
    }
}

/// The copy-and-go code a Controls showcase part carries: the control's
/// declaration, its template usage and any CSS, each with a Copy button.
private struct PartShowcaseSnippetsSection: View {
    let snippets: [PartShowcaseSnippet]
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "curlybraces")
                    .foregroundStyle(.secondary)
                Text("Snippets")
                    .font(.headline)
            }
            Text("Paste these into your own part to start from a working declaration.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(snippets) { snippet in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(snippet.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(copiedID == snippet.id ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(snippet.text, forType: .string)
                            copiedID = snippet.id
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                if copiedID == snippet.id { copiedID = nil }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Copy \(snippet.title) to the clipboard")
                    }
                    ScrollView(.horizontal) {
                        Text(snippet.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }
}

private struct PartSlotInspectorCard: View {
    let slot: PartPackageSlot
    let part: PartNode
    let pageID: UUID
    let editor: ProjectEditor
    let selectInsertedPart: (UUID) -> Void

    private var availableTypes: [PartType] {
        PartRegistry.availableTypes
            .filter {
                slot.offersInPicker($0) &&
                    ($0.definition.package?.manifest.permits(parent: part.type) ?? true)
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var children: [PartNode] {
        let definition = part.type.definition
        let package = definition.package
        let defaultSlotID = package?.dropZoneNames.first.map { package?.dropZoneSlotID(for: $0) ?? "" }
            ?? definition.inspectorRows.lazy.compactMap { row -> String? in
                if case .childPicker(let slot) = row { return slot.id }
                return nil
            }.first
        return part.children.filter { child in
            (child.slotID ?? defaultSlotID) == slot.id
        }
    }

    var body: some View {
        let options = availableTypes
        ChildPickerPartControl(
            label: slot.title,
            buttonText: slot.buttonText,
            buttonIcon: slot.buttonIcon,
            options: options,
            action: .resolve(options: options, childCount: slot.maximum == nil ? 0 : children.count, maximum: slot.maximum),
            help: slot.tooltip,
            add: addChild
        )
    }

    private func addChild(_ type: PartType) {
        guard availableTypes.contains(type),
              slot.maximum.map({ children.count < $0 }) ?? true else { return }
        guard let insertedID = editor.insertPart(
            type: type,
            on: pageID,
            placement: .insideSlot(part.id, slot.id)
        ) else { return }
        selectInsertedPart(insertedID)
    }
}

/// The opt-in Advanced section's fields: HTML ID, classes, custom CSS and
/// custom attributes for the placed part. Shown only when the part's
/// manifest declares the `advanced` grouped control.
private struct PartIdentityFields: View {
    @Binding var anchor: String
    @Binding var classes: String
    @Binding var customCSS: String
    @Binding var attributes: [PartHTMLAttribute]
    let isDuplicateAnchor: Bool
    @State private var showsAddAttributePopover = false
    /// The CSS is edited here and committed to the document on a short
    /// debounce and on losing focus. Binding the editor straight to the
    /// document reset its text on every keystroke and threw the cursor to
    /// the end.
    @State private var cssDraft = AttributedString("")
    @FocusState private var isEditingCSS: Bool
    private static let cssFontSize: CGFloat = 12

    var body: some View {
        InspectorGrid(contentInsets: EdgeInsets()) {
            InspectorRow(title: "ID") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("ID", text: $anchor)
                        .frame(maxWidth: .infinity)
                    if !anchor.isEmpty && !PartAnchorValidator.isValid(anchor) {
                        Text("Enter a valid ID.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if isDuplicateAnchor {
                        Text("ID already in use.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            InspectorRow(title: "Classes", alignment: .top) {
                // Starts three lines tall and grows with its content.
                TextField("Classes", text: $classes, axis: .vertical)
                    .lineLimit(3...12)
                    .frame(maxWidth: .infinity)
            }

            InspectorRow(title: "CSS", alignment: .top) {
                HighlightedCodeEditor(text: $cssDraft, language: .css, fontSize: Self.cssFontSize)
                    .focused($isEditingCSS)
                    .onAppear { cssDraft = highlighted(customCSS) }
                    .onChange(of: customCSS) { _, updated in
                        if !isEditingCSS { cssDraft = highlighted(updated) }
                    }
                    .onChange(of: isEditingCSS) { _, focused in
                        if !focused { commitCSS() }
                    }
                    .task(id: draftCSS) {
                        // Live enough for the canvas to follow, without a
                        // document mutation per keystroke.
                        guard isEditingCSS else { return }
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        commitCSS()
                    }
                    // Match the rounded text fields above: no editor
                    // background or border, the same fill and corners,
                    // three lines tall to start and growing with the text.
                    .scrollContentBackground(.hidden)
                    .frame(height: cssEditorHeight)
                    .padding(.vertical, 3)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        // TextEditor has no prompt, so show one like the fields above.
                        if draftCSS.isEmpty {
                            Text("CSS")
                                .foregroundStyle(Color(nsColor: .placeholderTextColor))
                                .padding(.leading, 5)
                                .padding(.top, 3)
                                .allowsHitTesting(false)
                        }
                    }
                    .help("CSS for this part only. Declarations style the part itself, :hover { … } styles it when hovered, and h2 { … } styles elements inside it.")
            }

            GridRow {
                Divider()
                    .gridCellColumns(2)
            }

            InspectorRow(title: "Attributes") {
                VStack(alignment: .leading, spacing: 0) {
                    if !attributes.isEmpty {
                        PartAttributeRows(attributes: $attributes)
                            .padding(.bottom, 15)
                    }
                    Button("Add Attribute…") {
                        showsAddAttributePopover = true
                    }
                    .popover(isPresented: $showsAddAttributePopover, arrowEdge: .trailing) {
                        PartAttributePopover(
                            attribute: nil,
                            existingAttributes: attributes
                        ) { attribute in
                            attributes.append(attribute)
                        }
                    }
                }
            }
        }
    }
    private var draftCSS: String { String(cssDraft.characters) }

    /// Three lines tall when empty, growing one line per line of CSS up to twelve.
    private var cssEditorHeight: CGFloat {
        let lines = draftCSS.split(separator: "\n", omittingEmptySubsequences: false).count
        let lineHeight = NSFont.monospacedSystemFont(ofSize: Self.cssFontSize, weight: .regular)
            .boundingRectForFont.height
        return CGFloat(min(max(lines, 3), 12)) * lineHeight + 10
    }

    private func highlighted(_ css: String) -> AttributedString {
        SourceSyntaxHighlighter.highlight(css, language: .css, fontSize: Self.cssFontSize)
    }

    private func commitCSS() {
        // Whitespace-only CSS is stored as nothing, so compare what the
        // document would hold rather than the raw text.
        let draft = draftCSS
        let stored = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : draft
        guard stored != customCSS else { return }
        customCSS = draft
    }
}

private struct PartAttributeRows: View {
    @Binding var attributes: [PartHTMLAttribute]
    @State private var editingAttribute: PartHTMLAttribute?

    var body: some View {
        VStack(spacing: InspectorMetrics.rowSpacing) {
            ForEach(attributes) { attribute in
                HStack(spacing: 6) {
                    Button {
                        editingAttribute = attribute
                    } label: {
                        Text(verbatim: #"\#(attribute.name) = "\#(attribute.value)""#)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                            .padding(.horizontal, 7)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help(renderedAttribute(attribute))

                    Button(role: .destructive) {
                        attributes.removeAll { $0.id == attribute.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete attribute")
                }
                .contextMenu {
                    Button("Move Up", systemImage: "arrow.up") {
                        move(attribute, by: -1)
                    }
                    .disabled(isFirst(attribute))

                    Button("Move Down", systemImage: "arrow.down") {
                        move(attribute, by: 1)
                    }
                    .disabled(isLast(attribute))

                    Divider()

                    Button("Add New Attribute…", systemImage: "plus") {
                        editingAttribute = PartHTMLAttribute()
                    }

                    Divider()

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        attributes.removeAll { $0.id == attribute.id }
                    }
                }
            }
        }
        .popover(item: $editingAttribute, arrowEdge: .trailing) { attribute in
            PartAttributePopover(
                attribute: attribute,
                existingAttributes: attributes
            ) { updatedAttribute in
                if let index = attributes.firstIndex(where: { $0.id == updatedAttribute.id }) {
                    attributes[index] = updatedAttribute
                } else {
                    attributes.append(updatedAttribute)
                }
            }
        }
    }

    private func renderedAttribute(_ attribute: PartHTMLAttribute) -> String {
        let escapedValue = attribute.value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "\(attribute.name)=\"\(escapedValue)\""
    }

    private func move(_ attribute: PartHTMLAttribute, by offset: Int) {
        guard let index = attributes.firstIndex(where: { $0.id == attribute.id }) else {
            return
        }
        let destination = index + offset
        guard attributes.indices.contains(destination) else {
            return
        }
        attributes.swapAt(index, destination)
    }

    private func isFirst(_ attribute: PartHTMLAttribute) -> Bool {
        attributes.first?.id == attribute.id
    }

    private func isLast(_ attribute: PartHTMLAttribute) -> Bool {
        attributes.last?.id == attribute.id
    }
}

private struct PartAttributePopover: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var value: String
    @State private var isExpanded = false

    let attributeID: UUID
    let existingAttributes: [PartHTMLAttribute]
    let save: (PartHTMLAttribute) -> Void

    init(
        attribute: PartHTMLAttribute?,
        existingAttributes: [PartHTMLAttribute],
        save: @escaping (PartHTMLAttribute) -> Void
    ) {
        attributeID = attribute?.id ?? UUID()
        self.existingAttributes = existingAttributes
        self.save = save
        _name = State(initialValue: attribute?.name ?? "")
        _value = State(initialValue: attribute?.value ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Attribute").font(.headline)
                Spacer()
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse value editor" : "Expand value editor")
                .accessibilityLabel(isExpanded ? "Collapse value editor" : "Expand value editor")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text("Name")
                    TextField("Name", text: $name)
                        .frame(width: isExpanded ? 430 : 190)
                }
                GridRow {
                    Text("Value").gridCellAnchor(.topLeading)
                    if isExpanded {
                        AttributeValueEditor(text: $value)
                            .frame(width: 430, height: 220)
                            .overlay {
                                Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                    .allowsHitTesting(false)
                            }
                    } else {
                        TextField("Value", text: $value)
                            .frame(width: 190)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save(PartHTMLAttribute(id: attributeID, name: trimmedName, value: value))
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: isExpanded ? .command : [])
                .disabled(!canSave)
            }
        }
        // Do not accept the popover's previous expanded width via the header Spacer.
        .fixedSize(horizontal: true, vertical: true)
        .padding(20)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        PartRootAttributeValidator.isValidName(trimmedName) &&
            !existingAttributes.contains {
                $0.id != attributeID &&
                    $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
            }
    }
}

/// The bindings the Advanced section renders — the placed part's HTML
/// identity, which lives on the node rather than in package properties.
private struct PartIdentityContext {
    let anchor: Binding<String>
    let classes: Binding<String>
    let customCSS: Binding<String>
    let attributes: Binding<[PartHTMLAttribute]>
    let isDuplicateAnchor: Bool
}

private struct PartInspectorGroup: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let group: PartPropertySection
    let rows: [PartInspectorRow]
    let identityFields: PartIdentityContext?
    let part: PartNode
    let selectedParts: [PartNode]
    let selectedPrimitive: CanvasPrimitiveSelection?
    let selectPrimitive: (CanvasPrimitiveSelection?) -> Void
    let currentPage: Page?
    let framework: Framework
    let assets: [ProjectAsset]
    let assetContents: ProjectAssetContents
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint
    let importMedia: (URL, UTType) -> ProjectAsset?
    let selectInsertedPart: (UUID) -> Void
    @Binding var isExpanded: Bool
    @Binding var usesAccordion: Bool
    let openAll: () -> Void
    let closeAll: () -> Void

    private var sectionStatus: (isModified: Bool, canReset: Bool) {
        let targets = selectedParts.isEmpty ? [part] : selectedParts
        var result = (isModified: false, canReset: false)
        for target in targets {
            let state = PartInspectorSectionState(part: target, section: group, framework: framework)
            result.isModified = result.isModified || state.hasChanges(in: target)
            result.canReset = result.canReset || state.canReset(target)
        }
        return result
    }

    private func resetSection() {
        editor.resetInspectorSection(
            ids: selectedParts.isEmpty ? [part.id] : selectedParts.map(\.id),
            section: group,
            editsSharedDefinition: editsSharedDefinition
        )
    }

    var body: some View {
        let status = sectionStatus
        DisclosureGroup(isExpanded: $isExpanded) {
            // Separate controls sit exactly as far apart as the rows of one
            // multi-part control. Developers who want more separation declare
            // a spacer or divider where they want it.
            VStack(spacing: InspectorMetrics.rowSpacing) {
                if let identityFields {
                    PartIdentityFields(
                        anchor: identityFields.anchor,
                        classes: identityFields.classes,
                        customCSS: identityFields.customCSS,
                        attributes: identityFields.attributes,
                        isDuplicateAnchor: identityFields.isDuplicateAnchor
                    )
                    .padding(.horizontal, InspectorMetrics.horizontalSectionPadding)
                }
                ForEach(rows) { row in
                    InspectorGrid(
                        contentInsets: EdgeInsets(
                            top: 0,
                            leading: InspectorMetrics.horizontalSectionPadding,
                            bottom: 0,
                            trailing: InspectorMetrics.horizontalSectionPadding
                        )
                    ) {
                        switch row {
                        case .controls(let controlGroup):
                            ForEach(controlGroup.properties) { definition in
                                propertyEditor(for: definition)
                                    .transition(.opacity)
                            }
                        case .childPicker(let slot):
                            if let pageID = currentPage?.id {
                                PartSlotInspectorCard(
                                    slot: slot,
                                    part: part,
                                    pageID: pageID,
                                    editor: editor,
                                    selectInsertedPart: selectInsertedPart
                                )
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.vertical, InspectorMetrics.verticalSectionPadding)
        } label: {
            Label {
                Text(group.rawValue)
                    .foregroundStyle(status.isModified ? Color.accentColor : Color.primary)
                    .underline(status.isModified && differentiateWithoutColor)
            } icon: {
                Image(systemName: part.type.definition.systemImage(for: group))
                    .foregroundStyle(.primary)
            }
        }
        .disclosureGroupStyle(PartInspectorDisclosureStyle(
            usesAccordion: $usesAccordion,
            openAll: openAll,
            closeAll: closeAll,
            hasChanges: status.isModified,
            canReset: status.canReset,
            resetSection: resetSection
        ))
    }

    private func propertyEditor(for definition: PartPropertyDefinition) -> some View {
        PartPropertyEditor(
            definition: definition,
            part: part,
            selectedParts: selectedParts,
            currentPage: currentPage,
            framework: framework,
            assets: assets,
            assetContents: assetContents,
            pages: pages,
            folders: folders,
            publicURL: publicURL,
            editor: editor,
            editsSharedDefinition: editsSharedDefinition,
            breakpoint: breakpoint,
            importMedia: importMedia,
            selectedPrimitive: selectedPrimitive,
            selectPrimitive: selectPrimitive
        )
    }
}

private struct PartInspectorDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var usesAccordion: Bool
    let openAll: () -> Void
    let closeAll: () -> Void
    let hasChanges: Bool
    let canReset: Bool
    let resetSection: () -> Void
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    configuration.label
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, InspectorMetrics.horizontalSectionPadding)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(isHovering ? 0.09 : 0.06))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .contextMenu {
                Button("Reset Section", action: resetSection)
                    .disabled(!canReset)
                Divider()
                Toggle("Accordion Mode", isOn: $usesAccordion)
                if !usesAccordion {
                    Divider()
                    Button("Open All") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15), openAll)
                    }
                    Button("Close All") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15), closeAll)
                    }
                }
            }
            .accessibilityValue((configuration.isExpanded ? "Expanded" : "Collapsed") + (hasChanges ? ", Modified" : ""))
            .accessibilityHint(configuration.isExpanded ? "Collapses this group" : "Expands this group")

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
    }
}

#Preview("Part Inspector") {
    PartInspectorPreviewHarness()
}

private struct PartInspectorPreviewHarness: View {
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                let type = PartType(rawValue: "foundry.layout.grid")
                let part = PartNode.make(type)
                let page = Page(title: "Grid", slug: "index", parts: [part])
                let document = FoundryDocument(site: Site(name: "Preview", pages: [page]))
                InspectorView(
                    page: nil,
                    currentPage: document.site.pages.first,
                    folder: nil,
                    asset: nil,
                    assetLibraryNode: nil,
                    assetLibrary: document.site.assetLibrary,
                    assetContents: document.assetContents,
                    folders: document.site.pageFolders,
                    pages: document.site.pages,
                    publicURL: document.site.publicURL,
                    part: part,
                    selectedParts: [part],
                    selectedPrimitive: nil,
                    selectPrimitive: { _ in },
                    allowsMultiPartEditing: false,
                    libraryPartType: nil,
                    assetCollectionSelection: nil,
                    importCollectionFiles: { _ in },
                    templateContext: nil,
                    insertTemplate: { _ in },
                    globalDefinition: nil,
                    insertGlobalPart: { _ in },
                    framework: document.site.framework,
                    assets: document.site.assets,
                    editor: ProjectEditor(document: document, undoManager: nil),
                    reusableDefinition: nil,
                    isGlobalOverride: false,
                    setGlobalOverride: { _ in },
                    selectInsertedPart: { _ in },
                    breakpoint: .large,
                    assetUsageCount: { _ in 0 },
                    renameAsset: { _, _ in },
                    renameAssetFolder: { _, _ in },
                    importMedia: { _, _ in nil },
                    editsSharedDefinition: .constant(false)
                )
            } else {
                ProgressView()
            }
        }
        .frame(width: 340, height: 900)
        .task {
            await PartPackageCatalog.shared.waitUntilLoaded()
            isReady = true
        }
    }
}
