import SwiftUI
import UniformTypeIdentifiers

struct PagesPanel: View {
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    @Binding var selectedPageID: UUID?
    @Binding var selectedFolderID: UUID?
    @Binding var selectedAssetID: UUID?
    let addPage: () -> Void
    let addFolder: (String) -> Void
    let duplicatePage: () -> Void
    let deletePage: () -> Void
    let movePage: (Int) -> Void
    let moveTreeItem: (PageTreeItem, PageTreePlacement) -> Bool
    let importURLs: ([URL], PageTreePlacement) -> Void
    @State private var isNamingFolder = false
    @State private var folderName = ""

    var body: some View {
        VStack(spacing: 0) {
            PagesOutlineView(
                pages: pages,
                folders: folders,
                assets: assets,
                selectedPageID: $selectedPageID,
                selectedFolderID: $selectedFolderID,
                selectedAssetID: $selectedAssetID,
                moveItem: moveTreeItem,
                importURLs: importURLs
            )
            .overlay {
                if pages.isEmpty && folders.isEmpty {
                    ContentUnavailableView("No Pages", systemImage: "doc")
                }
            }

            Divider()
            HStack {
                Menu("Add", systemImage: "plus") {
                    Button("New Page", systemImage: "doc.badge.plus", action: addPage)
                    Button("New Folder…", systemImage: "folder.badge.plus") {
                        folderName = ""
                        isNamingFolder = true
                    }
                }
                Menu("Page Actions", systemImage: "ellipsis.circle") {
                    Button("Duplicate", action: duplicatePage)
                    Button("Move Up") { movePage(-1) }
                    Button("Move Down") { movePage(1) }
                    Divider()
                    Button("Delete", role: .destructive, action: deletePage)
                        .disabled(pages.count <= 1)
                }
                Spacer()
            }
            .labelStyle(.iconOnly)
            .padding(8)
        }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                addFolder(folderName.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct ComponentLibraryPanel: View {
    let addToPageEnd: (ComponentType) -> Void
    @State private var selectedType: ComponentType? = .container
    @State private var catalog = ComponentPackageCatalog.shared
    @State private var isChoosingDevelopmentPackage = false
    @State private var packageError: String?

    var body: some View {
        let _ = catalog.revision
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(componentSections, id: \.category) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Divider()

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 74, maximum: 108), spacing: 10)],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(section.types) { type in
                                    ComponentLibraryTile(
                                        type: type,
                                        isSelected: selectedType == type,
                                        select: { selectedType = type }
                                    )
                                    .draggable(ComponentDragPayload.library(type).stringValue) {
                                        ComponentDragPreview(name: type.displayName, systemImage: type.systemImage)
                                    }
                                    .contextMenu {
                                        Button("Add to Page End", systemImage: "plus") {
                                            addToPageEnd(type)
                                        }
                                    }
                                    .accessibilityAction(named: "Add to Page End") {
                                        addToPageEnd(type)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: .infinity)

            Divider()

            if let selectedType {
                ComponentLibraryDetail(type: selectedType)
            }

            Divider()
            HStack {
                Button("Add Development Component", systemImage: "plus") {
                    isChoosingDevelopmentPackage = true
                }
                .labelStyle(.iconOnly)
                .help("Load and watch a .foundrycomponent-dev folder")
                Spacer()
            }
            .padding(8)
        }
        .fileImporter(
            isPresented: $isChoosingDevelopmentPackage,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                catalog.addDevelopmentPackage(at: url)
                if let errors = catalog.diagnostics[url]?.filter({ $0.severity == .error }),
                   !errors.isEmpty {
                    packageError = errors.map { "\($0.location): \($0.message)" }.joined(separator: "\n")
                } else if let type = ComponentType.allCases.first(where: {
                    $0.definition.package?.rootURL == url
                }) {
                    selectedType = type
                }
            } catch {
                packageError = error.localizedDescription
            }
        }
        .alert("Component Package Could Not Be Loaded", isPresented: packageErrorBinding) {
            Button("OK", role: .cancel) { packageError = nil }
        } message: {
            Text(packageError ?? "The component package is invalid.")
        }
    }

    private var packageErrorBinding: Binding<Bool> {
        Binding(
            get: { packageError != nil },
            set: { if !$0 { packageError = nil } }
        )
    }

    private var componentSections: [ComponentLibrarySection] {
        let types = ComponentType.allCases
        let preferredCategories: [ComponentCategory] = [.layout, .content, .media]
        let remainingCategories = Set(types.map { $0.definition.category })
            .subtracting(preferredCategories)
            .sorted { $0.rawValue < $1.rawValue }
        return (preferredCategories + remainingCategories).compactMap { category in
            let categoryTypes = types.filter { $0.definition.category == category }
            guard !categoryTypes.isEmpty else { return nil }
            return ComponentLibrarySection(
                category: category,
                title: category.rawValue.replacingOccurrences(of: " component", with: ""),
                types: categoryTypes
            )
        }
    }
}

