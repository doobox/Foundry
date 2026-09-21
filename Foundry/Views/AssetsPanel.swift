import SwiftUI

struct AssetsPanel: View {
    let library: [ProjectAssetNode]
    let assetContents: ProjectAssetContents
    @Binding var selectedNodeID: UUID?
    let importFiles: () -> Void
    let importURLs: ([URL], AssetPlacement) -> Void
    let createFolder: (String) -> Void
    let moveNode: (UUID, AssetPlacement) -> Bool
    let deleteNodes: ([UUID]) -> Void
    let renameAsset: (UUID, String) -> Void
    let renameFolder: (UUID, String) -> Void
    @State private var isNamingFolder = false
    @State private var folderName = ""
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                importFiles: importFiles,
                addFolder: {
                    folderName = ""
                    isNamingFolder = true
                }
            )
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
    }
}

private struct AssetsPanelHeader: View {
    let importFiles: () -> Void
    let addFolder: () -> Void

    var body: some View {
        HStack {
            Text("Assets")
                .font(.headline)
            Spacer()
            Menu {
                Button("Import Files or Folders…", systemImage: "square.and.arrow.down", action: importFiles)
                Button("New Folder…", systemImage: "folder.badge.plus", action: addFolder)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Import Assets or Add Folder")
            .help("Import files or add a folder")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}
