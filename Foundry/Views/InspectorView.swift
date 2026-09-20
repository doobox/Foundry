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
    let allowsMultiPartEditing: Bool
    let libraryPartType: PartType?
    let templateEntry: ReusablePartLibraryEntry?
    let insertTemplate: (UUID) -> Void
    let globalDefinition: ReusablePartDefinition?
    let insertGlobalPart: (UUID) -> Void
    let framework: Framework
    let assets: [ProjectAsset]
    let editor: ProjectEditor
    let reusableDefinition: ReusablePartDefinition?
    let isGlobalOverride: Bool
    let setGlobalOverride: (Bool) -> Void
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
        if templateEntry != nil { return "Template Info" }
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
                    breakpoint: breakpoint,
                    importMedia: importMedia,
                    editsSharedDefinition: $editsSharedDefinition,
                    groupExpansion: $partGroupExpansion
                )
            } else if selectedParts.isEmpty,
                      page == nil,
                      folder == nil,
                      asset == nil,
                      assetLibraryNode == nil,
                      templateEntry == nil,
                      globalDefinition == nil,
                      let libraryPartType {
                PartLibraryInspector(type: libraryPartType)
            } else {
                Form {
                    inspectorFormContent
                }
                .formStyle(.grouped)
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
        } else if let templateEntry {
            TemplateInspector(entry: templateEntry, insertTemplate: insertTemplate)
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
        } else if let page {
            PageInspector(page: page, pages: pages, folders: folders, editor: editor)
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
        ScrollView {
            LazyVStack(spacing: 14) {
                InspectorCard {
                    PartLibraryInspectorHeader(
                        type: type,
                        description: type.libraryDescription,
                        isDevelopmentPack: package?.isDevelopmentPack == true
                    )
                }

                InspectorCard(title: "Part") {
                    PartLibraryInspectorMetadata(
                        identifier: type.rawValue,
                        developer: package?.manifest.author,
                        version: package.flatMap(displayVersion),
                        category: type.definition.category.rawValue,
                        helpURL: package?.manifest.helpURL
                    )
                }

                if let tags = package?.manifest.tags, !tags.isEmpty {
                    InspectorCard(title: "Tags") {
                        PartLibraryInspectorTags(tags: tags)
                    }
                }

                if let updateSourceURL = package?.updateSourceURL {
                    InspectorCard(title: "Updates") {
                        PartLibraryUpdateControls(sourceURL: updateSourceURL)
                    }
                }

                if enablesDeveloperTools, let package, !package.isBuiltIn {
                    PartPackConversionControls(package: package)
                }
            }
            .padding(16)
        }
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
        InspectorCard(title: conversionTitle) {
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
            PartLibraryIcon(type: type, size: 48)

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
        LabeledContent("Developer", value: normalizedDeveloper)
        LabeledContent("Version", value: version ?? "—")
        LabeledContent("Category", value: category)
        LabeledContent("Identifier") {
            Text(identifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        if let helpURL {
            LabeledContent("Help") {
                Link("Open Documentation", destination: helpURL)
                    .help(helpURL.absoluteString)
            }
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
                "Slug",
                text: Binding(
                    get: { folder.slug },
                    set: { editor.setPageFolderSlug(id: folder.id, slug: $0) }
                )
            )
            LabeledContent("Path", value: "/\(path)/")
            Text("This folder becomes a directory when the site is exported.")
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

private struct PageInspector: View {
    @Environment(\.canvasAppearance) private var appearance
    let page: Page
    let pages: [Page]
    let folders: [PageFolder]
    let editor: ProjectEditor

    var body: some View {
        Section("Page") {
            TextField(
                "Title",
                text: Binding(
                    get: { page.title },
                    set: { editor.renamePage(id: page.id, title: $0) }
                )
            )
            TextField(
                "Slug",
                text: Binding(
                    get: { page.slug },
                    set: { editor.setPageSlug(id: page.id, slug: $0) }
                )
            )
            .disabled(page.slug == "index")
            LabeledContent("Path", value: exportPath)
            LabeledContent("Export File", value: exportFilePath)
            Toggle(
                "Include in Navigation",
                isOn: Binding(
                    get: { page.includeInNavigation },
                    set: { editor.setPageIncludedInNavigation(id: page.id, included: $0) }
                )
            )
            Text("Slugs use lowercase letters, numbers, and hyphens. Duplicate slugs receive a numeric suffix.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Appearance") {
            Grid(horizontalSpacing: 8) {
                FrameworkColorPartControl(
                    label: "Background", choices: framework.colorChoices, allowsCustom: true, framework: framework,
                    source: backgroundSource, shade: backgroundShade, customColor: backgroundCustomColour,
                    allowsOpacity: false,
                    indicator: .init(isVisible: false, isOverridden: false, breakpointName: "", toggle: {}),
                    resetToFramework: { editor.setPageBackground(id: page.id, value: nil) },
                    canResetToFramework: page.backgroundOverride != nil)
            }
            .controlSize(.small)
        }

        Section("Search") {
            metadataField("Browser Title", keyPath: \.browserTitle)
            TextField(
                "Description",
                text: metadataBinding(\.description),
                axis: .vertical
            )
            .lineLimit(3...6)
        }

        Section("Social Sharing") {
            metadataField("Title", keyPath: \.socialTitle)
            TextField(
                "Description",
                text: metadataBinding(\.socialDescription),
                axis: .vertical
            )
            .lineLimit(3...6)
            metadataField("Image URL", keyPath: \.socialImage)
        }
    }

    private var exportPath: String {
        PageRouteResolver.path(for: page, pages: pages, folders: folders)
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

    private var exportFilePath: String {
        let fileExtension = StaticSiteRenderer.requiresPHP(page) ? "php" : "html"
        return exportPath + "index.\(fileExtension)"
    }

    private func metadataField(
        _ title: String,
        keyPath: WritableKeyPath<PageMetadata, String>
    ) -> some View {
        TextField(title, text: metadataBinding(keyPath))
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
    @AppStorage(AppPreferenceKey.inspectorAccordion) private var usesAccordion = true
    @State private var loadedPartIcon: NSImage?
    @State private var showsAddAttributePopover = false
    let part: PartNode
    let selectedParts: [PartNode]
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
    let breakpoint: ResponsiveBreakpoint
    let importMedia: (URL, UTType) -> ProjectAsset?
    @Binding var editsSharedDefinition: Bool
    @Binding var groupExpansion: [UUID: PartInspectorExpansion]

    private var expandedGroups: [PartPropertySection] {
        groupExpansion[part.id]?.groups ?? []
    }

    private func setExpanded(_ expanded: Bool, group: PartPropertySection) {
        var groups = expandedGroups.filter { $0 != group }
        if expanded {
            groups = usesAccordion ? [group] : groups + [group]
        }
        groupExpansion[part.id] = PartInspectorExpansion(groups: groups)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                InspectorCard {
                    partIdentityHeader

                    if selectedParts.count == 1 {
                        Divider()
                        PartIdentityFields(
                            anchor: partAnchorBinding,
                            classes: partClassesBinding,
                            attributes: partAttributesBinding,
                            isDuplicateAnchor: partAnchorIsDuplicate,
                            localOverride: reusableDefinition == nil ? nil : Binding(
                                get: { isGlobalOverride },
                                set: setGlobalOverride
                            ),
                            globalLabel: isGlobalOverride ? nil : globalIndicatorLabel,
                            globalColor: globalIndicatorColor
                        )
                    }
                }

                ForEach(inspectorGroups, id: \.rawValue) { group in
                    Divider()
                    PartInspectorGroup(
                        group: group,
                        properties: properties(in: group),
                        childPickers: selectedParts.count == 1 ? childPickers(in: group) : [],
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
                        editsSharedDefinition: reusableDefinition != nil && !isGlobalOverride,
                        breakpoint: breakpoint,
                        importMedia: importMedia,
                        isExpanded: Binding(
                            get: { expandedGroups.contains(group) },
                            set: { setExpanded($0, group: group) }
                        ),
                        usesAccordion: $usesAccordion,
                        openAll: {
                            groupExpansion[part.id] = PartInspectorExpansion(groups: inspectorGroups)
                        },
                        closeAll: {
                            groupExpansion[part.id] = PartInspectorExpansion()
                        }
                    )
                }
            }
        }
        .controlSize(.small)
        .font(.callout)
        .onChange(of: usesAccordion, initial: true) { _, enabled in
            if enabled {
                // Keep the most recently opened group for every remembered part.
                groupExpansion = groupExpansion.mapValues {
                    PartInspectorExpansion(groups: Array($0.groups.suffix(1)))
                }
            }
        }
    }

    private var inspectorGroups: [PartPropertySection] {
        var groups: [PartPropertySection] = part.type.definition.properties.reduce(into: []) { groups, property in
            guard isVisible(property),
                  !groups.contains(property.section) else { return }
            groups.append(property.section)
        }
        for slot in partSlots where isVisible(slot) {
            let section = PartPropertySection(rawValue: slot.group)
            if !groups.contains(section) {
                groups.append(section)
            }
        }
        return groups
    }

    private var partSlots: [PartPackageSlot] {
        part.type.definition.package?.manifest.slots ?? []
    }

    private func properties(in section: PartPropertySection) -> [PartPropertyDefinition] {
        part.type.definition.properties.filter {
            $0.section == section && isVisible($0)
        }
    }

    private func childPickers(in section: PartPropertySection) -> [PartPackageSlot] {
        partSlots.filter {
            $0.group == section.rawValue && isVisible($0)
        }
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
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let icon = displayedPartIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: part.type.systemImage)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 32 * 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 32 * 0.16))

            VStack(alignment: .leading, spacing: 3) {
                Text(partHeaderTitle)
                    .font(.headline)
                Text(partDeveloper)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if selectedParts.count == 1 {
                Menu {
                    Button("Add Attribute…") {
                        showsAddAttributePopover = true
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.top, 1)
                .help("Part options")
                .popover(isPresented: $showsAddAttributePopover, arrowEdge: .trailing) {
                    PartAttributePopover(
                        attribute: nil,
                        existingAttributes: part.rootAttributes ?? []
                    ) { attribute in
                        var attributes = part.rootAttributes ?? []
                        attributes.append(attribute)
                        editor.setPartRootAttributes(id: part.id, attributes: attributes)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: part.type.definition.package?.iconURL) {
            guard let url = part.type.definition.package?.iconURL else {
                loadedPartIcon = nil
                return
            }
            if let cached = PartIconLoader.cachedIcon(at: url) {
                loadedPartIcon = cached.image
                return
            }
            loadedPartIcon = await PartIconLoader.shared.icon(at: url)?.image
        }
    }

    private var partHeaderTitle: String {
        let name = reusableDefinition?.name ?? part.type.displayName
        return selectedParts.count > 1 ? "\(name) · \(selectedParts.count) selected" : name
    }

    private var globalIndicatorColor: Color {
        Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
    }

    private var globalIndicatorLabel: String {
        part.reusableDefinitionID == reusableDefinition?.id ? "Global" : "Global — Child"
    }

    private var displayedPartIcon: NSImage? {
        loadedPartIcon ?? (part.type.definition.package?.iconURL).flatMap {
            PartIconLoader.cachedIcon(at: $0)?.image
        }
    }

    private var partDeveloper: String {
        part.type.definition.package?.manifest.author.flatMap { author in
            author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : author
        } ?? "Unknown Developer"
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

private struct PartSlotInspectorCard: View {
    let slot: PartPackageSlot
    let part: PartNode
    let pageID: UUID
    let editor: ProjectEditor

    @State private var selectedType: PartType?

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
        let package = part.type.definition.package
        let defaultSlotID = package?.dropZoneNames.first.map { package?.dropZoneSlotID(for: $0) ?? "" }
            ?? package?.manifest.slots.first?.id
        return part.children.filter { child in
            (child.slotID ?? defaultSlotID) == slot.id
        }
    }

    var body: some View {
        ChildPickerPartControl(
            label: slot.title,
            options: availableTypes,
            childCount: children.count,
            maximum: slot.maximum,
            help: slot.tooltip,
            selection: $selectedType,
            add: addSelectedType
        )
        .task(id: availableTypes) {
            if selectedType.map({ !availableTypes.contains($0) }) ?? true {
                selectedType = availableTypes.first
            }
        }
    }

    private func addSelectedType() {
        guard let selectedType else { return }
        _ = editor.insertPart(
            type: selectedType,
            on: pageID,
            placement: .insideSlot(part.id, slot.id)
        )
    }
}

private struct PartIdentityFields: View {
    @Binding var anchor: String
    @Binding var classes: String
    @Binding var attributes: [PartHTMLAttribute]
    let isDuplicateAnchor: Bool
    let localOverride: Binding<Bool>?
    let globalLabel: String?
    let globalColor: Color

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

            InspectorRow(title: "Classes") {
                TextField("Classes", text: $classes)
                    .frame(maxWidth: .infinity)
            }

            if !attributes.isEmpty {
                GridRow {
                    Divider()
                        .gridCellColumns(2)
                }

                InspectorRow(title: "Attributes") {
                    PartAttributeRows(attributes: $attributes)
                }
            }

            if let localOverride {
                GridRow {
                    Divider()
                        .gridCellColumns(2)
                }

                InspectorRow(title: "Local Override", alignment: .center) {
                    HStack(spacing: 8) {
                        Toggle("Local Override", isOn: localOverride)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                        Spacer(minLength: 8)

                        if let globalLabel {
                            Text(globalLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(globalColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(globalColor.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
        }
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

private struct PartInspectorGroup: View {
    let group: PartPropertySection
    let properties: [PartPropertyDefinition]
    let childPickers: [PartPackageSlot]
    let part: PartNode
    let selectedParts: [PartNode]
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
    @Binding var isExpanded: Bool
    @Binding var usesAccordion: Bool
    let openAll: () -> Void
    let closeAll: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: InspectorMetrics.controlSpacing) {
                ForEach(PartInspectorControlGroup.groups(for: properties)) { controlGroup in
                    InspectorGrid(
                        contentInsets: EdgeInsets(
                            top: 0,
                            leading: InspectorMetrics.horizontalSectionPadding,
                            bottom: 0,
                            trailing: InspectorMetrics.horizontalSectionPadding
                        )
                    ) {
                        ForEach(controlGroup.properties) { definition in
                            propertyEditor(for: definition)
                        }
                    }
                }
                if let pageID = currentPage?.id {
                    ForEach(childPickers) { slot in
                        InspectorGrid(
                            contentInsets: EdgeInsets(
                                top: 0,
                                leading: InspectorMetrics.horizontalSectionPadding,
                                bottom: 0,
                                trailing: InspectorMetrics.horizontalSectionPadding
                            )
                        ) {
                            PartSlotInspectorCard(
                                slot: slot,
                                part: part,
                                pageID: pageID,
                                editor: editor
                            )
                        }
                    }
                }
            }
            .padding(.vertical, InspectorMetrics.verticalSectionPadding)
        } label: {
            Label(group.rawValue, systemImage: part.type.definition.systemImage(for: group))
        }
        .disclosureGroupStyle(PartInspectorDisclosureStyle(
            usesAccordion: $usesAccordion,
            openAll: openAll,
            closeAll: closeAll
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
            importMedia: importMedia
        )
    }
}

private struct InspectorCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PartInspectorDisclosureStyle: DisclosureGroupStyle {
    @Binding var usesAccordion: Bool
    let openAll: () -> Void
    let closeAll: () -> Void
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
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
                Toggle("Accordion Mode", isOn: $usesAccordion)
                if !usesAccordion {
                    Divider()
                    Button("Open All", action: openAll)
                    Button("Close All", action: closeAll)
                }
            }
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
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
                    allowsMultiPartEditing: false,
                    libraryPartType: nil,
                    templateEntry: nil,
                    insertTemplate: { _ in },
                    globalDefinition: nil,
                    insertGlobalPart: { _ in },
                    framework: document.site.framework,
                    assets: document.site.assets,
                    editor: ProjectEditor(document: document, undoManager: nil),
                    reusableDefinition: nil,
                    isGlobalOverride: false,
                    setGlobalOverride: { _ in },
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
