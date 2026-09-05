import Combine
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

nonisolated struct FoundryDocumentSnapshot: Sendable {
    var site: Site
    var assetData: [UUID: Data]
    var assetRevision: UInt64 = 0
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
        if configuration.file.isRegularFile,
           let data = configuration.file.regularFileContents {
            storage = Mutex(.init(site: try Self.decodeProject(from: data), assetData: [:]))
            return
        }
        guard configuration.file.isDirectory,
              let wrappers = configuration.file.fileWrappers,
              let projectData = wrappers["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let site = try Self.decodeProject(from: projectData)
        let assetWrappers = wrappers["assets"]?.fileWrappers ?? [:]
        let data = Dictionary(uniqueKeysWithValues: site.assets.compactMap { asset in
            assetWrappers[asset.storageFilename]?.regularFileContents.map { (asset.id, $0) }
        })
        storage = Mutex(.init(site: site, assetData: data))
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
            snapshot.assetData[asset.id].map { (asset.id, ProjectAssetContent(asset: asset, data: $0)) }
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
        undoManager: UndoManager?
    ) -> UUID {
        let asset = ProjectAsset(filename: filename, mediaType: mediaType, byteCount: data.count)
        var nextSite = site
        guard nextSite.assetLibrary.insert(.asset(asset), at: placement) else { return asset.id }
        replaceContents(site: nextSite, assetData: storage.withLock { $0.assetData }.merging([asset.id: data]) { _, new in new }, undoManager: undoManager, actionName: "Import Asset")
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
        var nextSite = site
        guard let node = nextSite.assetLibrary.removeNode(id: id) else { return }
        var nextData = storage.withLock { $0.assetData }
        for assetID in node.assetIDs { nextData.removeValue(forKey: assetID) }
        replaceContents(site: nextSite, assetData: nextData, undoManager: undoManager, actionName: "Delete Asset Folder")
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
        var nextSite = site
        guard nextSite.assetLibrary.removeNode(id: id) != nil else { return }
        var nextData = storage.withLock { $0.assetData }
        nextData.removeValue(forKey: id)
        replaceContents(site: nextSite, assetData: nextData, undoManager: undoManager, actionName: "Delete Asset")
    }

    @MainActor
    private func replaceContents(site newSite: Site, assetData: [UUID: Data], undoManager: UndoManager?, actionName: String) {
        let previous = storage.withLock { $0 }
        undoManager?.registerUndo(withTarget: self) { document in
            document.replaceContents(site: previous.site, assetData: previous.assetData, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        objectWillChange.send()
        storage.withLock {
            $0 = .init(
                site: newSite,
                assetData: assetData,
                assetRevision: $0.assetRevision &+ 1
            )
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
