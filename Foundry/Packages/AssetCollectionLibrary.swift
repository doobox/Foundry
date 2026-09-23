import Foundation
import UniformTypeIdentifiers

/// One file inside a shipped asset collection, described without loading its
/// bytes — the browser lists thousands of files cheaply and bytes are read
/// only at import.
nonisolated struct AssetCollectionFile: Identifiable, Equatable, Sendable {
    let url: URL
    let filename: String
    let mediaType: String
    let byteCount: Int

    var id: String { url.path }

    var isImage: Bool { mediaType.hasPrefix("image/") }
    var isVideo: Bool { mediaType.hasPrefix("video/") }
    var isFont: Bool {
        mediaType.hasPrefix("font/")
            || ["ttf", "otf", "woff", "woff2", "ttc"].contains((filename as NSString).pathExtension.lowercased())
    }

    /// The row symbol for browsing: what kind of file this is at a glance.
    var systemImageName: String {
        if isImage { return "photo" }
        if isVideo { return "film" }
        if isFont { return "textformat" }
        return "doc"
    }
}

/// A folder inside a collection's Resources directory — organization only,
/// with no identity or licence of its own; those belong to the collection.
nonisolated struct AssetCollectionFolder: Equatable, Sendable {
    let url: URL
    let name: String
    let nodes: [AssetCollectionNode]

    var id: String { url.path }

    var files: [AssetCollectionFile] { AssetCollectionNode.flattenedFiles(nodes) }
}

/// One entry in a collection's Resources tree.
nonisolated enum AssetCollectionNode: Identifiable, Equatable, Sendable {
    case file(AssetCollectionFile)
    case folder(AssetCollectionFolder)

    var id: String {
        switch self {
        case .file(let file): file.id
        case .folder(let folder): folder.id
        }
    }

    static func flattenedFiles(_ nodes: [AssetCollectionNode]) -> [AssetCollectionFile] {
        nodes.flatMap { node -> [AssetCollectionFile] in
            switch node {
            case .file(let file): [file]
            case .folder(let folder): flattenedFiles(folder.nodes)
            }
        }
    }
}

/// A curated collection of importable files shipped in a pack's `Assets`
/// directory: photos, icons, textures, fonts, video. A collection is just a
/// folder — hand-authorable in Finder. An optional `Info.plist` inside it
/// adds a display title, a stable id, and the licence shown before anything
/// imports.
nonisolated struct AssetCollection: Identifiable, Equatable, Sendable {
    /// The manifest id when one is declared; the folder path otherwise.
    let identifier: String
    /// The id declared in the manifest, nil for plain folders.
    let manifestID: String?
    let title: String
    let license: String?
    let licenseURL: URL?
    let attribution: String?
    let itemURL: URL
    /// The folder tree as authored on disk.
    let nodes: [AssetCollectionNode]
    /// Every file at any depth, for counts, search, and Add All.
    let files: [AssetCollectionFile]

    var id: String { identifier }

    var totalByteCount: Int { files.reduce(0) { $0 + $1.byteCount } }
}

