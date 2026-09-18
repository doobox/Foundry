import Foundation
import Testing
@testable import Foundry

struct AssetByteStoreTests {
    private func makePackage(with data: Data, asset: ProjectAsset) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let assetsDir = root.appending(path: "assets", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try data.write(to: assetsDir.appending(path: asset.storageFilename))
        return root
    }

    @Test
    func resolvesBytesFromTheAdoptedPackageURL() throws {
        let data = Data("package bytes".utf8)
        let asset = ProjectAsset(
            filename: "photo.png",
            mediaType: "image/png",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data)
        )
        let root = try makePackage(with: data, asset: asset)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AssetByteStore()

        #expect(store.resolve(asset) == nil)
        #expect(!store.hasContent(for: asset))

        store.adoptPackageURL(root)

        #expect(store.hasContent(for: asset))
        #expect(store.resolve(asset) == data)
    }

    @Test
    func pendingImportsResolveBeforeAPackageURLExists() {
        let data = Data("pending bytes".utf8)
        let asset = ProjectAsset(
            filename: "pending.png",
            mediaType: "image/png",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data)
        )
        let store = AssetByteStore()

        store.stagePendingImport(id: asset.id, data: data)

        #expect(store.hasContent(for: asset))
        #expect(store.resolve(asset) == data)
    }

    @Test
    func pinForUndoKeepsBytesResolvableAfterThePackageFileIsRemoved() throws {
        let data = Data("pinned bytes".utf8)
        let asset = ProjectAsset(
            filename: "pinned.bin",
            mediaType: "application/octet-stream",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data)
        )
        let root = try makePackage(with: data, asset: asset)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AssetByteStore()
        store.adoptPackageURL(root)

        let pin = store.pinForUndo(asset)
        #expect(pin != nil)

        try FileManager.default.removeItem(at: root.appending(path: "assets/\(asset.storageFilename)"))

        #expect(store.resolve(asset) == data, "The pin should keep the deleted asset's bytes resolvable after the package file is gone.")
    }

    @Test
    func pinRefCountKeepsBytesResolvableUntilEveryPinReleases() throws {
        let data = Data("double-pinned bytes".utf8)
        let asset = ProjectAsset(
            filename: "double-pinned.bin",
            mediaType: "application/octet-stream",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data)
        )
        let root = try makePackage(with: data, asset: asset)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AssetByteStore()
        store.adoptPackageURL(root)

        var firstPin = store.pinForUndo(asset)
        let secondPin = store.pinForUndo(asset)
        #expect(firstPin != nil)
        #expect(secondPin != nil)

        try FileManager.default.removeItem(at: root.appending(path: "assets/\(asset.storageFilename)"))

        firstPin = nil
        #expect(store.resolve(asset) == data, "A second outstanding pin should keep the bytes alive after the first pin releases.")
        _ = secondPin
    }

    @Test
    func missingAssetsResolveToNilWithoutAnyBacking() {
        let asset = ProjectAsset(
            filename: "missing.bin",
            mediaType: "application/octet-stream",
            byteCount: 4,
            contentDigest: FoundryDocumentSnapshot.digest(for: Data("none".utf8))
        )
        let store = AssetByteStore()

        #expect(!store.hasContent(for: asset))
        #expect(store.resolve(asset) == nil)
    }
}
