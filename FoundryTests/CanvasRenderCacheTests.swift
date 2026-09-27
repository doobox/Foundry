import Foundation
import Testing
@testable import Foundry

struct CanvasRenderCacheTests {
    @Test @MainActor func cancelledExportDoesNotReturnPartialFiles() async {
        let task = Task { @MainActor in StaticSiteRenderer().render(site: Site(name: "Cancelled", pages: [Page(title: "Home", slug: "index", parts: [])])) }
        task.cancel()
        let result = await task.value
        #expect(result.files.isEmpty)
        #expect(result.errors.isEmpty == false)
    }

    @Test func keysTrackContentAndRelationshipsAndPruneRemovedParts() {
        let cache = CanvasRenderCache()
        let page = Page(title: "Test", slug: "index", parts: [])
        let environment = CanvasRenderCache.Environment(site: nil, page: page, framework: .standard,
            assets: [:], breakpoint: .mobile, appearance: .light, packageRevision: 0)
        var node = PartNode(type: .paragraph)
        let session = cache.session(environment: environment, liveIDs: [node.id])
        var computations = 0
        func read(_ key: CanvasRenderCache.Key) {
            _ = session.value(.html, key: key) { computations += 1; return .text("rendered") }
        }
        read(.init(node: node))
        read(.init(node: node))
        #expect(computations == 1)
        node.name = "Changed"
        read(.init(node: node))
        read(.init(node: node, parentID: UUID()))
        #expect(computations == 3)
        _ = cache.session(environment: environment, liveIDs: [])
        read(.init(node: node))
        #expect(computations == 4)
    }

    @Test func obsoleteSessionsCannotOverwriteNewEnvironment() {
        let cache = CanvasRenderCache()
        let node = PartNode(type: .paragraph)
        let page = Page(title: "Test", slug: "index", parts: [node])
        func environment(_ revision: Int) -> CanvasRenderCache.Environment {
            .init(site: nil, page: page, framework: .standard, assets: [:], breakpoint: .mobile,
                  appearance: .light, packageRevision: revision)
        }
        let old = cache.session(environment: environment(0), liveIDs: [node.id])
        let new = cache.session(environment: environment(1), liveIDs: [node.id])
        _ = new.value(.html, key: .init(node: node)) { .text("new") }
        _ = old.value(.html, key: .init(node: node)) { .text("old") }
        let result = new.value(.html, key: .init(node: node)) { Issue.record("New result was lost"); return .text("missing") }
        guard case .text(let text) = result else { Issue.record("Wrong artifact kind"); return }
        #expect(text == "new")
    }
}