nonisolated enum AssetCollectionStore {
    /// Reads one collection folder. The manifest is optional — a plain folder
    /// of files is a complete collection, titled by its name. A manifest that
    /// exists but cannot be parsed throws so installs can reject bad packs;
    /// browsing uses `entry(at:)` and skips instead.
    static func load(from itemURL: URL) throws -> AssetCollection {
        let manifestURL = itemURL.appending(path: "Info.plist")
        var manifest: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            manifest = parsed
        }
        let manifestID = (manifest["id"] as? String).flatMap { id in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let nodes = nodes(in: itemURL, excludingRootNames: ["Info.plist"])
        return AssetCollection(
            identifier: manifestID ?? itemURL.standardizedFileURL.path,
            manifestID: manifestID,
            title: manifest["title"] as? String ?? itemURL.lastPathComponent,
            license: manifest["license"] as? String,
            licenseURL: (manifest["licenseURL"] as? String).flatMap(URL.init(string:)),
            attribution: manifest["attribution"] as? String,
            itemURL: itemURL.standardizedFileURL,
            nodes: nodes,
            files: AssetCollectionNode.flattenedFiles(nodes)
                .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        )
    }

    static func entry(at itemURL: URL) -> AssetCollection? {
        try? load(from: itemURL)
    }

    static func writeManifest(
        identifier: String?,
        title: String,
        license: String?,
        licenseURL: URL?,
        attribution: String?,
        to itemURL: URL
    ) throws {
        var manifest: [String: Any] = ["title": title]
        if let identifier, !identifier.isEmpty { manifest["id"] = identifier }
        if let license, !license.isEmpty { manifest["license"] = license }
        if let licenseURL { manifest["licenseURL"] = licenseURL.absoluteString }
        if let attribution, !attribution.isEmpty { manifest["attribution"] = attribution }
        let data = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        try data.write(to: itemURL.appending(path: "Info.plist"), options: .atomic)
    }

    /// One directory level of the collection tree, recursing into subfolders:
    /// folders first, then files, each in stable name order. Hidden files
    /// never ship; empty folders are kept so freshly created ones show. The
    /// root level excludes the optional manifest.
    private static func nodes(
        in directoryURL: URL,
        excludingRootNames: Set<String> = []
    ) -> [AssetCollectionNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var folders: [AssetCollectionFolder] = []
        var files: [AssetCollectionFile] = []
        for url in contents {
            guard !excludingRootNames.contains(url.lastPathComponent) else { continue }
            guard let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
            ) else { continue }
            if values.isDirectory == true {
                folders.append(AssetCollectionFolder(
                    url: url.standardizedFileURL,
                    name: url.lastPathComponent,
                    nodes: nodes(in: url)
                ))
            } else if values.isRegularFile == true {
                let mediaType = UTType(filenameExtension: url.pathExtension.lowercased())?
                    .preferredMIMEType ?? "application/octet-stream"
                files.append(AssetCollectionFile(
                    url: url.standardizedFileURL,
                    filename: url.lastPathComponent,
                    mediaType: mediaType,
                    byteCount: values.fileSize ?? 0
                ))
            }
        }
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        return folders.map { .folder($0) } + files.map { .file($0) }
    }
}

/// One pack's worth of asset collections, for grouped presentation. Editable
/// sources (the personal pack and dev packs) accept curation; installed
/// packs are read-only.
nonisolated struct AssetCollectionSource: Identifiable, Sendable {
    let rootURL: URL?
    let title: String
    let isEditable: Bool
    /// The user's own My Library pack — shown on the Library tab; every
    /// other dev pack belongs to the Dev tab.
    let isPersonal: Bool
    let collections: [AssetCollection]

    var id: String { rootURL?.standardizedFileURL.path ?? title }
}

/// Asset collections resolved from every installed pack, open dev pack, and
/// the built-in pack. Collections are always read-only sources for projects:
/// importing copies files into the document's own asset library. Curation —
/// creating collections, adding and removing files — happens here for
/// editable packs, with My Library as the default home.
@MainActor
@Observable
final class AssetCollectionLibrary {
    static let shared = AssetCollectionLibrary()

    private(set) var sources: [AssetCollectionSource] = []
    private var externalDevelopmentPackURLs: Set<URL> = []
    /// Injected in tests: fixed pack roots instead of the installed catalog.
    private let fixedRootURLs: [URL]?

    init(fixedRootURLs: [URL]? = nil) {
        self.fixedRootURLs = fixedRootURLs
        refresh()
    }

    var isEmpty: Bool { sources.allSatisfy(\.collections.isEmpty) }

    /// Sources with anything to import — what project-facing browsers show.
    var importableSources: [AssetCollectionSource] {
        sources.filter { !$0.collections.isEmpty }
    }

    func openDevelopmentPack(at url: URL) {
        externalDevelopmentPackURLs.insert(url.standardizedFileURL)
        refresh()
    }

