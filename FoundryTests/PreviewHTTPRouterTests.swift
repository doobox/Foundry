import Foundation
import Testing
@testable import Foundry

struct PreviewHTTPRouterTests {
    @Test
    func diskPreviewExecutesPHPAndRefreshes() async throws {
        let server = PreviewServer()
        for text in ["FirstPHP", "SecondPHP"] {
            let snapshot = try PreviewDiskSnapshot.build { emit in
                try emit(.init(path: "index.php", contents: "<?php echo '<body>\(text)</body>'; ?>"))
            }
            let url = try await server.publish(snapshot)
            let (data, response) = try await URLSession.shared.data(from: url)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(String(decoding: data, as: UTF8.self).contains(text))
            #expect(!String(decoding: data, as: UTF8.self).contains("<?php"))
        }
        await server.stop()
    }

    @Test
    func cancelledGenerationDoesNotReplaceWorkingPreview() async throws {
        let server = PreviewServer()
        let working = try PreviewDiskSnapshot.build { try $0(.init(path: "index.html", contents: "Working")) }
        _ = try await server.publish(working)
        let task = Task.detached {
            // Wait until the caller cancels, without racing a completed generation.
            while !Task.isCancelled { await Task.yield() }
            return try PreviewDiskSnapshot.build { try $0(.init(path: "index.html", contents: "Stale")) }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled generation must throw")
        } catch is CancellationError { }
        #expect(await server.currentSnapshot()?.root == working.root)
        await server.stop()
    }

