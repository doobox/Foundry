import CryptoKit
import Foundation

/// A template bundle in the app-wide library: the saved definition plus the
/// metadata of every project asset it embeds.
nonisolated struct ReusablePartLibraryEntry: Identifiable, Equatable, Sendable {
    let definition: ReusablePartDefinition
    let assets: [ProjectAsset]

    var id: UUID { definition.id }
    var name: String { definition.name }
}

/// One source of templates in the panel: the personal "My Library" pack, an
/// open development pack, or an installed read-only pack.
nonisolated struct ReusablePartLibraryPack: Identifiable, Sendable {
    let rootURL: URL?
    let title: String
    let isEditable: Bool
    /// The user's own My Library pack — shown on the Library tab; every
    /// other dev pack belongs to the Dev tab.
    let isPersonal: Bool
    /// Whether the panel shows this source even without templates: dev packs
    /// are standing drop targets; a read-only pack earns its section with
    /// content.
    let showsWhenEmpty: Bool
    let nodes: [ReusablePartNode]

    var id: String { rootURL?.standardizedFileURL.path ?? "library" }
}

/// The templates library: every pack that carries templates, resolved into
/// panel sections. Editable packs (the personal "My Library" pack and open
/// development packs) accept saves, renames, deletions and moves; installed
/// `.foundrypack`s are read-only sources whose templates can only be copied
/// out. Inserting a template stamps an independent copy onto the page —
/// nothing ever links back to the library.
///
/// Organization is the directory tree itself: a child of `Templates/`
/// without a `manifest.json` is a folder, hand-authorable in Finder. Folders
/// and templates list alphabetically — there is no custom ordering to store,
/// so there is no sidecar file.
@MainActor
@Observable
final class ReusablePartLibrary {
    static let shared = ReusablePartLibrary()

    /// One template source and everything loaded from it.
    private struct PackState {
        let rootURL: URL?
        let templatesURL: URL
        let title: String
        let isEditable: Bool
        let isPersonal: Bool
        let showsWhenEmpty: Bool
        var entries: [ReusablePartLibraryEntry] = []
        var nodes: [ReusablePartNode] = []

        var id: String { rootURL?.standardizedFileURL.path ?? "library" }
    }

    private(set) var entries: [ReusablePartLibraryEntry] = []
    private(set) var packs: [ReusablePartLibraryPack] = []
    private(set) var loadingErrors: [String] = []
    private var packStates: [PackState] = []
    private var entryURLs: [UUID: URL] = [:]
    private var entryPackIDs: [UUID: String] = [:]
    /// Organization folders by their path-derived ids.
    private var folderURLs: [UUID: URL] = [:]
    private var folderPackIDs: [UUID: String] = [:]
    private var externalDevelopmentPackURLs: Set<URL> = []
    /// Injected in tests: a plain directory of bundles instead of the pack
    /// catalog, presented as one editable source.
    private let fixedDirectoryURL: URL?

    init(directoryURL: URL? = nil) {
        fixedDirectoryURL = directoryURL
        refresh()
    }

    /// Re-resolves the personal pack from the library-location preference,
    /// e.g. after the user changes the Library Folder in Settings.
    func reloadFromPreferredLocation() {
        refresh()
    }

    // MARK: Listing

    func refresh() {
        loadingErrors = []
        entryURLs.removeAll(keepingCapacity: true)
        entryPackIDs.removeAll(keepingCapacity: true)
        folderURLs.removeAll(keepingCapacity: true)
        folderPackIDs.removeAll(keepingCapacity: true)
        var states: [PackState] = []
        for source in resolvedSources() {
            var state = source
            state.nodes = scanNodes(in: state.templatesURL, packID: state.id, entries: &state.entries)
            states.append(state)
        }
        packStates = states
        entries = states.flatMap(\.entries)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        packs = states.map { state in
            ReusablePartLibraryPack(
                rootURL: state.rootURL,
                title: state.title,
                isEditable: state.isEditable,
                isPersonal: state.isPersonal,
                showsWhenEmpty: state.showsWhenEmpty,
                nodes: state.nodes
            )
        }
    }

