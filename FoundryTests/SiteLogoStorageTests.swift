import Foundation
import Testing
@testable import Foundry

@Suite("Site logo storage")
struct SiteLogoStorageTests {
    @Test @MainActor
    func finderImportStoresTheLogoPrivately() throws {
        let document = FoundryDocument(site: .starter())
        let editor = ProjectEditor(document: document, undoManager: nil)
        let data = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)

        editor.importSiteLogo(data: data, filename: "brand.svg", mediaType: "image/svg+xml")

        let logoID = try #require(document.site.logo.foundryAssetID)
        #expect(document.site.assets.isEmpty)
        #expect(document.site.siteLogoAssets.count == 1)
        #expect(document.site.siteLogoAssets[0].id == logoID)
        #expect(document.site.siteLogoAssets[0].filename == "site-logo-source.svg")
        #expect(document.assetContents[logoID]?.data == data)
    }

    @Test @MainActor
    func choosingAVisibleAssetCopiesItAndLeavesTheOriginalAvailable() throws {
        let document = FoundryDocument(site: .starter())
        let editor = ProjectEditor(document: document, undoManager: nil)
        let data = Data("logo image".utf8)
        let visibleID = document.importAsset(
            data: data,
            filename: "brand.png",
            mediaType: "image/png",
            undoManager: nil
        )

        editor.setSiteLogo("foundry-asset:\(visibleID.uuidString)")

        let privateID = try #require(document.site.logo.foundryAssetID)
        #expect(privateID != visibleID)
        #expect(document.site.assets.contains(where: { $0.id == visibleID }))
        #expect(document.site.siteLogoAssets.contains(where: { $0.id == privateID }))
        #expect(document.assetContents[privateID]?.data == data)
    }

    @Test @MainActor
    func replacingAndClearingTheLogoRemovesOldPrivateData() throws {
        let document = FoundryDocument(site: .starter())
        let editor = ProjectEditor(document: document, undoManager: nil)
        editor.importSiteLogo(data: Data("first".utf8), filename: "first.png", mediaType: "image/png")
        let firstID = try #require(document.site.logo.foundryAssetID)

        editor.importSiteLogo(data: Data("second".utf8), filename: "second.webp", mediaType: "image/webp")
        let secondID = try #require(document.site.logo.foundryAssetID)

        #expect(secondID != firstID)
        #expect(document.assetContents[firstID] == nil)
        #expect(document.assetContents[secondID]?.data == Data("second".utf8))

        editor.setSiteLogo("")
        #expect(document.site.logo.isEmpty)
        #expect(document.site.siteLogoAssets.isEmpty)
        #expect(document.assetContents[secondID] == nil)
    }

    @Test
    func rendererPublishesOnlyTheManagedLogoCopyInItsOwnDirectory() throws {
        let data = Data("logo".utf8)
        let logo = ProjectAsset(
            filename: "site-logo-source.svg",
            mediaType: "image/svg+xml",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data)
        )
        var site = Site.starter()
        site.logo = logo.reference
        site.siteLogoAssets = [logo]

        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [logo.id: ProjectAssetContent(asset: logo, data: data)]
        )

        let path = "assets/site-logo/site-logo.svg"
        #expect(bundle.file(at: path)?.data == data)
        #expect(bundle.files.filter { $0.path.hasPrefix("assets/site-logo/") }.map(\.path) == [path])
    }

}
