import Foundation
import Testing
@testable import Foundry

struct PreviewPageNavigationTests {
    @Test @MainActor func routesMatchOnlyProjectPages() {
        var home = Page(title: "Home", slug: "index", parts: [])
        var about = Page(title: "About", slug: "about", parts: [])
        let site = Site(name: "Routes", pages: [home, about])
        #expect(PreviewPageNavigation.pageID(for: "/", in: site) == home.id)
        #expect(PreviewPageNavigation.pageID(for: "/about/?q=test", in: site) == about.id)
        #expect(PreviewPageNavigation.pageID(for: "/about/index.html", in: site) == about.id)
        for path in ["https://example.com/about/", "//example.com/about/", "/../about/", "/files/site.css", "/missing/"] {
            #expect(PreviewPageNavigation.pageID(for: path, in: site) == nil)
        }
        home.filenameOverride = "index.php"
        about.filenameOverride = "details.html"
        let custom = Site(name: "Custom routes", pages: [home, about])
        #expect(PreviewPageNavigation.pageID(for: "/", in: custom) == home.id)
        #expect(PreviewPageNavigation.pageID(for: "/about/details.html", in: custom) == about.id)
        #expect(PreviewPageNavigation.pageID(for: "/about/index.html", in: custom) == nil)
    }

    @Test(.timeLimit(.minutes(1))) func pageVisitReportsSessionAndPathWithoutPublishing() async throws {
        let server = PreviewServer()
        let visits = await server.pageVisits()
        let url = try await server.publish(.init(files: [.init(path: "index.html", contents: "<body>Preview</body>")]))
        let snapshot = await server.currentSnapshot()
        let session = UUID()
        var endpoint = URLComponents(url: url.appending(path: "__foundry/page-visit"), resolvingAgainstBaseURL: false)!
        endpoint.queryItems = [.init(name: "session", value: session.uuidString), .init(name: "path", value: "/about/")]
        let (_, response) = try await URLSession.shared.data(from: #require(endpoint.url))
        #expect((response as? HTTPURLResponse)?.statusCode == 204)
        #expect(await server.currentSnapshot()?.root == snapshot?.root)
        await server.stop()
        var iterator = visits.makeAsyncIterator()
        let visit = try #require(await iterator.next())
        #expect(visit.0 == session)
        #expect(visit.1 == "/about/")
        #expect(await iterator.next() == nil)
    }

    @Test(.timeLimit(.minutes(1))) func replacingSubscriptionFinishesThePreviousConsumer() async {
        let server = PreviewServer()
        let old = await server.pageVisits()
        let new = await server.pageVisits()
        var oldIterator = old.makeAsyncIterator()
        #expect(await oldIterator.next() == nil)
        await server.stop()
        var newIterator = new.makeAsyncIterator()
        #expect(await newIterator.next() == nil)
    }
}
