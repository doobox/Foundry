import Foundation
import Testing
@testable import Foundry

/// The built-in Image part's responsive output and its Inspector polish.
struct ImagePartTests {
    private func imageSite(width: Int, height: Int, configure: (inout PartNode) -> Void = { _ in }) throws -> (Site, ProjectAsset, Data) {
        let data = try testPNG(width: width, height: height)
        let asset = ProjectAsset(
            filename: "hero.png",
            mediaType: "image/png",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data),
            pixelWidth: width,
            pixelHeight: height
        )
        var part = PartNode.make(.image)
        part.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        part.setProperty(PartPackageAdapter.imageAltKey(for: "source"), value: .string("The harbour"))
        configure(&part)
        let site = Site(name: "Image", pages: [Page(title: "Home", slug: "index", parts: [part])], assets: [asset])
        return (site, asset, data)
    }

    @Test @MainActor
    func exportOffersRenditionsWithTheirRealWidths() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        // Portrait: a rendition capped at 480 on its long side is 240 wide.
        let (site, asset, data) = try imageSite(width: 1000, height: 2000)
        let bundle = StaticSiteRenderer().render(site: site, assets: [asset.id: .init(asset: asset, data: data)])
        let html = try #require(bundle.file(at: "index.html")?.contents)
        let id = asset.id.uuidString.lowercased()
        #expect(html.contains(
            "srcset=\"assets/renditions/\(id)-480.png 240w, assets/renditions/\(id)-960.png 480w, "
            + "assets/renditions/\(id)-1600.png 800w, assets/hero.png 1000w\""
        ))
        // The built-in default is a 1200px custom width, so sizes tells the
        // browser the image never grows past it.
        #expect(html.contains("sizes=\"auto, (max-width: 1200px) 100vw, 1200px\""))
        #expect(html.contains("loading=\"lazy\" decoding=\"async\" style="))
        #expect(!html.contains("fetchpriority"))
        #expect(bundle.file(at: "assets/renditions/\(id)-480.png") != nil)
    }

    @Test @MainActor
    func smallImagesReuseTheOriginalAndImmediateLoadingGetsPriority() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let (site, asset, data) = try imageSite(width: 300, height: 200) { part in
            part.setProperty(.init(rawValue: "loading"), value: .choice("eager"))
            part.setProperty(.init(rawValue: "sizing.widthMode"), value: .choice("full"))
        }
        let bundle = StaticSiteRenderer().render(site: site, assets: [asset.id: .init(asset: asset, data: data)])
        let html = try #require(bundle.file(at: "index.html")?.contents)
        // Nothing to shrink: every candidate is the original at its own width.
        #expect(html.contains("srcset=\"assets/hero.png 300w, assets/hero.png 300w, assets/hero.png 300w, assets/hero.png 300w\""))
        #expect(html.contains("sizes=\"auto, 100vw\""))
        #expect(html.contains("loading=\"eager\" decoding=\"async\" fetchpriority=\"high\" style="))
        #expect(!bundle.files.contains { $0.path.hasPrefix("assets/renditions/") })
    }

    @Test @MainActor
    func canvasReportsRenditionSizesWithoutMakingFiles() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let (site, asset, data) = try imageSite(width: 2000, height: 1000)
        let html = HTMLPageRenderer(site: site).render(
            page: site.pages[0], language: "en", framework: site.framework,
            assets: [asset.id: .init(asset: asset, data: data)], breakpoint: .doubleExtraLarge
        )
        // Every candidate is the full image on the canvas, described at the
        // width export will give it.
        #expect(html.contains(" 480w, "))
        #expect(html.contains(" 960w, "))
        #expect(html.contains(" 1600w, "))
        #expect(html.contains(" 2000w\""))
    }

    @Test @MainActor
    func linkOverlayFallsBackToTheAltTextAndFitFollowsTheControl() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let (site, asset, data) = try imageSite(width: 300, height: 200) { part in
            part.setProperty(.init(rawValue: "destination"), value: .url("https://example.com"))
            part.setProperty(.init(rawValue: "sizing.heightMode"), value: .choice("custom"))
            part.setProperty(.init(rawValue: "fit"), value: .choice("contain"))
        }
        let bundle = StaticSiteRenderer().render(site: site, assets: [asset.id: .init(asset: asset, data: data)])
        let output = bundle.files.map(\.contents).joined()
        #expect(output.contains("aria-label=\"The harbour\""))
        #expect(output.contains("object-fit: contain"))
    }

    @Test @MainActor
    func linkedWebImagesRenderWithoutRenditionsOrDimensions() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.image)
        part.setProperty(.init(rawValue: "source"), value: .url("https://example.com/photos/harbour.jpg"))
        let site = Site(name: "Linked", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        // Nothing is known about a linked image's pixels, so it is offered as is.
        #expect(html.contains("<img class=\"fd-image\" src=\"https://example.com/photos/harbour.jpg\" loading=\"lazy\""))
        #expect(!html.contains("srcset"))
        #expect(!html.contains("width=\"\""))
    }

    @Test @MainActor
    func inspectorControlsShowOnlyWhenTheyApply() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let definition = PartType.image.definition
        let properties = Dictionary(uniqueKeysWithValues: definition.properties.map { ($0.key.rawValue, $0) })
        func visible(_ id: String, in part: PartNode) -> Bool {
            PartPackageVisibilityEvaluator.isVisible(properties[id]?.visibleWhen, for: part, at: .mobile)
        }
        var part = PartNode.make(.image)
        // Fit and the aspect ratio's cropping only matter once the image is
        // cut to a shape; Alignment only when the part can be narrower.
        #expect(!visible("fit", in: part))
        #expect(visible("alignment", in: part))
        #expect(visible("sizing.aspectRatio", in: part))
        part.setProperty(.init(rawValue: "sizing.aspectRatio"), value: .choice("16 / 9"))
        #expect(visible("fit", in: part))
        part.setProperty(.init(rawValue: "sizing.heightMode"), value: .choice("custom"))
        #expect(visible("fit", in: part))
        #expect(!visible("sizing.aspectRatio", in: part))
        part.setProperty(.init(rawValue: "sizing.widthMode"), value: .choice("full"))
        #expect(!visible("alignment", in: part))

        // A height limit alone shapes the image too, so Fit appears for it.
        var limited = PartNode.make(.image)
        #expect(!visible("fit", in: limited))
        var maximum = FrameworkSingleSpacingValue()
        maximum.selection.token = "lg"
        limited.setProperty(.init(rawValue: "sizing.maxHeight"), value: .frameworkSpacing(maximum))
        #expect(visible("fit", in: limited))
    }

    @Test @MainActor
    func aspectRatioShapesAnyPartWithTheSizingGroup() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.container)
        part.setProperty(.init(rawValue: "sizing.aspectRatio"), value: .choice("custom"))
        part.setProperty(.init(rawValue: "sizing.aspectRatioWidth"), value: .number(5))
        part.setProperty(.init(rawValue: "sizing.aspectRatioHeight"), value: .number(2))
        let site = Site(name: "Ratio", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let html = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(html.contains("aspect-ratio: 5 / 2;"))
    }
}
