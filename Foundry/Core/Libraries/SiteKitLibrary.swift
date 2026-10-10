import Foundation
import Observation

/// A starter project shipped in a pack's `Sites` directory: a `.foundry`
/// document plus optional card artwork and metadata. A kit is just a folder —
/// hand-authorable in Finder. Creating a project from a kit stamps a fresh
/// copy; the kit itself is never opened in place.
nonisolated struct SiteKit: Identifiable, Sendable {
    let itemURL: URL
    let documentURL: URL
    let title: String
    /// The one-line card description from the optional manifest.
    let details: String?
    let previewURL: URL?
    let packTitle: String
    /// Kits in non-personal development packs group under Development in the
    /// chooser, so authors test the real flow without installing.
    let isDevelopment: Bool

    var id: String { itemURL.standardizedFileURL.path }
}

nonisolated enum SiteKitStore {
    /// Reads one kit folder. The manifest is optional — a folder holding a
    /// `.foundry` document is a complete kit, titled by its name. A manifest
    /// that exists but cannot be parsed throws so installs can reject bad
    /// packs; browsing uses `entry(at:)` and skips instead.
    static func load(from itemURL: URL, packTitle: String, isDevelopment: Bool) throws -> SiteKit {
        var manifest: [String: Any] = [:]
        let manifestURL = itemURL.appending(path: "manifest.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            manifest = parsed
        }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: itemURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard let documentURL = children.first(where: {
            $0.pathExtension.caseInsensitiveCompare("foundry") == .orderedSame
        }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        // Card artwork matches theme previews: PNG, JPEG, or WebP.
        let previewURL = ["png", "jpg", "jpeg", "webp"]
            .map { itemURL.appending(path: "preview.\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        return SiteKit(
            itemURL: itemURL.standardizedFileURL,
            documentURL: documentURL.standardizedFileURL,
            title: manifest["title"] as? String ?? itemURL.lastPathComponent,
            details: manifest["description"] as? String,
            previewURL: previewURL,
            packTitle: packTitle,
            isDevelopment: isDevelopment
        )
    }

    static func entry(at itemURL: URL, packTitle: String, isDevelopment: Bool) -> SiteKit? {
        try? load(from: itemURL, packTitle: packTitle, isDevelopment: isDevelopment)
    }
}

/// Site kits resolved from every installed pack, open dev pack, and the
/// built-in pack — the New Project chooser's content. Kits are read-only
/// sources: creating a project decodes the kit's document and stamps a fresh
/// site identity into a new untitled document.
@MainActor
@Observable
final class SiteKitLibrary {
    static let shared = SiteKitLibrary()

    private(set) var kits: [SiteKit] = []
    private var externalDevelopmentPackURLs: Set<URL> = []
    /// Kits load lazily: nothing scans until the New Project chooser first
    /// appears, so the launch path never pays for packs it may not show.
    private var hasScanned = false
    /// Injected in tests: fixed pack roots instead of the installed catalog.
    private let fixedRootURLs: [URL]?

    init(fixedRootURLs: [URL]? = nil) {
        self.fixedRootURLs = fixedRootURLs
        if fixedRootURLs != nil {
            refresh()
        }
    }

    /// Installed packs and My Library — the chooser's "Your Library" section.
    var libraryKits: [SiteKit] { kits.filter { !$0.isDevelopment } }

    /// Kits inside open dev packs — the chooser's "Development" section.
    var developmentKits: [SiteKit] { kits.filter(\.isDevelopment) }

    func openDevelopmentPack(at url: URL) {
        externalDevelopmentPackURLs.insert(url.standardizedFileURL)
        refreshIfScanned()
    }

    /// Pack catalog reloads keep an already-presented chooser fresh without
    /// triggering the first scan at launch.
    func refreshIfScanned() {
        guard hasScanned else { return }
        refresh()
    }

    func refresh() {
        hasScanned = true
        var roots: [(url: URL, isPersonal: Bool)] = []
        if let fixedRootURLs {
            roots = fixedRootURLs.map { ($0.standardizedFileURL, false) }
        } else {
            if let personal = try? FoundryPackLoader.personalDevelopmentPackURL() {
                roots.append((personal.standardizedFileURL, true))
            }
            let installed = (try? FoundryPackLoader.installedPacksURL())
                .map { FoundryPackLoader.packURLs(in: $0) } ?? []
            roots += externalDevelopmentPackURLs
                .subtracting(roots.map(\.url))
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                .map { ($0, false) }
            roots += installed
                .filter { url in !roots.contains { $0.url == url.standardizedFileURL } }
                .map { ($0, false) }
            if let builtIn = FoundryPackLoader.builtInPackURL() {
                roots.append((builtIn, false))
            }
        }
        var seenKitPaths: Set<String> = []
        kits = roots.flatMap { root -> [SiteKit] in
            guard let pack = try? FoundryPackLoader.load(from: root.url) else { return [] }
            let isDevelopment = root.url.pathExtension.lowercased() == "foundrydevpack" && !root.isPersonal
            let packTitle = pack.metadata.title ?? root.url.deletingPathExtension().lastPathComponent
            return pack.siteKitURLs.compactMap { itemURL in
                guard seenKitPaths.insert(itemURL.standardizedFileURL.path).inserted else { return nil }
                return SiteKitStore.entry(at: itemURL, packTitle: packTitle, isDevelopment: isDevelopment)
            }
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Decodes the kit's document and stamps it into a brand-new project:
    /// fresh site identity, factory publishing settings, empty publishing
    /// history — everything else exactly as the kit author saved it.
    nonisolated static func makeDocument(from kit: SiteKit) throws -> FoundryDocument {
        let wrapper = try FileWrapper(url: kit.documentURL, options: .immediate)
        var snapshot = try FoundryDocument.decodeSnapshot(from: wrapper)
        snapshot.site.prepareAsKitCopy(named: kit.title)
        // A fresh snapshot keeps the kit's asset bytes reachable but drops
        // any publishing manifests the author left behind.
        return FoundryDocument(
            snapshot: FoundryDocumentSnapshot(site: snapshot.site, byteStore: snapshot.byteStore)
        )
    }
}
