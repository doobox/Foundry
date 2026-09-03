import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PagesPanel: View {
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let publishingChanges: [UUID: PublishingChange]
    @Binding var selectedPageID: UUID?
    @Binding var selectedFolderID: UUID?
    @Binding var selectedAssetID: UUID?
    let addPage: () -> Void
    let addFolder: (String) -> Void
    let duplicatePage: (UUID) -> Void
    let renamePage: (UUID, String) -> Void
    let deletePage: (UUID) -> Void
    let movePage: (UUID, Int) -> Void
    let setHomePage: (UUID) -> Void
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
                publishingChanges: publishingChanges,
                selectedPageID: $selectedPageID,
                selectedFolderID: $selectedFolderID,
                selectedAssetID: $selectedAssetID,
                addPage: addPage,
                requestAddFolder: {
                    folderName = ""
                    isNamingFolder = true
                },
                duplicatePage: duplicatePage,
                renamePage: renamePage,
                deletePage: deletePage,
                movePage: movePage,
                setHomePage: setHomePage,
                moveItem: moveTreeItem,
                importURLs: importURLs
            )
            .padding(.top, 12)
            .overlay {
                if pages.isEmpty && folders.isEmpty {
                    ContentUnavailableView("No Pages", systemImage: "doc")
                }
            }

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
                                        if let packageURL = type.definition.package?.rootURL {
                                            Divider()
                                            Button(
                                                "Show in Finder",
                                                systemImage: "macwindow.and.pointer.arrow"
                                            ) {
                                                NSWorkspace.shared.activateFileViewerSelecting([packageURL])
                                            }
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
        }
    }

    private var componentSections: [ComponentLibrarySection] {
        let types = ComponentType.allCases
        let preferredCategories: [ComponentCategory] = [
            .layout, .content, .media, .navigation, .forms, .interactive, .other
        ]
        let remainingCategories = Set(types.map { $0.definition.category })
            .subtracting(preferredCategories)
            .sorted { $0.rawValue < $1.rawValue }
        return (preferredCategories + remainingCategories).compactMap { category in
            let categoryTypes = types.filter { $0.definition.category == category }
            guard !categoryTypes.isEmpty else { return nil }
            return ComponentLibrarySection(
                category: category,
                title: category.rawValue,
                types: categoryTypes
            )
        }
    }
}

struct DeveloperPanel: View {
    @State private var catalog = ComponentPackageCatalog.shared

