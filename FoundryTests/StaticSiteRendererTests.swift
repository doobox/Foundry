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
            framework: site.framework
        )

        #expect(exportedCSS.contains("html,body{min-height:100%}"))
        // svh, not a percentage: body's min-height must not depend on the
        // html height chain, or flex-grow parts have no space to fill.
        #expect(exportedCSS.contains("body{margin:0;min-height:100svh;background:"))
        #expect(exportedCSS.contains("display:flex;flex-direction:column;align-items:stretch"))
        #expect(exportedCSS.contains("*,*::before,*::after{box-sizing:border-box;border-width:0;border-style:solid;border-color:currentColor}"))
        #expect(exportedCSS.contains("--bs-primary-base:"))
        #expect(exportedCSS.contains("--bs-bg-body:"))
        #expect(exportedCSS.contains("a{color:var(--bs-primary-fg)}"))
        #expect(exportedCSS.contains("--foundry-spacing-base:"))
        #expect(exportedCSS.contains(".fd-container{"))
        #expect(!exportedCSS.contains("--background:"))
        #expect(!exportedCSS.contains("--framework-container-width:"))
        #expect(!exportedCSS.contains("padding:48px"))
        #expect(canvasHTML.contains("html,body{min-height:100%}"))
        #expect(canvasHTML.contains("display:flex;flex-direction:column;align-items:stretch"))
        #expect(canvasHTML.contains("--bs-primary-base:"))
        #expect(canvasHTML.contains("--bs-bg-body:"))
        #expect(canvasHTML.contains("a{color:var(--bs-primary-fg)}"))
        #expect(canvasHTML.contains("--foundry-editor-chrome"))
        #expect(canvasHTML.contains(".fd-container{"))
        #expect(!canvasHTML.contains("--background:"))
        #expect(!canvasHTML.contains("padding: 48px"))
    }

    @Test
    func responsiveOverridesExportAsMediaQueriesWithoutCanvasMetadata() throws {
        var site = TestSiteFixtures.populatedSite()
        // Section roots no longer carry the sizing max-width; a Flex
        // exercises the shared responsive control instead.
        let stack = PartNode.make(.stack)
        site.pages[0].parts.insert(stack, at: 0)
        let partID = stack.id
        site.updatePart(id: partID) {
            for (amount, breakpoint) in [(800.0, ResponsiveBreakpoint.mobile), (900, .medium), (1000, .large)] {
                $0.setResponsiveProperty(
                    .init(rawValue: "sizing.maxWidth"),
                    value: .frameworkSpacing(.init(
                        selection: .init(token: "none", isCustom: true, amount: amount, unit: "px")
                    )),
                    at: breakpoint
                )
            }
        }

        let bundle = StaticSiteRenderer().render(site: site)
        let css = try #require(bundle.files.first(where: { $0.path == "files/page.css" })?.contents)
        let html = try #require(bundle.files.first(where: { $0.path == "index.html" })?.contents)

        #expect(css.contains("@media(min-width:768px)"))
        #expect(css.contains("@media(min-width:1024px)"))
        #expect(!css.contains("@media(max-width:"))
        #expect(css.contains("max-width: min(100%, 800.0px)"))
        #expect(css.contains("max-width: min(100%, 900.0px)"))
        #expect(css.contains("max-width: min(100%, 1000.0px)"))
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
        #expect(try #require(bundle.file(at: "index.html")).contents.contains("href=\"files/site.css?v="))
        #expect(try #require(bundle.file(at: "about/index.html")).contents.contains("href=\"../files/site.css?v="))
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
        #expect(about.contents.contains("href=\"../../../files/site.css?v="))
    }

    @Test
    func explicitlyPlacedAssetExportsAtItsPageTreeLocation() throws {
        let folder = PageFolder(name: "Downloads", slug: "downloads")
        let data = Data("hello".utf8)
        let asset = ProjectAsset(
            filename: "guide.txt",
            mediaType: "text/plain",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data),
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
            contentDigest: FoundryDocumentSnapshot.digest(for: data),
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
    func sitewideSocialTagsEmitAutomatically() throws {
        var site = Site.starter()
        site.name = "Doobox"
        site.publicURL = "https://example.com"
        site.language = "en-GB"
        site.defaultSocialImage = "https://example.com/share.png"
        site.socialImageAlt = "The Doobox logo on a blue field"
        site.socialAccount = "@doobox"
        var about = Page(title: "About", slug: "about")
        about.language = "fr"
        site.pages.append(about)

        let bundle = StaticSiteRenderer().render(site: site)
        let html = try #require(bundle.file(at: "about/index.html")?.contents)

        #expect(html.contains("<meta property=\"og:site_name\" content=\"Doobox\">"))
        #expect(html.contains("<meta property=\"og:type\" content=\"website\">"))
        // The page's language override wins and hyphens become underscores.
        #expect(html.contains("<meta property=\"og:locale\" content=\"fr\">"))
        #expect(html.contains("<meta property=\"og:url\" content=\"https://example.com/about/\">"))
        #expect(html.contains("<meta property=\"og:image:alt\" content=\"The Doobox logo on a blue field\">"))
        #expect(html.contains("<meta name=\"twitter:card\" content=\"summary_large_image\">"))
        #expect(html.contains("<meta name=\"twitter:site\" content=\"@doobox\">"))
        let home = try #require(bundle.file(at: "index.html")?.contents)
        #expect(home.contains("<meta property=\"og:locale\" content=\"en_GB\">"))

        // Without any social image the card falls back to summary, and a
        // page-provided image drops the site-wide alt text.
        var plain = Site.starter()
        plain.pages[0].metadata.socialImage = "https://example.com/custom.png"
        plain.socialImageAlt = "Never emitted for page images"
        let plainHTML = try #require(StaticSiteRenderer().render(site: plain).file(at: "index.html")?.contents)
        #expect(plainHTML.contains("<meta name=\"twitter:card\" content=\"summary_large_image\">"))
        #expect(!plainHTML.contains("og:image:alt"))
        #expect(!plainHTML.contains("twitter:site"))
        var bare = Site.starter()
        bare.socialAccount = "doobox"
        let bareHTML = try #require(StaticSiteRenderer().render(site: bare).file(at: "index.html")?.contents)
        #expect(bareHTML.contains("<meta name=\"twitter:card\" content=\"summary\">"))
    }

    @Test
    func perPageSearchExclusionEmitsNoindexAndLeavesTheSitemap() throws {
        var site = Site.starter()
        site.publicURL = "https://example.com"
        var hidden = Page(title: "Thanks", slug: "thanks")
        hidden.includeInSearch = false
        site.pages.append(hidden)

        let bundle = StaticSiteRenderer().render(site: site)
        let hiddenHTML = try #require(bundle.file(at: "thanks/index.html")?.contents)
        let home = try #require(bundle.file(at: "index.html")?.contents)
        let sitemap = try #require(bundle.file(at: "sitemap.xml")?.contents)

        #expect(hiddenHTML.contains("<meta name=\"robots\" content=\"noindex\">"))
        #expect(!home.contains("noindex"))
        #expect(home.contains("<meta name=\"generator\" content=\"Foundry\">"))
        #expect(!sitemap.contains("thanks"))
        #expect(sitemap.contains("<loc>https://example.com/</loc>"))

        // The site-wide switch still outranks the page's own setting.
        site.allowsSearchIndexing = false
        let locked = StaticSiteRenderer().render(site: site)
        let lockedHome = try #require(locked.file(at: "index.html")?.contents)
        #expect(lockedHome.contains("<meta name=\"robots\" content=\"noindex, nofollow\">"))
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
    func folderAndFilenameOverridesControlOutputLinksLanguageAndSitemap() throws {
        var site = Site.starter()
        site.publicURL = "https://example.com"
        site.language = "en"
        var menu = Page(title: "Menu", slug: "menu")
        menu.folderOverride = ""
        menu.filenameOverride = "menu"
        menu.includeInSitemap = false
        var archive = Page(title: "Archive", slug: "archive")
        archive.folderOverride = "photos/2026"
        archive.language = "fr"
        site.pages.append(contentsOf: [menu, archive])

        let bundle = StaticSiteRenderer().render(site: site)

        // The overrides place the files; the derived locations don't exist.
        let menuHTML = try #require(bundle.file(at: "menu.html")?.contents)
        let archiveHTML = try #require(bundle.file(at: "photos/2026/index.html")?.contents)
        #expect(bundle.file(at: "menu/index.html") == nil)
        #expect(bundle.file(at: "archive/index.html") == nil)

        // Pretty URLs stand for index files; custom filenames stay visible.
        #expect(StaticSiteRenderer.urlPath(for: menu, pages: site.pages, folders: site.pageFolders) == "/menu.html")
        #expect(StaticSiteRenderer.urlPath(for: archive, pages: site.pages, folders: site.pageFolders) == "/photos/2026/")
        let link = PartLinkResolver.resolve(
            .init(destination: .page(menu.id)), pages: site.pages, folders: site.pageFolders,
            assets: [], assetLibrary: nil, publicURL: "", absoluteURL: false
        )
        #expect(link.href == "/menu.html")

        // Canonical URLs, sitemap membership, and the page language follow.
        #expect(menuHTML.contains("rel=\"canonical\" href=\"https://example.com/menu.html\""))
        #expect(archiveHTML.contains("<html lang=\"fr\">"))
        #expect(menuHTML.contains("<html lang=\"en\">"))
        let sitemap = try #require(bundle.file(at: "sitemap.xml")?.contents)
        #expect(sitemap.contains("<loc>https://example.com/photos/2026/</loc>"))
        #expect(!sitemap.contains("menu.html"))
    }

    @Test
    func filenameOverrideExtensionYieldsToPHPRequirements() throws {
        var page = Page(title: "Contact", slug: "contact")
        page.filenameOverride = "contact.php"
        #expect(StaticSiteRenderer.filename(for: page) == "contact.php")
        page.filenameOverride = "contact"
        page.preferredExtension = .php
        #expect(StaticSiteRenderer.filename(for: page) == "contact.php")
        page.preferredExtension = nil
        #expect(StaticSiteRenderer.filename(for: page) == "contact.html")
        // The home page ignores filename overrides entirely.
        var home = Page(title: "Home", slug: "index")
        home.filenameOverride = "welcome.html"
        #expect(StaticSiteRenderer.filename(for: home) == "index.html")
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
    func writerRemovesManagedWebIconsWhenGeneralCleanupIsDisabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FoundryWebIconCleanupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SiteExportWriter()
        let iconPath = "assets/web-icons/favicon.ico"

        try writer.write(
            SiteExportBundle(files: [
                .init(path: "index.html", contents: "old"),
                .init(path: iconPath, contents: "icon")
            ]),
            to: directory
        )
        try writer.write(
            SiteExportBundle(files: [.init(path: "index.html", contents: "new")]),
            to: directory,
            cleaningObsoleteFiles: false
        )

        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: iconPath).path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "index.html").path))
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

    @Test
    func cacheBustingVersionsGeneratedStylesAndScripts() throws {
        var site = Site.starter()
        site.generatesCacheBustingLinks = true

        let bundle = StaticSiteRenderer().render(site: site)
        let html = try #require(bundle.file(at: "index.html")?.contents)

        #expect(html.contains("files/site.css?v="))
        #expect(html.contains("files/page.css?v="))
    }

    @Test
    func cacheBustingCanBeDisabled() throws {
        var site = Site.starter()
        site.generatesCacheBustingLinks = false

        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)

        #expect(html.contains("href=\"files/site.css\""))
        #expect(!html.contains("files/site.css?v="))
    }

    @Test @MainActor
    func defaultExtensionOnlyAppliesWhenCreatingNewPages() throws {
        let document = FoundryDocument(site: .starter())
        let editor = ProjectEditor(document: document, undoManager: nil)
        let existingPage = try #require(document.site.pages.first)
        editor.setDefaultPageExtension(.php)
        let newPageID = editor.addPage()
        let newPage = try #require(document.site.pages.first(where: { $0.id == newPageID }))

        #expect(StaticSiteRenderer.outputPath(for: existingPage, in: document.site) == "index.html")
        #expect(newPage.preferredExtension == .php)
        #expect(StaticSiteRenderer.outputPath(for: newPage, in: document.site).hasSuffix("index.php"))
    }

    @Test
    func unsafeMinificationFallsBackToOriginalJavaScript() {
        var site = Site.starter()
        site.minifiesGeneratedOutput = true
        let script = "const pattern = /a b/;\nconsole.log(pattern);"

        let output = PublishedOutputProcessor.process(
            [.init(path: "files/page.js", contents: script)],
            for: site
        )

        #expect(output[0].contents == script)
    }

    @Test
    func safeGeneratedCSSAndJavaScriptAreMinified() {
        var site = Site.starter()
        site.minifiesGeneratedOutput = true
        site.generatesCacheBustingLinks = false

        let output = PublishedOutputProcessor.process([
            .init(path: "files/site.css", contents: "body {\n    color: red;\n}"),
            .init(path: "files/page.js", contents: "const   answer =   42;\n")
        ], for: site)

        #expect(output[0].contents == "body { color: red; }")
        #expect(output[1].contents == "const answer = 42;")
    }

    @Test
    func cacheBustingVersionIsStableAndChangesOnlyWithContent() throws {
        var site = Site.starter()
        site.generatesCacheBustingLinks = true
        let html = SiteExportFile(
            path: "index.html",
            contents: "<link rel=\"stylesheet\" href=\"files/site.css\">"
        )

        let first = PublishedOutputProcessor.process([
            html, .init(path: "files/site.css", contents: "body { color: red; }")
        ], for: site)
        let second = PublishedOutputProcessor.process([
            html, .init(path: "files/site.css", contents: "body { color: red; }")
        ], for: site)
        let changed = PublishedOutputProcessor.process([
            html, .init(path: "files/site.css", contents: "body { color: blue; }")
        ], for: site)
        let firstHTML = try #require(first.first?.contents)
        let secondHTML = try #require(second.first?.contents)
        let changedHTML = try #require(changed.first?.contents)

        #expect(firstHTML == secondHTML)
        #expect(firstHTML != changedHTML)
    }
}
