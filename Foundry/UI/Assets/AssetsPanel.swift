import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AssetsPanel: View {
    let library: [ProjectAssetNode]
    let assetContents: ProjectAssetContents
    @Binding var selectedNodeID: UUID?
    /// Selection in the Library/Dev tabs — collection identifiers or file
    /// paths — driving the Inspector like every other panel selection.
    @Binding var selectedCollectionItemID: String?
    let importFiles: () -> Void
    let importURLs: ([URL], AssetPlacement) -> Void
    /// Imports collection files into the project — the Library tab's
    /// "Add to Project" gesture.
    let importCollectionFiles: ([AssetCollectionFile]) -> Void
    let createFolder: (String) -> Void
    let moveNode: (UUID, AssetPlacement) -> Bool
    let deleteNodes: ([UUID]) -> Void
    let renameAsset: (UUID, String) -> Void
    let renameFolder: (UUID, String) -> Void
    @State private var tab: LibraryPanelTab = .project
    @State private var isNamingFolder = false
    @State private var folderName = ""
    @State private var isNamingCollection = false
    @State private var collectionName = ""
    @State private var collectionDestinationURL: URL?
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The Library tab: My Library plus installed packs that ship
    /// collections. Dev packs get their own tab, shown only when any exist.
    private var librarySources: [AssetCollectionSource] {
        AssetCollectionLibrary.shared.sources
            .filter { $0.isPersonal || (!$0.isEditable && !$0.collections.isEmpty) }
    }

    private var devSources: [AssetCollectionSource] {
        AssetCollectionLibrary.shared.sources
            .filter { $0.isEditable && !$0.isPersonal }
    }

    private var availableTabs: [LibraryPanelTab] {
        devSources.isEmpty ? [.project, .library] : [.project, .library, .dev]
    }

    /// The packs New Collection can create into on the active tab — every
    /// editable pack is an explicit menu target, never a silent default.
    private var collectionCreationTargets: [AssetCollectionSource] {
        switch tab {
        case .project: []
        case .library: librarySources.filter(\.isEditable)
        case .dev: devSources
        }
    }

    /// Searching filters the same tree down to matching assets as a flat
    /// list — one outline, one presentation, whether filtered or not.
    private var displayedNodes: [ProjectAssetNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library }
        func matches(_ nodes: [ProjectAssetNode]) -> [ProjectAssetNode] {
            nodes.flatMap { node -> [ProjectAssetNode] in
                switch node {
                case .asset(let asset):
                    return asset.filename.localizedCaseInsensitiveContains(query) ? [node] : []
                case .folder(let folder):
                    return matches(folder.children)
                }
            }
        }
        return matches(library)
    }

    var body: some View {
        VStack(spacing: 0) {
            AssetsPanelHeader(
                tab: tab,
                collectionTargets: collectionCreationTargets,
                importFiles: importFiles,
                addFolder: {
                    folderName = ""
                    isNamingFolder = true
                },
                addCollection: { destinationURL in
                    collectionName = ""
                    collectionDestinationURL = destinationURL
                    isNamingCollection = true
                }
            )
            Divider()
            LibraryPanelTabPicker(tab: $tab, tabs: availableTabs)
            switch tab {
            case .project:
                projectTab
            case .library:
                AssetLibraryTab(
                    sources: librarySources,
                    searchText: searchText,
                    selectedItemID: $selectedCollectionItemID,
                    importCollectionFiles: importCollectionFiles
                )
            case .dev:
                AssetLibraryTab(
                    sources: devSources,
                    searchText: searchText,
                    selectedItemID: $selectedCollectionItemID,
                    importCollectionFiles: importCollectionFiles
                )
            }
            Divider()
            PanelSearchField(prompt: "Search Assets", text: $searchText)
        }
        .alert("New Asset Folder", isPresented: $isNamingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                createFolder(folderName.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("New Collection", isPresented: $isNamingCollection) {
            TextField("Collection Name", text: $collectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                _ = AssetCollectionLibrary.shared.createCollection(
                    named: collectionName.trimmingCharacters(in: .whitespacesAndNewlines),
                    inPackRoot: collectionDestinationURL
                )
            }
            .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            if let destinationURL = collectionDestinationURL,
               let title = collectionCreationTargets.first(where: { $0.rootURL == destinationURL })?.title {
                Text("Creates the collection in \(title).")
            }
        }
    }

    @ViewBuilder
    private var projectTab: some View {
        AssetsOutlineView(
            nodes: displayedNodes,
            assetContents: assetContents,
            selectedNodeID: $selectedNodeID,
            // Reordering a filtered list would silently reorganize the
            // real tree; moves resume when the search clears.
            moveNode: { id, placement in
                isSearching ? false : moveNode(id, placement)
            },
            importURLs: importURLs,
            deleteNodes: deleteNodes,
            renameAsset: renameAsset,
            renameFolder: renameFolder
        )
        .overlay {
            if displayedNodes.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                        .allowsHitTesting(false)
                } else {
                    ContentUnavailableView(
                        "No Assets",
                        systemImage: "folder",
                        description: Text("Import files or drop files and folders here.")
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct AssetsPanelHeader: View {
    let tab: LibraryPanelTab
    /// The editable packs New Collection can target — one plain item when
    /// there is a single pack, one named item per pack otherwise.
    let collectionTargets: [AssetCollectionSource]
    let importFiles: () -> Void
    let addFolder: () -> Void
    let addCollection: (URL) -> Void

    var body: some View {
        HStack {
            Text("Assets")
                .font(.headline)
            Spacer()
            Menu {
                if tab == .project {
                    Button("Import Files or Folders…", systemImage: "square.and.arrow.down", action: importFiles)
                    Button("New Folder…", systemImage: "folder.badge.plus", action: addFolder)
                } else if collectionTargets.count == 1, let target = collectionTargets.first,
                          let rootURL = target.rootURL {
                    Button("New Collection…", systemImage: "rectangle.stack.badge.plus") {
                        addCollection(rootURL)
                    }
                } else {
                    ForEach(collectionTargets) { target in
                        if let rootURL = target.rootURL {
                            Button("New Collection in “\(target.title)”…", systemImage: "rectangle.stack.badge.plus") {
                                addCollection(rootURL)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .accessibilityLabel(tab == .project ? "Import Assets or Add Folder" : "New Collection")
            .help(tab == .project ? "Import files or add a folder" : "Create a collection")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

/// The Assets panel's Library and Dev tabs, presented exactly like the
/// Project tab and the Templates panel's: one outline, symbol icons, a
/// padlock on read-only section headers, selection driving the Inspector.
/// Files drag out as file URLs, so dropping one on the canvas or the
/// Project tab imports a copy.
private struct AssetLibraryTab: View {
    /// The sources this tab presents — Library and Dev tabs slice the same
    /// resolved packs differently.
    let sources: [AssetCollectionSource]
    let searchText: String
    @Binding var selectedItemID: String?
    let importCollectionFiles: ([AssetCollectionFile]) -> Void

    /// Where the file importer copies into: a collection root or a folder.
    private struct ImportTarget {
        let collectionID: String
        let folderID: String?
    }

    /// Where New Folder creates: the collection and, when nested, the parent.
    private struct FolderCreationTarget {
        let collectionID: String
        let parentFolderID: String?
    }

    @State private var detailsCollectionID: String?
    @State private var detailsName = ""
    @State private var detailsLicence = ""
    @State private var detailsLicenceURL = ""
    @State private var detailsAttribution = ""
    @State private var collectionPendingDeletion: AssetCollection?
    @State private var folderPendingDeletion: AssetCollectionFolder?
    @State private var filesPendingRemoval: [AssetCollectionFile] = []
    @State private var importTarget: ImportTarget?
    @State private var folderCreationTarget: FolderCreationTarget?
    @State private var newFolderName = ""

    private var library: AssetCollectionLibrary { .shared }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        AssetLibraryOutlineView(
            sources: sources,
            searchQuery: query,
            selectedItemID: $selectedItemID,
            renameCollection: { library.renameCollection(id: $0, to: $1) },
            renameFolder: { folderID, name in
                // Renaming changes the folder's path id; selection follows.
                guard let newID = library.renameFolder(id: folderID, to: name) else { return }
                if selectedItemID == folderID { selectedItemID = newID }
            },
            addAllToProject: { itemID in
                if let collection = library.collection(withID: itemID) {
                    importCollectionFiles(collection.files)
                } else if let context = library.folderContext(withID: itemID) {
                    importCollectionFiles(context.folder.files)
                }
            },
            addFilesRequested: { itemID in
                if library.collection(withID: itemID) != nil {
                    importTarget = ImportTarget(collectionID: itemID, folderID: nil)
                } else if let context = library.folderContext(withID: itemID) {
                    importTarget = ImportTarget(collectionID: context.collection.identifier, folderID: itemID)
                }
            },
            createFolderRequested: { collectionID, parentFolderID in
                newFolderName = ""
                folderCreationTarget = FolderCreationTarget(
                    collectionID: collectionID,
                    parentFolderID: parentFolderID
                )
            },
            editDetailsRequested: { collectionID in
                guard let collection = library.collection(withID: collectionID) else { return }
                beginEditingDetails(of: collection)
            },
            requestDeleteCollection: { collectionID in
                collectionPendingDeletion = library.collection(withID: collectionID)
            },
            requestDeleteFolder: { folderID in
                folderPendingDeletion = library.folderContext(withID: folderID)?.folder
            },
            addFilesToProject: { fileIDs in
                importCollectionFiles(files(withIDs: fileIDs))
            },
            removeFiles: { fileIDs in
                filesPendingRemoval = files(withIDs: fileIDs)
            },
            moveFiles: { fileIDs, collectionID, folderID in
                library.moveFiles(Set(fileIDs), in: collectionID, toFolderID: folderID)
            },
            showInFinder: { itemID in
                guard let url = fileSystemURL(forItemID: itemID) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            dropFileURLs: { urls, collectionID, folderID in
                library.addFiles(at: urls, to: collectionID, insideFolderID: folderID) > 0
            },
            transferCollection: { collectionID, targetSectionID in
                // Destinations resolve across every pack, not just this
                // tab's — the Move to menu reaches packs drags cannot.
                guard let targetRoot = library.sources.first(where: { $0.id == targetSectionID })?.rootURL,
                      let sourceSection = library.source(containing: collectionID) else { return false }
                return sourceSection.isEditable
                    ? library.moveCollection(id: collectionID, toPackRoot: targetRoot)
                    : library.copyCollection(id: collectionID, toPackRoot: targetRoot)
            },
            moveDestinations: library.sources
                .filter(\.isEditable)
                .map { LibraryMoveDestination(sectionID: $0.id, title: $0.title) },
            emptySectionPlaceholder: "Use + to create a collection"
        )
        .fileImporter(
            isPresented: Binding(
                get: { importTarget != nil },
                set: { if !$0 { importTarget = nil } }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard let target = importTarget, case .success(let urls) = result else { return }
            _ = library.addFiles(at: urls, to: target.collectionID, insideFolderID: target.folderID)
        }
        .alert("New Folder", isPresented: Binding(
            get: { folderCreationTarget != nil },
            set: { if !$0 { folderCreationTarget = nil } }
        )) {
            TextField("Folder Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                guard let target = folderCreationTarget else { return }
                _ = library.createFolder(
                    named: newFolderName.trimmingCharacters(in: .whitespacesAndNewlines),
                    in: target.collectionID,
                    insideFolderID: target.parentFolderID
                )
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            filesPendingRemoval.count == 1
                ? "Remove “\(filesPendingRemoval.first?.filename ?? "File")”?"
                : "Remove \(filesPendingRemoval.count) Files?",
            isPresented: Binding(
                get: { !filesPendingRemoval.isEmpty },
                set: { if !$0 { filesPendingRemoval = [] } }
            )
        ) {
            Button(
                filesPendingRemoval.count == 1 ? "Remove File" : "Remove \(filesPendingRemoval.count) Files",
                role: .destructive
            ) {
                for (collectionID, ids) in filesByCollection(withIDs: filesPendingRemoval.map(\.id)) {
                    library.removeFiles(Set(ids), from: collectionID)
                }
                filesPendingRemoval = []
            }
            Button("Cancel", role: .cancel) { filesPendingRemoval = [] }
        } message: {
            Text("Removes the file\(filesPendingRemoval.count == 1 ? "" : "s") from the collection on disk. Assets already imported into projects are unchanged.")
        }
        .confirmationDialog(
            "Delete “\(folderPendingDeletion?.name ?? "Folder")”?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            )
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderPendingDeletion {
                    library.deleteFolder(id: folder.id)
                }
                folderPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { folderPendingDeletion = nil }
        } message: {
            Text("Deletes the folder and the \(folderPendingDeletion?.files.count ?? 0) files inside it from your library.")
        }
        .alert("Collection Details", isPresented: Binding(
            get: { detailsCollectionID != nil },
            set: { if !$0 { detailsCollectionID = nil } }
        )) {
            TextField("Collection Name", text: $detailsName)
            TextField("Licence", text: $detailsLicence)
            TextField("Licence URL", text: $detailsLicenceURL)
            TextField("Attribution", text: $detailsAttribution)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveCollectionDetails() }
        }
        .confirmationDialog(
            "Delete \(collectionPendingDeletion?.title ?? "Collection")?",
            isPresented: Binding(
                get: { collectionPendingDeletion != nil },
                set: { if !$0 { collectionPendingDeletion = nil } }
            )
        ) {
            Button("Delete Collection", role: .destructive) {
                if let collection = collectionPendingDeletion {
                    library.deleteCollection(id: collection.identifier)
                }
                collectionPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { collectionPendingDeletion = nil }
        } message: {
            Text("Deletes the collection and its files from your library. Assets already imported into projects are unchanged.")
        }
    }

    private func files(withIDs fileIDs: [String]) -> [AssetCollectionFile] {
        let wanted = Set(fileIDs)
        return sources.flatMap(\.collections).flatMap(\.files).filter { wanted.contains($0.id) }
    }

    private func filesByCollection(withIDs fileIDs: [String]) -> [String: [String]] {
        let wanted = Set(fileIDs)
        var result: [String: [String]] = [:]
        for collection in sources.flatMap(\.collections) {
            let ids = collection.files.map(\.id).filter { wanted.contains($0) }
            if !ids.isEmpty { result[collection.identifier] = ids }
        }
        return result
    }

    private func fileSystemURL(forItemID itemID: String) -> URL? {
        if let collection = library.collection(withID: itemID) { return collection.itemURL }
        if let context = library.folderContext(withID: itemID) { return context.folder.url }
        return sources.flatMap(\.collections).flatMap(\.files).first { $0.id == itemID }?.url
    }

    private func beginEditingDetails(of collection: AssetCollection) {
        detailsName = collection.title
        detailsLicence = collection.license ?? ""
        detailsLicenceURL = collection.licenseURL?.absoluteString ?? ""
        detailsAttribution = collection.attribution ?? ""
        detailsCollectionID = collection.identifier
    }

    private func saveCollectionDetails() {
        guard let collectionID = detailsCollectionID,
              let collection = library.collection(withID: collectionID) else { return }
        let trimmedName = detailsName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, trimmedName != collection.title {
            library.renameCollection(id: collectionID, to: trimmedName)
        }
        library.setLicence(
            id: collectionID,
            license: detailsLicence.isEmpty ? nil : detailsLicence,
            licenseURL: URL(string: detailsLicenceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            attribution: detailsAttribution.isEmpty ? nil : detailsAttribution
        )
    }
}
