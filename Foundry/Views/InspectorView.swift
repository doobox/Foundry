import AppKit
import SwiftUI

struct InspectorView: View {
    let page: Page?
    let currentPage: Page?
    let folder: PageFolder?
    let asset: ProjectAsset?
    let assetLibraryNode: ProjectAssetNode?
    let assetLibrary: [ProjectAssetNode]
    let assetContents: [UUID: ProjectAssetContent]
    let folders: [PageFolder]
    let pages: [Page]
    let publicURL: String
    let component: ComponentNode?
    let componentSelectionCount: Int
    let libraryComponentType: ComponentType?
    let theme: Theme
    let assets: [ProjectAsset]
    let editor: ProjectEditor
    let reusableDefinition: ReusableComponentDefinition?
    let isGlobalOverride: Bool
    let setGlobalOverride: (Bool) -> Void
    let breakpoint: ResponsiveBreakpoint
    let assetUsageCount: (UUID) -> Int
    let renameAsset: (UUID, String) -> Void
    let renameAssetFolder: (UUID, String) -> Void
    let importImage: (URL) -> ProjectAsset?
    @Binding var editsSharedDefinition: Bool

    var body: some View {
        Group {
            if componentSelectionCount == 1, let component {
                ComponentInspector(
                    component: component,
                    currentPage: currentPage,
                    theme: theme,
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
                    importImage: importImage,
                    editsSharedDefinition: $editsSharedDefinition
                )
            } else if componentSelectionCount == 0,
                      page == nil,
                      folder == nil,
                      asset == nil,
                      assetLibraryNode == nil,
                      let libraryComponentType {
                ComponentLibraryInspector(type: libraryComponentType)
            } else {
                Form {
                    inspectorFormContent
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Inspector")
    }

    @ViewBuilder
    private var inspectorFormContent: some View {
        if componentSelectionCount > 1 {
                Section("Multiple Selection") {
                    LabeledContent("Components", value: componentSelectionCount.formatted())
                    Text("Group dragging and deletion apply to the selected components.")
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
        } else if let folder {
            PageFolderInspector(folder: folder, folders: folders, editor: editor)
        } else if let asset {
            PageAssetInspector(asset: asset, content: assetContents[asset.id], folders: folders)
        } else if let page {
            PageInspector(page: page, pages: pages, folders: folders, editor: editor)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "slider.horizontal.3",
                description: Text("Select a page, folder, or component to edit it.")
            )
        }
    }
}

private struct ComponentLibraryInspector: View {
    let type: ComponentType
    @AppStorage(AppPreferenceKey.showsDeveloperPanel) private var enablesDeveloperTools = false

    var body: some View {
        let package = type.definition.package
        ScrollView {
            LazyVStack(spacing: 14) {
                InspectorCard {
                    ComponentLibraryInspectorHeader(
                        type: type,
                        description: type.libraryDescription,
                        isDevelopmentPack: package?.isDevelopmentPack == true
                    )
                }

                InspectorCard(title: "Component") {
                    ComponentLibraryInspectorMetadata(
                        identifier: type.rawValue,
                        developer: package?.manifest.author,
                        version: package.flatMap(displayVersion),
                        category: type.definition.category.rawValue,
                        helpURL: package?.manifest.helpURL
                    )
                }

                if let tags = package?.manifest.tags, !tags.isEmpty {
                    InspectorCard(title: "Tags") {
                        ComponentLibraryInspectorTags(tags: tags)
                    }
                }

                if let updateSourceURL = package?.updateSourceURL {
                    InspectorCard(title: "Updates") {
                        ComponentLibraryUpdateControls(sourceURL: updateSourceURL)
                    }
                }

                if enablesDeveloperTools, let package, !package.isBuiltIn {
                    ComponentPackConversionControls(package: package)
                }
            }
            .padding(16)
        }
        .controlSize(.small)
        .font(.callout)
    }

    private func displayVersion(for package: LoadedComponentPackage) -> String? {
        let metadataSourceURL = package.developmentPackRootURL ?? package.updateSourceURL
        guard let metadataSourceURL,
              let metadataPack = try? FoundryPackLoader.load(from: metadataSourceURL) else {
            return package.manifest.version
        }
        return metadataPack.metadata.version ?? package.manifest.version
    }
}

private struct ComponentPackConversionControls: View {
    let package: LoadedComponentPackage
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
        convertedURL ?? ComponentPackageCatalog.shared.conversionRootURL(for: package)
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
            convertedURL = try ComponentPackageCatalog.shared.convertPack(
                at: packURL,
                toExtension: destinationExtension
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ComponentLibraryUpdateControls: View {
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

private struct ComponentLibraryInspectorHeader: View {
    let type: ComponentType
    let description: String
    let isDevelopmentPack: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComponentLibraryIcon(type: type, size: 48)

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

private struct ComponentLibraryInspectorMetadata: View {
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

private struct ComponentLibraryInspectorTags: View {
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
    let contents: [UUID: ProjectAssetContent]
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
        func find(_ nodes: [ProjectAssetNode], components: [String]) -> [String]? {
            for node in nodes {
                switch node {
                case .asset(let asset):
                    if asset.id == id { return components + [asset.filename] }
                case .folder(let folder):
                    let path = components + [folder.name]
                    if folder.id == id { return path }
                    if let match = find(folder.children, components: path) { return match }
                }
            }
            return nil
        }
        return "/" + (find(library, components: []) ?? []).joined(separator: "/")
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
            Text("This file is exported only at the path above. Component references follow that path.")
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
                ThemeColorComponentControl(
                    label: "Background", choices: theme.colorChoices, allowsCustom: true, theme: theme,
                    source: backgroundSource, shade: backgroundShade, customColor: backgroundCustomColour,
                    allowsOpacity: false,
                    indicator: .init(isVisible: false, isOverridden: false, breakpointName: "", toggle: {}),
                    resetToTheme: { editor.setPageBackground(id: page.id, value: nil) },
                    canResetToTheme: page.backgroundOverride != nil)
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

    private var theme: Theme { editor.document.site.theme }
    private var background: ComponentPackageColorValue { page.backgroundSelection(theme: theme) }

    private var backgroundSource: Binding<String> {
        Binding(get: { background.source }, set: { source in
            var value = background
            value.source = source
            if let palette = theme.colourPalettes.resolvedPalette(id: value.paletteID) {
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

private struct ComponentInspector: View {
    @State private var loadedComponentIcon: NSImage?
    @State private var showsAddAttributePopover = false
    let component: ComponentNode
    let currentPage: Page?
    let theme: Theme
    let assets: [ProjectAsset]
    let assetContents: [UUID: ProjectAssetContent]
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let reusableDefinition: ReusableComponentDefinition?
    let isGlobalOverride: Bool
    let setGlobalOverride: (Bool) -> Void
    let breakpoint: ResponsiveBreakpoint
    let importImage: (URL) -> ProjectAsset?
    @Binding var editsSharedDefinition: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                InspectorCard {
                    componentIdentityHeader

                    Divider()
                    ComponentIdentityFields(
                        anchor: componentAnchorBinding,
                        classes: componentClassesBinding,
                        attributes: componentAttributesBinding,
                        isDuplicateAnchor: componentAnchorIsDuplicate,
                        localOverride: reusableDefinition == nil ? nil : Binding(
                            get: { isGlobalOverride },
                            set: setGlobalOverride
                        ),
                        globalLabel: isGlobalOverride ? nil : globalIndicatorLabel,
                        globalColor: globalIndicatorColor
                    )
                }

                ForEach(inspectorGroups, id: \.rawValue) { group in
                    ComponentInspectorGroup(
                        group: group,
                        properties: properties(in: group),
                        childPickers: childPickers(in: group),
                        component: component,
                        currentPage: currentPage,
                        theme: theme,
                        assets: assets,
                        assetContents: assetContents,
                        pages: pages,
                        folders: folders,
                        publicURL: publicURL,
                        editor: editor,
                        editsSharedDefinition: reusableDefinition != nil && !isGlobalOverride,
                        breakpoint: breakpoint,
                        importImage: importImage
                    )
                }
            }
            .padding(16)
        }
        .controlSize(.small)
        .font(.callout)
    }

    private var inspectorGroups: [ComponentPropertySection] {
        var groups: [ComponentPropertySection] = component.type.definition.properties.reduce(into: []) { groups, property in
            guard isVisible(property),
                  !groups.contains(property.section) else { return }
            groups.append(property.section)
        }
        for slot in componentSlots where isVisible(slot) {
            let section = ComponentPropertySection(rawValue: slot.group)
            if !groups.contains(section) {
                groups.append(section)
            }
        }
        return groups
    }

    private var componentSlots: [ComponentPackageSlot] {
        component.type.definition.package?.manifest.slots ?? []
    }

    private func properties(in section: ComponentPropertySection) -> [ComponentPropertyDefinition] {
        component.type.definition.properties.filter {
            $0.section == section && isVisible($0)
        }
    }

    private func childPickers(in section: ComponentPropertySection) -> [ComponentPackageSlot] {
        componentSlots.filter {
            $0.group == section.rawValue && isVisible($0)
        }
    }

    private func isVisible(_ slot: ComponentPackageSlot) -> Bool {
        ComponentPackageVisibilityEvaluator.isVisible(slot.visibleWhen, for: component, at: breakpoint)
    }

    private func isVisible(_ property: ComponentPropertyDefinition) -> Bool {
        property.isInspectorVisible && ComponentPackageVisibilityEvaluator.isVisible(
            property.visibleWhen,
            for: component,
            at: property.isResponsive ? breakpoint : .mobile
        )
    }

    private var componentIdentityHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let icon = displayedComponentIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: component.type.systemImage)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 32 * 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 32 * 0.16))

            VStack(alignment: .leading, spacing: 3) {
                Text(reusableDefinition?.name ?? component.type.displayName)
                    .font(.headline)
                Text(componentDeveloper)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

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
            .help("Component options")
            .popover(isPresented: $showsAddAttributePopover, arrowEdge: .trailing) {
                ComponentAttributePopover(
                    attribute: nil,
                    existingAttributes: component.rootAttributes ?? []
                ) { attribute in
                    var attributes = component.rootAttributes ?? []
                    attributes.append(attribute)
                    editor.setComponentRootAttributes(id: component.id, attributes: attributes)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: component.type.definition.package?.iconURL) {
            guard let url = component.type.definition.package?.iconURL else {
                loadedComponentIcon = nil
                return
            }
            if let cached = ComponentIconLoader.cachedIcon(at: url) {
                loadedComponentIcon = cached.image
                return
            }
            loadedComponentIcon = await ComponentIconLoader.shared.icon(at: url)?.image
        }
    }

    private var globalIndicatorColor: Color {
        Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
    }

    private var globalIndicatorLabel: String {
        component.reusableDefinitionID == reusableDefinition?.id ? "Global" : "Global — Child"
    }

    private var displayedComponentIcon: NSImage? {
        loadedComponentIcon ?? (component.type.definition.package?.iconURL).flatMap {
            ComponentIconLoader.cachedIcon(at: $0)?.image
        }
    }

    private var componentDeveloper: String {
        component.type.definition.package?.manifest.author.flatMap { author in
            author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : author
        } ?? "Unknown Developer"
    }

    private var componentAnchorBinding: Binding<String> {
        Binding(
            get: { component.anchor ?? "" },
            set: { editor.setComponentAnchor(id: component.id, anchor: $0) }
        )
    }

    private var componentClassesBinding: Binding<String> {
        Binding(
            get: { component.customClasses ?? "" },
            set: { editor.setComponentClasses(id: component.id, classes: $0) }
        )
    }

    private var componentAttributesBinding: Binding<[ComponentHTMLAttribute]> {
        Binding(
            get: { component.rootAttributes ?? [] },
            set: { editor.setComponentRootAttributes(id: component.id, attributes: $0) }
        )
    }

    private var componentAnchorIsDuplicate: Bool {
        guard let anchor = component.anchor, !anchor.isEmpty, let currentPage else { return false }
        return currentPage.components.reduce(0) { $0 + anchorCount(anchor, in: $1) } > 1
    }

    private func anchorCount(_ anchor: String, in node: ComponentNode) -> Int {
        let matches = node.anchor == anchor
        return (matches ? 1 : 0) + node.children.reduce(0) { $0 + anchorCount(anchor, in: $1) }
    }
}

private struct ComponentSlotInspectorCard: View {
    let slot: ComponentPackageSlot
    let component: ComponentNode
    let pageID: UUID
    let editor: ProjectEditor

    @State private var selectedType: ComponentType?

    private var availableTypes: [ComponentType] {
        ComponentRegistry.availableTypes
            .filter {
                slot.offersInPicker($0) &&
                    ($0.definition.package?.manifest.permits(parent: component.type) ?? true)
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var children: [ComponentNode] {
        let package = component.type.definition.package
        let defaultSlotID = package?.dropZoneNames.first.map { package?.dropZoneSlotID(for: $0) ?? "" }
            ?? package?.manifest.slots.first?.id
        return component.children.filter { child in
            (child.slotID ?? defaultSlotID) == slot.id
        }
    }

    var body: some View {
        ChildPickerComponentControl(
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
        _ = editor.insertComponent(
            type: selectedType,
            on: pageID,
            placement: .insideSlot(component.id, slot.id)
        )
    }
}

private struct ComponentIdentityFields: View {
    @Binding var anchor: String
    @Binding var classes: String
    @Binding var attributes: [ComponentHTMLAttribute]
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
                    if !anchor.isEmpty && !ComponentAnchorValidator.isValid(anchor) {
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
                    ComponentAttributeRows(attributes: $attributes)
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

private struct ComponentAttributeRows: View {
    @Binding var attributes: [ComponentHTMLAttribute]
    @State private var editingAttribute: ComponentHTMLAttribute?

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
                        editingAttribute = ComponentHTMLAttribute()
                    }

                    Divider()

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        attributes.removeAll { $0.id == attribute.id }
                    }
                }
            }
        }
        .popover(item: $editingAttribute, arrowEdge: .trailing) { attribute in
            ComponentAttributePopover(
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

    private func renderedAttribute(_ attribute: ComponentHTMLAttribute) -> String {
        let escapedValue = attribute.value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "\(attribute.name)=\"\(escapedValue)\""
    }

    private func move(_ attribute: ComponentHTMLAttribute, by offset: Int) {
        guard let index = attributes.firstIndex(where: { $0.id == attribute.id }) else {
            return
        }
        let destination = index + offset
        guard attributes.indices.contains(destination) else {
            return
        }
        attributes.swapAt(index, destination)
    }

    private func isFirst(_ attribute: ComponentHTMLAttribute) -> Bool {
        attributes.first?.id == attribute.id
    }

    private func isLast(_ attribute: ComponentHTMLAttribute) -> Bool {
        attributes.last?.id == attribute.id
    }
}

private struct ComponentAttributePopover: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var value: String
    @State private var isExpanded = false

    let attributeID: UUID
    let existingAttributes: [ComponentHTMLAttribute]
    let save: (ComponentHTMLAttribute) -> Void

    init(
        attribute: ComponentHTMLAttribute?,
        existingAttributes: [ComponentHTMLAttribute],
        save: @escaping (ComponentHTMLAttribute) -> Void
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
                    save(ComponentHTMLAttribute(id: attributeID, name: trimmedName, value: value))
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
        ComponentRootAttributeValidator.isValidName(trimmedName) &&
            !existingAttributes.contains {
                $0.id != attributeID &&
                    $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
            }
    }
}

private struct ComponentInspectorGroup: View {
    let group: ComponentPropertySection
    let properties: [ComponentPropertyDefinition]
    let childPickers: [ComponentPackageSlot]
    let component: ComponentNode
    let currentPage: Page?
    let theme: Theme
    let assets: [ProjectAsset]
    let assetContents: [UUID: ProjectAssetContent]
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint
    let importImage: (URL) -> ProjectAsset?
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: InspectorMetrics.controlSpacing) {
                ForEach(ComponentInspectorControlGroup.groups(for: properties)) { controlGroup in
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
                            ComponentSlotInspectorCard(
                                slot: slot,
                                component: component,
                                pageID: pageID,
                                editor: editor
                            )
                        }
                    }
                }
            }
            .padding(.vertical, InspectorMetrics.verticalSectionPadding)
        } label: {
            Text(group.rawValue)
        }
        .disclosureGroupStyle(ComponentInspectorDisclosureStyle())
    }

    private func propertyEditor(for definition: ComponentPropertyDefinition) -> some View {
        ComponentPropertyEditor(
            definition: definition,
            component: component,
            currentPage: currentPage,
            theme: theme,
            assets: assets,
            assetContents: assetContents,
            pages: pages,
            folders: folders,
            publicURL: publicURL,
            editor: editor,
            editsSharedDefinition: editsSharedDefinition,
            breakpoint: breakpoint,
            importImage: importImage
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

private struct ComponentInspectorDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 0 : -90))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.075))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(configuration.isExpanded ? "Collapses this group" : "Expands this group")

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
