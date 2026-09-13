import Foundation
import Testing
@testable import Foundry

struct StaticSiteRendererTests {
    @Test @MainActor
    func deletingAPartRemovesItsHTMLCSSAndJavaScriptArtifacts() throws {
        _ = PartPackageCatalog.shared
        var html = PartNode.make(.init(rawValue: "foundry.content.html"))
        html.setProperty(.init(rawValue: "content"), value: "<div>unique-deleted-html</div>")
        html.setProperty(PartPackageAdapter.htmlCSSKey(for: "content"), value: ".unique-deleted-css { color: red; }")
        html.setProperty(PartPackageAdapter.htmlJavaScriptKey(for: "content"), value: "window.uniqueDeletedJavaScript = true;")
        let page = Page(title: "Home", slug: "index", parts: [html])
        let document = FoundryDocument(site: Site(name: "Deletion", pages: [page]))
        let before = StaticSiteRenderer().render(site: document.site)
        #expect(try #require(before.file(at: "index.html")).contents.contains("unique-deleted-html"))
        #expect(try #require(before.file(at: "files/page.css")).contents.contains("unique-deleted-css"))
        #expect(try #require(before.file(at: "files/page.js")).contents.contains("uniqueDeletedJavaScript"))

        ProjectEditor(document: document, undoManager: nil).removePart(id: html.id)

        let after = StaticSiteRenderer().render(site: document.site)
        #expect(!(try #require(after.file(at: "index.html"))).contents.contains("unique-deleted-html"))
        #expect(!(try #require(after.file(at: "files/page.css"))).contents.contains("unique-deleted-css"))
        #expect(after.file(at: "files/page.js") == nil)
    }

    @Test @MainActor
    func pageShellIsNeutralAndAllowsEdgeToEdgeParts() throws {
        let site = Site.starter()
        let exportedCSS = try #require(
            StaticSiteRenderer().render(site: site).file(at: "files/site.css")?.contents
        )
        let canvasHTML = HTMLPageRenderer(site: site).render(
            page: try #require(site.pages.first),
            theme: site.theme
        )

