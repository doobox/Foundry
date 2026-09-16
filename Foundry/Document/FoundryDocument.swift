import Combine
import CryptoKit
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

nonisolated struct FoundryDocumentSnapshot: Sendable {
    private let assetBacking: DocumentAssetBacking
    var site: Site
    var assetData: [UUID: Data]
    var assetRevision: UInt64 = 0
    private(set) var assetDigestByID: [UUID: Data]
    private(set) var assetIDsByDigest: [Data: Set<UUID>]

    init(site: Site, assetData: [UUID: Data], assetRevision: UInt64 = 0) {
        let backing = DocumentAssetBacking()
        assetBacking = backing
        var site = site
        site.assetLibrary.hydrateImageMetadata(from: assetData)
        self.site = site
        self.assetData = assetData.mapValues { backing.back($0) }
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
        assetData[id] = assetBacking.back(data)
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

/// Keep large retained assets in reclaimable, read-only file mappings rather
/// than heap buffers. Snapshots share this owner; undo and saves retain their
/// own immutable Data mappings. Failure falls back to the original bytes.
nonisolated final class DocumentAssetBacking: @unchecked Sendable {
    private let root = FileManager.default.temporaryDirectory.appending(path: "FoundryAssets-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit { try? FileManager.default.removeItem(at: root) }

    func back(_ data: Data) -> Data {
        guard data.count >= 256 * 1_024 else { return data }
        let url = root.appending(path: UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            let mapped = try Data(contentsOf: url, options: .alwaysMapped)
            // The mapping retains its inode until the final Data reference dies.
            // Unlink now so deleted assets and crashed sessions leave no files.
            try? FileManager.default.removeItem(at: url)
            return mapped
        } catch {
            try? FileManager.default.removeItem(at: url)
            return data
        }
    }
}

final class FoundryDocument: ReferenceFileDocument {
    typealias Snapshot = FoundryDocumentSnapshot

    nonisolated static let readableContentTypes: [UTType] = [.foundryProject]

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let storage: Mutex<FoundryDocumentSnapshot>
    @MainActor private(set) var mutationEvent = ProjectMutationEvent(revision: 0, impact: .page)
    @MainActor private var cachedAssetContentsRevision: UInt64?
    @MainActor private var cachedAssetContents: [UUID: ProjectAssetContent] = [:]
    @MainActor private(set) var assetContentsBuildCount = 0

    @MainActor
    var site: Site {
        get { storage.withLock { $0.site } }
        set {
            applySite(newValue, impact: .page)
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
        var site = try decodeProject(from: projectData)
        let assetWrappers = wrappers["assets"]?.fileWrappers ?? [:]
        var data = Dictionary(uniqueKeysWithValues: (site.assets + site.webIconAssets + site.siteLogoAssets).compactMap { asset in
            assetWrappers[asset.storageFilename]?.regularFileContents.map { (asset.id, $0) }
        })
        if let sourceID = site.favicon.foundryAssetID,
           !site.webIconAssets.contains(where: { $0.id == sourceID }),
           let sourceAsset = (site.assets + site.webIconAssets).first(where: { $0.id == sourceID }),
           let sourceData = data[sourceID] {
            let oldManagedIDs = site.webIconAssets.map(\.id)
            let records = managedWebIconRecords(sourceAsset: sourceAsset, sourceData: sourceData)
            oldManagedIDs.forEach { data[$0] = nil }
            site.webIconAssets = records.map(\.asset)
            site.favicon = records.first?.asset.reference ?? ""
            records.forEach { data[$0.asset.id] = $0.data }
        }
        if let sourceID = site.logo.foundryAssetID,
           !site.siteLogoAssets.contains(where: { $0.id == sourceID }),
           let sourceAsset = (site.assets + site.webIconAssets + site.siteLogoAssets)
            .first(where: { $0.id == sourceID }),
           let sourceData = data[sourceID] {
            let oldManagedIDs = site.siteLogoAssets.map(\.id)
            let record = managedSiteLogoRecord(sourceAsset: sourceAsset, sourceData: sourceData)
            oldManagedIDs.forEach { data[$0] = nil }
            site.siteLogoAssets = [record.asset]
            site.logo = record.asset.reference
            data[record.asset.id] = record.data
        }
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
        let assets = Dictionary(uniqueKeysWithValues: (snapshot.site.assets + snapshot.site.webIconAssets + snapshot.site.siteLogoAssets).compactMap { asset in
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
        actionName: String,
        impact: ProjectMutationImpact = .page
    ) {
        guard newSite != site else {
            return
        }
        let previousSite = site
        undoManager?.registerUndo(withTarget: self) { document in
            document.replaceSite(
                with: previousSite,
                undoManager: undoManager,
                actionName: actionName,
                impact: impact
            )
        }
        undoManager?.setActionName(actionName)
        applySite(newSite, impact: impact)
    }

    @MainActor
    var assetContents: [UUID: ProjectAssetContent] {
        let snapshot = storage.withLock { $0 }
        guard cachedAssetContentsRevision != snapshot.assetRevision else {
            return cachedAssetContents
        }
        let contents = Dictionary(uniqueKeysWithValues: (snapshot.site.assets + snapshot.site.webIconAssets + snapshot.site.siteLogoAssets).compactMap { asset in
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
        cachedAssetContents = contents
        cachedAssetContentsRevision = snapshot.assetRevision
        assetContentsBuildCount += 1
        return contents
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
        let processed = PartImageProcessor.canonicalize(data: data, filename: filename, mimeType: mediaType)
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
        var destination = placement
        if ["ttf", "otf", "woff", "woff2"].contains((asset.filename as NSString).pathExtension.lowercased()) {
            let existingFolder = next.site.assetLibrary.compactMap { node -> ProjectAssetFolder? in
                guard case .folder(let folder) = node,
                      folder.name.caseInsensitiveCompare("Fonts") == .orderedSame else { return nil }
                return folder
            }.first
            let folder = existingFolder ?? ProjectAssetFolder(name: "Fonts")
            if existingFolder == nil {
                next.site.assetLibrary.append(.folder(folder))
            }
            destination = .inside(folderID: folder.id)
        }
        guard next.site.assetLibrary.insert(.asset(asset), at: destination) else { return asset.id }
        next.insertAssetData(processed.data, id: asset.id, digest: digest)
        replaceContents(with: next, undoManager: undoManager, actionName: "Import Asset")
        return asset.id
    }

    @MainActor
    func setFaviconSource(
        _ source: ProjectAssetContent?,
        undoManager: UndoManager?
    ) {
        var next = storage.withLock { $0 }
        if let sourceID = source?.asset.id,
           next.site.favicon.foundryAssetID == sourceID,
           next.site.webIconAssets.contains(where: { $0.id == sourceID }) {
            return
        }
        guard source != nil || !next.site.favicon.isEmpty || !next.site.webIconAssets.isEmpty else { return }
        next.site.webIconAssets.forEach { next.removeAssetData(id: $0.id) }
        let records = source.map {
            Self.managedWebIconRecords(sourceAsset: $0.asset, sourceData: $0.data)
        } ?? []
        next.site.favicon = records.first?.asset.reference ?? ""
        next.site.webIconAssets = records.map(\.asset)
        for record in records {
            next.insertAssetData(
                record.data,
                id: record.asset.id,
                digest: FoundryDocumentSnapshot.digest(for: record.data)
            )
        }
        replaceContents(with: next, undoManager: undoManager, actionName: "Set Site Icon")
    }

    @MainActor
    func setSiteLogoSource(
        _ source: ProjectAssetContent?,
        undoManager: UndoManager?
    ) {
        var next = storage.withLock { $0 }
        if let sourceID = source?.asset.id,
           next.site.logo.foundryAssetID == sourceID,
           next.site.siteLogoAssets.contains(where: { $0.id == sourceID }) {
            return
        }
        guard source != nil || !next.site.logo.isEmpty || !next.site.siteLogoAssets.isEmpty else { return }
        next.site.siteLogoAssets.forEach { next.removeAssetData(id: $0.id) }
        let record = source.map {
            Self.managedSiteLogoRecord(sourceAsset: $0.asset, sourceData: $0.data)
        }
        next.site.logo = record?.asset.reference ?? ""
        next.site.siteLogoAssets = record.map { [$0.asset] } ?? []
        if let record {
            next.insertAssetData(
                record.data,
                id: record.asset.id,
                digest: FoundryDocumentSnapshot.digest(for: record.data)
            )
        }
        replaceContents(with: next, undoManager: undoManager, actionName: "Set Site Logo")
    }

    @MainActor
    func createAssetFolder(named name: String, at placement: AssetPlacement = .end, undoManager: UndoManager?) -> UUID {
        let folder = ProjectAssetFolder(name: name)
        var nextSite = site
        guard nextSite.assetLibrary.insert(.folder(folder), at: placement) else { return folder.id }
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "New Asset Folder", impact: .assets)
        return folder.id
    }

    @MainActor
    func renameAssetFolder(id: UUID, name: String, undoManager: UndoManager?) {
        var nextSite = site
        guard nextSite.assetLibrary.renameFolder(id: id, to: name) else { return }
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "Rename Asset Folder", impact: .assets)
    }

    @MainActor
    func renameAsset(id: UUID, filename: String, undoManager: UndoManager?) {
        let safeFilename = (filename as NSString).lastPathComponent
        guard !safeFilename.isEmpty else { return }
        var nextSite = site
        guard nextSite.assetLibrary.renameAsset(id: id, to: safeFilename) else { return }
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "Rename Asset", impact: .assets)
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
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "Move Asset Item", impact: .assets)
        return true
    }

    @MainActor
    func moveAssetNodeToResources(id: UUID, to placement: AssetPlacement, undoManager: UndoManager?) -> Bool {
        var nextSite = site
        guard nextSite.assetLibrary.move(id: id, to: placement) else { return false }
        _ = nextSite.assetLibrary.clearExportDirectory(forAssetID: id)
        replaceSite(with: nextSite, undoManager: undoManager, actionName: "Move Asset to Resources", impact: .assets)
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
        advanceMutationEvent(.assets)
        objectWillChange.send()
        storage.withLock {
            var replacement = newSnapshot
            replacement.assetRevision = $0.assetRevision &+ 1
            $0 = replacement
        }
    }

    @MainActor
    private func applySite(_ newSite: Site, impact: ProjectMutationImpact) {
        advanceMutationEvent(impact)
        objectWillChange.send()
        storage.withLock {
            if $0.site.assets != newSite.assets {
                $0.assetRevision &+= 1
            }
            $0.site = newSite
        }
    }

    @MainActor
    private func advanceMutationEvent(_ impact: ProjectMutationImpact) {
        mutationEvent = ProjectMutationEvent(
            revision: mutationEvent.revision &+ 1,
            impact: impact
        )
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

    nonisolated private static func generatedWebIconRecords(
        from files: [SiteExportFile]
    ) -> [(asset: ProjectAsset, data: Data)] {
        files.map { file in
            let filename = URL(filePath: file.path).lastPathComponent
            let mediaType = filename.hasSuffix(".ico") ? "image/x-icon" : "image/png"
            return (
                ProjectAsset(
                    filename: filename,
                    mediaType: mediaType,
                    byteCount: file.data.count
                ),
                file.data
            )
        }
    }

    nonisolated private static func managedWebIconRecords(
        sourceAsset: ProjectAsset,
        sourceData: Data
    ) -> [(asset: ProjectAsset, data: Data)] {
        let sourceExtension = (sourceAsset.filename as NSString).pathExtension.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        let source = ProjectAsset(
            filename: "web-icon-source." + (sourceExtension.isEmpty ? "png" : sourceExtension),
            mediaType: sourceAsset.mediaType,
            byteCount: sourceData.count,
            pixelWidth: sourceAsset.pixelWidth,
            pixelHeight: sourceAsset.pixelHeight
        )
        return [(source, sourceData)]
            + generatedWebIconRecords(from: WebIconGenerator.generateFiles(from: sourceData))
    }

    nonisolated private static func managedSiteLogoRecord(
        sourceAsset: ProjectAsset,
        sourceData: Data
    ) -> (asset: ProjectAsset, data: Data) {
        let sourceExtension = (sourceAsset.filename as NSString).pathExtension.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return (
            ProjectAsset(
                filename: "site-logo-source." + (sourceExtension.isEmpty ? "png" : sourceExtension),
                mediaType: sourceAsset.mediaType,
                byteCount: sourceData.count,
                pixelWidth: sourceAsset.pixelWidth,
                pixelHeight: sourceAsset.pixelHeight
            ),
            sourceData
        )
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
