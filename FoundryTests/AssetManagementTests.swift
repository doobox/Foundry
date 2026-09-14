import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Foundry

struct AssetManagementTests {
    @Test @MainActor
    func fontImportsCreateAndReuseFontsFolder() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let first = document.importAsset(data: Data([1]), filename: "Regular.TTF", mediaType: "font/ttf", undoManager: undo)
        undo.endUndoGrouping()
        let folder = try #require(document.site.assetLibrary.compactMap { node -> ProjectAssetFolder? in
            guard case .folder(let folder) = node, folder.name == "Fonts" else { return nil }
            return folder
        }.first)
        #expect(folder.children.map(\.id) == [first])
        undo.undo()
        #expect(document.site.assetLibrary.isEmpty)
        undo.redo()
        document.renameAssetFolder(id: folder.id, name: "fonts", undoManager: nil)
        let second = document.importAsset(data: Data([2]), filename: "Bold.woff2", mediaType: "font/woff2", undoManager: nil)
        #expect(document.site.assetLibrary.count == 1)
        guard case .folder(let updated) = try #require(document.site.assetLibrary.first) else {
            Issue.record("Expected Fonts folder")
            return
        }
        #expect(updated.children.map(\.id) == [first, second])
    }

    @Test
    func canonicalizesOversizedStillImagesAndCreatesSmallerRenditionsWithoutUpscaling() throws {
        let data = try testPNG(width: 5_000, height: 2)
        let canonical = PartImageProcessor.canonicalize(
            data: data,
            filename: "wide.png",
            mimeType: "image/png"
        )
        #expect(canonical.metadata.width == 3_840)
        #expect(canonical.metadata.height == 2)

        let rendition = try #require(PartImageProcessor.rendition(
            data: canonical.data,
            filename: "wide.png",
            mimeType: "image/png",
            maximumDimension: 1_000
        ))
        #expect(rendition.metadata.width == 1_000)
        #expect(PartImageProcessor.rendition(
            data: rendition.data,
            filename: "wide.png",
            mimeType: "image/png",
            maximumDimension: 2_000
        ) == nil)
    }

    @Test
    func renditionDiskCacheReusesInvalidatesAndRecovers() throws {
        let cache = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let data = try testPNG(width: 100, height: 50)
        func render(_ source: Data, _ size: Int = 40) throws -> PartImageProcessor.Result {
            try #require(PartImageProcessor.rendition(data: source, filename: "test.png", mimeType: "image/png", maximumDimension: size, cacheDirectory: cache))
        }
        let first = try render(data)
        let file = try #require(FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).first)
        let fileID = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        let second = try render(data)
        #expect(second.data == first.data)
        #expect(second.metadata == first.metadata)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber == fileID)
        _ = try render(data, 20)
        _ = try render(testPNG(width: 120, height: 60))
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).count == 3)
        try Data("broken".utf8).write(to: file)
        #expect(try render(data).data == first.data)
        #expect(try Data(contentsOf: file) == first.data)
        // An unwritable cache (a regular file in place of its directory) is optional.
        let uncached = PartImageProcessor.rendition(data: data, filename: "test.png", mimeType: "image/png", maximumDimension: 40, cacheDirectory: file)
        #expect(uncached?.data == first.data)
    }

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
        var image = PartNode.make(.image)
        image.setProperty(.source, value: .url(asset.reference))
        let site = Site(
            name: "Assets",
            pages: [Page(title: "Home", slug: "index", parts: [image])],
            assets: [asset]
        )

        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [asset.id: ProjectAssetContent(asset: asset, data: data)]
        )

        #expect(bundle.file(at: "assets/hero.png")?.data == data)
        #expect(bundle.file(at: "index.html")?.contents.contains("assets/hero.png") == true)
    }

    @Test
    func managedExportPreservesNestedResourceFolderStructure() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let asset = ProjectAsset(filename: "hero.png", mediaType: "image/png", byteCount: data.count)
        let nested = ProjectAssetFolder(name: "Test Folder", children: [.asset(asset)])
        let parent = ProjectAssetFolder(name: "Downloads", children: [.folder(nested)])
        let site = Site(
            name: "Assets",
            pages: [Page(title: "Home", slug: "index")],
            assetLibrary: [.folder(parent)]
        )

        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [asset.id: ProjectAssetContent(asset: asset, data: data)]
        )
        let expectedPath = "assets/downloads/test-folder/hero.png"

        #expect(site.publishedPath(for: asset) == expectedPath)
        #expect(bundle.file(at: expectedPath)?.data == data)
        #expect(bundle.file(at: "assets/images/\(asset.storageFilename)") == nil)
    }

    @Test
    func managedExportUsesReadableNamesAndStableSuffixesOnlyForCollisions() {
        let first = ProjectAsset(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            filename: "Team Photo@2x.PNG",
            mediaType: "image/png",
            byteCount: 1
        )
        let second = ProjectAsset(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            filename: "Team Photo 2x.png",
            mediaType: "image/png",
            byteCount: 1
        )
        let unique = ProjectAsset(filename: "Company Logo.svg", mediaType: "image/svg+xml", byteCount: 1)
        let library: [ProjectAssetNode] = [.asset(first), .asset(second), .asset(unique)]

        #expect(library.managedExportPath(for: first) == "assets/team-photo-2x--11111111.png")
        #expect(library.managedExportPath(for: second) == "assets/team-photo-2x--22222222.png")
        #expect(library.managedExportPath(for: unique) == "assets/company-logo.svg")
    }

    @Test
    func managedExportDisambiguatesSanitizedFolderNameCollisions() {
        let firstAsset = ProjectAsset(filename: "Photo.png", mediaType: "image/png", byteCount: 1)
        let secondAsset = ProjectAsset(filename: "Photo.png", mediaType: "image/png", byteCount: 1)
        let firstFolder = ProjectAssetFolder(
            id: UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!,
            name: "Team Photos",
            children: [.asset(firstAsset)]
        )
        let secondFolder = ProjectAssetFolder(
            id: UUID(uuidString: "bbbbbbbb-2222-2222-2222-222222222222")!,
            name: "Team@Photos",
            children: [.asset(secondAsset)]
        )
        let library: [ProjectAssetNode] = [.folder(firstFolder), .folder(secondFolder)]

        #expect(library.managedExportPath(for: firstAsset) == "assets/team-photos--aaaaaaaa/photo.png")
        #expect(library.managedExportPath(for: secondAsset) == "assets/team-photos--bbbbbbbb/photo.png")
    }

    @Test
    func resourcesViewOmitsPagePlacedAssetsWithoutDiscardingTheirFolders() throws {
        let resource = ProjectAsset(filename: "library.png", mediaType: "image/png", byteCount: 1)
        let placed = ProjectAsset(
            filename: "download.png",
            mediaType: "image/png",
            byteCount: 1,
            exportDirectory: .root
        )
        let folder = ProjectAssetFolder(name: "Images", children: [.asset(resource), .asset(placed)])

        let visible = [ProjectAssetNode.folder(folder)].resourcesOnly
        guard case .folder(let visibleFolder) = try #require(visible.first) else {
            Issue.record("Expected the resource folder to remain visible")
            return
        }
        #expect(visibleFolder.children == [.asset(resource)])
    }

    @Test @MainActor
    func movingPagePlacedAssetToResourcesClearsItsPublicPlacement() throws {
        let asset = ProjectAsset(
            filename: "guide.pdf",
            mediaType: "application/pdf",
            byteCount: 1,
            exportDirectory: .root
        )
        let document = FoundryDocument(site: Site(
            name: "Assets",
            pages: [Page(title: "Home", slug: "index")],
            assetLibrary: [.asset(asset)]
        ))

        #expect(document.moveAssetNodeToResources(id: asset.id, to: .end, undoManager: nil))
        #expect(try #require(document.site.assets.first).exportDirectory == nil)
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

    @Test @MainActor
    func reusesIdenticalAssetContentWhenRequested() {
        let document = FoundryDocument()
        let data = Data("same image bytes".utf8)

        let firstID = document.importAsset(
            data: data,
            filename: "first.png",
            mediaType: "image/png",
            reuseIdenticalContent: true,
            undoManager: nil
        )
        let secondID = document.importAsset(
            data: data,
            filename: "second.png",
            mediaType: "image/png",
            reuseIdenticalContent: true,
            undoManager: nil
        )

        #expect(secondID == firstID)
        #expect(document.site.assets.count == 1)
    }

    @Test @MainActor
    func removesDeletedAssetsFromIdenticalContentIndex() {
        let document = FoundryDocument()
        let data = Data("reusable image bytes".utf8)
        let firstID = document.importAsset(
            data: data,
            filename: "first.png",
            mediaType: "image/png",
            reuseIdenticalContent: true,
            undoManager: nil
        )

        document.removeAsset(id: firstID, undoManager: nil)
        let replacementID = document.importAsset(
            data: data,
            filename: "replacement.png",
            mediaType: "image/png",
            reuseIdenticalContent: true,
            undoManager: nil
        )

        #expect(replacementID != firstID)
        #expect(document.site.assets.map(\.id) == [replacementID])
    }

    @Test @MainActor
    func retainsOtherIdenticalAssetAfterDeletingOneDuplicate() {
        let document = FoundryDocument()
        let data = Data("duplicate image bytes".utf8)
        let firstID = document.importAsset(
            data: data,
            filename: "first.png",
            mediaType: "image/png",
            undoManager: nil
        )
        let secondID = document.importAsset(
            data: data,
            filename: "second.png",
            mediaType: "image/png",
            undoManager: nil
        )

        document.removeAsset(id: firstID, undoManager: nil)
        let reusedID = document.importAsset(
            data: data,
            filename: "third.png",
            mediaType: "image/png",
            reuseIdenticalContent: true,
            undoManager: nil
        )

        #expect(reusedID == secondID)
        #expect(document.site.assets.map(\.id) == [secondID])
    }
}

func testPNG(width: Int, height: Int) throws -> Data {
    let bytes = Data(repeating: 0x7f, count: width * height * 4)
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    let image = try #require(CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        output,
        UTType.png.identifier as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}
