import Combine
import CryptoKit
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

nonisolated struct FoundryDocumentSnapshot: Sendable {
    var site: Site
    var assetData: [UUID: Data]
    var assetRevision: UInt64 = 0
    private(set) var assetDigestByID: [UUID: Data]
    private(set) var assetIDsByDigest: [Data: Set<UUID>]

    init(site: Site, assetData: [UUID: Data], assetRevision: UInt64 = 0) {
        var site = site
        site.assetLibrary.hydrateImageMetadata(from: assetData)
        self.site = site
        self.assetData = assetData
        self.assetRevision = assetRevision

        var digestByID: [UUID: Data] = [:]
        var IDsByDigest: [Data: Set<UUID>] = [:]
        for (assetID, data) in assetData {
            let digest = Self.digest(for: data)
            digestByID[assetID] = digest
            IDsByDigest[digest, default: []].insert(assetID)
        }
        assetDigestByID = digestByID
        assetIDsByDigest = IDsByDigest
    }

    func matchingAssetID(for data: Data, digest: Data) -> UUID? {
        guard let candidates = assetIDsByDigest[digest] else { return nil }
        return site.assets.first { asset in
            candidates.contains(asset.id) && assetData[asset.id] == data
        }?.id
    }

    mutating func insertAssetData(_ data: Data, id: UUID, digest: Data) {
        assetData[id] = data
        assetDigestByID[id] = digest
        assetIDsByDigest[digest, default: []].insert(id)
    }

    mutating func removeAssetData(id: UUID) {
        assetData.removeValue(forKey: id)
        guard let digest = assetDigestByID.removeValue(forKey: id) else { return }
        assetIDsByDigest[digest]?.remove(id)
        if assetIDsByDigest[digest]?.isEmpty == true {
            assetIDsByDigest.removeValue(forKey: digest)
        }
    }

    static func digest(for data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}

final class FoundryDocument: ReferenceFileDocument {
    typealias Snapshot = FoundryDocumentSnapshot

    nonisolated static let readableContentTypes: [UTType] = [.foundryProject]

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let storage: Mutex<FoundryDocumentSnapshot>

    @MainActor
    var site: Site {
        get { storage.withLock { $0.site } }
        set {
            objectWillChange.send()
            storage.withLock {
                if $0.site.assets != newValue.assets {
                    $0.assetRevision &+= 1
                }
                $0.site = newValue
            }
        }
    }

    init(site: Site = .starter()) {
        storage = Mutex(.init(site: site, assetData: [:]))
    }

    required init(configuration: ReadConfiguration) throws {
        storage = Mutex(try Self.decodeSnapshot(from: configuration.file))
    }

    nonisolated static func decodeSnapshot(from file: FileWrapper) throws -> FoundryDocumentSnapshot {
        if file.isRegularFile,
           let data = file.regularFileContents {
            return .init(site: try decodeProject(from: data), assetData: [:])
        }
        guard file.isDirectory,
              let wrappers = file.fileWrappers,
              let projectData = wrappers["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let site = try decodeProject(from: projectData)
        let assetWrappers = wrappers["assets"]?.fileWrappers ?? [:]
        let data = Dictionary(uniqueKeysWithValues: site.assets.compactMap { asset in
            assetWrappers[asset.storageFilename]?.regularFileContents.map { (asset.id, $0) }
        })
        return .init(site: site, assetData: data)
    }

    nonisolated func snapshot(contentType: UTType) throws -> FoundryDocumentSnapshot {
        storage.withLock { $0 }
    }

    nonisolated func fileWrapper(
        snapshot: FoundryDocumentSnapshot,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let project = FileWrapper(regularFileWithContents: try Self.encoder.encode(snapshot.site))
        let assets = Dictionary(uniqueKeysWithValues: snapshot.site.assets.compactMap { asset in
            snapshot.assetData[asset.id].map { (asset.storageFilename, FileWrapper(regularFileWithContents: $0)) }
        })
        return FileWrapper(directoryWithFileWrappers: [
            "project.json": project,
            "assets": FileWrapper(directoryWithFileWrappers: assets)
        ])
    }

    @MainActor
    func replaceSite(
        with newSite: Site,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard newSite != site else {
            return
        }
        let previousSite = site
        undoManager?.registerUndo(withTarget: self) { document in
            document.replaceSite(
                with: previousSite,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
        site = newSite
    }

    @MainActor
    var assetContents: [UUID: ProjectAssetContent] {
        let snapshot = storage.withLock { $0 }
        return Dictionary(uniqueKeysWithValues: snapshot.site.assets.compactMap { asset in
            snapshot.assetData[asset.id].map {
                (
                    asset.id,
                    ProjectAssetContent(
                        asset: asset,
                        data: $0,
                        digest: snapshot.assetDigestByID[asset.id]
                    )
                )
            }
        })
    }

    @MainActor
    var assetRevision: UInt64 {
        storage.withLock { $0.assetRevision }
    }

    @MainActor
    func importAsset(
        data: Data,
        filename: String,
        mediaType: String,
        placement: AssetPlacement = .end,
        reuseIdenticalContent: Bool = false,
        undoManager: UndoManager?
    ) -> UUID {
        let processed = ComponentImageProcessor.canonicalize(data: data, filename: filename, mimeType: mediaType)
        let digest = FoundryDocumentSnapshot.digest(for: processed.data)
        var next = storage.withLock { $0 }
        if reuseIdenticalContent,
           let existingID = next.matchingAssetID(for: processed.data, digest: digest) {
            return existingID
        }
        let metadata = processed.metadata
        let asset = ProjectAsset(
            filename: metadata.filename,
            mediaType: metadata.mimeType,
            byteCount: processed.data.count,
            pixelWidth: metadata.width,
            pixelHeight: metadata.height
        )
        guard next.site.assetLibrary.insert(.asset(asset), at: placement) else { return asset.id }
        next.insertAssetData(processed.data, id: asset.id, digest: digest)
        replaceContents(with: next, undoManager: undoManager, actionName: "Import Asset")
        return asset.id
    }

    @MainActor
    func createAssetFolder(named name: String, at placement: AssetPlacement = .end, undoManager: UndoManager?) -> UUID {
        let folder = ProjectAssetFolder(name: name)
        var nextSite = site
        guard nextSite.assetLibrary.insert(.folder(folder), at: placement) else { return folder.id }
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "New Asset Folder")
        return folder.id
    }

    @MainActor
    func renameAssetFolder(id: UUID, name: String, undoManager: UndoManager?) {
        var nextSite = site
        guard nextSite.assetLibrary.renameFolder(id: id, to: name) else { return }
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "Rename Asset Folder")
    }

    @MainActor
    func renameAsset(id: UUID, filename: String, undoManager: UndoManager?) {
        let safeFilename = (filename as NSString).lastPathComponent
        guard !safeFilename.isEmpty else { return }
        var nextSite = site
        guard nextSite.assetLibrary.renameAsset(id: id, to: safeFilename) else { return }
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "Rename Asset")
    }

    @MainActor
    func removeAssetFolder(id: UUID, undoManager: UndoManager?) {
        var next = storage.withLock { $0 }
        guard let node = next.site.assetLibrary.removeNode(id: id) else { return }
        for assetID in node.assetIDs { next.removeAssetData(id: assetID) }
        replaceContents(with: next, undoManager: undoManager, actionName: "Delete Asset Folder")
    }

    @MainActor
    func moveAssetNode(id: UUID, to placement: AssetPlacement, undoManager: UndoManager?) -> Bool {
        var nextSite = site
        guard nextSite.assetLibrary.move(id: id, to: placement) else { return false }
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "Move Asset Item")
        return true
    }

    @MainActor
    func moveAssetNodeToResources(id: UUID, to placement: AssetPlacement, undoManager: UndoManager?) -> Bool {
        var nextSite = site
        guard nextSite.assetLibrary.move(id: id, to: placement) else { return false }
        _ = nextSite.assetLibrary.clearExportDirectory(forAssetID: id)
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "Move Asset to Resources")
        return true
    }

    @MainActor
    func removeAsset(id: UUID, undoManager: UndoManager?) {
        var next = storage.withLock { $0 }
        guard next.site.assetLibrary.removeNode(id: id) != nil else { return }
        next.removeAssetData(id: id)
        replaceContents(with: next, undoManager: undoManager, actionName: "Delete Asset")
    }

    @MainActor
    private func replaceContents(
        with newSnapshot: FoundryDocumentSnapshot,
        undoManager: UndoManager?,
        actionName: String
    ) {
        let previous = storage.withLock { $0 }
        undoManager?.registerUndo(withTarget: self) { document in
            document.replaceContents(with: previous, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        objectWillChange.send()
        storage.withLock {
            var replacement = newSnapshot
            replacement.assetRevision = $0.assetRevision &+ 1
            $0 = replacement
        }
    }

    nonisolated static func decodeProject(from data: Data) throws -> Site {
        let site = try decoder.decode(Site.self, from: data)
        try site.validate()
        return site
    }

    nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    nonisolated static var decoder: JSONDecoder {
        JSONDecoder()
    }
}

private extension ProjectAssetNode {
    var assetIDs: [UUID] {
        switch self {
        case .asset(let asset): [asset.id]
        case .folder(let folder): folder.children.flatMap(\.assetIDs)
        }
    }
}
