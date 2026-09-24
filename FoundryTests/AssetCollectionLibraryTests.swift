import Foundation
import Testing
@testable import Foundry

@MainActor
struct AssetCollectionLibraryTests {
    private func makePackRoot(extension packExtension: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(packExtension)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "id": "test.assets.\(UUID().uuidString.lowercased())",
            "title": "Test Pack",
            "version": "1.0.0",
            "minimumAPIVersion": 1
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appending(path: "manifest.json"))
        return root
    }

    @Test
    func curationManagesCollectionsInsideAnEditablePack() throws {
        let root = try makePackRoot(extension: "foundrydevpack")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = AssetCollectionLibrary(fixedRootURLs: [root])

        // An editable source is listed even before it has collections.
        #expect(library.sources.count == 1)
        #expect(library.sources.first?.isEditable == true)

        let created = try #require(library.createCollection(named: "Logos", inPackRoot: root))
        #expect(library.isEditable(collectionID: created.identifier))
        #expect(created.files.isEmpty)

        // Files copy in from disk and from memory; name collisions unique.
        let source = FileManager.default.temporaryDirectory.appending(path: "banner-\(UUID().uuidString).png")
        try Data([1, 2, 3]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        #expect(library.addFiles(at: [source], to: created.identifier) == 1)
        #expect(library.addFile(data: Data("svg".utf8), filename: "logo.svg", to: created.identifier))
        #expect(library.addFiles(at: [source], to: created.identifier) == 1)
        let filenames = try #require(library.collection(withID: created.identifier)).files.map(\.filename)
        #expect(filenames.count == 3)
        #expect(Set(filenames).count == 3, "colliding filenames must be uniqued")

        // Rename and licence edits round-trip through the item manifest.
        library.renameCollection(id: created.identifier, to: "Brand Logos")
        library.setLicence(
            id: created.identifier,
            license: "CC0",
            licenseURL: URL(string: "https://example.com/license"),
            attribution: "Test"
        )
        let updated = try #require(library.collection(withID: created.identifier))
        #expect(updated.title == "Brand Logos")
        #expect(updated.license == "CC0")
        #expect(updated.licenseURL == URL(string: "https://example.com/license"))
        #expect(updated.attribution == "Test")

        // Removing files and deleting the collection clean up on disk.
        library.removeFiles([updated.files[0].id], from: created.identifier)
        #expect(library.collection(withID: created.identifier)?.files.count == 2)
        library.deleteCollection(id: created.identifier)
        #expect(library.collection(withID: created.identifier) == nil)
        #expect(!FileManager.default.fileExists(atPath: updated.itemURL.path))
    }

    @Test
    func foldersOrganizeFilesInsideACollection() throws {
        let root = try makePackRoot(extension: "foundrydevpack")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = AssetCollectionLibrary(fixedRootURLs: [root])
        let created = try #require(library.createCollection(named: "Textures", inPackRoot: root))
        #expect(library.addFile(data: Data([1]), filename: "wood.png", to: created.identifier))
        #expect(library.addFile(data: Data([2]), filename: "stone.png", to: created.identifier))

        // Folders create at the root and nested, and empty ones still list.
        #expect(library.createFolder(named: "Wood", in: created.identifier))
        let woodFolder = try #require(
            library.collection(withID: created.identifier)?.nodes
                .compactMap { node -> AssetCollectionFolder? in
                    guard case .folder(let folder) = node else { return nil }
                    return folder
                }
                .first
        )
        #expect(woodFolder.files.isEmpty)
        #expect(library.createFolder(named: "Oak", in: created.identifier, insideFolderID: woodFolder.id))
        #expect(library.folderContext(withID: woodFolder.id)?.folder.nodes.count == 1)

        // Files move into a folder and back to the collection root.
        let woodFile = try #require(
            library.collection(withID: created.identifier)?.files.first { $0.filename == "wood.png" }
        )
        library.moveFiles([woodFile.id], in: created.identifier, toFolderID: woodFolder.id)
        var collection = try #require(library.collection(withID: created.identifier))
        #expect(collection.files.count == 2, "moving keeps the file in the collection")
        var movedFolder = try #require(library.folderContext(withID: woodFolder.id)?.folder)
        #expect(movedFolder.files.map(\.filename) == ["wood.png"])
        let movedFile = try #require(movedFolder.files.first)
        library.moveFiles([movedFile.id], in: created.identifier, toFolderID: nil)
        movedFolder = try #require(library.folderContext(withID: woodFolder.id)?.folder)
        #expect(movedFolder.files.isEmpty)

        // Renaming returns the folder's new path id; deletion removes the
        // folder and its contents but not the rest of the collection.
        let renamedID = try #require(library.renameFolder(id: woodFolder.id, to: "Timber"))
        #expect(library.folderContext(withID: renamedID)?.folder.name == "Timber")
        #expect(library.folderContext(withID: woodFolder.id) == nil)
        library.moveFiles(
            [try #require(library.collection(withID: created.identifier)?.files.first { $0.filename == "stone.png" }?.id)],
            in: created.identifier,
            toFolderID: renamedID
        )
        library.deleteFolder(id: renamedID)
        collection = try #require(library.collection(withID: created.identifier))
        #expect(library.folderContext(withID: renamedID) == nil)
        #expect(collection.files.map(\.filename) == ["wood.png"])
    }

    @Test
    func collectionsMoveBetweenEditablePacksAndCopyOutOfReadOnlyOnes() throws {
        let firstDevPack = try makePackRoot(extension: "foundrydevpack")
        let secondDevPack = try makePackRoot(extension: "foundrydevpack")
        let readOnlyPack = try makePackRoot(extension: "foundrypack")
        defer {
            try? FileManager.default.removeItem(at: firstDevPack)
            try? FileManager.default.removeItem(at: secondDevPack)
            try? FileManager.default.removeItem(at: readOnlyPack)
        }
        let shippedItem = readOnlyPack.appending(path: "Assets/shipped", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shippedItem, withIntermediateDirectories: true)
        try Data([7]).write(to: shippedItem.appending(path: "photo.jpg"))
        try AssetCollectionStore.writeManifest(
            identifier: "test.shipped",
            title: "Shipped",
            license: "CC0",
            licenseURL: nil,
            attribution: nil,
            to: shippedItem
        )
        let library = AssetCollectionLibrary(fixedRootURLs: [firstDevPack, secondDevPack, readOnlyPack])

        // Moving between editable packs relocates the folder with its
        // contents; a manifest-less collection's path id changes with it.
        let created = try #require(library.createCollection(named: "Icons", inPackRoot: firstDevPack))
        #expect(library.addFile(data: Data([1]), filename: "icon.svg", to: created.identifier))
        #expect(library.moveCollection(id: created.identifier, toPackRoot: secondDevPack))
        #expect(library.collection(withID: created.identifier) == nil)
        let moved = try #require(
            library.sources
                .first { $0.rootURL == secondDevPack.standardizedFileURL }?
                .collections.first
        )
        #expect(moved.title == "Icons")
        #expect(moved.itemURL.path.hasPrefix(secondDevPack.standardizedFileURL.path))
        #expect(moved.files.count == 1)

        // Moving onto its own pack or a read-only pack is refused.
        #expect(!library.moveCollection(id: moved.identifier, toPackRoot: secondDevPack))
        #expect(!library.moveCollection(id: moved.identifier, toPackRoot: readOnlyPack))

        // Copying out of a read-only pack duplicates under a fresh identity,
        // keeping title, licence, and files; the original is untouched.
        #expect(library.copyCollection(id: "test.shipped", toPackRoot: firstDevPack))
        #expect(library.collection(withID: "test.shipped")?.itemURL == shippedItem.standardizedFileURL)
        let copy = try #require(
            library.sources
                .first { $0.rootURL == firstDevPack.standardizedFileURL }?
                .collections.first
        )
        #expect(copy.identifier != "test.shipped")
        #expect(copy.title == "Shipped")
        #expect(copy.license == "CC0")
        #expect(copy.files.count == 1)

        // A read-only collection cannot be moved, only copied.
        #expect(!library.moveCollection(id: "test.shipped", toPackRoot: firstDevPack))
    }

    @Test
    func readOnlyPacksRefuseCurationButListTheirCollections() throws {
        let root = try makePackRoot(extension: "foundrypack")
        defer { try? FileManager.default.removeItem(at: root) }
        let item = root.appending(path: "Assets/shipped", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        try Data([7]).write(to: item.appending(path: "photo.jpg"))
        try AssetCollectionStore.writeManifest(
            identifier: "test.shipped",
            title: "Shipped",
            license: nil,
            licenseURL: nil,
            attribution: nil,
            to: item
        )
        let library = AssetCollectionLibrary(fixedRootURLs: [root])

        #expect(library.sources.first?.isEditable == false)
        #expect(library.collection(withID: "test.shipped")?.files.count == 1)

        // Every write path is a no-op against a read-only pack.
        #expect(library.createCollection(named: "Nope", inPackRoot: root) == nil)
        #expect(library.addFiles(at: [item], to: "test.shipped") == 0)
        library.renameCollection(id: "test.shipped", to: "Renamed")
        library.deleteCollection(id: "test.shipped")
        #expect(library.collection(withID: "test.shipped")?.title == "Shipped")
    }
}
