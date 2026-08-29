import Foundation
import Testing
@testable import Foundry

struct StaticSiteRendererTests {
    @Test
    func responsiveOverridesExportAsMediaQueriesWithoutCanvasMetadata() throws {
        var site = Site.starter()
        let componentID = try #require(site.pages.first?.components.first?.id)
        site.updateComponent(id: componentID) {
            $0.setResponsiveProperty(.padding, value: .number(8), at: .mobile)
            $0.setResponsiveProperty(.padding, value: .number(18), at: .tabletPortrait)
            $0.setResponsiveProperty(.padding, value: .number(24), at: .tabletLandscape)
        }

        let bundle = StaticSiteRenderer().render(site: site)
        let css = try #require(bundle.files.first(where: { $0.path == "assets/site.css" })?.contents)
        let html = try #require(bundle.files.first(where: { $0.path == "index.html" })?.contents)

        #expect(css.contains("@media(min-width:768px)"))
        #expect(css.contains("@media(min-width:1024px)"))
        #expect(!css.contains("@media(max-width:"))
        #expect(css.contains("padding:18px!important"))
        #expect(css.contains("padding:24px!important"))
        #expect(html.contains("padding: 8px"))
        #expect(html.contains("c-\(componentID.uuidString.lowercased())"))
        #expect(!html.contains("data-foundry"))
    }

    @Test
    func rendersHomeAndNestedPagePathsWithSharedStylesheet() throws {
        var site = Site.starter()
        site.pages.append(Page(title: "About", slug: "about", components: [.make(.paragraph)]))

        let bundle = StaticSiteRenderer().render(site: site)

        #expect(bundle.files.map(\.path) == ["about/index.html", "assets/site.css", "index.html"])
        #expect(try #require(bundle.file(at: "index.html")).contents.contains("href=\"assets/site.css\""))
        #expect(try #require(bundle.file(at: "about/index.html")).contents.contains("href=\"../assets/site.css\""))
    }

    @Test
    func pageFoldersBecomeExportDirectoriesAndHomeRemainsAtRoot() throws {
        let company = PageFolder(name: "Company", slug: "company")
        let team = PageFolder(name: "Team", slug: "team", parentID: company.id)
        let site = Site(
            name: "Folders",
            pages: [
                Page(title: "Home", slug: "index", folderID: team.id),
                Page(title: "About", slug: "about", folderID: team.id)
            ],
            pageFolders: [company, team],
            assetLibrary: []
        )

        let bundle = StaticSiteRenderer().render(site: site)

        #expect(bundle.file(at: "index.html") != nil)
        let about = try #require(bundle.file(at: "company/team/about/index.html"))
        #expect(about.contents.contains("href=\"../../../assets/site.css\""))
    }

    @Test
    func explicitlyPlacedAssetExportsAtItsPageTreeLocation() throws {
        let folder = PageFolder(name: "Downloads", slug: "downloads")
        let data = Data("hello".utf8)
        let asset = ProjectAsset(
            filename: "guide.txt",
            mediaType: "text/plain",
            byteCount: data.count,
            exportDirectory: .folder(folder.id)
        )
        let site = Site(
            name: "Files",
            pages: [Page(title: "Home", slug: "index")],
            pageFolders: [folder],
            assetLibrary: [.asset(asset)]
        )

        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [asset.id: ProjectAssetContent(asset: asset, data: data)]
        )

        #expect(bundle.file(at: "downloads/guide.txt")?.data == data)
        #expect(bundle.file(at: asset.exportPath)?.data == data)
    }

    @Test
    func productionHTMLExcludesCanvasMetadataAndDropZones() throws {
        let html = try #require(StaticSiteRenderer().render(site: .starter()).file(at: "index.html")).contents

        #expect(!html.contains("data-foundry"))
        #expect(!html.contains("foundry-selected"))
        #expect(!html.contains("Drop a component"))
        #expect(!html.contains("contenteditable"))
    }

    @Test
    func escapesPageTitlesAndComponentContent() throws {
        let text = ComponentNode(
            type: .paragraph,
            properties: [.init(key: .init(rawValue: "content1"), value: .string("<Hello & goodbye>"))]
        )
        let site = Site(name: "Test", pages: [Page(title: "A < B", slug: "index", components: [text])])

        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")).contents

        #expect(html.contains("<title>A &lt; B</title>"))
        #expect(html.contains("&lt;Hello &amp; goodbye&gt;"))
    }

    @Test
    func rendersEscapedSearchAndSocialMetadata() throws {
        var site = Site.starter()
        site.language = "en-GB"
        site.pages[0].metadata = PageMetadata(
            browserTitle: "A \"better\" <title>",
            description: "Search & discover",
            socialTitle: "Share \"this\"",
            socialDescription: "Social <description>",
            socialImage: "https://example.com/image?a=1&b=2"
        )

        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")).contents

        #expect(html.contains("<html lang=\"en-GB\">"))
        #expect(html.contains("<title>A \"better\" &lt;title&gt;</title>"))
        #expect(html.contains("name=\"description\" content=\"Search &amp; discover\""))
        #expect(html.contains("property=\"og:title\" content=\"Share &quot;this&quot;\""))
        #expect(html.contains("property=\"og:description\" content=\"Social &lt;description&gt;\""))
        #expect(html.contains("property=\"og:image\" content=\"https://example.com/image?a=1&amp;b=2\""))
    }

    @Test
    func outputIsDeterministic() {
        let site = Site.starter()
        #expect(StaticSiteRenderer().render(site: site) == StaticSiteRenderer().render(site: site))
    }

    @Test
    func writerCreatesNestedExportFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FoundryExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try SiteExportWriter().write(StaticSiteRenderer().render(site: .starter()), to: directory)

        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "index.html").path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "assets/site.css").path))
    }
}
