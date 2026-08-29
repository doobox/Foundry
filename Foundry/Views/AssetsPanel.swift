import SwiftUI

struct AssetsPanel: View {
    let library: [ProjectAssetNode]
    @Binding var selectedNodeID: UUID?
    let importFiles: () -> Void
    let importURLs: ([URL], AssetPlacement) -> Void
    let createFolder: (String, AssetPlacement) -> Void
    let moveNode: (UUID, AssetPlacement) -> Bool
    let deleteNode: (UUID) -> Void
    @State private var isNamingFolder = false
    @State private var folderName = ""

    var body: some View {
        VStack(spacing: 0) {
            AssetsOutlineView(
                nodes: library,
                selectedNodeID: $selectedNodeID,
                moveNode: moveNode,
                importURLs: importURLs
            )
            .overlay {
                if library.isEmpty {
                    ContentUnavailableView(
                        "No Assets",
                        systemImage: "folder",
                        description: Text("Import files or drop files and folders here.")
                    )
                    .allowsHitTesting(false)
                }
            }

            Divider()
            HStack {
                Menu("Add", systemImage: "plus") {
                    Button("Import Files or Folders…", systemImage: "square.and.arrow.down", action: importFiles)
                    Button("New Folder…", systemImage: "folder.badge.plus") {
                        folderName = ""
                        isNamingFolder = true
                    }
                }
                Menu("Asset Actions", systemImage: "ellipsis.circle") {
                    Button("Delete", role: .destructive) {
                        if let selectedNodeID { deleteNode(selectedNodeID) }
                    }
                    .disabled(selectedNodeID == nil)
                }
                Spacer()
            }
            .labelStyle(.iconOnly)
            .padding(8)
        }
        .alert("New Asset Folder", isPresented: $isNamingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                createFolder(folderName.trimmingCharacters(in: .whitespacesAndNewlines), .end)
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
