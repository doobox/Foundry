import Foundation
import Testing
@testable import Foundry

struct AssetManagementTests {
    @Test
    func assetLibrarySupportsNestedOrderedFolders() {
        let hero = ProjectAsset(filename: "hero.png", mediaType: "image/png", byteCount: 4)
        let nestedFolder = ProjectAssetFolder(name: "Homepage")
        let imagesFolder = ProjectAssetFolder(name: "Images", children: [.folder(nestedFolder)])
        var library: [ProjectAssetNode] = [.folder(imagesFolder)]

        let inserted = library.insert(.asset(hero), at: .inside(folderID: nestedFolder.id))
        #expect(inserted)
        #expect(library.node(withID: hero.id) == .asset(hero))
        let moved = library.move(id: hero.id, to: .before(nodeID: imagesFolder.id))
        #expect(moved)
        #expect(library.first == .asset(hero))
    }

    @Test
    func folderCannotMoveInsideItsDescendant() {
        let child = ProjectAssetFolder(name: "Child")
        let parent = ProjectAssetFolder(name: "Parent", children: [.folder(child)])
        var library: [ProjectAssetNode] = [.folder(parent)]

        let moved = library.move(id: parent.id, to: .inside(folderID: child.id))
        #expect(!moved)
        #expect(library == [.folder(parent)])
    }

    @Test
    func recursiveAssetLibraryRoundTripsThroughProjectJSON() throws {
        let asset = ProjectAsset(filename: "logo.png", mediaType: "image/png", byteCount: 12)
        let folder = ProjectAssetFolder(name: "Brand", children: [.asset(asset)])
        let site = Site(name: "Assets", pages: [Page(title: "Home", slug: "index")], assetLibrary: [.folder(folder)])

        let decoded = try FoundryDocument.decodeProject(from: FoundryDocument.encoder.encode(site))

        #expect(decoded.assetLibrary == site.assetLibrary)
        #expect(decoded.assets == [asset])
    }

    @Test
    func assetMetadataRoundTripsWithStableIdentifier() throws {
        let asset = ProjectAsset(filename: "hero.png", mediaType: "image/png", byteCount: 4)
        let site = Site(name: "Assets", pages: [Page(title: "Home", slug: "index")], assets: [asset])

        let decoded = try FoundryDocument.decodeProject(from: FoundryDocument.encoder.encode(site))

        #expect(decoded.assets == [asset])
        #expect(decoded.assets[0].reference.foundryAssetID == asset.id)
    }

    @Test
    func staticExportIncludesManagedImageAndRewritesItsSource() {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let asset = ProjectAsset(filename: "hero.png", mediaType: "image/png", byteCount: data.count)
        var image = ComponentNode.make(.image)
        image.setProperty(.source, value: .url(asset.reference))
        let site = Site(
            name: "Assets",
            pages: [Page(title: "Home", slug: "index", components: [image])],
            assets: [asset]
        )

        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [asset.id: ProjectAssetContent(asset: asset, data: data)]
        )

        #expect(bundle.file(at: asset.exportPath)?.data == data)
        #expect(bundle.file(at: "index.html")?.contents.contains(asset.exportPath) == true)
    }

    @Test @MainActor
    func importsAndRenamesArbitraryFileTypesInsideFolders() throws {
        let document = FoundryDocument()
        let folderID = document.createAssetFolder(named: "Documents", undoManager: nil)
        let data = Data("User-agent: *".utf8)

        let assetID = document.importAsset(
            data: data,
            filename: "robots.txt",
            mediaType: "text/plain",
            placement: .inside(folderID: folderID),
            undoManager: nil
        )
        document.renameAsset(id: assetID, filename: "server-rules.txt", undoManager: nil)

        let folderNode = try #require(document.site.assetLibrary.node(withID: folderID))
        guard case .folder(let folder) = folderNode else {
            Issue.record("Expected imported asset folder")
            return
        }
        let asset = try #require(folder.children.node(withID: assetID))
        guard case .asset(let file) = asset else {
            Issue.record("Expected imported file")
            return
        }
        #expect(file.filename == "server-rules.txt")
        #expect(file.mediaType == "text/plain")
        #expect(document.assetContents[assetID]?.data == data)
    }
}