    func refresh() {
        var roots: [URL] = []
        var personalRootURL: URL?
        if let fixedRootURLs {
            roots = fixedRootURLs.map(\.standardizedFileURL)
            // In tests the first editable fixture stands in for My Library.
            personalRootURL = roots.first { $0.pathExtension.lowercased() == "foundrydevpack" }
        } else {
            if let personal = try? FoundryPackLoader.personalDevelopmentPackURL() {
                personalRootURL = personal.standardizedFileURL
                roots.append(personal.standardizedFileURL)
            }
            let installed = (try? FoundryPackLoader.installedPacksURL())
                .map { FoundryPackLoader.packURLs(in: $0) } ?? []
            roots += externalDevelopmentPackURLs
                .subtracting(roots)
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            roots += installed.filter { !roots.contains($0.standardizedFileURL) }
            if let builtIn = FoundryPackLoader.builtInPackURL() {
                roots.append(builtIn)
            }
        }
        var seenCollectionIDs: Set<String> = []
        sources = roots.compactMap { rootURL in
            guard let pack = try? FoundryPackLoader.load(from: rootURL) else { return nil }
            let isEditable = rootURL.pathExtension.lowercased() == "foundrydevpack"
            let collections = pack.assetCollectionURLs
                .compactMap(AssetCollectionStore.entry(at:))
                .filter { seenCollectionIDs.insert($0.identifier).inserted }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            // A read-only pack without collections would be a dead group;
            // editable sources stay listed as curation targets.
            guard isEditable || !collections.isEmpty else { return nil }
            return AssetCollectionSource(
                rootURL: rootURL.standardizedFileURL,
                title: pack.metadata.title ?? rootURL.deletingPathExtension().lastPathComponent,
                isEditable: isEditable,
                isPersonal: rootURL.standardizedFileURL == personalRootURL,
                collections: collections
            )
        }
    }

    // MARK: Lookup

    func collection(withID id: String) -> AssetCollection? {
        sources.lazy.flatMap(\.collections).first { $0.identifier == id }
    }

    func source(containing id: String) -> AssetCollectionSource? {
        sources.first { $0.collections.contains { $0.identifier == id } }
    }

    func isEditable(collectionID: String) -> Bool {
        source(containing: collectionID)?.isEditable ?? false
    }

    /// Locates a folder anywhere in the loaded sources by its path id.
    func folderContext(withID folderID: String) -> (folder: AssetCollectionFolder, collection: AssetCollection)? {
        for source in sources {
            for collection in source.collections {
                if let folder = Self.findFolder(folderID, in: collection.nodes) {
                    return (folder, collection)
                }
            }
        }
        return nil
    }

    private static func findFolder(_ id: String, in nodes: [AssetCollectionNode]) -> AssetCollectionFolder? {
        for case .folder(let folder) in nodes {
            if folder.id == id { return folder }
            if let nested = findFolder(id, in: folder.nodes) { return nested }
        }
        return nil
    }

    // MARK: Curation

