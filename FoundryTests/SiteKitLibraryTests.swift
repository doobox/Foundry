import Foundation
import Testing
@testable import Foundry

@MainActor
struct SiteKitLibraryTests {
    private func makePackRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrydevpack", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["id": "test.kits.\(UUID().uuidString.lowercased())", "title": "Kit Pack"]
        try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
            .write(to: root.appending(path: "Info.plist"))
        return root
    }

    private func writeKitDocument(at documentURL: URL, site: Site) throws {
        let wrapper = try FoundryDocument.makeFileWrapper(
            snapshot: .init(site: site),
            existingFile: nil
        )
        try wrapper.write(to: documentURL, options: .atomic, originalContentsURL: nil)
    }

    @Test
    func kitsAreFoldersWithADocumentAndOptionalManifest() throws {
        let root = try makePackRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let itemURL = root.appending(path: "Sites/Starter Kit", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: true)
        try writeKitDocument(
            at: itemURL.appending(path: "site.foundry", directoryHint: .isDirectory),
            site: Site.starter()
        )

        let library = SiteKitLibrary(fixedRootURLs: [root])
        #expect(library.kits.count == 1)
        let plain = try #require(library.kits.first)
        #expect(plain.title == "Starter Kit")
        #expect(plain.details == nil)
        #expect(plain.previewURL == nil)
        #expect(plain.packTitle == "Kit Pack")

        // The optional manifest adds a display title and card description;
        // preview.png becomes the card artwork.
        try PropertyListSerialization.data(
            fromPropertyList: ["title": "Restaurant", "description": "High-impact site for restaurants."],
            format: .xml,
            options: 0
        ).write(to: itemURL.appending(path: "Info.plist"))
        try Data([1]).write(to: itemURL.appending(path: "preview.png"))
        library.refresh()
        let described = try #require(library.kits.first)
        #expect(described.title == "Restaurant")
        #expect(described.details == "High-impact site for restaurants.")
        #expect(described.previewURL != nil)

        // A folder without a .foundry document is not a kit; browsing skips it.
        try FileManager.default.createDirectory(
            at: root.appending(path: "Sites/Empty", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        library.refresh()
        #expect(library.kits.count == 1)
        #expect(try FoundryPackLoader.load(from: root).siteKitURLs.count == 2)
    }

    @Test
    func creatingFromAKitStampsAFreshIdentityAndFactoryPublishing() throws {
        let root = try makePackRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let itemURL = root.appending(path: "Sites/Portfolio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: true)
        let authored = Site(
            name: "Author Working Copy",
            publicURL: "https://author.example.com",
            publishingDestination: .sftp,
            publishingHost: "ftp.author.example.com",
            publishingUsername: "author",
            pages: [
                Page(title: "Home", slug: "index", parts: [PartNode.make(.container)]),
                Page(title: "About", slug: "about", parts: [])
            ],
            assetLibrary: []
        )
        try writeKitDocument(
            at: itemURL.appending(path: "site.foundry", directoryHint: .isDirectory),
            site: authored
        )

        let library = SiteKitLibrary(fixedRootURLs: [root])
        let kit = try #require(library.kits.first)
        let document = try SiteKitLibrary.makeDocument(from: kit)

        // Fresh identity — publishing destinations and keychain entries key
        // off the site id — but the authored content arrives untouched.
        #expect(document.site.id != authored.id)
        #expect(document.site.name == "Portfolio")
        #expect(document.site.pages.map(\.id) == authored.pages.map(\.id))
        #expect(document.site.pages.map(\.title) == ["Home", "About"])

        // The kit author's publishing setup never travels.
        #expect(document.site.publicURL.isEmpty)
        #expect(document.site.publishingHost.isEmpty)
        #expect(document.site.publishingUsername.isEmpty)
        #expect(document.site.publishingDestinations.count == 1)
        #expect(document.site.publishingDestinations.first?.kind == .local)

        // Stamping twice never produces siblings that share an identity.
        let sibling = try SiteKitLibrary.makeDocument(from: kit)
        #expect(sibling.site.id != document.site.id)
    }
}