    var body: some View {
        let _ = catalog.revision
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryTitle)
                        .font(.headline)
                    Text(summaryDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Reload Components", systemImage: "arrow.clockwise") {
                    catalog.reloadAllPacks()
                }
                .labelStyle(.iconOnly)
                .help("Reload component packages")
            }
            .padding(12)

            Divider()

            if issues.isEmpty {
                ContentUnavailableView(
                    "No Component Issues",
                    systemImage: "checkmark.circle",
                    description: Text("Package validation and loading issues will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(issues) { issue in
                            DeveloperPackageIssueCard(issue: issue)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var issues: [DeveloperPackageIssue] {
        catalog.diagnostics.compactMap { url, diagnostics in
            guard !diagnostics.isEmpty else { return nil }
            return DeveloperPackageIssue(url: url, diagnostics: diagnostics)
        }
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private var errorCount: Int {
        issues.reduce(into: 0) { count, issue in
            count += issue.diagnostics.count { $0.severity == .error }
        }
    }

    private var warningCount: Int {
        issues.reduce(into: 0) { count, issue in
            count += issue.diagnostics.count { $0.severity == .warning }
        }
    }

    private var summaryTitle: String {
        guard !issues.isEmpty else { return "Components are healthy" }
        return issues.count == 1 ? "1 component needs attention" : "\(issues.count) components need attention"
    }

    private var summaryDescription: String {
        guard !issues.isEmpty else { return "All discovered component packages loaded successfully." }
        var parts: [String] = []
        if errorCount > 0 {
            parts.append(errorCount == 1 ? "1 error" : "\(errorCount) errors")
        }
        if warningCount > 0 {
            parts.append(warningCount == 1 ? "1 warning" : "\(warningCount) warnings")
        }
        return parts.joined(separator: ", ")
    }
}

private struct DeveloperPackageIssue: Identifiable {
    let url: URL
    let diagnostics: [ComponentPackageDiagnostic]
    let displayName: String
    let identifier: String?

    var id: URL { url }
    var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

    init(url: URL, diagnostics: [ComponentPackageDiagnostic]) {
        self.url = url
        self.diagnostics = diagnostics

        let manifestURL = url.appending(path: "Contents/Info.plist")
        let manifest: [String: Any]?
        if let data = try? Data(contentsOf: manifestURL),
           let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            manifest = propertyList as? [String: Any]
        } else {
            manifest = nil
        }
        let title = manifest?["title"] as? String
        let identifier = manifest?["id"] as? String
        displayName = title.flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        self.identifier = identifier?.isEmpty == false ? identifier : nil
    }
}

private struct DeveloperPackageIssueCard: View {
    let issue: DeveloperPackageIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: issue.hasErrors ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.hasErrors ? .red : .orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.displayName)
                        .font(.headline)
                    Text(issue.hasErrors ? "Failed to load" : "Loaded with warnings")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(issue.hasErrors ? .red : .orange)
                    if let identifier = issue.identifier {
                        Text(identifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 8)

                Button("Show in Finder", systemImage: "macwindow.and.pointer.arrow") {
                    NSWorkspace.shared.activateFileViewerSelecting([issue.url])
                }
                .labelStyle(.iconOnly)
                .help("Show package in Finder")
            }

            Divider()

            ForEach(Array(issue.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: diagnostic.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnostic.message)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text(diagnostic.location)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Text(issue.url.path(percentEncoded: false))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
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
            HStack(alignment: .center, spacing: 10) {
                ComponentLibraryIcon(type: type, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.headline)
                    Text(type.libraryDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    Text("Developer")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(componentDeveloper)
                        if let helpURL = componentPackage?.manifest.helpURL {
                            Link(destination: helpURL) {
                                Image(systemName: "link")
                            }
                            .buttonStyle(.plain)
                            .help("Open component documentation")
                        }
                    }
                }
                GridRow {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Text(componentVersion)
                }
            }
            .font(.caption)

            if !componentTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 58), spacing: 5)],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(componentTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private var componentDeveloper: String {
        componentPackage?.manifest.author.flatMap { author in
            author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : author
        } ?? "Unknown Developer"
    }

    private var componentVersion: String {
        componentPackage?.manifest.version ?? "—"
    }

    private var componentTags: [String] {
        componentPackage?.manifest.tags ?? []
    }

    private var componentPackage: LoadedComponentPackage? {
        type.definition.package
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
            } else {
                Image(systemName: type.systemImage)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16))
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
    let saveDraggedComponents: ([UUID]) -> Bool
    @State private var definitionToRename: ReusableComponentDefinition?
    @State private var definitionToDelete: ReusableComponentDefinition?
    @State private var renameText = ""
    @State private var isDropTargeted = false

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
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first,
                  let payload = ComponentDragPayload(value) else { return false }
            switch payload {
            case .node(let id):
                return saveDraggedComponents([id])
            case .nodes(let ids):
                return saveDraggedComponents(ids)
            case .library, .reusable, .global:
                return false
            }
        } isTargeted: {
            isDropTargeted = $0
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
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: isDropTargeted ? 2 : 0)
                .padding(4)
                .allowsHitTesting(false)
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
    let renameComponent: (UUID, String) -> Void
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
    let saveReusableComponent: (String) -> Void
    let saveGlobalComponent: (String) -> Void
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
                    renameComponent: renameComponent,
                    moveComponents: moveComponentsToPlacement,
                    insertComponent: insertComponent,
                    insertReusableComponent: insertReusableComponent,
                    insertGlobalComponent: insertGlobalComponent,
                    duplicateComponent: duplicateComponent,
                    copyComponent: copyComponent,
                    pasteComponent: pasteComponent,
                    canPasteComponent: canPasteComponent,
                    saveAsReusableComponent: {
                        reusableComponentName = $0
                        isNamingReusableComponent = true
                    },
                    saveAsGlobalComponent: {
                        globalComponentName = $0
                        isNamingGlobalComponent = true
                    },
                    moveComponent: moveComponent,
                    outdentComponent: outdentComponent,
                    deleteComponent: deleteComponent
                )
            } else {
                ContentUnavailableView("No Page", systemImage: "doc")
            }
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
