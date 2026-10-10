import Foundation
import Synchronization

/// Document-local canvas artifacts. A render session can only read/write the
/// environment it was created for; an older background render cannot poison a
/// newer session. Nodes are compared by value, never just by their identifier.
nonisolated final class CanvasRenderCache: Sendable {
    struct Environment: Equatable, Sendable {
        let site: Site?
        let page: Page
        let routes: [String]
        let theme: Theme
        let assets: ProjectAssetContents
        let breakpoint: ResponsiveBreakpoint
        let appearance: SiteAppearance
        let packageRevision: Int

        init(site: Site?, page: Page, theme: Theme, assets: ProjectAssetContents,
             breakpoint: ResponsiveBreakpoint, appearance: SiteAppearance, packageRevision: Int,
             knownRoutes: [String]? = nil) {
            // Part content is tracked by artifact keys. Everything outside it
            // remains an invalidation input, including resolved PHP routes.
            routes = knownRoutes ?? site.map { site in site.pages.map {
                StaticSiteRenderer.urlPath(for: $0, pages: site.pages, folders: site.pageFolders)
            }} ?? []
            if var contextSite = site {
                for index in contextSite.pages.indices { contextSite.pages[index].parts = [] }
                // Package availability is versioned separately by the catalog;
                // adding a lock for a new instance does not change other parts.
                contextSite.partPackages = []
                self.site = contextSite
            } else {
                self.site = nil
            }
            var contextPage = page
            contextPage.parts = []
            self.page = contextPage
            self.theme = theme
            self.assets = assets
            self.breakpoint = breakpoint
            self.appearance = appearance
            self.packageRevision = packageRevision
        }
    }

    enum Kind: Hashable, Sendable { case html, css, script, properties }
    struct Key: Equatable, Sendable {
        let node: PartNode
        var globalID: UUID? = nil
        var parentID: UUID? = nil
        var slot: PartPackageSlot? = nil
        var dropZone: String? = nil
    }
    enum Value: Sendable {
        case text(String)
        case properties([String: PartPackageValue])
    }
    private struct Address: Hashable { let id: UUID; let kind: Kind }
    private struct Entry { let key: Key; let value: Value }
    private struct State {
        var environment: Environment?
        var generation: UInt64 = 0
        var entries: [Address: Entry] = [:]
        var hits = 0
        var misses = 0
    }
    private let state = Mutex(State())

    struct Session: Sendable {
        fileprivate let cache: CanvasRenderCache
        fileprivate let generation: UInt64

        func value(_ kind: Kind, key: Key, compute: () -> Value) -> Value {
            let address = Address(id: key.node.id, kind: kind)
            let existing: Value? = cache.state.withLock { state in
                guard state.generation == generation else { return nil }
                if let entry = state.entries[address], entry.key == key {
                    state.hits += 1
                    return entry.value
                }
                state.misses += 1
                return nil
            }
            if let existing { return existing }
            let result = compute()
            cache.state.withLock { state in
                guard state.generation == generation, !Task.isCancelled else { return }
                state.entries[address] = Entry(key: key, value: result)
            }
            return result
        }
    }

    func session(environment: Environment, liveIDs: Set<UUID>) -> Session {
        state.withLock { state in
            if state.environment != environment {
                state.environment = environment
                state.generation &+= 1
                state.entries.removeAll(keepingCapacity: true)
            } else {
                state.entries = state.entries.filter { liveIDs.contains($0.key.id) }
            }
            return Session(cache: self, generation: state.generation)
        }
    }

    var statistics: (hits: Int, misses: Int) {
        state.withLock { ($0.hits, $0.misses) }
    }
}