    /// One directory level of a pack's Templates tree: a directory with a
    /// manifest.json is a template bundle, a directory without one is an
    /// organization folder, recursed. Folders list first, then templates,
    /// each in name order.
    private func scanNodes(
        in directoryURL: URL,
        packID: String,
        entries: inout [ReusablePartLibraryEntry]
    ) -> [ReusablePartNode] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var folders: [ReusablePartFolder] = []
        var parts: [ReusablePartDefinition] = []
        for url in children {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            if FileManager.default.fileExists(atPath: url.appending(path: "manifest.json").path) {
                guard let entry = Self.entry(at: url), entryURLs[entry.id] == nil else { continue }
                entryURLs[entry.id] = url.standardizedFileURL
                entryPackIDs[entry.id] = packID
                entries.append(entry)
                parts.append(entry.definition)
            } else {
                let folderID = Self.folderID(forPath: url.standardizedFileURL.path)
                folderURLs[folderID] = url.standardizedFileURL
                folderPackIDs[folderID] = packID
                folders.append(ReusablePartFolder(
                    id: folderID,
                    name: url.lastPathComponent,
                    children: scanNodes(in: url, packID: packID, entries: &entries)
                ))
            }
        }
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        parts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folders.map { .folder($0) } + parts.map { .part($0) }
    }

    /// A folder's identity is derived from its path, so it is stable across
    /// refreshes and across app instances without any stored state.
    nonisolated private static func folderID(forPath path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func resolvedSources() -> [PackState] {
        if let fixedDirectoryURL {
            return [PackState(
                rootURL: nil,
                templatesURL: fixedDirectoryURL,
                title: "Templates",
                isEditable: true,
                isPersonal: true,
                showsWhenEmpty: true
            )]
        }
        var roots: [(url: URL, isPersonal: Bool, showsWhenEmpty: Bool)] = []
        do {
            let personal = try FoundryPackLoader.personalDevelopmentPackURL()
            roots.append((personal.standardizedFileURL, true, true))
        } catch {
            loadingErrors.append("My Library: \(error.localizedDescription)")
        }
        let installedRoots: [URL]
        do {
            installedRoots = FoundryPackLoader.packURLs(in: try FoundryPackLoader.installedPacksURL())
        } catch {
            loadingErrors.append("Installed packs: \(error.localizedDescription)")
            installedRoots = []
        }
        // Dev packs are standing authoring targets and always show, even
        // empty — the Dev tab keeps them out of everyone else's view, so a
        // first template can land in any of them without ceremony.
        let external = externalDevelopmentPackURLs.subtracting(roots.map(\.url))
        roots += external
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { ($0, false, true) }
        roots += installedRoots
            .filter { url in !roots.contains { $0.url == url.standardizedFileURL } }
            .map { ($0, false, $0.pathExtension.lowercased() == "foundrydevpack") }
        // Templates shipped inside the app's built-in pack surface as the
        // panel's final read-only section, like Elements' protected Core.
        if let builtIn = FoundryPackLoader.builtInPackURL() {
            roots.append((builtIn, false, false))
        }
        return roots.compactMap {
            packSource(at: $0.url, isPersonal: $0.isPersonal, showsWhenEmpty: $0.showsWhenEmpty)
        }
    }

    private func packSource(at rootURL: URL, isPersonal: Bool, showsWhenEmpty: Bool) -> PackState? {
        let pack: FoundryPack
        do {
            pack = try FoundryPackLoader.load(from: rootURL)
        } catch {
            loadingErrors.append("\(rootURL.deletingPathExtension().lastPathComponent): \(error.localizedDescription)")
            return nil
        }
        return PackState(
            rootURL: rootURL.standardizedFileURL,
            templatesURL: rootURL.appending(
                path: FoundryPackItemKind.template.rawValue,
                directoryHint: .isDirectory
            ),
            title: pack.metadata.title ?? rootURL.deletingPathExtension().lastPathComponent,
            isEditable: rootURL.pathExtension.lowercased() == "foundrydevpack",
            isPersonal: isPersonal,
            showsWhenEmpty: showsWhenEmpty
        )
    }

    func entry(withID id: UUID) -> ReusablePartLibraryEntry? {
        entries.first { $0.id == id }
    }

    func openDevelopmentPack(at url: URL) {
        externalDevelopmentPackURLs.insert(url.standardizedFileURL)
        refresh()
    }

    func bundleURL(forID id: UUID) -> URL {
        entryURLs[id] ?? personalTemplatesURL().appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// The pack a loaded template belongs to; nil for unknown ids.
    func packRootURL(forID id: UUID) -> URL? {
        packState(containingEntry: id)?.rootURL
    }

    func isEditable(id: UUID) -> Bool {
        packState(containingEntry: id)?.isEditable ?? false
    }

    /// The tree of the first editable source — the personal pack, or the
    /// injected directory in tests.
    var organizedNodes: [ReusablePartNode] {
        packs.first(where: \.isEditable)?.nodes ?? []
    }

    private func packState(containingEntry id: UUID) -> PackState? {
        guard let packID = entryPackIDs[id] else { return nil }
        return packStates.first { $0.id == packID }
    }

    /// The source containing this node — a template bundle or an
    /// organization folder, both real directories.
    private func packState(containingNode id: UUID) -> PackState? {
        guard let packID = entryPackIDs[id] ?? folderPackIDs[id] else { return nil }
        return packStates.first { $0.id == packID }
    }

    /// The on-disk directory of a node: a template's bundle or a folder.
    private func nodeURL(_ id: UUID) -> URL? {
        entryURLs[id] ?? folderURLs[id]
    }

    /// The directory a placement lands in, inside the given pack: a folder
    /// for `.inside`, a sibling's parent for `.before`/`.after`, the
    /// Templates root for `.end`.
    private func destinationDirectory(
        for placement: ReusablePartPlacement,
        inPack state: PackState
    ) -> URL? {
        switch placement {
        case .end:
            return state.templatesURL
        case .inside(let folderID):
            guard folderPackIDs[folderID] == state.id else { return nil }
            return folderURLs[folderID]
        case .before(let nodeID), .after(let nodeID):
            guard (entryPackIDs[nodeID] ?? folderPackIDs[nodeID]) == state.id else { return nil }
            return nodeURL(nodeID)?.deletingLastPathComponent()
        }
    }

    /// Moves a bundle or folder directory into another directory of the same
    /// pack, refusing self-moves, no-ops, and folder-into-own-subtree.
    private func moveItem(at sourceURL: URL, intoDirectory destinationDir: URL) -> Bool {
        let source = sourceURL.standardizedFileURL
        let destination = destinationDir.standardizedFileURL
        guard destination != source,
              !destination.path.hasPrefix(source.path + "/"),
              source.deletingLastPathComponent() != destination else { return false }
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let target = uniqueDirectory(for: source.lastPathComponent, in: destination)
        guard (try? FileManager.default.moveItem(at: source, to: target)) != nil else { return false }
        refresh()
        return true
    }

    private func uniqueDirectory(for name: String, in directoryURL: URL) -> URL {
        var candidate = directoryURL.appending(path: name, directoryHint: .isDirectory)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appending(path: "\(name) \(counter)", directoryHint: .isDirectory)
            counter += 1
        }
        return candidate
    }

    private func personalTemplatesURL() -> URL {
        if let fixedDirectoryURL { return fixedDirectoryURL }
        return packStates.first(where: \.isEditable)?.templatesURL
            ?? FileManager.default.temporaryDirectory.appending(path: "FoundryTemplates", directoryHint: .isDirectory)
    }

    private func templatesURL(forPackRoot rootURL: URL?) -> URL? {
        guard let rootURL else { return personalTemplatesURL() }
        return packStates.first {
            $0.rootURL?.standardizedFileURL == rootURL.standardizedFileURL && $0.isEditable
        }?.templatesURL
    }

    // MARK: Saving

    /// Writes (or overwrites) the bundle for this definition: latest save
    /// wins. `assetContents` supplies bytes for the assets the definition
    /// references; unresolvable assets are skipped rather than failing the
    /// save. Without a destination the bundle stays in its current editable
    /// pack, or joins the personal pack.
    func save(
        definition: ReusablePartDefinition,
        assetContents: ProjectAssetContents,
        to packRootURL: URL? = nil
    ) {
        let bundleURL: URL
        if let packRootURL {
            guard let templatesURL = templatesURL(forPackRoot: packRootURL) else { return }
            bundleURL = templatesURL.appending(path: definition.id.uuidString, directoryHint: .isDirectory)
        } else {
            bundleURL = writableBundleURL(forID: definition.id)
        }
        writeBundle(definition: definition, assetContents: assetContents, to: bundleURL)
        refresh()
    }

    private func writableBundleURL(forID id: UUID) -> URL {
        if let existing = entryURLs[id], packState(containingEntry: id)?.isEditable == true {
            return existing
        }
        return personalTemplatesURL().appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private func writeBundle(
        definition: ReusablePartDefinition,
        assetContents: ProjectAssetContents,
        to bundleURL: URL
    ) {
        let fileManager = FileManager.default
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
            let manifestData = try JSONSerialization.data(
                withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]
            )
            try manifestData.write(to: bundleURL.appending(path: "manifest.json"), options: .atomic)

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
        guard entry(withID: id) != nil, isEditable(id: id) else { return }
        let url = bundleURL(forID: id).appending(path: "Resources/preview.png")
        try? data.write(to: url, options: .atomic)
        previewRevision += 1
    }

    // MARK: Managing

    func rename(id: UUID, to name: String) {
        guard let entry = entry(withID: id), isEditable(id: id) else { return }
        var definition = entry.definition
        definition.name = name
        let resourcesURL = bundleURL(forID: id).appending(path: "Resources", directoryHint: .isDirectory)
        try? FoundryDocument.encoder.encode(definition)
            .write(to: resourcesURL.appending(path: "part.json"), options: .atomic)
        refresh()
    }

    func delete(id: UUID) {
        guard let state = packState(containingEntry: id), state.isEditable else { return }
        try? FileManager.default.removeItem(at: bundleURL(forID: id))
        refresh()
    }

    /// Copies a template's bundle under a fresh identity. Without a
    /// destination the copy lands beside the original — same folder — when
    /// its pack is editable, otherwise in the personal pack — the "duplicate
    /// out of a read-only pack" gesture. An explicit duplicate gains a
    /// " Copy" suffix; a drag-copy between packs keeps the original name.
    @discardableResult
    func duplicate(id: UUID, to packRootURL: URL? = nil, renaming: Bool = true) -> UUID? {
        let sourceState = packState(containingEntry: id)
        let destinationDirectory: URL
        if let packRootURL {
            guard let url = templatesURL(forPackRoot: packRootURL) else { return nil }
            destinationDirectory = url
        } else if let sourceState, sourceState.isEditable, let sourceURL = entryURLs[id] {
            destinationDirectory = sourceURL.deletingLastPathComponent()
        } else {
            destinationDirectory = personalTemplatesURL()
        }
        guard let copiedID = copyBundle(of: id, into: destinationDirectory, renaming: renaming) else {
            return nil
        }
        refresh()
        return copiedID
    }

    /// Copies one bundle into a templates directory under a fresh identity —
    /// no organization changes, no refresh; callers arrange both.
    private func copyBundle(of id: UUID, into destinationTemplatesURL: URL, renaming: Bool) -> UUID? {
        guard let entry = entry(withID: id) else { return nil }
        let copied = ReusablePartDefinition(
            name: renaming ? entry.definition.name + " Copy" : entry.definition.name,
            root: entry.definition.root.duplicatedForReusableDefinition()
        )
        let fileManager = FileManager.default
        let sourceURL = bundleURL(forID: id)
        let destinationURL = destinationTemplatesURL.appending(path: copied.id.uuidString, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: destinationTemplatesURL, withIntermediateDirectories: true)
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
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                .write(to: destinationURL.appending(path: "manifest.json"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            return nil
        }
        return copied.id
    }

    /// Physically moves a template's bundle into another editable pack's
    /// Templates root; a following `moveNode` can slot it into a folder.
    @discardableResult
    func moveTemplate(id: UUID, toPackRoot packRootURL: URL?) -> Bool {
        guard let sourceState = packState(containingEntry: id), sourceState.isEditable,
              let sourceURL = entryURLs[id],
              let targetState = editablePackState(forRoot: packRootURL),
              targetState.id != sourceState.id else {
            return false
        }
        return moveItem(at: sourceURL, intoDirectory: targetState.templatesURL)
    }

    /// Moves a folder — the directory and every bundle inside — into another
    /// editable pack, keeping the arrangement intact.
    @discardableResult
    func moveFolder(id: UUID, toPackRoot packRootURL: URL?, at placement: ReusablePartPlacement = .end) -> Bool {
        guard let sourceState = packState(containingNode: id), sourceState.isEditable,
              let folderURL = folderURLs[id],
              let targetState = editablePackState(forRoot: packRootURL),
              targetState.id != sourceState.id else {
            return false
        }
        let destination = destinationDirectory(for: placement, inPack: targetState)
            ?? targetState.templatesURL
        return moveItem(at: folderURL, intoDirectory: destination)
    }

    /// Recreates a folder from a read-only pack inside an editable one: the
    /// directory tree copies across with every bundle re-identified, same
    /// names and arrangement. The source is untouched.
    @discardableResult
    func copyFolder(id: UUID, toPackRoot packRootURL: URL?, at placement: ReusablePartPlacement = .end) -> Bool {
        guard let folderURL = folderURLs[id],
              let targetState = editablePackState(forRoot: packRootURL) else {
            return false
        }
        let destinationParent = destinationDirectory(for: placement, inPack: targetState)
            ?? targetState.templatesURL
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let destination = uniqueDirectory(for: folderURL.lastPathComponent, in: destinationParent)
        guard (try? fileManager.copyItem(at: folderURL, to: destination)) != nil else { return false }
        reidentifyBundles(in: destination)
        refresh()
        return true
    }

    /// Gives every template bundle below the directory a fresh identity —
    /// copies must never share definition ids with their originals.
    private func reidentifyBundles(in directoryURL: URL) {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in children {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard fileManager.fileExists(atPath: url.appending(path: "manifest.json").path) else {
                reidentifyBundles(in: url)
                continue
            }
            guard let entry = Self.entry(at: url) else {
                try? fileManager.removeItem(at: url)
                continue
            }
            let copied = ReusablePartDefinition(
                name: entry.definition.name,
                root: entry.definition.root.duplicatedForReusableDefinition()
            )
            let resourcesURL = url.appending(path: "Resources", directoryHint: .isDirectory)
            do {
                try FoundryDocument.encoder.encode(copied)
                    .write(to: resourcesURL.appending(path: "part.json"), options: .atomic)
                let manifest: [String: Any] = [
                    "reusablePart": true,
                    "minimumAPIVersion": 1,
                    "id": copied.id.uuidString,
                    "title": copied.name
                ]
                try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                    .write(to: url.appending(path: "manifest.json"), options: .atomic)
                try fileManager.moveItem(
                    at: url,
                    to: url.deletingLastPathComponent()
                        .appending(path: copied.id.uuidString, directoryHint: .isDirectory)
                )
            } catch {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func editablePackState(forRoot packRootURL: URL?) -> PackState? {
        guard let packRootURL else { return packStates.first(where: \.isEditable) }
        return packStates.first {
            $0.rootURL?.standardizedFileURL == packRootURL.standardizedFileURL && $0.isEditable
        }
    }

    // MARK: Folders

    /// Creates a directory at the placement's location — the Templates root,
    /// or inside another folder. Returns the new folder's path-derived id.
    @discardableResult
    func createFolder(
        name: String,
        inPackRoot packRootURL: URL? = nil,
        at placement: ReusablePartPlacement = .end
    ) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let targetState = editablePackState(forRoot: packRootURL) else { return nil }
        let parent = destinationDirectory(for: placement, inPack: targetState)
            ?? targetState.templatesURL
        let directory = uniqueDirectory(for: trimmed, in: parent)
        guard (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )) != nil else { return nil }
        refresh()
        return Self.folderID(forPath: directory.standardizedFileURL.path)
    }

    /// Renames the folder's directory. Returns the folder's new id — its
    /// path changes — so selection can follow, or nil when refused.
    @discardableResult
    func renameFolder(id: UUID, to name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let state = packState(containingNode: id), state.isEditable,
              let folderURL = folderURLs[id],
              trimmed != folderURL.lastPathComponent else { return nil }
        let destination = folderURL.deletingLastPathComponent()
            .appending(path: trimmed, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path),
              (try? FileManager.default.moveItem(at: folderURL, to: destination)) != nil else { return nil }
        refresh()
        return Self.folderID(forPath: destination.standardizedFileURL.path)
    }

    /// Deletes a folder's directory and every template bundle inside it.
    func deleteFolder(id: UUID) {
        guard let state = packState(containingNode: id), state.isEditable,
              let folderURL = folderURLs[id] else { return }
        try? FileManager.default.removeItem(at: folderURL)
        refresh()
    }

    /// Moves a node within its own pack: into a folder, beside a sibling —
    /// meaning into that sibling's folder — or to the Templates root.
    /// Ordering inside a directory is alphabetical, so a drop that changes
    /// only position is a no-op. Crossing packs is `moveTemplate`.
    @discardableResult
    func moveNode(id: UUID, to placement: ReusablePartPlacement) -> Bool {
        guard let state = packState(containingNode: id), state.isEditable,
              let sourceURL = nodeURL(id),
              let destination = destinationDirectory(for: placement, inPack: state) else { return false }
        return moveItem(at: sourceURL, intoDirectory: destination)
    }

    // MARK: Importing

    /// Produces a copy of the entry's definition ready for the given document:
    /// embedded assets are imported into the document's asset library (reusing
    /// identical content) and every asset reference is remapped to the imported
    /// identifiers. Theme role references pass through untouched.
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

    // MARK: Bundle reading

    private nonisolated static let assetReferencePattern = /foundry-asset:([0-9A-Fa-f-]{36})/

    nonisolated static func entry(at bundleURL: URL) -> ReusablePartLibraryEntry? {
        let resourcesURL = bundleURL.appending(path: "Resources", directoryHint: .isDirectory)
        guard let manifestData = try? Data(contentsOf: bundleURL.appending(path: "manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
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
