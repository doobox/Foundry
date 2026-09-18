import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Foundry

struct WebIconGeneratorTests {
    @Test
    func storedWebIconsAndMarkupAreIncludedForEveryPageDepth() throws {
        let source = try squarePNG(size: 256)
        let sourceAsset = ProjectAsset(
            filename: "web-icon.png",
            mediaType: "image/png",
            byteCount: source.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: source),
            pixelWidth: 256,
            pixelHeight: 256
        )
        let generated = storedAssets(from: WebIconGenerator.generateFiles(from: source))
        var site = Site.starter()
        site.favicon = sourceAsset.reference
        site.webIconAssets = generated.assets
        site.assetLibrary.append(.asset(sourceAsset))
        site.pages.append(Page(title: "About", slug: "about"))

        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: ProjectAssetContents(
                [sourceAsset.id: ProjectAssetContent(asset: sourceAsset, data: source)]
                    .merging(generated.contents) { _, generated in generated }
            )
        )

        #expect(bundle.file(at: "assets/web-icons/favicon.ico") != nil)
        #expect(bundle.file(at: "assets/web-icons/favicon-16x16.png") != nil)
        #expect(bundle.file(at: "assets/web-icons/favicon-32x32.png") != nil)
        #expect(bundle.file(at: "assets/web-icons/favicon-48x48.png") != nil)
        #expect(bundle.file(at: "assets/web-icons/apple-touch-icon-180x180.png") != nil)

        let home = try #require(bundle.file(at: "index.html")?.contents)
        let about = try #require(bundle.file(at: "about/index.html")?.contents)
        #expect(home.contains("href=\"assets/web-icons/favicon.ico\""))
        #expect(home.contains("href=\"assets/web-icons/favicon-32x32.png\""))
        #expect(home.contains("href=\"assets/web-icons/apple-touch-icon-180x180.png\""))
        #expect(about.contains("href=\"../assets/web-icons/favicon.ico\""))
        #expect(about.contains("href=\"../assets/web-icons/favicon-32x32.png\""))
    }

    @Test
    func rendererDoesNotGenerateIconsFromTheSourceImage() throws {
        let source = try squarePNG(size: 256)
        let favicon = ProjectAsset(
            filename: "web-icon.png",
            mediaType: "image/png",
            byteCount: source.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: source),
            pixelWidth: 256,
            pixelHeight: 256
        )
        var site = Site.starter()
        site.favicon = favicon.reference
        site.assetLibrary = [.asset(favicon)]

        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [favicon.id: ProjectAssetContent(asset: favicon, data: source)]
        )
        let html = try #require(bundle.file(at: "index.html")?.contents)

        #expect(!html.contains("rel=\"icon\""))
        #expect(!html.contains("rel=\"shortcut icon\""))
        #expect(!html.contains("rel=\"apple-touch-icon\""))
        #expect(bundle.files.allSatisfy { !WebIconGenerator.isManagedExportPath($0.path) })
    }

    @Test @MainActor
    func assigningFaviconGeneratesOnceAndClearingItRemovesTheCache() throws {
        let document = FoundryDocument(site: .starter())
        let editor = ProjectEditor(document: document, undoManager: nil)
        let source = try squarePNG(size: 256)
        let sourceID = document.importAsset(
            data: source,
            filename: "web-icon.png",
            mediaType: "image/png",
            undoManager: nil
        )
        let reference = "foundry-asset:\(sourceID.uuidString)"

        editor.setSiteFavicon(reference)
        let firstGeneratedIDs = document.site.webIconAssets.map(\.id)
        #expect(!firstGeneratedIDs.isEmpty)
        #expect(document.site.favicon.foundryAssetID != sourceID)
        #expect(document.site.assets.contains(where: { $0.id == sourceID }))

        editor.setSiteFavicon(document.site.favicon)
        #expect(document.site.webIconAssets.map(\.id) == firstGeneratedIDs)

        editor.setSiteFavicon("")
        #expect(document.site.webIconAssets.isEmpty)
        #expect(firstGeneratedIDs.allSatisfy { document.assetContents[$0] == nil })
    }

    @Test @MainActor
    func finderImportStoresTheSourcePrivately() throws {
        let document = FoundryDocument(site: .starter())
        let editor = ProjectEditor(document: document, undoManager: nil)

        editor.importSiteFavicon(
            data: try squarePNG(size: 256),
            filename: "site-icon.png",
            mediaType: "image/png"
        )

        #expect(document.site.assets.isEmpty)
        #expect(document.site.webIconAssets.contains(where: {
            $0.id == document.site.favicon.foundryAssetID
                && $0.filename == "web-icon-source.png"
        }))
    }

    @Test
    func sourceValidationRequiresASquareImageAtLeast256Pixels() throws {
        #expect(WebIconGenerator.sourceValidationError(for: try squarePNG(size: 255)) != nil)
        #expect(WebIconGenerator.sourceValidationError(for: try squarePNG(size: 256)) == nil)
        #expect(WebIconGenerator.sourceValidationError(for: try png(width: 256, height: 300)) != nil)
    }

    private func squarePNG(size: Int) throws -> Data {
        try png(width: size, height: size)
    }

    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func storedAssets(
        from files: [SiteExportFile]
    ) -> (assets: [ProjectAsset], contents: [UUID: ProjectAssetContent]) {
        let records = files.map { file -> (ProjectAsset, Data) in
            let filename = URL(filePath: file.path).lastPathComponent
            return (
                ProjectAsset(
                    filename: filename,
                    mediaType: filename.hasSuffix(".ico") ? "image/x-icon" : "image/png",
                    byteCount: file.data.count,
                    contentDigest: FoundryDocumentSnapshot.digest(for: file.data)
                ),
                file.data
            )
        }
        return (
            records.map(\.0),
            Dictionary(uniqueKeysWithValues: records.map { asset, data in
                (asset.id, ProjectAssetContent(asset: asset, data: data))
            })
        )
    }
}