    @Test
    func largeProgressivePreviewIndexContainsNoAssetBytes() throws {
        let clock = ContinuousClock()
        let start = clock.now
        let snapshot = try PreviewDiskSnapshot.build { emit in
            for index in 0..<64 {
                try emit(.init(path: "assets/\(index).bin", data: Data(repeating: UInt8(index), count: 1_024 * 1_024)))
            }
        }
        #expect(snapshot.fingerprints.count == 64)
        #expect(snapshot.index.files.allSatisfy { $0.data.isEmpty })
        #expect(try Data(contentsOf: snapshot.root.appending(path: "assets/63.bin")).count == 1_024 * 1_024)
        print("64 MiB progressive preview: \(start.duration(to: clock.now))")
    }
    @Test @MainActor
    func progressivePreviewMatchesExportAndKeepsGenerationsIsolated() throws {
        let site = TestSiteFixtures.populatedSite()
        let renderer = StaticSiteRenderer(environment: .preview)
        let expected = renderer.render(site: site)
        try expected.validate()
        var first: PreviewDiskSnapshot? = try PreviewDiskSnapshot.build { emit in
            try renderer.generate(site: site, assets: [:], emit: emit)
        }
        let root = try #require(first?.root)
        #expect(first?.fingerprints.count == expected.files.count)
        for file in expected.files {
            #expect(try Data(contentsOf: root.appending(path: file.path)) == file.data)
        }
        let second = try PreviewDiskSnapshot.build(previous: first) { emit in
            for file in expected.files { try emit(file) }
        }
        let path = try #require(expected.files.first?.path)
        try Data("changed".utf8).write(to: second.root.appending(path: path))
        #expect(try Data(contentsOf: root.appending(path: path)) == expected.files.first?.data)
        first = nil
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test
    func diskPreviewStreamsRangesAndSeparatesProjects() async throws {
        let bytes = Data(repeating: 97, count: 200_000)
        let first = try PreviewDiskSnapshot.build { emit in
            try emit(.init(path: "index.html", contents: "<body>First</body>"))
            try emit(.init(path: "assets/video.mp4", data: bytes))
        }
        let second = try PreviewDiskSnapshot.build { emit in
            try emit(.init(path: "index.html", contents: "<body>Second</body>"))
        }
        let serverA = PreviewServer()
        let serverB = PreviewServer()
        let urlA = try await serverA.publish(first)
        let urlB = try await serverB.publish(second)
        let (html, _) = try await URLSession.shared.data(from: urlA)
        #expect(String(decoding: html, as: UTF8.self).contains("First"))
        let (other, _) = try await URLSession.shared.data(from: urlB)
        #expect(String(decoding: other, as: UTF8.self).contains("Second"))
        let (whole, _) = try await URLSession.shared.data(from: urlA.appending(path: "assets/video.mp4"))
        #expect(whole == bytes)
        var request = URLRequest(url: urlA.appending(path: "assets/video.mp4"))
        request.setValue("bytes=65530-65550", forHTTPHeaderField: "Range")
        let (range, response) = try await URLSession.shared.data(for: request)
        #expect(range == bytes.subdata(in: 65530..<65551))
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        request.httpMethod = "HEAD"
        let (head, _) = try await URLSession.shared.data(for: request)
        #expect(head.isEmpty)
        await serverA.stop()
        await serverB.stop()
    }

    @Test
    func diskPreviewRejectsConflictsAndUnsafePaths() {
        #expect(throws: (any Error).self) {
            try PreviewDiskSnapshot.build { emit in
                try emit(.init(path: "../escape", contents: "bad"))
            }
        }
        #expect(throws: (any Error).self) {
            try PreviewDiskSnapshot.build { emit in
                try emit(.init(path: "index.html", contents: "one"))
                try emit(.init(path: "index.html", contents: "two"))
            }
        }
    }
    private let bundle = SiteExportBundle(files: [
        .init(path: "index.html", contents: "<h1>Home</h1>"),
        .init(path: "about/index.html", contents: "<h1>About</h1>"),
        .init(path: "assets/site.css", contents: "body{}")
    ])

    @Test
    func staticPreviewDoesNotRequireFilesystemStaging() {
        #expect(!PreviewServer.requiresPHPDocumentRoot(for: bundle))
    }

    @Test
    func phpPreviewRequiresFilesystemStaging() {
        let phpBundle = SiteExportBundle(files: [
            .init(path: "index.PHP", contents: "<?php echo 'Hello';")
        ])

        #expect(PreviewServer.requiresPHPDocumentRoot(for: phpBundle))
    }

    @Test
    func mapsRootNestedRoutesAndAssets() {
        #expect(PreviewHTTPRouter.safeBundlePath("/") == "index.html")
        #expect(PreviewHTTPRouter.safeBundlePath("/about/") == "about/index.html")
        #expect(PreviewHTTPRouter.safeBundlePath("/assets/site.css?v=1") == "assets/site.css")
    }

    @Test
    func parsesCompletePHPPostRequest() throws {
        let header = Data("POST /contact/?source=test HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 7\r\n\r\n".utf8)
        var partial = header
        partial.append(Data("name".utf8))
        var complete = header
        complete.append(Data("name=Jo".utf8))

        #expect(!PreviewHTTPRequest.isComplete(partial))
        #expect(PreviewHTTPRequest.isComplete(complete))
        let request = try #require(PreviewHTTPRequest(data: complete))
        #expect(request.method == "POST")
        #expect(request.target == "/contact/")
        #expect(request.query == "source=test")
        #expect(request.headers["content-type"] == "application/x-www-form-urlencoded")
        #expect(String(data: request.body, encoding: .utf8) == "name=Jo")
    }

    @Test
    func convertsCGIResponseToHTTPAndInjectsLiveReload() throws {
        let cgi = PHPPreviewCGIResponse(
            statusCode: 201,
            headers: ["Content-Type": "text/html; charset=utf-8", "X-PHP": "working"],
            body: Data("<body>Created</body>".utf8),
            diagnostics: ""
        )

        let response = PreviewHTTPRouter.response(for: cgi, method: "POST", revision: 9)
        let text = try #require(String(data: response, encoding: .utf8))

        #expect(text.contains("HTTP/1.1 201 Created"))
        #expect(text.contains("X-PHP: working\r\n"))
        #expect(text.contains("/__foundry/events"))
        #expect(text.contains("Created"))
        let parts = text.components(separatedBy: "\r\n\r\n")
        #expect(parts.count == 2)
        let body = try #require(parts.last)
        #expect(!body.contains("Cache-Control:"))
        #expect(!body.contains("Connection:"))
        #expect(!body.contains("X-Content-Type-Options:"))
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
    func servesPhpIndexAtTheCleanPageRoute() throws {
        let phpBundle = SiteExportBundle(files: [
            .init(path: "index.php", contents: "<h1>PHP Home</h1>")
        ])

        let response = PreviewHTTPRouter.response(
            for: Data("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8),
            bundle: phpBundle
        )
        let responseString = try #require(String(data: response, encoding: .utf8))

        #expect(responseString.contains("HTTP/1.1 200 OK"))
        #expect(responseString.contains("Content-Type: text/html; charset=utf-8"))
        #expect(responseString.hasSuffix("<h1>PHP Home</h1>"))
    }

    @Test
    func livePreviewUsesASingleEventStreamForReloads() throws {
        let sessionID = UUID()
        let html = PreviewHTTPRouter.response(
            for: Data("GET /?\(foundryPreviewSessionQueryName)=\(sessionID.uuidString) HTTP/1.1\r\n\r\n".utf8),
            bundle: bundle,
            liveReloadRevision: 42
        )

        let text = try #require(String(data: html, encoding: .utf8))
        #expect(text.contains("new EventSource('/__foundry/events?revision='"))
        #expect(text.contains("addEventListener('reload'"))
        #expect(text.contains("addEventListener('navigate'"))
        #expect(text.contains("/__foundry/navigation-ack?id="))
        #expect(text.contains(sessionID.uuidString))
        #expect(!text.contains("setInterval"))
        #expect(!text.contains("fetch('/__foundry/revision'"))
    }

    @Test
    func eventStreamRequestKeepsItsRevisionQuery() throws {
        let sessionID = UUID()
        let request = try #require(PreviewHTTPRequest(data: Data(
            "GET /__foundry/events?revision=42&\(foundryPreviewSessionQueryName)=\(sessionID.uuidString) HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8
        )))

        #expect(request.target == "/__foundry/events")
        #expect(request.queryValue(named: "revision") == "42")
        #expect(request.previewSessionID == sessionID)
    }

    @Test
    func returnsNotFoundAndRejectsUnsupportedMethods() throws {
        let missing = PreviewHTTPRouter.response(for: Data("GET /missing HTTP/1.1\r\n\r\n".utf8), bundle: bundle)
        let post = PreviewHTTPRouter.response(for: Data("POST / HTTP/1.1\r\n\r\n".utf8), bundle: bundle)

        #expect(try #require(String(data: missing, encoding: .utf8)).contains("404 Not Found"))
        #expect(try #require(String(data: post, encoding: .utf8)).contains("405 Method Not Allowed"))
    }
}