private struct ComponentLibrarySection {
    let category: ComponentCategory
    let title: String
    let types: [ComponentType]
}

struct ReusableComponentLibraryPanel: View {
    let definitions: [ReusableComponentDefinition]
    let renameDefinition: (UUID, String) -> Void
    let deleteDefinition: (UUID) -> Void
    @State private var definitionToRename: ReusableComponentDefinition?
    @State private var definitionToDelete: ReusableComponentDefinition?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(definitions) { definition in
                ReusableComponentLibraryRow(definition: definition)
                    .draggable(ComponentDragPayload.reusable(definition.id).stringValue) {
                        ComponentDragPreview(
                            name: definition.name,
                            systemImage: definition.root.type.systemImage
                        )
                    }
                    .contextMenu {
                        Button("Rename…") {
                            renameText = definition.name
                            definitionToRename = definition
                        }
                        Button("Delete…", role: .destructive) {
                            definitionToDelete = definition
                        }
                    }
            }
        }
        .overlay {
            if definitions.isEmpty {
                ContentUnavailableView(
                    "No Reusable Components",
                    systemImage: "square.stack.3d.up",
                    description: Text("Save a component from Structure to add it here.")
                )
            }
        }
        .alert("Rename Reusable Component", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { definitionToRename = nil }
            Button("Rename") {
                guard let id = definitionToRename?.id else { return }
                renameDefinition(id, renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                definitionToRename = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Delete \(definitionToDelete?.name ?? "Reusable Component")?",
            isPresented: deleteAlertBinding
        ) {
            Button("Delete Reusable Component", role: .destructive) {
                guard let id = definitionToDelete?.id else { return }
                deleteDefinition(id)
                definitionToDelete = nil
            }
            Button("Cancel", role: .cancel) { definitionToDelete = nil }
        } message: {
            Text("Components already added from this reusable item are independent and will be unchanged.")
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { definitionToRename != nil }, set: { if !$0 { definitionToRename = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { definitionToDelete != nil }, set: { if !$0 { definitionToDelete = nil } })
    }
}

private struct ComponentLibraryTile: View {
    let type: ComponentType
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                ComponentLibraryIcon(type: type, size: 54)
                Text(type.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color.primary.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName), drag to add")
        .accessibilityIdentifier("component-library-\(type.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ComponentLibraryDetail: View {
    let type: ComponentType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ComponentLibraryIcon(type: type, size: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName)
                        .font(.headline)
                    Text(type.definition.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(type.libraryDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                type.definition.allowsChildren ? "Accepts child components" : "Content component",
                systemImage: type.definition.allowsChildren ? "square.stack.3d.down.right" : "square"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)

            Text("Drag into the canvas or Structure to add")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

private struct ComponentLibraryIcon: View {
    let type: ComponentType
    let size: CGFloat

    var body: some View {
        Group {
            if let url = type.definition.package?.iconURL,
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            } else {
                Image(systemName: type.systemImage)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}

private struct ComponentDragPreview: View {
    let name: String
    let systemImage: String

    var body: some View {
        Label(name, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 150, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

private struct ReusableComponentLibraryRow: View {
    let definition: ReusableComponentDefinition

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: definition.root.type.systemImage)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                Text("Reusable component")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(definition.name), reusable component, drag to add")
    }
}

struct GlobalComponentLibraryPanel: View {
    let definitions: [ReusableComponentDefinition]
    let renameDefinition: (UUID, String) -> Void
    let deleteDefinition: (UUID) -> Void
    @State private var definitionToRename: ReusableComponentDefinition?
    @State private var definitionToDelete: ReusableComponentDefinition?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(definitions) { definition in
                HStack(spacing: 10) {
                    Image(systemName: definition.root.type.systemImage)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(definition.name)
                        Text("Updates everywhere")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "link")
                        .foregroundStyle(.tertiary)
                }
                .draggable(ComponentDragPayload.global(definition.id).stringValue) {
                    ComponentDragPreview(name: definition.name, systemImage: definition.root.type.systemImage)
                }
                .contextMenu {
                    Button("Rename…") {
                        renameText = definition.name
                        definitionToRename = definition
                    }
                    Button("Delete…", role: .destructive) { definitionToDelete = definition }
                }
            }
        }
        .overlay {
            if definitions.isEmpty {
                ContentUnavailableView(
                    "No Global Components",
                    systemImage: "globe",
                    description: Text("Save a component as global from Structure to add it here.")
                )
            }
        }
        .alert("Rename Global Component", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { definitionToRename = nil }
            Button("Rename") {
                guard let id = definitionToRename?.id else { return }
                renameDefinition(id, renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                definitionToRename = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Delete \(definitionToDelete?.name ?? "Global Component")?", isPresented: deleteAlertBinding) {
            Button("Delete Global Component", role: .destructive) {
                guard let id = definitionToDelete?.id else { return }
                deleteDefinition(id)
                definitionToDelete = nil
            }
            Button("Cancel", role: .cancel) { definitionToDelete = nil }
        } message: {
            Text("Existing instances will be detached and keep their current content.")
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { definitionToRename != nil }, set: { if !$0 { definitionToRename = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { definitionToDelete != nil }, set: { if !$0 { definitionToDelete = nil } })
    }
}

struct StructurePanel: View {
    let page: Page?
    @Binding var selectedComponentIDs: Set<UUID>
    @Binding var selectedComponentID: UUID?
    let moveComponentsToPlacement: ([UUID], ComponentPlacement) -> Bool
    let insertComponent: (ComponentType, ComponentPlacement) -> Bool
    let insertReusableComponent: (UUID, ComponentPlacement) -> Bool
    let insertGlobalComponent: (UUID, ComponentPlacement) -> Bool
    let duplicateComponent: () -> Void
    let copyComponent: () -> Void
    let pasteComponent: () -> Void
    let moveComponent: (Int) -> Void
    let outdentComponent: () -> Void
    let deleteComponent: () -> Void
    let canPasteComponent: Bool
    let selectedComponentName: String?
    let isReusableInstance: Bool
    let canUpdateReusableComponent: Bool
    let saveReusableComponent: (String) -> Void
    let saveGlobalComponent: (String) -> Void
    let updateReusableComponent: () -> Void
    let detachReusableComponent: () -> Void
    @State private var expandedComponentIDs: Set<UUID> = []
    @State private var isNamingReusableComponent = false
    @State private var reusableComponentName = ""
    @State private var isNamingGlobalComponent = false
    @State private var globalComponentName = ""

    var body: some View {
        VStack(spacing: 0) {
            if let page {
                StructureOutlineView(
                    components: page.components,
                    selectedComponentIDs: $selectedComponentIDs,
                    primarySelectedComponentID: $selectedComponentID,
                    moveComponents: moveComponentsToPlacement,
                    insertComponent: insertComponent,
                    insertReusableComponent: insertReusableComponent,
                    insertGlobalComponent: insertGlobalComponent
                )
            } else {
                ContentUnavailableView("No Page", systemImage: "doc")
            }

            Divider()
            HStack {
                Menu("Component Actions", systemImage: "ellipsis.circle") {
                    Button("Duplicate", action: duplicateComponent)
                    Button("Copy", action: copyComponent)
                    Button("Paste", action: pasteComponent)
                        .disabled(!canPasteComponent)
                    Button("Save as Reusable Component…") {
                        reusableComponentName = selectedComponentName ?? "Reusable Component"
                        isNamingReusableComponent = true
                    }
                    .disabled(selectedComponentID == nil)
                    Button("Save as Global Component…") {
                        globalComponentName = selectedComponentName ?? "Global Component"
                        isNamingGlobalComponent = true
                    }
                    .disabled(selectedComponentID == nil)
                    if isReusableInstance {
                        Button("Update Reusable Definition", action: updateReusableComponent)
                            .disabled(!canUpdateReusableComponent)
                        Button("Detach from Reusable Definition", action: detachReusableComponent)
                    }
                    Divider()
                    Button("Move Up") { moveComponent(-1) }
                    Button("Move Down") { moveComponent(1) }
                    Button("Move Out of Container", action: outdentComponent)
                    Divider()
                    Button("Delete", role: .destructive, action: deleteComponent)
                }
                .disabled(selectedComponentID == nil && !canPasteComponent)
                Spacer()
            }
            .labelStyle(.iconOnly)
            .padding(8)
        }
        .alert("Save Reusable Component", isPresented: $isNamingReusableComponent) {
            TextField("Name", text: $reusableComponentName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveReusableComponent(reusableComponentName) }
                .disabled(reusableComponentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The selected component and its children will be available in the Project library.")
        }
        .alert("Save Global Component", isPresented: $isNamingGlobalComponent) {
            TextField("Name", text: $globalComponentName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveGlobalComponent(globalComponentName) }
                .disabled(globalComponentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Every linked instance will update when this global component is edited.")
        }
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard let selectedComponentID, let page else { return }
        expandedComponentIDs.formUnion(page.components.ancestorIDs(of: selectedComponentID))
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(selectedComponentID, anchor: .center)
        }
    }

    private func acceptAtEnd(_ payload: ComponentDragPayload) -> Bool {
        switch payload {
        case .library(let type): insertComponent(type, .end)
        case .reusable(let id): insertReusableComponent(id, .end)
        case .global(let id): insertGlobalComponent(id, .end)
        case .node(let id): moveComponentsToPlacement([id], .end)
        case .nodes(let ids): moveComponentsToPlacement(ids, .end)
        }
    }

    private func visibleComponents(in page: Page) -> [StructureTreeItem] {
        StructureTreeItem.flatten(page.components, expandedIDs: expandedComponentIDs)
    }

    private func applyReorder(
        _ difference: ReorderDifference<UUID, ReorderableSingleCollectionIdentifier>
    ) {
        let placement: ComponentPlacement
        switch difference.destination.position {
        case .before(let targetID):
            placement = .before(targetID)
        case .end:
            placement = .end
        }
        for sourceID in difference.sources {
            _ = moveComponentsToPlacement([sourceID], placement)
        }
    }

}

nonisolated struct StructureTreeItem: Identifiable, Sendable {
    let component: ComponentNode
    let depth: Int

    var id: UUID { component.id }

    static func flatten(
        _ components: [ComponentNode],
        expandedIDs: Set<UUID>,
        depth: Int = 0
    ) -> [StructureTreeItem] {
        components.flatMap { component in
            var result = [StructureTreeItem(component: component, depth: depth)]
            if expandedIDs.contains(component.id) {
                result += flatten(component.children, expandedIDs: expandedIDs, depth: depth + 1)
            }
            return result
        }
    }
}

private struct StructureEndDropZone: View {
    let isEmpty: Bool
    let accept: (ComponentDragPayload) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Label(
            isEmpty ? "Drop a component here" : "Drop at page end",
            systemImage: isEmpty ? "square.and.arrow.down" : "arrow.down.to.line"
        )
        .font(.caption)
        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: isEmpty ? 64 : 28)
        .background(
            isTargeted ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(isEmpty ? 0.35 : 0),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let payload = ComponentDragPayload(value) else { return false }
            return accept(payload)
        } isTargeted: {
            isTargeted = $0
        }
    }
}
