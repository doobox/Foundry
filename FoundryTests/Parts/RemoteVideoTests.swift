import Foundation
import Testing
@testable import Foundry

struct RemoteVideoTests {
    @Test(arguments: [200, 404])
    func rejectsWebPagesAndHTTPErrorsAndRemovesDownload(status: Int) async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".html")
        try Data("<html>Not a video</html>".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let url = try #require(URL(string: "https://example.com/movie.mp4"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "text/html"]))
        do {
            let imported = try await RemoteVideoImport.download(url, fetch: { _ in (file, response) })
            defer { try? FileManager.default.removeItem(at: imported.deletingLastPathComponent()) }
            Issue.record("A web page must not be imported as a video")
        } catch is URLError {
            #expect(FileManager.default.fileExists(atPath: file.path) == false)
        }
    }
    @Test(arguments: ["https://example.com/movie.mp4?token=abc&v=2", "http://example.com/video.webm", " https://example.com/download?id=1 "])
    func acceptsWebFileAddresses(_ source: String) {
        #expect(RemoteVideoImport.webURL(source) != nil)
    }

    @Test(arguments: ["", "file:///tmp/movie.mp4", "javascript:alert(1)", "ftp://example.com/a.mp4", "https:///", "movie.mp4"])
    func rejectsNonWebAddresses(_ source: String) {
        #expect(RemoteVideoImport.webURL(source) == nil)
    }

    @Test @MainActor func linkedVideoExportsURLAndCanvasPlaceholderWithoutAsset() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: root.appending(path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Video"))
        let previous = PartType.video.definition.package
        PartRegistry.register(package)
        defer {
            if let previous { PartRegistry.register(previous) }
            else { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        }
        var part = PartNode(type: .video)
        part.setProperty(.init(rawValue: "source"), value: .url("https://example.com/movie.mp4?token=abc&v=2"))
        let site = Site(name: "Remote video", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(canvas.contains("Linked video"))
        #expect(canvas.contains("data-foundry-video-drop-zone"))
        #expect(canvas.contains("src=\"https://example.com/movie.mp4") == false)
        let export = StaticSiteRenderer().render(site: site)
        #expect(export.errors.isEmpty)
        let page = try #require(export.files.first { $0.path == "index.html" })
        #expect(String(decoding: page.data, as: UTF8.self).contains("src=\"https://example.com/movie.mp4?token=abc&amp;v=2\""))
        #expect(export.files.contains { $0.path.hasSuffix(".mp4") } == false)
    }

    @Test func remoteMetadataIsEmptyAndPlaybackOptionsStillApply() {
        var values: [String: PartPackageValue] = [:]
        PartVideoTemplateValues.insert(propertyID: "film", href: "https://example.com/a.mp4", poster: "", asset: nil, into: &values)
        #expect(values["film.href"] == .string("https://example.com/a.mp4"))
        #expect(values["film.poster"] == .string(""))
        #expect(values["film.duration"] == .string(""))
        #expect(values["film.width"] == .string(""))
        #expect(values["film.attributes"]?.stringValue.contains("controls") == true)
    }
}
