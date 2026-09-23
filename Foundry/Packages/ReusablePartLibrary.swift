import Foundation

/// A template bundle in the app-wide library: the saved definition plus the
/// metadata of every project asset it embeds.
nonisolated struct ReusablePartLibraryEntry: Identifiable, Equatable, Sendable {
    let definition: ReusablePartDefinition
    let assets: [ProjectAsset]

    var id: UUID { definition.id }
    var name: String { definition.name }
}

/// The library's folder organization, stored beside the bundles so every
/// project (and every synced Mac) sees the same arrangement.
nonisolated struct TemplateLibraryFolder: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var children: [TemplateLibraryNode]

    init(id: UUID = UUID(), name: String, children: [TemplateLibraryNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

nonisolated indirect enum TemplateLibraryNode: Codable, Equatable, Identifiable, Sendable {
    case folder(TemplateLibraryFolder)
    case template(UUID)

    var id: UUID {
        switch self {
        case .folder(let folder): folder.id
        case .template(let id): id
        }
    }

    var templateIDs: [UUID] {
        switch self {
        case .folder(let folder): folder.children.flatMap(\.templateIDs)
        case .template(let id): [id]
        }
    }
}

/// The templates library: the only home templates have. Saving a template in
/// any project writes a self-contained bundle here; the Templates panel in
/// every project is a live view of this directory. Inserting a template stamps
/// an independent copy onto the page — nothing ever links back to the library.
@MainActor
@Observable
final class ReusablePartLibrary {
    static let shared = ReusablePartLibrary()

    private(set) var entries: [ReusablePartLibraryEntry] = []
    private(set) var organization: [TemplateLibraryNode] = []
    private var directoryURL: URL
    private let usesPackCatalog: Bool
    private var entryURLs: [UUID: URL] = [:]
    private var externalDevelopmentPackURLs: Set<URL> = []

    init(directoryURL: URL? = nil) {
        usesPackCatalog = directoryURL == nil
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL()
        refresh()
    }

    private static func defaultDirectoryURL() -> URL {
        (try? personalTemplatesURL())
            ?? FileManager.default.temporaryDirectory
                .appending(path: "FoundryTemplates", directoryHint: .isDirectory)
    }

    private static func personalTemplatesURL() throws -> URL {
        let url = try FoundryPackLoader.personalDevelopmentPackURL()
            .appending(path: FoundryPackItemKind.template.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Re-resolves the directory from the library-location preference, e.g.
    /// after the user changes the Library Folder in Settings.
    func reloadFromPreferredLocation() {
        directoryURL = Self.defaultDirectoryURL()
        refresh()
    }

    // MARK: Listing

    func refresh() {
        let fileManager = FileManager.default
        let bundleURLs: [URL]
        if usesPackCatalog, let packsRoot = try? FoundryPackLoader.installedPacksURL() {
            bundleURLs = (FoundryPackLoader.packURLs(in: packsRoot) + externalDevelopmentPackURLs)
                .compactMap { try? FoundryPackLoader.load(from: $0) }
                .flatMap(\.templateURLs)
        } else {
            bundleURLs = (try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        let loaded = bundleURLs.compactMap { url in Self.entry(at: url).map { ($0, url) } }
        entryURLs.removeAll(keepingCapacity: true)
        var uniqueEntries: [ReusablePartLibraryEntry] = []
        for (entry, url) in loaded where entryURLs[entry.id] == nil {
            entryURLs[entry.id] = url
            uniqueEntries.append(entry)
        }
        entries = uniqueEntries
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        organization = Self.normalized(loadOrganization(), entryIDs: entries.map(\.id))
        saveOrganization()
    }

    func entry(withID id: UUID) -> ReusablePartLibraryEntry? {
        entries.first { $0.id == id }
    }

    func openDevelopmentPack(at url: URL) {
        externalDevelopmentPackURLs.insert(url.standardizedFileURL)
        refresh()
    }

    func bundleURL(forID id: UUID) -> URL {
        entryURLs[id] ?? directoryURL.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private func writableBundleURL(forID id: UUID) -> URL {
        if let existing = entryURLs[id],
           existing.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL {
            return existing
        }
        return directoryURL.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// The panel's tree: the stored organization resolved against the loaded
    /// entries, in the shared node vocabulary the outline renders.
    var organizedNodes: [ReusablePartNode] {
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        func resolve(_ nodes: [TemplateLibraryNode]) -> [ReusablePartNode] {
            nodes.compactMap { node in
                switch node {
                case .folder(let folder):
                    return .folder(ReusablePartFolder(
                        id: folder.id,
                        name: folder.name,
                        children: resolve(folder.children)
                    ))
                case .template(let id):
                    guard let entry = entriesByID[id] else { return nil }
                    return .part(entry.definition)
                }
            }
        }
        return resolve(organization)
    }

    // MARK: Saving

    /// Writes (or overwrites) the bundle for this definition: latest save wins.
    /// `assetContents` supplies bytes for the assets the definition references;
    /// unresolvable assets are skipped rather than failing the save.
    func save(definition: ReusablePartDefinition, assetContents: ProjectAssetContents) {
        let fileManager = FileManager.default
        let bundleURL = writableBundleURL(forID: definition.id)
        let resourcesURL = bundleURL.appending(path: "Resources", directoryHint: .isDirectory)
        let assetsURL = resourcesURL.appending(path: "Assets", directoryHint: .isDirectory)
        do {
            try? fileManager.removeItem(at: bundleURL)
            try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)

            let manifest: [String: Any] = [
                "reusablePart": true,
                "minimumAPIVersion": 1,
                "id": definition.id.uuidString,
                "title": definition.name
            ]
            let manifestData = try PropertyListSerialization.data(
                fromPropertyList: manifest, format: .xml, options: 0
            )
            try manifestData.write(to: bundleURL.appending(path: "Info.plist"), options: .atomic)

            try FoundryDocument.encoder.encode(definition)
                .write(to: resourcesURL.appending(path: "part.json"), options: .atomic)

            var embedded: [ProjectAsset] = []
            for assetID in Self.referencedAssetIDs(in: definition) {
                guard let content = assetContents[assetID] else { continue }
                try content.data.write(
                    to: assetsURL.appending(path: content.asset.storageFilename),
                    options: .atomic
                )
                embedded.append(content.asset)
            }
            try FoundryDocument.encoder.encode(embedded)
                .write(to: resourcesURL.appending(path: "assets.json"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: bundleURL)
        }
        refresh()
    }

    // MARK: Previews

    /// Bumped whenever a preview image lands so views re-read preview files.
    private(set) var previewRevision = 0

    func previewURL(forID id: UUID) -> URL? {
        let url = bundleURL(forID: id).appending(path: "Resources/preview.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Attaches the offscreen-rendered preview to an existing bundle; arrives a
    /// beat after the save once painting settles.
    func savePreview(_ data: Data, forID id: UUID) {
        guard entry(withID: id) != nil else { return }
        let url = bundleURL(forID: id).appending(path: "Resources/preview.png")
        try? data.write(to: url, options: .atomic)
        previewRevision += 1
    }

    // MARK: Managing

    func rename(id: UUID, to name: String) {
        guard let entry = entry(withID: id) else { return }
        guard bundleURL(forID: id).deletingLastPathComponent().standardizedFileURL
            == directoryURL.standardizedFileURL else { return }
        var definition = entry.definition
        definition.name = name
        let resourcesURL = bundleURL(forID: id).appending(path: "Resources", directoryHint: .isDirectory)
        try? FoundryDocument.encoder.encode(definition)
            .write(to: resourcesURL.appending(path: "part.json"), options: .atomic)
        refresh()
    }

    func delete(id: UUID) {
        guard bundleURL(forID: id).deletingLastPathComponent().standardizedFileURL
            == directoryURL.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: bundleURL(forID: id))
        organization.removeNode(id: id)
        saveOrganization()
        refresh()
    }

    /// Copies a template's bundle under a fresh identity, placed after the
    /// original in the organization.
    func duplicate(id: UUID) {
        guard let entry = entry(withID: id) else { return }
        var copy = entry.definition
        let copied = ReusablePartDefinition(
            name: copy.name + " Copy",
            root: copy.root.duplicatedForReusableDefinition()
        )
        copy = copied
        let fileManager = FileManager.default
        let sourceURL = bundleURL(forID: id)
        let destinationURL = bundleURL(forID: copied.id)
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            let resourcesURL = destinationURL.appending(path: "Resources", directoryHint: .isDirectory)
            try FoundryDocument.encoder.encode(copied)
                .write(to: resourcesURL.appending(path: "part.json"), options: .atomic)
            let manifest: [String: Any] = [
                "reusablePart": true,
                "minimumAPIVersion": 1,
                "id": copied.id.uuidString,
                "title": copied.name
            ]
            try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
                .write(to: destinationURL.appending(path: "Info.plist"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            return
        }
        _ = organization.insert(.template(copied.id), at: .after(nodeID: id))
        saveOrganization()
        refresh()
    }

    // MARK: Folders and ordering

    @discardableResult
    func createFolder(name: String, at placement: ReusablePartPlacement = .end) -> UUID? {
        let folder = TemplateLibraryFolder(name: name)
        guard organization.insert(.folder(folder), at: placement) else { return nil }
        saveOrganization()
        return folder.id
    }

    func renameFolder(id: UUID, to name: String) {
        guard organization.renameFolder(id: id, to: name) else { return }
        saveOrganization()
    }

    /// Deletes a folder and every template bundle inside it.
    func deleteFolder(id: UUID) {
        guard case .folder(let folder)? = organization.node(withID: id) else { return }
        for templateID in folder.children.flatMap(\.templateIDs) {
            let url = bundleURL(forID: templateID)
            if url.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        organization.removeNode(id: id)
        saveOrganization()
        refresh()
    }

    @discardableResult
    func moveNode(id: UUID, to placement: ReusablePartPlacement) -> Bool {
        guard organization.move(id: id, to: placement) else { return false }
        saveOrganization()
        return true
    }

    // MARK: Importing

    /// Produces a copy of the entry's definition ready for the given document:
    /// embedded assets are imported into the document's asset library (reusing
    /// identical content) and every asset reference is remapped to the imported
    /// identifiers. Framework role references pass through untouched.
    func importedDefinition(
        for entry: ReusablePartLibraryEntry,
        into document: FoundryDocument,
        undoManager: UndoManager?
    ) -> ReusablePartDefinition? {
        let assetsURL = bundleURL(forID: entry.id)
            .appending(path: "Resources/Assets", directoryHint: .isDirectory)
        var replacements: [UUID: UUID] = [:]
        for asset in entry.assets {
            let fileURL = assetsURL.appending(path: asset.storageFilename)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let importedID = document.importAsset(
                data: data,
                filename: asset.filename,
                mediaType: asset.mediaType,
                reuseIdenticalContent: true,
                undoManager: undoManager
            )
            if importedID != asset.id { replacements[asset.id] = importedID }
        }
        return Self.remappingAssetIDs(in: entry.definition, replacements: replacements)
    }

    // MARK: Definition inspection

    /// Every `foundry-asset:` reference in the definition, wherever it appears —
    /// image and video values, rich text content, background images. Scanning
    /// the encoded JSON catches every representation with one rule.
    nonisolated static func referencedAssetIDs(in definition: ReusablePartDefinition) -> [UUID] {
        guard let data = try? FoundryDocument.encoder.encode(definition),
              let json = String(data: data, encoding: .utf8) else { return [] }
        var seen: Set<UUID> = []
        var ordered: [UUID] = []
        for match in json.matches(of: Self.assetReferencePattern) {
            guard let id = UUID(uuidString: String(match.output.1)), seen.insert(id).inserted else { continue }
            ordered.append(id)
        }
        return ordered
    }

    nonisolated static func remappingAssetIDs(
        in definition: ReusablePartDefinition,
        replacements: [UUID: UUID]
    ) -> ReusablePartDefinition? {
        guard !replacements.isEmpty else { return definition }
        guard let data = try? FoundryDocument.encoder.encode(definition),
              var json = String(data: data, encoding: .utf8) else { return nil }
        for (old, new) in replacements {
            json = json.replacingOccurrences(
                of: "foundry-asset:\(old.uuidString)",
                with: "foundry-asset:\(new.uuidString)"
            )
        }
        return try? FoundryDocument.decoder.decode(ReusablePartDefinition.self, from: Data(json.utf8))
    }

    // MARK: Organization persistence

    private var organizationURL: URL {
        directoryURL.appending(path: "library.json")
    }

    private func loadOrganization() -> [TemplateLibraryNode] {
        guard let data = try? Data(contentsOf: organizationURL),
              let nodes = try? FoundryDocument.decoder.decode([TemplateLibraryNode].self, from: data) else {
            return []
        }
        return nodes
    }

    private func saveOrganization() {
        guard let data = try? FoundryDocument.encoder.encode(organization) else { return }
        try? data.write(to: organizationURL, options: .atomic)
    }

    /// Drops references to bundles that no longer exist and appends templates
    /// the organization has never seen, so external file changes stay coherent.
    nonisolated private static func normalized(
        _ nodes: [TemplateLibraryNode],
        entryIDs: [UUID]
    ) -> [TemplateLibraryNode] {
        let known = Set(entryIDs)
        var referenced: Set<UUID> = []
        func prune(_ nodes: [TemplateLibraryNode]) -> [TemplateLibraryNode] {
            nodes.compactMap { node in
                switch node {
                case .template(let id):
                    guard known.contains(id), referenced.insert(id).inserted else { return nil }
                    return node
                case .folder(var folder):
                    folder.children = prune(folder.children)
                    return .folder(folder)
                }
            }
        }
        var result = prune(nodes)
        for id in entryIDs where !referenced.contains(id) {
            result.append(.template(id))
        }
        return result
    }

    // MARK: Bundle reading

    private nonisolated static let assetReferencePattern = /foundry-asset:([0-9A-Fa-f-]{36})/

    nonisolated static func entry(at bundleURL: URL) -> ReusablePartLibraryEntry? {
        let resourcesURL = bundleURL.appending(path: "Resources", directoryHint: .isDirectory)
        guard let manifestData = try? Data(contentsOf: bundleURL.appending(path: "Info.plist")),
              let manifest = try? PropertyListSerialization.propertyList(from: manifestData, format: nil) as? [String: Any],
              manifest["reusablePart"] as? Bool == true,
              let definitionData = try? Data(contentsOf: resourcesURL.appending(path: "part.json")),
              let definition = try? FoundryDocument.decoder.decode(ReusablePartDefinition.self, from: definitionData) else {
            return nil
        }
        let assets = (try? Data(contentsOf: resourcesURL.appending(path: "assets.json")))
            .flatMap { try? FoundryDocument.decoder.decode([ProjectAsset].self, from: $0) } ?? []
        return ReusablePartLibraryEntry(definition: definition, assets: assets)
    }
}

nonisolated extension Array where Element == TemplateLibraryNode {
    func node(withID id: UUID) -> TemplateLibraryNode? {
        for node in self {
            if node.id == id { return node }
            if case .folder(let folder) = node,
               let match = folder.children.node(withID: id) {
                return match
            }
        }
        return nil
    }

    mutating func insert(_ node: TemplateLibraryNode, at placement: ReusablePartPlacement) -> Bool {
        switch placement {
        case .end:
            append(node)
            return true
        case .inside(let folderID):
            return mutateFolder(id: folderID) { $0.children.append(node) }
        case .before(let nodeID):
            return insert(node, adjacentTo: nodeID, offset: 0)
        case .after(let nodeID):
            return insert(node, adjacentTo: nodeID, offset: 1)
        }
    }

    mutating func move(id: UUID, to placement: ReusablePartPlacement) -> Bool {
        guard !placement.targets(id),
              let node = node(withID: id),
              !node.containsTargetFolder(for: placement) else { return false }
        var copy = self
        guard let removed = copy.removeNode(id: id), copy.insert(removed, at: placement) else { return false }
        self = copy
        return true
    }

    @discardableResult
    mutating func removeNode(id: UUID) -> TemplateLibraryNode? {
        if let index = firstIndex(where: { $0.id == id }) {
            return remove(at: index)
        }
        for index in indices {
            guard case .folder(var folder) = self[index],
                  let removed = folder.children.removeNode(id: id) else { continue }
            self[index] = .folder(folder)
            return removed
        }
        return nil
    }

    mutating func renameFolder(id: UUID, to name: String) -> Bool {
        mutateFolder(id: id) { $0.name = name }
    }

    private mutating func insert(_ node: TemplateLibraryNode, adjacentTo targetID: UUID, offset: Int) -> Bool {
        if let index = firstIndex(where: { $0.id == targetID }) {
            insert(node, at: index + offset)
            return true
        }
        for index in indices {
            guard case .folder(var folder) = self[index],
                  folder.children.insert(node, adjacentTo: targetID, offset: offset) else { continue }
            self[index] = .folder(folder)
            return true
        }
        return false
    }

    private mutating func mutateFolder(id: UUID, mutation: (inout TemplateLibraryFolder) -> Void) -> Bool {
        for index in indices {
            switch self[index] {
            case .template:
                continue
            case .folder(var folder):
                if folder.id == id {
                    mutation(&folder)
                    self[index] = .folder(folder)
                    return true
                }
                if folder.children.mutateFolder(id: id, mutation: mutation) {
                    self[index] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }
}

nonisolated private extension TemplateLibraryNode {
    func containsTargetFolder(for placement: ReusablePartPlacement) -> Bool {
        guard case .folder(let folder) = self,
              case .inside(let targetID) = placement else { return false }
        return folder.id == targetID || folder.children.node(withID: targetID) != nil
    }
}
