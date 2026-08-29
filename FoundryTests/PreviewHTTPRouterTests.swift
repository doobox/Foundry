import Foundation
import Testing
@testable import Foundry

struct PreviewHTTPRouterTests {
    private let bundle = SiteExportBundle(files: [
        .init(path: "index.html", contents: "<h1>Home</h1>"),
        .init(path: "about/index.html", contents: "<h1>About</h1>"),
        .init(path: "assets/site.css", contents: "body{}")
    ])

    @Test
    func mapsRootNestedRoutesAndAssets() {
        #expect(PreviewHTTPRouter.safeBundlePath("/") == "index.html")
        #expect(PreviewHTTPRouter.safeBundlePath("/about/") == "about/index.html")
        #expect(PreviewHTTPRouter.safeBundlePath("/assets/site.css?v=1") == "assets/site.css")
    }

    @Test
    func rejectsPathTraversal() {
        #expect(PreviewHTTPRouter.safeBundlePath("/../secret") == nil)
        #expect(PreviewHTTPRouter.safeBundlePath("/%2E%2E/secret") == nil)
        #expect(PreviewHTTPRouter.safeBundlePath("/assets\\secret") == nil)
    }

    @Test
    func servesHTMLAndCSSWithCorrectHeaders() throws {
        let html = PreviewHTTPRouter.response(for: Data("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8), bundle: bundle)
        let css = PreviewHTTPRouter.response(for: Data("GET /assets/site.css HTTP/1.1\r\n\r\n".utf8), bundle: bundle)
        let htmlString = try #require(String(data: html, encoding: .utf8))
        let cssString = try #require(String(data: css, encoding: .utf8))

        #expect(htmlString.contains("HTTP/1.1 200 OK"))
        #expect(htmlString.contains("Content-Type: text/html; charset=utf-8"))
        #expect(htmlString.hasSuffix("<h1>Home</h1>"))
        #expect(cssString.contains("Content-Type: text/css; charset=utf-8"))
    }

    @Test
    func livePreviewPublishesRevisionAndReloadScript() throws {
        let revision = PreviewHTTPRouter.response(
            for: Data("GET /__foundry/revision HTTP/1.1\r\n\r\n".utf8),
            bundle: bundle,
            liveReloadRevision: 42
        )
        let html = PreviewHTTPRouter.response(
            for: Data("GET / HTTP/1.1\r\n\r\n".utf8),
            bundle: bundle,
            liveReloadRevision: 42
        )

        #expect(try #require(String(data: revision, encoding: .utf8)).hasSuffix("42"))
        #expect(try #require(String(data: html, encoding: .utf8)).contains("/__foundry/revision"))
    }

    @Test
    func returnsNotFoundAndRejectsUnsupportedMethods() throws {
        let missing = PreviewHTTPRouter.response(for: Data("GET /missing HTTP/1.1\r\n\r\n".utf8), bundle: bundle)
        let post = PreviewHTTPRouter.response(for: Data("POST / HTTP/1.1\r\n\r\n".utf8), bundle: bundle)

        #expect(try #require(String(data: missing, encoding: .utf8)).contains("404 Not Found"))
        #expect(try #require(String(data: post, encoding: .utf8)).contains("405 Method Not Allowed"))
    }
}
