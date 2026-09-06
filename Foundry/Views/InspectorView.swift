import AppKit
import SwiftUI

struct InspectorView: View {
    let page: Page?
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
            Text("Slugs use lowercase letters, numbers, and hyphens. Duplicate slugs receive a numeric suffix.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var exportFilePath: String {
        let fileExtension = StaticSiteRenderer.requiresPhp(page) ? "php" : "html"
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
    let component: ComponentNode
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
                if let reusableDefinition {
                    InspectorCard(title: "Global Component") {
                        LabeledContent("Definition", value: reusableDefinition.name)
                        Toggle(
                            "Local Override",
                            isOn: Binding(
                                get: { isGlobalOverride },
                                set: setGlobalOverride
                            )
                        )
                        Text(isGlobalOverride
                             ? "This component is a local override. Changes apply only here."
                             : "Changes apply to every linked instance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                InspectorCard {
                    componentIdentityHeader
                }

                ForEach(inspectorGroups, id: \.rawValue) { group in
                    ComponentInspectorGroup(
                        group: group,
                        properties: properties(in: group),
                        component: component,
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
        component.type.definition.properties.reduce(into: []) { groups, property in
            guard isVisible(property),
                  !groups.contains(property.section) else { return }
            groups.append(property.section)
        }
    }

    private func properties(in section: ComponentPropertySection) -> [ComponentPropertyDefinition] {
        component.type.definition.properties.filter {
            $0.section == section && isVisible($0)
        }
    }

    private func isVisible(_ property: ComponentPropertyDefinition) -> Bool {
        property.isInspectorVisible && ComponentPackageEnableEvaluator.isVisible(
            property.enable,
            for: component,
            at: property.isResponsive ? breakpoint : .mobile
        )
    }

    private var componentIdentityHeader: some View {
        HStack(spacing: 12) {
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
                Text(component.type.displayName)
                    .font(.headline)
                Text(componentDeveloper)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
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
}

private struct ComponentInspectorGroup: View {
    let group: ComponentPropertySection
    let properties: [ComponentPropertyDefinition]
    let component: ComponentNode
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
                ForEach(properties) { definition in
                    InspectorGrid(
                        contentInsets: EdgeInsets(
                            top: 0,
                            leading: InspectorMetrics.horizontalSectionPadding,
                            bottom: 0,
                            trailing: InspectorMetrics.horizontalSectionPadding
                        )
                    ) {
                        propertyEditor(for: definition)
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
