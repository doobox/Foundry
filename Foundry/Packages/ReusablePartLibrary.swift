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

/// One source of templates in the panel: the personal "My Library" pack, an
/// open development pack, or an installed read-only pack.
nonisolated struct ReusablePartLibraryPack: Identifiable, Sendable {
    let rootURL: URL?
    let title: String
    let isEditable: Bool
    /// Whether the panel shows this source even without templates: the
    /// personal pack and explicitly opened dev packs are standing drop
    /// targets; a merely installed pack earns its section with content.
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
@MainActor
@Observable
final class ReusablePartLibrary {
    static let shared = ReusablePartLibrary()

    /// One template source and everything loaded from it.
    private struct PackState {
        let rootURL: URL?
        let templatesURL: URL
        let organizationURL: URL
        let title: String
        let isEditable: Bool
        let showsWhenEmpty: Bool
        var entries: [ReusablePartLibraryEntry]
        var organization: [TemplateLibraryNode]

        var id: String { rootURL?.standardizedFileURL.path ?? "library" }
    }

    private(set) var entries: [ReusablePartLibraryEntry] = []
    private(set) var packs: [ReusablePartLibraryPack] = []
    private var packStates: [PackState] = []
    private var entryURLs: [UUID: URL] = [:]
    private var entryPackIDs: [UUID: String] = [:]
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
        entryURLs.removeAll(keepingCapacity: true)
        entryPackIDs.removeAll(keepingCapacity: true)
        var states: [PackState] = []
        for source in resolvedSources() {
            var state = source
            let bundleURLs = templateBundleURLs(for: source)
            let loaded = bundleURLs
                .compactMap { url in Self.entry(at: url).map { ($0, url) } }
                .sorted { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
            for (entry, url) in loaded where entryURLs[entry.id] == nil {
                entryURLs[entry.id] = url
                entryPackIDs[entry.id] = state.id
                state.entries.append(entry)
            }
            state.organization = Self.normalized(
                loadOrganization(at: state.organizationURL),
                entryIDs: state.entries.map(\.id)
            )
            // Read-only packs keep their shipped arrangement untouched on disk.
            if state.isEditable {
                saveOrganization(state.organization, at: state.organizationURL)
            }
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
                showsWhenEmpty: state.showsWhenEmpty,
                nodes: resolvedNodes(state.organization, entries: state.entries)
            )
        }
    }

    private func resolvedSources() -> [PackState] {
        if let fixedDirectoryURL {
            return [PackState(
                rootURL: nil,
                templatesURL: fixedDirectoryURL,
                organizationURL: fixedDirectoryURL.appending(path: "library.json"),
                title: "Templates",
                isEditable: true,
                showsWhenEmpty: true,
                entries: [],
                organization: []
            )]
        }
        var roots: [(url: URL, showsWhenEmpty: Bool)] = []
        if let personal = try? FoundryPackLoader.personalDevelopmentPackURL() {
            roots.append((personal.standardizedFileURL, true))
        }
        let installedRoots = (try? FoundryPackLoader.installedPacksURL())
            .map { FoundryPackLoader.packURLs(in: $0) } ?? []
        // Explicitly opened dev packs are the active authoring context and
        // stay visible even before their first template lands.
        let external = externalDevelopmentPackURLs.subtracting(roots.map(\.url))
        roots += external
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { ($0, true) }
        roots += installedRoots
            .filter { url in !roots.contains { $0.url == url.standardizedFileURL } }
            .map { ($0, false) }
        // Templates shipped inside the app's built-in pack surface as the
        // panel's final read-only section, like Elements' protected Core.
        if let builtIn = Self.builtInPackURL() {
            roots.append((builtIn, false))
        }
        return roots.compactMap { packSource(at: $0.url, showsWhenEmpty: $0.showsWhenEmpty) }
    }

    private nonisolated static func builtInPackURL() -> URL? {
        guard let bundleURL = Bundle.main.url(forResource: "BuiltInParts", withExtension: "bundle"),
              let partBundle = Bundle(url: bundleURL) else { return nil }
        let containerURL = partBundle.url(forResource: "BuiltInParts", withExtension: "foundrypack")
            ?? partBundle.resourceURL?.appending(path: "BuiltInParts.foundrypack", directoryHint: .isDirectory)
        return containerURL?.standardizedFileURL
    }

    private func packSource(at rootURL: URL, showsWhenEmpty: Bool) -> PackState? {
        guard let pack = try? FoundryPackLoader.load(from: rootURL) else { return nil }
        return PackState(
            rootURL: rootURL.standardizedFileURL,
            templatesURL: rootURL.appending(
                path: FoundryPackItemKind.template.rawValue,
                directoryHint: .isDirectory
            ),
            organizationURL: rootURL
                .appending(path: "Resources", directoryHint: .isDirectory)
                .appending(path: "library.json"),
            title: pack.metadata.title ?? rootURL.deletingPathExtension().lastPathComponent,
            isEditable: rootURL.pathExtension.lowercased() == "foundrydevpack",
            showsWhenEmpty: showsWhenEmpty,
            entries: [],
            organization: []
        )
    }

    private func templateBundleURLs(for source: PackState) -> [URL] {
        guard fixedDirectoryURL == nil else {
            return (try? FileManager.default.contentsOfDirectory(
                at: source.templatesURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        guard let rootURL = source.rootURL,
              let pack = try? FoundryPackLoader.load(from: rootURL) else { return [] }
        return pack.templateURLs
    }

    private func resolvedNodes(
        _ organization: [TemplateLibraryNode],
        entries: [ReusablePartLibraryEntry]
    ) -> [ReusablePartNode] {
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

    /// The source whose organization tree contains this node (template or
    /// folder) — folders exist only in organizations, not on disk.
    private func packState(containingNode id: UUID) -> PackState? {
        packStates.first { $0.organization.node(withID: id) != nil }
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
        mutateOrganization(ofPackID: state.id) { $0.removeNode(id: id) }
        refresh()
    }

    /// Copies a template's bundle under a fresh identity. Without a
    /// destination the copy lands beside the original when its pack is
    /// editable, otherwise in the personal pack — the "duplicate out of a
    /// read-only pack" gesture. An explicit duplicate gains a " Copy" suffix;
    /// a drag-copy between packs keeps the original name.
    @discardableResult
    func duplicate(id: UUID, to packRootURL: URL? = nil, renaming: Bool = true) -> UUID? {
        let sourceState = packState(containingEntry: id)
        let destinationTemplatesURL: URL
        if let packRootURL {
            guard let url = templatesURL(forPackRoot: packRootURL) else { return nil }
            destinationTemplatesURL = url
        } else if let sourceState, sourceState.isEditable {
            destinationTemplatesURL = sourceState.templatesURL
        } else {
            destinationTemplatesURL = personalTemplatesURL()
        }
        guard let copiedID = copyBundle(of: id, into: destinationTemplatesURL, renaming: renaming) else {
            return nil
        }
        // A copy beside its original slots in right after it; a copy landing
        // in another pack joins the end of that pack's tree via refresh.
        if let sourceState, sourceState.isEditable,
           destinationTemplatesURL.standardizedFileURL == sourceState.templatesURL.standardizedFileURL {
            mutateOrganization(ofPackID: sourceState.id) {
                _ = $0.insert(.template(copiedID), at: .after(nodeID: id))
            }
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
            try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
                .write(to: destinationURL.appending(path: "Info.plist"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            return nil
        }
        return copied.id
    }

    /// Physically moves a template's bundle into another editable pack.
    @discardableResult
    func moveTemplate(id: UUID, toPackRoot packRootURL: URL?) -> Bool {
        guard let sourceState = packState(containingEntry: id), sourceState.isEditable,
              let destinationTemplatesURL = templatesURL(forPackRoot: packRootURL),
              destinationTemplatesURL.standardizedFileURL != sourceState.templatesURL.standardizedFileURL else {
            return false
        }
        let fileManager = FileManager.default
        let sourceURL = bundleURL(forID: id)
        let destinationURL = destinationTemplatesURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: destinationTemplatesURL, withIntermediateDirectories: true)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            return false
        }
        mutateOrganization(ofPackID: sourceState.id) { $0.removeNode(id: id) }
        refresh()
        return true
    }

    /// Moves a folder — its organization subtree and every bundle inside —
    /// into another editable pack, keeping the arrangement intact.
    @discardableResult
    func moveFolder(id: UUID, toPackRoot packRootURL: URL?, at placement: ReusablePartPlacement = .end) -> Bool {
        guard let sourceState = packState(containingNode: id), sourceState.isEditable,
              case .folder? = sourceState.organization.node(withID: id),
              let targetState = editablePackState(forRoot: packRootURL),
              targetState.id != sourceState.id else {
            return false
        }
        var transplanted: TemplateLibraryNode?
        mutateOrganization(ofPackID: sourceState.id) { transplanted = $0.removeNode(id: id) }
        guard let transplanted else { return false }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: targetState.templatesURL, withIntermediateDirectories: true)
        for templateID in transplanted.templateIDs {
            let sourceURL = bundleURL(forID: templateID)
            let destinationURL = targetState.templatesURL.appending(path: templateID.uuidString, directoryHint: .isDirectory)
            try? fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
        mutateOrganization(ofPackID: targetState.id) { _ = $0.insert(transplanted, at: placement) }
        refresh()
        return true
    }

    /// Recreates a folder from a read-only pack inside an editable one:
    /// fresh folder identities, freshly copied bundles, same names and
    /// arrangement. The source is untouched.
    @discardableResult
    func copyFolder(id: UUID, toPackRoot packRootURL: URL?, at placement: ReusablePartPlacement = .end) -> Bool {
        guard let sourceState = packState(containingNode: id),
              case .folder? = sourceState.organization.node(withID: id),
              let targetState = editablePackState(forRoot: packRootURL) else {
            return false
        }
        func copied(_ node: TemplateLibraryNode) -> TemplateLibraryNode? {
            switch node {
            case .template(let templateID):
                return copyBundle(of: templateID, into: targetState.templatesURL, renaming: false)
                    .map(TemplateLibraryNode.template)
            case .folder(let folder):
                return .folder(TemplateLibraryFolder(
                    name: folder.name,
                    children: folder.children.compactMap(copied)
                ))
            }
        }
        guard let source = sourceState.organization.node(withID: id),
              let replica = copied(source) else { return false }
        mutateOrganization(ofPackID: targetState.id) { _ = $0.insert(replica, at: placement) }
        refresh()
        return true
    }

    private func editablePackState(forRoot packRootURL: URL?) -> PackState? {
        guard let packRootURL else { return packStates.first(where: \.isEditable) }
        return packStates.first {
            $0.rootURL?.standardizedFileURL == packRootURL.standardizedFileURL && $0.isEditable
        }
    }

    // MARK: Folders and ordering

    @discardableResult
    func createFolder(
        name: String,
        inPackRoot packRootURL: URL? = nil,
        at placement: ReusablePartPlacement = .end
    ) -> UUID? {
        let targetID: String?
        if let packRootURL {
            targetID = packStates.first {
                $0.rootURL?.standardizedFileURL == packRootURL.standardizedFileURL && $0.isEditable
            }?.id
        } else {
            targetID = packStates.first(where: \.isEditable)?.id
        }
        guard let targetID else { return nil }
        let folder = TemplateLibraryFolder(name: name)
        var created = false
        mutateOrganization(ofPackID: targetID) {
            created = $0.insert(.folder(folder), at: placement)
        }
        refresh()
        return created ? folder.id : nil
    }

    func renameFolder(id: UUID, to name: String) {
        guard let state = packState(containingNode: id), state.isEditable else { return }
        mutateOrganization(ofPackID: state.id) { _ = $0.renameFolder(id: id, to: name) }
        refresh()
    }

    /// Deletes a folder and every template bundle inside it.
    func deleteFolder(id: UUID) {
        guard let state = packState(containingNode: id), state.isEditable,
              case .folder(let folder)? = state.organization.node(withID: id) else { return }
        for templateID in folder.children.flatMap(\.templateIDs) {
            let url = bundleURL(forID: templateID)
            if url.deletingLastPathComponent().standardizedFileURL == state.templatesURL.standardizedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        mutateOrganization(ofPackID: state.id) { $0.removeNode(id: id) }
        refresh()
    }

    /// Reorders within the node's own pack; crossing packs is `moveTemplate`.
    @discardableResult
    func moveNode(id: UUID, to placement: ReusablePartPlacement) -> Bool {
        guard let state = packState(containingNode: id), state.isEditable else { return false }
        var moved = false
        mutateOrganization(ofPackID: state.id) { moved = $0.move(id: id, to: placement) }
        refresh()
        return moved
    }

    private func mutateOrganization(
        ofPackID packID: String,
        _ mutation: (inout [TemplateLibraryNode]) -> Void
    ) {
        guard let index = packStates.firstIndex(where: { $0.id == packID }) else { return }
        mutation(&packStates[index].organization)
        guard packStates[index].isEditable else { return }
        saveOrganization(packStates[index].organization, at: packStates[index].organizationURL)
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

    private func loadOrganization(at url: URL) -> [TemplateLibraryNode] {
        guard let data = try? Data(contentsOf: url),
              let nodes = try? FoundryDocument.decoder.decode([TemplateLibraryNode].self, from: data) else {
            return []
        }
        return nodes
    }

    private func saveOrganization(_ organization: [TemplateLibraryNode], at url: URL) {
        guard let data = try? FoundryDocument.encoder.encode(organization) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
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
