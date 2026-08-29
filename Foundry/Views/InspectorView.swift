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
        Form {
            if componentSelectionCount > 1 {
                Section("Multiple Selection") {
                    LabeledContent("Components", value: componentSelectionCount.formatted())
                    Text("Group dragging and deletion apply to the selected components.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let component {
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
        .formStyle(.grouped)
        .navigationTitle("Inspector")
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
        if reusableDefinition != nil {
            Section("Global Component") {
                if let reusableDefinition {
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
                } else {
                    Label("The reusable definition is missing. This instance remains editable locally.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }

        Section("Component") {
            LabeledContent("Type", value: component.type.displayName)
            TextField(
                "Name",
                text: Binding(
                    get: { component.name },
                    set: {
                        if reusableDefinition != nil, !isGlobalOverride {
                            editor.renameSharedReusableComponentInstance(componentID: component.id, name: $0)
                        } else {
                            editor.renameComponent(id: component.id, name: $0)
                        }
                    }
                )
            )
        }

        ForEach(inspectorSections, id: \.rawValue) { section in
            Section(section.rawValue) {
                ForEach(properties(in: section)) { definition in
                    propertyEditor(definition)
                }
            }
        }

        if let inlineContentProperty {
            Section {
                DisclosureGroup {
                    propertyEditor(inlineContentProperty)
                    Text("This content can also be edited directly on the canvas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Content")
                        Text("Editable on canvas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var inspectorSections: [ComponentPropertySection] {
        component.type.definition.properties.reduce(into: []) { sections, property in
            guard property.key != component.type.definition.inlineEditableProperty,
                  !sections.contains(property.section) else { return }
            sections.append(property.section)
        }
    }

    private func properties(in section: ComponentPropertySection) -> [ComponentPropertyDefinition] {
        component.type.definition.properties.filter {
            $0.section == section && $0.key != component.type.definition.inlineEditableProperty
        }
    }

    private func propertyEditor(_ definition: ComponentPropertyDefinition) -> some View {
        ComponentPropertyEditor(
            definition: definition,
            component: component,
            theme: theme,
            assets: assets,
            editor: editor,
            editsSharedDefinition: reusableDefinition != nil && !isGlobalOverride,
            breakpoint: breakpoint
        )
    }

    private var inlineContentProperty: ComponentPropertyDefinition? {
        guard let key = component.type.definition.inlineEditableProperty else { return nil }
        return component.type.definition.properties.first(where: { $0.key == key })
    }
}
