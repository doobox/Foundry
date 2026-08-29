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
    let component: ComponentNode?
    let componentSelectionCount: Int
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
    @Binding var editsSharedDefinition: Bool

    var body: some View {
        Group {
            if componentSelectionCount == 1, let component {
                ComponentInspector(
                    component: component,
                    theme: theme,
                    assets: assets,
                    editor: editor,
                    reusableDefinition: reusableDefinition,
                    isGlobalOverride: isGlobalOverride,
                    setGlobalOverride: setGlobalOverride,
                    breakpoint: breakpoint,
                    editsSharedDefinition: $editsSharedDefinition
                )
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
            PageInspector(page: page, folders: folders, editor: editor)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "slider.horizontal.3",
                description: Text("Select a page, folder, or component to edit it.")
            )
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
                LabeledContent("Managed Path", value: "/\(asset.exportPath)")
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
            Text("This file is exported at the path above and retained in managed asset storage for component references.")
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
        guard page.slug != "index" else { return "/" }
        var currentID = page.folderID
        var slugs = [page.slug]
        var visited = Set<UUID>()
        while let id = currentID,
              visited.insert(id).inserted,
              let folder = folders.first(where: { $0.id == id }) {
            slugs.insert(folder.slug, at: 0)
            currentID = folder.parentID
        }
        return "/" + slugs.joined(separator: "/") + "/"
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
    let component: ComponentNode
    let theme: Theme
    let assets: [ProjectAsset]
    let editor: ProjectEditor
    let reusableDefinition: ReusableComponentDefinition?
    let isGlobalOverride: Bool
    let setGlobalOverride: (Bool) -> Void
    let breakpoint: ResponsiveBreakpoint
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
                        editor: editor,
                        editsSharedDefinition: reusableDefinition != nil && !isGlobalOverride,
                        breakpoint: breakpoint
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
            guard property.isInspectorVisible,
                  !groups.contains(property.section) else { return }
            groups.append(property.section)
        }
    }

    private func properties(in section: ComponentPropertySection) -> [ComponentPropertyDefinition] {
        component.type.definition.properties.filter {
            $0.section == section && $0.isInspectorVisible
        }
    }

    private var componentIdentityHeader: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = componentIcon {
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
    }

    private var componentIcon: NSImage? {
        guard let package = component.type.definition.package else { return nil }
        return NSImage(contentsOf: package.iconURL)
    }

    private var componentDeveloper: String {
        component.type.definition.package?.manifest.author ?? "Foundry"
    }
}

private struct ComponentInspectorGroup: View {
    let group: ComponentPropertySection
    let properties: [ComponentPropertyDefinition]
    let component: ComponentNode
    let theme: Theme
    let assets: [ProjectAsset]
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 0) {
                ForEach(properties) { definition in
                    ComponentPropertyEditor(
                        definition: definition,
                        component: component,
                        theme: theme,
                        assets: assets,
                        editor: editor,
                        editsSharedDefinition: editsSharedDefinition,
                        breakpoint: breakpoint
                    )
                    .padding(.vertical, 8)
                }
            }
        } label: {
            Text(group.rawValue)
        }
        .disclosureGroupStyle(ComponentInspectorDisclosureStyle())
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
                    .bold()
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
                        .bold()
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            }
        }
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
