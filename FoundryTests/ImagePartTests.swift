import Foundation
import Testing
@testable import Foundry

@MainActor
struct ImagePartTests {
    private func imageSite(width: Int, height: Int, configure: (inout PartNode) -> Void = { _ in }) throws -> (Site, ProjectAsset, Data) {
        let data = try testPNG(width: width, height: height)
        let asset = ProjectAsset(filename: "hero.png", mediaType: "image/png", byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data), pixelWidth: width, pixelHeight: height)
        var part = PartNode.make(.image)
        part.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        part.setProperty(PartPackageAdapter.imageAltKey(for: "source"), value: .string("The harbour"))
        configure(&part)
        return (Site(name: "Image", pages: [Page(title: "Home", slug: "index", parts: [part])], assets: [asset]), asset, data)
    }

    @Test func exportOffersRenditionsWithTheirRealWidths() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let (site, asset, data) = try imageSite(width: 1000, height: 2000)
        let bundle = StaticSiteRenderer().render(site: site, assets: [asset.id: .init(asset: asset, data: data)])
        #expect(bundle.errors.isEmpty)
        let html = try #require(bundle.file(at: "index.html")?.contents)
        let id = asset.id.uuidString.lowercased()
        #expect(html.contains("srcset=\"assets/renditions/\(id)-480.png 240w, assets/renditions/\(id)-960.png 480w, assets/renditions/\(id)-1600.png 800w, assets/hero.png 1000w\""))
        #expect(html.contains("sizes=\"auto, 100vw\""))
        #expect(html.contains("loading=\"lazy\" decoding=\"async\""))
        #expect(html.contains("alt=\"The harbour\""))
        #expect(html.contains("img-fluid"))
        #expect(html.contains("<figure") == false)
        #expect(html.contains("data-foundry-") == false)
        #expect(bundle.file(at: "assets/renditions/\(id)-480.png") != nil)
    }

    @Test func smallImagesUseOriginalAndDecorativeImagesHaveEmptyAlt() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let (site, asset, data) = try imageSite(width: 300, height: 200) {
            $0.setProperty(.init(rawValue: "loading"), value: .choice("eager"))
            $0.setProperty(.init(rawValue: "decorative"), value: .boolean(true))
        }
        let bundle = StaticSiteRenderer().render(site: site, assets: [asset.id: .init(asset: asset, data: data)])
        let html = try #require(bundle.file(at: "index.html")?.contents)
        #expect(html.contains("srcset=\"assets/hero.png 300w, assets/hero.png 300w, assets/hero.png 300w, assets/hero.png 300w\""))
        #expect(html.contains("fetchpriority=\"high\""))
        #expect(html.contains("alt=\"\""))
        #expect(bundle.files.contains { $0.path.hasPrefix("assets/renditions/") } == false)
    }

    @Test func vectorImagesExportWithoutPhantomRenditions() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let data = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>"#.utf8)
        let asset = ProjectAsset(filename: "logo.svg", mediaType: "image/svg+xml", byteCount: data.count, contentDigest: "svg")
        var part = PartNode.make(.image)
        part.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        let site = Site(name: "Vector", pages: [Page(title: "Home", slug: "index", parts: [part])], assets: [asset])
        let bundle = StaticSiteRenderer().render(site: site, assets: [asset.id: .init(asset: asset, data: data)])
        #expect(bundle.errors.isEmpty)
        #expect(bundle.files.contains { $0.path.hasPrefix("assets/renditions/") } == false)
        let html = try #require(bundle.file(at: "index.html")?.contents)
        #expect(html.contains("src=\"assets/logo.svg\""))
        #expect(html.contains("srcset") == false)
    }

    @Test func linkedImagesAndEmptyWellsHaveCleanOutput() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.image)
        for source in ["", "https://example.com/hero.jpg"] {
            part.setProperty(.init(rawValue: "source"), value: .url(source))
            let site = Site(name: "Image", pages: [Page(title: "Home", slug: "index", parts: [part])])
            let bundle = StaticSiteRenderer().render(site: site)
            #expect(bundle.errors.isEmpty)
            let html = try #require(bundle.file(at: "index.html")?.contents)
            #expect(html.contains("<img") == (source.isEmpty == false))
            #expect(html.contains("srcset") == false)
            #expect(html.contains("foundry-image-drop-zone") == false)
            let canvas = HTMLPageRenderer().render(page: site.pages[0], theme: site.theme)
            #expect(canvas.contains("data-foundry-image-drop-zone"))
        }
    }

    @Test func fitControlsOnlyAppearForConstrainedImages() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let fit = try #require(PartType.image.definition.properties.first { $0.key.rawValue == "objectFit.fit" })
        var part = PartNode.make(.image)
        func visible() -> Bool { PartPackageVisibilityEvaluator.isVisible(fit.visibleWhen, for: part, at: .mobile) }
        #expect(visible() == false)
        part.setProperty(.init(rawValue: "sizing.aspectRatio"), value: .choice("ratio-1x1"))
        #expect(visible())
        part.setProperty(.init(rawValue: "sizing.aspectRatio"), value: .choice("ratio-auto"))
        #expect(visible() == false)
        part.setProperty(.init(rawValue: "sizing.height"), value: .choice("vh-100"))
        #expect(visible())
    }
}
