import SwiftUI

struct PackageSiteAsset: Identifiable, Equatable {
    let packageIdentifier: String
    let packageTitle: String
    let declaredPath: String
    let pageCount: Int

    var id: String { packageIdentifier + ":" + declaredPath }
    var publishedPath: String { "assets/" + declaredPath }
}

struct AssetsPanel: View {
    let library: [ProjectAssetNode]
    let packageSiteAssets: [PackageSiteAsset]
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
            VStack(spacing: 0) {
                AssetsOutlineView(
                    nodes: library,
                    selectedNodeID: $selectedNodeID,
                    moveNode: moveNode,
                    importURLs: importURLs
                )
                if !packageSiteAssets.isEmpty {
                    Divider()
                    packageAssetsSection
                        .frame(maxHeight: 180)
                }
            }
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

    private var packageAssetsSection: some View {
        List {
            Section("Package Site Assets") {
                ForEach(packageSiteAssets) { asset in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(asset.declaredPath, systemImage: "shippingbox")
                        Text(asset.publishedPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("\(asset.packageTitle) · used on \(asset.pageCount) page\(asset.pageCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .help("Read-only site asset from \(asset.packageIdentifier)")
                }
            }
        }
        .listStyle(.sidebar)
    }
}