    /// Creates an empty collection — just a named folder, exactly what a
    /// hand-author would make in Finder. Without a destination it joins the
    /// personal pack — My Library.
    @discardableResult
    func createCollection(named name: String, inPackRoot rootURL: URL? = nil) -> AssetCollection? {
        let targetRoot: URL?
        if let rootURL {
            targetRoot = sources.first {
                $0.rootURL?.standardizedFileURL == rootURL.standardizedFileURL && $0.isEditable
            }?.rootURL
        } else {
            targetRoot = sources.first(where: \.isEditable)?.rootURL
                ?? (try? FoundryPackLoader.personalDevelopmentPackURL())
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let targetRoot, !trimmed.isEmpty,
              let itemURL = preparedDestination(for: trimmed, inPackRoot: targetRoot),
              (try? FileManager.default.createDirectory(
                  at: itemURL,
                  withIntermediateDirectories: true
              )) != nil else { return nil }
        refresh()
        return AssetCollectionStore.entry(at: itemURL)
    }

    /// Renames by writing the manifest title — the folder keeps its name, so
    /// path-based identity is stable. Hand-authors rename folders in Finder.
    func renameCollection(id: String, to name: String) {
        updateManifest(id: id) { collection in
            try AssetCollectionStore.writeManifest(
                identifier: collection.manifestID,
                title: name,
                license: collection.license,
                licenseURL: collection.licenseURL,
                attribution: collection.attribution,
                to: collection.itemURL
            )
        }
    }

    func setLicence(id: String, license: String?, licenseURL: URL?, attribution: String?) {
        updateManifest(id: id) { collection in
            try AssetCollectionStore.writeManifest(
                identifier: collection.manifestID,
                title: collection.title,
                license: license,
                licenseURL: licenseURL,
                attribution: attribution,
                to: collection.itemURL
            )
        }
    }

    func deleteCollection(id: String) {
        guard let collection = collection(withID: id), isEditable(collectionID: id) else { return }
        try? FileManager.default.removeItem(at: collection.itemURL)
        refresh()
    }

    /// Moves a collection between editable packs; its identifier and licence
    /// travel with it.
    @discardableResult
    func moveCollection(id: String, toPackRoot rootURL: URL) -> Bool {
        guard let collection = collection(withID: id),
              isEditable(collectionID: id),
              let destinationRoot = editablePackRoot(at: rootURL),
              source(containing: id)?.rootURL?.standardizedFileURL != destinationRoot.standardizedFileURL,
              let destination = preparedDestination(
                  for: collection.itemURL.lastPathComponent,
                  inPackRoot: destinationRoot
              ) else { return false }
        guard (try? FileManager.default.moveItem(at: collection.itemURL, to: destination)) != nil else {
            return false
        }
        refresh()
        return true
    }

    /// Copies a collection — the way content leaves a read-only pack — into
    /// an editable pack under a fresh identity, keeping title and licence.
    @discardableResult
    func copyCollection(id: String, toPackRoot rootURL: URL) -> Bool {
        guard let collection = collection(withID: id),
              let destinationRoot = editablePackRoot(at: rootURL),
              let destination = preparedDestination(
                  for: collection.itemURL.lastPathComponent,
                  inPackRoot: destinationRoot
              ) else { return false }
        do {
            try FileManager.default.copyItem(at: collection.itemURL, to: destination)
            // A declared id must not travel — two live collections with one
            // id would collide; the copy identifies by its own path.
            if collection.manifestID != nil {
                try AssetCollectionStore.writeManifest(
                    identifier: nil,
                    title: collection.title,
                    license: collection.license,
                    licenseURL: collection.licenseURL,
                    attribution: collection.attribution,
                    to: destination
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return false
        }
        refresh()
        return true
    }

    private func editablePackRoot(at rootURL: URL) -> URL? {
        sources.first {
            $0.isEditable && $0.rootURL?.standardizedFileURL == rootURL.standardizedFileURL
        }?.rootURL
    }

    /// The destination item directory inside a pack's Assets kind directory,
    /// with the kind directory created and the name uniqued on collision.
    private func preparedDestination(for itemName: String, inPackRoot rootURL: URL) -> URL? {
        let kindURL = rootURL.appending(
            path: FoundryPackItemKind.assetCollection.rawValue,
            directoryHint: .isDirectory
        )
        guard (try? FileManager.default.createDirectory(
            at: kindURL,
            withIntermediateDirectories: true
        )) != nil else { return nil }
        var candidate = kindURL.appending(path: itemName, directoryHint: .isDirectory)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = kindURL.appending(path: "\(itemName) \(counter)", directoryHint: .isDirectory)
            counter += 1
        }
        return candidate
    }

    /// Copies files into the collection — at its Resources root or inside one
    /// of its folders — uniquing filenames on collision. Returns how many
    /// copied.
    @discardableResult
    func addFiles(at urls: [URL], to collectionID: String, insideFolderID folderID: String? = nil) -> Int {
        guard let destinationURL = writableDirectory(in: collectionID, folderID: folderID) else { return 0 }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        var copied = 0
        for url in urls {
            // A file named Info.plist at the collection root would become
            // the manifest; refuse rather than corrupt the collection.
            if folderID == nil, url.lastPathComponent == "Info.plist" { continue }
            let destination = uniqueDestination(for: url.lastPathComponent, in: destinationURL)
            if (try? fileManager.copyItem(at: url, to: destination)) != nil {
                copied += 1
            }
        }
        if copied > 0 { refresh() }
        return copied
    }

    /// Creates a folder inside a collection — at its Resources root or nested
    /// in another of its folders.
    @discardableResult
    func createFolder(named name: String, in collectionID: String, insideFolderID folderID: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parentURL = writableDirectory(in: collectionID, folderID: folderID) else { return false }
        let destination = uniqueDestination(for: trimmed, in: parentURL)
        guard (try? FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )) != nil else { return false }
        refresh()
        return true
    }

    /// Renames a folder on disk. Returns the folder's new id — its path
    /// changes — so selection can follow, or nil when refused.
    @discardableResult
    func renameFolder(id folderID: String, to name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let context = folderContext(withID: folderID),
              isEditable(collectionID: context.collection.identifier),
              !trimmed.isEmpty, trimmed != context.folder.name else { return nil }
        let destination = context.folder.url.deletingLastPathComponent()
            .appending(path: trimmed, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path),
              (try? FileManager.default.moveItem(at: context.folder.url, to: destination)) != nil else {
            return nil
        }
        refresh()
        return destination.standardizedFileURL.path
    }

    /// Deletes a folder and everything inside it.
    func deleteFolder(id folderID: String) {
        guard let context = folderContext(withID: folderID),
              isEditable(collectionID: context.collection.identifier) else { return }
        try? FileManager.default.removeItem(at: context.folder.url)
        refresh()
    }

    /// Moves files already inside a collection into one of its folders, or
    /// back to its Resources root when `folderID` is nil.
    func moveFiles(_ fileIDs: Set<String>, in collectionID: String, toFolderID folderID: String?) {
        guard let collection = collection(withID: collectionID),
              let destinationURL = writableDirectory(in: collectionID, folderID: folderID) else { return }
        var moved = false
        for file in collection.files where fileIDs.contains(file.id) {
            if folderID == nil, file.filename == "Info.plist" { continue }
            guard file.url.deletingLastPathComponent().standardizedFileURL
                    != destinationURL.standardizedFileURL else { continue }
            let destination = uniqueDestination(for: file.filename, in: destinationURL)
            if (try? FileManager.default.moveItem(at: file.url, to: destination)) != nil {
                moved = true
            }
        }
        if moved { refresh() }
    }

    /// The on-disk directory a curation write lands in: the collection's own
    /// folder, or one of its subfolders. Nil when the collection is read-only
    /// or the folder belongs elsewhere.
    private func writableDirectory(in collectionID: String, folderID: String?) -> URL? {
        guard let collection = collection(withID: collectionID), isEditable(collectionID: collectionID) else {
            return nil
        }
        guard let folderID else { return collection.itemURL }
        guard let context = folderContext(withID: folderID),
              context.collection.identifier == collectionID else { return nil }
        return context.folder.url
    }

    /// Writes in-memory bytes into the collection — the "send a project
    /// asset to my library" gesture.
    @discardableResult
    func addFile(data: Data, filename: String, to collectionID: String) -> Bool {
        guard let destinationURL = writableDirectory(in: collectionID, folderID: nil) else { return false }
        let destination = uniqueDestination(for: filename, in: destinationURL)
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return false }
        refresh()
        return true
    }