        #expect(exportedCSS.contains("html,body{min-height:100%}"))
        #expect(exportedCSS.contains("body{margin:0;background:"))
        #expect(exportedCSS.contains("display:flex;flex-direction:column;align-items:stretch"))
        #expect(exportedCSS.contains("*,*::before,*::after{box-sizing:border-box}"))
        #expect(exportedCSS.contains("--foundry-color-background:"))
        #expect(exportedCSS.contains("--foundry-color-links:"))
        #expect(exportedCSS.contains("a{color:var(--foundry-color-links)}"))
        #expect(exportedCSS.contains("--foundry-spacing-base:"))
        #expect(exportedCSS.contains(".foundry-container{"))
        #expect(!exportedCSS.contains("--background:"))
        #expect(!exportedCSS.contains("--theme-container-width:"))
        #expect(!exportedCSS.contains("padding:48px"))
        #expect(canvasHTML.contains("html, body { min-height: 100%; }"))
        #expect(canvasHTML.contains("display: flex; flex-direction: column; align-items: stretch;"))
        #expect(canvasHTML.contains("--foundry-color-background:"))
        #expect(canvasHTML.contains("--foundry-color-links:"))
        #expect(canvasHTML.contains("a { color: var(--foundry-color-links); }"))
        #expect(canvasHTML.contains("--foundry-editor-chrome"))
        #expect(canvasHTML.contains("foundry-container"))
        #expect(!canvasHTML.contains("--background:"))
        #expect(!canvasHTML.contains("padding: 48px"))
    }

    @Test
    func responsiveOverridesExportAsMediaQueriesWithoutCanvasMetadata() throws {
        var site = TestSiteFixtures.populatedSite()
        let partID = try #require(site.pages.first?.parts.first?.id)
        site.updatePart(id: partID) {
            $0.setResponsiveProperty(
                .maxWidth,
                value: .number(800),
                at: .mobile
            )
            $0.setResponsiveProperty(
                .maxWidth,
                value: .number(900),
                at: .medium
            )
            $0.setResponsiveProperty(
                .maxWidth,
                value: .number(1000),
                at: .large
            )
        }

        let bundle = StaticSiteRenderer().render(site: site)
        let css = try #require(bundle.files.first(where: { $0.path == "files/page.css" })?.contents)
        let html = try #require(bundle.files.first(where: { $0.path == "index.html" })?.contents)

        #expect(css.contains("@media(min-width:768px)"))
        #expect(css.contains("@media(min-width:1024px)"))
        #expect(!css.contains("@media(max-width:"))
        #expect(css.contains("max-width: 800px"))
        #expect(css.contains("max-width: 900px"))
        #expect(css.contains("max-width: 1000px"))
        #expect(html.contains("data-foundry-id=\"\(partID.uuidString)\""))
        #expect(!html.contains("data-foundry-part-type"))
    }

    @Test
    func rendersHomeAndNestedPagePathsWithSharedStylesheet() throws {
        var site = Site.starter()
        site.pages.append(Page(title: "About", slug: "about", parts: [.make(.paragraph)]))

        let bundle = StaticSiteRenderer().render(site: site)

        #expect(bundle.file(at: "files/site.css") != nil)
        #expect(bundle.file(at: "files/site.js") == nil)
        #expect(bundle.file(at: "files/page.css") != nil)
        #expect(bundle.file(at: "about/files/page.css") != nil)
        #expect(bundle.file(at: "files/page.js") == nil)
        #expect(bundle.file(at: "about/files/page.js") == nil)
        #expect(try #require(bundle.file(at: "index.html")).contents.contains("href=\"files/site.css\""))
        #expect(try #require(bundle.file(at: "about/index.html")).contents.contains("href=\"../files/site.css\""))
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
        #expect(about.contents.contains("href=\"../../../files/site.css\""))
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
        #expect(bundle.file(at: asset.exportPath) == nil)
    }

    @Test
    func pagePlacedImageUsesItsSinglePublicPathFromNestedPages() throws {
        let pagesFolder = PageFolder(name: "Articles", slug: "articles")
        let filesFolder = PageFolder(name: "Downloads", slug: "downloads")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let asset = ProjectAsset(
            filename: "hero.png",
            mediaType: "image/png",
            byteCount: data.count,
            pixelWidth: 1600,
            pixelHeight: 900,
            exportDirectory: .folder(filesFolder.id)
        )
        var image = PartNode.make(.image)
        image.setProperty(.source, value: .url(asset.reference))
        image.setProperty(
            PartPackageAdapter.imageAltKey(for: "source"),
            value: "A descriptive image"
        )
        image.setProperty(
            PartPackageAdapter.imageFocalPointKey(for: "source"),
            value: .array([.number(25), .number(70)])
        )
        let page = Page(title: "Story", slug: "story", parts: [image], folderID: pagesFolder.id)
        let site = Site(
            name: "Files",
            pages: [page],
            pageFolders: [pagesFolder, filesFolder],
            assetLibrary: [.asset(asset)]
        )

        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [asset.id: ProjectAssetContent(asset: asset, data: data)]
        )

        #expect(bundle.file(at: "downloads/hero.png")?.data == data)
        #expect(bundle.file(at: asset.exportPath) == nil)
        let html = try #require(bundle.file(at: "articles/story/index.html")).contents
        #expect(html.contains("src=\"../../downloads/hero.png\""))
        #expect(html.contains("width=\"1600\""))
        #expect(html.contains("height=\"900\""))
        #expect(html.contains("object-position: 25% 70%"))
        #expect(html.contains("alt=\"A descriptive image\""))
    }

    @Test
    func productionHTMLExcludesCanvasMetadataAndDropZones() throws {
        let html = try #require(StaticSiteRenderer().render(site: .starter()).file(at: "index.html")).contents

        #expect(!html.contains("data-foundry"))
        #expect(!html.contains("foundry-selected"))
        #expect(!html.contains("Drop a part"))
        #expect(!html.contains("contenteditable"))
    }

    @Test
    func escapesPageTitlesAndPartContent() throws {
        let text = PartNode(
            type: .paragraph,
            properties: [.init(key: .init(rawValue: "content"), value: .string("<Hello & goodbye>"))]
        )
        let site = Site(name: "Test", pages: [Page(title: "A < B", slug: "index", parts: [text])])

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
    func siteIdentityProvidesPageMetadataFallbacks() throws {
        var site = Site.starter()
        site.titleSuffix = " — Example"
        site.defaultDescription = "Default & description"
        site.favicon = "https://example.com/favicon.png"
        site.defaultSocialImage = "https://example.com/social.png"

        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")).contents

        #expect(html.contains("<title>Home — Example</title>"))
        #expect(html.contains("name=\"description\" content=\"Default &amp; description\""))
        #expect(html.contains("property=\"og:description\" content=\"Default &amp; description\""))
        #expect(html.contains("property=\"og:image\" content=\"https://example.com/social.png\""))
        #expect(html.contains("rel=\"icon\" href=\"https://example.com/favicon.png\""))
    }

    @Test
    func publishingSettingsGenerateCanonicalSitemapAndRobotsFiles() throws {
        var site = Site.starter()
        site.publicURL = "https://example.com"
        site.pages.append(Page(title: "About", slug: "about"))

        let bundle = StaticSiteRenderer().render(site: site)
        let home = try #require(bundle.file(at: "index.html")?.contents)
        let about = try #require(bundle.file(at: "about/index.html")?.contents)
        let sitemap = try #require(bundle.file(at: "sitemap.xml")?.contents)
        let robots = try #require(bundle.file(at: "robots.txt")?.contents)

        #expect(home.contains("rel=\"canonical\" href=\"https://example.com/\""))
        #expect(about.contains("rel=\"canonical\" href=\"https://example.com/about/\""))
        #expect(sitemap.contains("<loc>https://example.com/</loc>"))
        #expect(sitemap.contains("<loc>https://example.com/about/</loc>"))
        #expect(robots.contains("Allow: /"))
        #expect(robots.contains("Sitemap: https://example.com/sitemap.xml"))
    }

    @Test
    func disabledIndexingEmitsNoindexAndBlocksRobots() throws {
        var site = Site.starter()
        site.allowsSearchIndexing = false

        let bundle = StaticSiteRenderer().render(site: site)
        let html = try #require(bundle.file(at: "index.html")?.contents)
        let robots = try #require(bundle.file(at: "robots.txt")?.contents)

        #expect(html.contains("name=\"robots\" content=\"noindex, nofollow\""))
        #expect(robots.contains("Disallow: /"))
        #expect(bundle.file(at: "sitemap.xml") == nil)
    }

    @Test
    func enabledSiteCodeIsPlacedAtEachConfiguredDocumentLocation() throws {
        var site = Site.starter()
        site.headCode = "<meta name=\"site-head\" content=\"enabled\">"
        site.bodyStartCode = "<div id=\"body-start\"></div>"
        site.bodyEndCode = "<div id=\"body-end\"></div>"
        site.analyticsCode = "<script id=\"analytics\"></script>"

        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)

        #expect(html.contains(site.headCode))
        #expect(html.contains(site.bodyStartCode))
        #expect(html.contains(site.bodyEndCode))
        #expect(html.contains(site.analyticsCode))
        let bodyOpen = try #require(html.range(of: "<body>"))
        let bodyStart = try #require(html.range(of: site.bodyStartCode))
        let analytics = try #require(html.range(of: site.analyticsCode))
        let headClose = try #require(html.range(of: "</head>"))
        let bodyEnd = try #require(html.range(of: site.bodyEndCode))
        let bodyClose = try #require(html.range(of: "</body>"))
        #expect(bodyOpen.lowerBound < bodyStart.lowerBound)
        #expect(analytics.lowerBound < headClose.lowerBound)
        #expect(bodyEnd.lowerBound < bodyClose.lowerBound)
    }

    @Test
    func disabledSiteCodeIsRetainedButNotRendered() throws {
        var site = Site.starter()
        site.customCodeEnabled = false
        site.headCode = "<meta name=\"disabled-site-code\">"

        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)

        #expect(!html.contains(site.headCode))
        #expect(site.headCode == "<meta name=\"disabled-site-code\">")
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
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "files/site.css").path))
    }

    @Test
    func writerCleanupOnlyRemovesFilesOwnedByPreviousExport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FoundryExportCleanupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = SiteExportWriter()
        try writer.write(
            SiteExportBundle(files: [
                SiteExportFile(path: "index.html", contents: "old"),
                SiteExportFile(path: "obsolete.html", contents: "obsolete")
            ]),
            to: directory
        )
        try Data("customer file".utf8).write(to: directory.appending(path: "keep.txt"))

        try writer.write(
            SiteExportBundle(files: [SiteExportFile(path: "index.html", contents: "new")]),
            to: directory
        )

        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "obsolete.html").path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "keep.txt").path))
        #expect(try String(contentsOf: directory.appending(path: "index.html"), encoding: .utf8) == "new")
    }

    @Test
    func writerPreservesModifiedObsoleteFilesAndPrunesOnlyEmptyOwnedDirectories() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FoundryExportOwnershipTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = SiteExportWriter()
        try writer.write(
            SiteExportBundle(files: [
                SiteExportFile(path: "old/files/generated.css", contents: "generated"),
                SiteExportFile(path: "changed/files/generated.css", contents: "generated")
            ]),
            to: directory
        )
        let changedURL = directory.appending(path: "changed/files/generated.css")
        try Data("user edit".utf8).write(to: changedURL)

        try writer.write(SiteExportBundle(files: []), to: directory)

        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "old").path))
        #expect(FileManager.default.fileExists(atPath: changedURL.path))
        #expect(try String(contentsOf: changedURL, encoding: .utf8) == "user edit")
    }

    @Test
    func writerRejectsPathsOutsideTheExportRoot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FoundryExportPathTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: SiteExportWriterError.self) {
            try SiteExportWriter().write(
                SiteExportBundle(files: [SiteExportFile(path: "../outside.txt", contents: "unsafe")]),
                to: directory
            )
        }
    }
}
