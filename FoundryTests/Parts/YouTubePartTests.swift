import Foundation
import Testing
@testable import Foundry

struct YouTubePartTests {
    @Test(arguments: ["https://youtu.be/M7lc1UVf-VE", "https://youtube.com/watch?v=M7lc1UVf-VE", "https://m.youtube.com/shorts/M7lc1UVf-VE", "https://www.youtube-nocookie.com/embed/M7lc1UVf-VE"])
    func acceptsVideoLinks(_ source: String) {
        #expect(YouTubeVideo.id(from: source) == "M7lc1UVf-VE")
    }

    @Test(arguments: ["https://youtube.com.evil.com/watch?v=M7lc1UVf-VE", "https://youtube.com@evil.com/watch?v=M7lc1UVf-VE", "javascript:alert(1)", "https://youtu.be/invalid", "https://youtube.com/playlist?list=abc"])
    func rejectsInvalidLinks(_ source: String) {
        #expect(YouTubeVideo.id(from: source) == nil)
    }

    @Test func playbackParameters() {
        let source = YouTubeVideo.embed(for: "M7lc1UVf-VE", controls: false, loops: true, start: 42.9)
        #expect(source.contains("controls=0"))
        #expect(source.contains("loop=1&playlist=M7lc1UVf-VE"))
        #expect(source.contains("start=42"))
    }
    @Test(arguments: [false, true], [false, true]) @MainActor
    func canvasIsInertAndExportIncludesPlayer(posterFirst: Bool, customPoster: Bool) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: root.appending(path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Video"))
        let previous = PartType.video.definition.package
        PartRegistry.register(package)
        defer {
            if let previous { PartRegistry.register(previous) }
            else { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        }
        var part = PartNode(type: .video)
        part.setProperty(.init(rawValue: "source"), value: .url("https://youtu.be/M7lc1UVf-VE"))
        part.setProperty(PartVideoTemplateValues.posterFirstPropertyKey(for: "source"), value: .boolean(posterFirst))
        if customPoster {
            part.setProperty(PartVideoTemplateValues.posterPropertyKey(for: "source"), value: .url("https://example.com/custom.jpg"))
        }
        let site = Site(name: "YouTube", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(canvas.contains(customPoster ? "https://example.com/custom.jpg" : "https://i.ytimg.com/vi/M7lc1UVf-VE/maxresdefault.jpg"))
        #expect(canvas.contains("data-foundry-youtube-thumbnail=\"M7lc1UVf-VE\"") == !customPoster)
        #expect(canvas.contains("object-fit:cover"))
        #expect(canvas.contains("data-foundry-video-drop-zone"))
        #expect(canvas.contains("<iframe") == false)
        #expect(canvas.contains("document.createElement('iframe')") == false)
        let export = StaticSiteRenderer().render(site: site)
        #expect(export.errors.isEmpty)
        let page = try #require(export.files.first { $0.path == "index.html" })
        let html = String(decoding: page.data, as: UTF8.self)
        #expect(html.contains("<iframe") == !posterFirst)
        #expect(html.contains("data-foundry-youtube-play=\"") == posterFirst)
        if posterFirst {
            #expect(html.contains("button.replaceWith(player)"))
            #expect(html.contains(customPoster ? "https://example.com/custom.jpg" : "maxresdefault.jpg"))
        }
        #expect(export.files.contains { String(decoding: $0.data, as: UTF8.self).contains("https://www.youtube-nocookie.com/embed/") })
    }
}