    func removeFiles(_ fileIDs: Set<String>, from collectionID: String) {
        guard let collection = collection(withID: collectionID), isEditable(collectionID: collectionID) else {
            return
        }
        for file in collection.files where fileIDs.contains(file.id) {
            try? FileManager.default.removeItem(at: file.url)
        }
        refresh()
    }

    private func updateManifest(id: String, _ write: (AssetCollection) throws -> Void) {
        guard let collection = collection(withID: id), isEditable(collectionID: id) else { return }
        try? write(collection)
        refresh()
    }

    private func uniqueDestination(for filename: String, in directoryURL: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directoryURL.appending(path: filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directoryURL.appending(path: name)
            counter += 1
        }
        return candidate
    }

    // MARK: Importing

    /// Imports the chosen files into the document's asset library, reusing
    /// identical content already in the project. Returns the asset ids in
    /// import order; unreadable files are skipped.
    func importFiles(
        _ files: [AssetCollectionFile],
        into document: FoundryDocument,
        undoManager: UndoManager?
    ) -> [UUID] {
        files.compactMap { file in
            guard let data = try? Data(contentsOf: file.url) else { return nil }
            return document.importAsset(
                data: data,
                filename: file.filename,
                mediaType: file.mediaType,
                reuseIdenticalContent: true,
                undoManager: undoManager
            )
        }
    }
}
