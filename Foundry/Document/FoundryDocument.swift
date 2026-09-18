import Combine
import CryptoKit
import Darwin
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

nonisolated struct FoundryDocumentSnapshot: Sendable {
    var site: Site
    var assetRevision: UInt64 = 0
    let byteStore: AssetByteStore
    private(set) var assetDigestByID: [UUID: String]
    private(set) var assetIDsByDigest: [String: Set<UUID>]

    init(site: Site, byteStore: AssetByteStore = AssetByteStore(), assetRevision: UInt64 = 0) {
        self.site = site
        self.byteStore = byteStore
        self.assetRevision = assetRevision

        // Every asset already carries its own digest as persisted metadata, so
        // building this index never needs to hash bytes at document open.
        var digestByID: [UUID: String] = [:]
        var idsByDigest: [String: Set<UUID>] = [:]
        for asset in site.assets + site.webIconAssets + site.siteLogoAssets {
            digestByID[asset.id] = asset.contentDigest
            idsByDigest[asset.contentDigest, default: []].insert(asset.id)
        }
        assetDigestByID = digestByID
        assetIDsByDigest = idsByDigest
    }

    /// A persisted digest is the sole correctness signal for dedup; there is
    /// no legacy, digest-less data it needs to fall back for.
    func matchingAssetID(for digest: String) -> UUID? {
        assetIDsByDigest[digest]?.first
    }

    mutating func insertAssetIndex(id: UUID, digest: String) {
        assetDigestByID[id] = digest
        assetIDsByDigest[digest, default: []].insert(id)
    }

    mutating func removeAssetIndex(id: UUID) {
        guard let digest = assetDigestByID.removeValue(forKey: id) else { return }
        assetIDsByDigest[digest]?.remove(id)
        if assetIDsByDigest[digest]?.isEmpty == true {
            assetIDsByDigest.removeValue(forKey: digest)
        }
    }

    static func digest(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A directory of on-disk files that need a stable URL: bytes imported this
/// session but not yet proven saved, and bytes pinned for undo after a
/// delete. Unlike a throwaway temp copy, spool files are not unlinked on
/// creation — callers need the URL to remain valid for as long as the entry
/// exists.
nonisolated final class AssetSpool: @unchecked Sendable {
    private let root = FileManager.default.temporaryDirectory.appending(path: "FoundryAssetSpool-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ data: Data) -> URL? {
        let url = root.appending(path: UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// A copy-on-write clone when possible; a real copy otherwise. Either
    /// way the result is an independent file the source can be deleted
    /// out from under.
    func clone(from source: URL) -> URL? {
        let url = root.appending(path: UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        if clonefile(source.path, url.path, 0) == 0 {
            return url
        }
        return (try? FileManager.default.copyItem(at: source, to: url)) != nil ? url : nil
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Keeps a deleted asset's bytes resolvable for as long as any undo entry
/// referencing this token is reachable. Releasing it (on dealloc) unpins the
/// spool copy once nothing else still holds a pin for the same asset.
nonisolated final class AssetBytePin: Sendable {
    private let id: UUID
    private let store: AssetByteStore

    fileprivate init(id: UUID, store: AssetByteStore) {
        self.id = id
        self.store = store
    }

    deinit { store.releasePin(for: id) }
}

/// The shared owner of resolved asset bytes for one document's lifetime.
/// Resolution order: the bounded cache, the real package file on disk, a
/// pending import staged this session, an undo pin for a deleted asset,
/// then — only before a package URL exists — a synthetic `FileWrapper`
/// fallback used while opening a document and in tests.
nonisolated final class AssetByteStore: @unchecked Sendable {
    private struct State {
        var packageURL: URL?
        var fallbackWrapper: FileWrapper?
        var pending: [UUID: URL] = [:]
        var pinURLs: [UUID: URL] = [:]
        var pinRefCounts: [UUID: Int] = [:]
    }

    private let state = Mutex(State())
    private let cache = NSCache<NSString, NSData>()
    private let spool = AssetSpool()

    init() {
        cache.totalCostLimit = 192 * 1_024 * 1_024
        cache.countLimit = 64
    }

    /// Adopted once the document's on-disk package URL becomes known; a
    /// brand-new, unsaved document has none yet.
    func adoptPackageURL(_ url: URL?) {
        state.withLock { $0.packageURL = url }
    }

    /// Used only before a package URL exists: reading a just-opened document
    /// straight from its `FileWrapper`, or a synthetic wrapper in tests.
    func adoptFallbackWrapper(_ wrapper: FileWrapper?) {
        state.withLock { $0.fallbackWrapper = wrapper }
    }

    /// Stages bytes imported this session so they resolve before the next
    /// save proves them written into the package.
    func stagePendingImport(id: UUID, data: Data) {
        guard let url = spool.write(data) else { return }
        state.withLock { $0.pending[id] = url }
        cache.setObject(data as NSData, forKey: cacheKey(id), cost: data.count)
    }

    func hasContent(for asset: ProjectAsset) -> Bool {
        let id = asset.id
        if cache.object(forKey: cacheKey(id)) != nil { return true }
        let (packageURL, hasPending, hasPin) = state.withLock {
            ($0.packageURL, $0.pending[id] != nil, $0.pinURLs[id] != nil)
        }
        if let packageURL, FileManager.default.fileExists(atPath: packagePath(packageURL, asset: asset).path) {
            return true
        }
        if hasPending || hasPin { return true }
        return state.withLock { $0.fallbackWrapper?.fileWrappers?[asset.storageFilename]?.isRegularFile } ?? false
    }

    func resolve(_ asset: ProjectAsset) -> Data? {
        let id = asset.id
        let key = cacheKey(id)
        if let cached = cache.object(forKey: key) { return cached as Data }
        let (packageURL, pendingURL, pinnedURL) = state.withLock {
            ($0.packageURL, $0.pending[id], $0.pinURLs[id])
        }
        if let packageURL, let data = try? Data(contentsOf: packagePath(packageURL, asset: asset), options: .mappedIfSafe) {
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            return data
        }
        if let pendingURL, let data = try? Data(contentsOf: pendingURL, options: .mappedIfSafe) {
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            return data
        }
        if let pinnedURL, let data = try? Data(contentsOf: pinnedURL, options: .mappedIfSafe) {
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            return data
        }
        if let data = state.withLock({ $0.fallbackWrapper?.fileWrappers?[asset.storageFilename]?.regularFileContents }) {
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            return data
        }
        return nil
    }

    /// Pins a deleted asset's bytes so undo can restore them, for as long as
    /// the returned token is reachable. Cheap when the bytes already live in
    /// the saved package (a `clonefile` copy); otherwise resolves once and
    /// spools the result.
    func pinForUndo(_ asset: ProjectAsset) -> AssetBytePin? {
        let id = asset.id
        let alreadyPinned = state.withLock { state in
            if state.pinRefCounts[id] != nil {
                state.pinRefCounts[id, default: 0] += 1
                return true
            }
            return false
        }
        if alreadyPinned { return AssetBytePin(id: id, store: self) }

        let packageURL = state.withLock { $0.packageURL }
        let spooledURL = packageURL.flatMap { spool.clone(from: packagePath($0, asset: asset)) }
            ?? resolve(asset).flatMap { spool.write($0) }
        guard let spooledURL else { return nil }
        state.withLock { state in
            state.pinURLs[id] = spooledURL
            state.pinRefCounts[id, default: 0] += 1
        }
        return AssetBytePin(id: id, store: self)
    }

    fileprivate func releasePin(for id: UUID) {
        state.withLock { state in
            guard let count = state.pinRefCounts[id] else { return }
            if count <= 1 {
                state.pinRefCounts.removeValue(forKey: id)
                if let url = state.pinURLs.removeValue(forKey: id) {
                    spool.remove(url)
                }
            } else {
                state.pinRefCounts[id] = count - 1
            }
        }
    }

    private func packagePath(_ packageURL: URL, asset: ProjectAsset) -> URL {
        packageURL.appending(path: "assets/\(asset.storageFilename)")
    }

    private func cacheKey(_ id: UUID) -> NSString {
        id.uuidString as NSString
    }
}

final class FoundryDocument: ReferenceFileDocument {
    typealias Snapshot = FoundryDocumentSnapshot

    nonisolated static let readableContentTypes: [UTType] = [.foundryProject]

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let storage: Mutex<FoundryDocumentSnapshot>
    @MainActor private(set) var mutationEvent = ProjectMutationEvent(revision: 0, impact: .page)
    @MainActor private var cachedAssetContentsRevision: UInt64?
    @MainActor private var cachedAssetContents: ProjectAssetContents = [:]
    @MainActor private(set) var assetContentsBuildCount = 0

    @MainActor
    var site: Site {
        get { storage.withLock { $0.site } }
        set {
            applySite(newValue, impact: .page)
        }
    }

    init(site: Site = .starter()) {
        storage = Mutex(.init(site: site))
    }

    required init(configuration: ReadConfiguration) throws {
        storage = Mutex(try Self.decodeSnapshot(from: configuration.file))
    }

    nonisolated static func decodeSnapshot(from file: FileWrapper) throws -> FoundryDocumentSnapshot {
        if file.isRegularFile, let data = file.regularFileContents {
            return .init(site: try decodeProject(from: data))
        }
        guard file.isDirectory,
              let wrappers = file.fileWrappers,
              let projectData = wrappers["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let site = try decodeProject(from: projectData)
        let byteStore = AssetByteStore()
        byteStore.adoptFallbackWrapper(wrappers["assets"])
        return .init(site: site, byteStore: byteStore)
    }

    nonisolated func snapshot(contentType: UTType) throws -> FoundryDocumentSnapshot {
        storage.withLock { $0 }
    }

    nonisolated func fileWrapper(
        snapshot: FoundryDocumentSnapshot,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let project = FileWrapper(regularFileWithContents: try Self.encoder.encode(snapshot.site))
        let existingAssetWrappers = configuration.existingFile?.fileWrappers?["assets"]?.fileWrappers ?? [:]
        var assets: [String: FileWrapper] = [:]
        for asset in snapshot.site.assets + snapshot.site.webIconAssets + snapshot.site.siteLogoAssets {
            // Reusing the existing child lets `FileWrapper` avoid rewriting
            // bytes that haven't changed; asset ids are never reused for
            // different content, so presence plus a size check is enough.
            if let existing = existingAssetWrappers[asset.storageFilename], existing.isRegularFile,
               (existing.fileAttributes[FileAttributeKey.size.rawValue] as? Int) == asset.byteCount {
                assets[asset.storageFilename] = existing
                continue
            }
            guard let data = snapshot.byteStore.resolve(asset) else { continue }
            assets[asset.storageFilename] = FileWrapper(regularFileWithContents: data)
        }
        return FileWrapper(directoryWithFileWrappers: [
            "project.json": project,
            "assets": FileWrapper(directoryWithFileWrappers: assets)
        ])
    }

    /// Adopted once SwiftUI's `DocumentGroup` reports the document's on-disk
    /// URL — nil for a brand-new, unsaved document.
    @MainActor
    func adoptPackageURL(_ url: URL?) {
        storage.withLock { $0.byteStore }.adoptPackageURL(url)
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
    var assetContents: ProjectAssetContents {
        let snapshot = storage.withLock { $0 }
        guard cachedAssetContentsRevision != snapshot.assetRevision else {
            return cachedAssetContents
        }
        let assetsByID = Dictionary(uniqueKeysWithValues: (snapshot.site.assets + snapshot.site.webIconAssets + snapshot.site.siteLogoAssets).map { ($0.id, $0) })
        let contents = ProjectAssetContents(store: snapshot.byteStore, assetsByID: assetsByID, revision: snapshot.assetRevision)
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
           let existingID = next.matchingAssetID(for: digest) {
            return existingID
        }
        let metadata = processed.metadata
        let asset = ProjectAsset(
            filename: metadata.filename,
            mediaType: metadata.mimeType,
            byteCount: processed.data.count,
            contentDigest: digest,
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
        next.insertAssetIndex(id: asset.id, digest: digest)
        next.byteStore.stagePendingImport(id: asset.id, data: processed.data)
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
        next.site.webIconAssets.forEach { next.removeAssetIndex(id: $0.id) }
        let records = source.map {
            Self.managedWebIconRecords(sourceAsset: $0.asset, sourceData: $0.data)
        } ?? []
        next.site.favicon = records.first?.asset.reference ?? ""
        next.site.webIconAssets = records.map(\.asset)
        for record in records {
            next.insertAssetIndex(id: record.asset.id, digest: record.asset.contentDigest)
            next.byteStore.stagePendingImport(id: record.asset.id, data: record.data)
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
        next.site.siteLogoAssets.forEach { next.removeAssetIndex(id: $0.id) }
        let record = source.map {
            Self.managedSiteLogoRecord(sourceAsset: $0.asset, sourceData: $0.data)
        }
        next.site.logo = record?.asset.reference ?? ""
        next.site.siteLogoAssets = record.map { [$0.asset] } ?? []
        if let record {
            next.insertAssetIndex(id: record.asset.id, digest: record.asset.contentDigest)
            next.byteStore.stagePendingImport(id: record.asset.id, data: record.data)
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
    func setVideoMetadata(id: UUID, result: VideoPosterGenerator.Result) {
        var nextSite = site
        guard nextSite.assetLibrary.setVideoMetadata(
            id: id,
            metadata: result.metadata,
            pixelWidth: result.pixelWidth,
            pixelHeight: result.pixelHeight
        ) else { return }
        replaceSite(with: nextSite, undoManager: nil, actionName: "Analyse Video", impact: .assets)
    }

    @MainActor
    func removeAssetFolder(id: UUID, undoManager: UndoManager?) {
        var next = storage.withLock { $0 }
        guard let node = next.site.assetLibrary.removeNode(id: id) else { return }
        for assetID in node.assetIDs { next.removeAssetIndex(id: assetID) }
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
        next.removeAssetIndex(id: id)
        replaceContents(with: next, undoManager: undoManager, actionName: "Delete Asset")
    }

    @MainActor
    private func replaceContents(
        with newSnapshot: FoundryDocumentSnapshot,
        undoManager: UndoManager?,
        actionName: String
    ) {
        let previous = storage.withLock { $0 }

        // Bytes for any asset the new snapshot no longer references must stay
        // resolvable for as long as undo can bring it back. Pin exactly those
        // (not the whole library) for the lifetime of the undo entry itself.
        let pins: [AssetBytePin] = undoManager == nil ? [] : (previous.site.assets + previous.site.webIconAssets + previous.site.siteLogoAssets)
            .filter { newSnapshot.assetDigestByID[$0.id] == nil }
            .compactMap { previous.byteStore.pinForUndo($0) }

        undoManager?.registerUndo(withTarget: self) { document in
            _ = pins
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
                    byteCount: file.data.count,
                    contentDigest: FoundryDocumentSnapshot.digest(for: file.data)
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
            contentDigest: FoundryDocumentSnapshot.digest(for: sourceData),
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
                contentDigest: FoundryDocumentSnapshot.digest(for: sourceData),
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
