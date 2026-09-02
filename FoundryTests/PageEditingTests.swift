import Foundation
import Testing
@testable import Foundry

@MainActor
struct PageEditingTests {
    @Test
    func completeSiteURLDropsItsTrailingSlashWithoutBreakingAnIncompleteScheme() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)

        editor.setSitePublicURL("https://")
        #expect(document.site.publicURL == "https://")

        editor.setSitePublicURL("https://example.com/")
        #expect(document.site.publicURL == "https://example.com")

        editor.setSitePublicURL("https://example.com/subsite/")
        #expect(document.site.publicURL == "https://example.com/subsite")
    }

    @Test
    func createsPageWithUniqueSlugAndStableIdentifier() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)

        let pageID = editor.addPage()
        let page = document.site.pages.first(where: { $0.id == pageID })

        #expect(page != nil)
        #expect(page?.title == "Page 2")
        #expect(page?.slug == "page-2")
        #expect(document.site.pages.count == 2)
    }

    @Test
    func derivesEachNewPageSlugFromItsGeneratedTitle() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)

        _ = editor.addPage()
        let pageID = editor.addPage()
        let page = document.site.pages.first(where: { $0.id == pageID })

        #expect(page?.title == "Page 3")
        #expect(page?.slug == "page-3")
    }

    @Test
    func duplicatesPageWithFreshTreeIdentifiers() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let source = try #require(document.site.pages.first)
        let sourceComponent = try #require(source.components.first)

        let duplicateID = try #require(editor.duplicatePage(id: source.id))
        let duplicate = try #require(
            document.site.pages.first(where: { $0.id == duplicateID })
        )

        #expect(duplicate.id != source.id)
        #expect(duplicate.slug == "index-2")
        #expect(duplicate.components.first?.id != sourceComponent.id)
        #expect(duplicate.components.first?.children.first?.id !=
                sourceComponent.children.first?.id)
    }

    @Test
    func cannotDeleteFinalPage() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let pageID = try #require(document.site.pages.first?.id)

        let nextSelection = editor.removePage(id: pageID)

        #expect(nextSelection == nil)
        #expect(document.site.pages.count == 1)
    }

    @Test
    func cannotDeleteHomePageWhenOtherPagesExist() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let homeID = try #require(document.site.pages.first?.id)
        _ = editor.addPage()

        let nextSelection = editor.removePage(id: homeID)

        #expect(nextSelection == nil)
        #expect(document.site.pages.contains(where: { $0.id == homeID }))
        #expect(document.site.pages.count == 2)
    }

    @Test
    func nonHomePageCanBeDeleted() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let pageID = editor.addPage()

        _ = editor.removePage(id: pageID)

        #expect(!document.site.pages.contains(where: { $0.id == pageID }))
        #expect(document.site.pages.count == 1)
        #expect(document.site.pages.first?.slug == "index")
    }

    @Test
    func pageChangesParticipateInUndoAndRedo() {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)

        let pageID = editor.addPage()
        #expect(document.site.pages.contains(where: { $0.id == pageID }))

        undoManager.undo()
        #expect(!document.site.pages.contains(where: { $0.id == pageID }))

        undoManager.redo()
        #expect(document.site.pages.contains(where: { $0.id == pageID }))
    }

    @Test
    func metadataChangesParticipateInUndoAndRedo() throws {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let pageID = try #require(document.site.pages.first?.id)

        editor.setPageMetadata(id: pageID) {
            $0.browserTitle = "A better title"
        }
        #expect(document.site.pages.first?.metadata.browserTitle == "A better title")

        undoManager.undo()
        #expect(document.site.pages.first?.metadata.browserTitle == "")

        undoManager.redo()
        #expect(document.site.pages.first?.metadata.browserTitle == "A better title")
    }

    @Test
    func reordersPagesWithoutChangingIdentity() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let homeID = document.site.pages[0].id
        let secondID = editor.addPage()
        let thirdID = editor.addPage()

        editor.movePage(id: thirdID, offset: -1)

        let visibleOrder = document.site.pages
            .sorted { $0.order < $1.order }
            .map(\.id)
        #expect(visibleOrder == [homeID, thirdID, secondID])
    }

    @Test
    func setsTopLevelPageAsHomeWithoutLosingPreviousRoute() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let previousHomeID = try #require(document.site.pages.first?.id)
        let newHomeID = editor.addPage()
        let previousRoute = try #require(
            document.site.pages.first(where: { $0.id == newHomeID })?.slug
        )

        editor.setHomePage(id: newHomeID)

        #expect(document.site.pages.first(where: { $0.id == newHomeID })?.slug == "index")
        #expect(document.site.pages.first(where: { $0.id == previousHomeID })?.slug == previousRoute)
        #expect(document.site.pages.filter { $0.slug == "index" }.count == 1)
        let rootOrder = document.site.pages
            .filter { $0.folderID == nil }
            .sorted { $0.order < $1.order }
            .map(\.id)
        #expect(rootOrder.first == newHomeID)
    }

    @Test
    func homePageSlugAndTreePositionCannotBeChangedDirectly() throws {
        let folder = PageFolder(name: "Company", slug: "company", order: 1)
        let site = Site(
            name: "Protected Home",
            pages: [Page(title: "Home", slug: "index", order: 0)],
            pageFolders: [folder],
            assetLibrary: []
        )
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let homeID = try #require(document.site.pages.first?.id)

        editor.setPageSlug(id: homeID, slug: "welcome")
        let movedIntoFolder = editor.movePageTreeItem(.page(homeID), to: .insideFolder(folder.id))
        let placedBeforeHome = editor.movePageTreeItem(.folder(folder.id), to: .before(.page(homeID)))

        #expect(document.site.pages.first?.slug == "index")
        #expect(document.site.pages.first?.folderID == nil)
        #expect(!movedIntoFolder)
        #expect(!placedBeforeHome)
    }

    @Test
    func nestedPageCannotBecomeHome() throws {
        let folder = PageFolder(name: "Company", slug: "company")
        let nestedPage = Page(title: "About", slug: "about", folderID: folder.id)
        let site = Site(
            name: "Nested",
            pages: [Page(title: "Home", slug: "index"), nestedPage],
            pageFolders: [folder],
            assetLibrary: []
        )
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)

        editor.setHomePage(id: nestedPage.id)

        #expect(document.site.pages.first(where: { $0.id == nestedPage.id })?.slug == "about")
        #expect(document.site.pages.filter { $0.slug == "index" }.count == 1)
    }

    @Test
    func movesPagesAndFoldersThroughTheExportTree() throws {
        let page = Page(title: "About", slug: "about")
        let parent = PageFolder(name: "Company", slug: "company")
        let child = PageFolder(name: "Team", slug: "team")
        let site = Site(
            name: "Tree",
            pages: [page],
            pageFolders: [parent, child],
            assetLibrary: []
        )
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)

        #expect(editor.movePageTreeItem(.folder(child.id), to: .insideFolder(parent.id)))
        #expect(editor.movePageTreeItem(.page(page.id), to: .insideFolder(child.id)))
        #expect(document.site.pageFolders.first(where: { $0.id == child.id })?.parentID == parent.id)
        #expect(document.site.pages.first?.folderID == child.id)
        #expect(!editor.movePageTreeItem(.folder(parent.id), to: .insideFolder(child.id)))
    }

    @Test
    func placesManagedAssetsInThePageExportTree() throws {
        let asset = ProjectAsset(filename: "robots.txt", mediaType: "text/plain", byteCount: 12)
        let folder = PageFolder(name: "Public", slug: "public")
        let site = Site(
            name: "Assets",
            pages: [Page(title: "Home", slug: "index")],
            pageFolders: [folder],
            assetLibrary: [.asset(asset)]
        )
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)

        #expect(editor.movePageTreeItem(.asset(asset.id), to: .insideFolder(folder.id)))
        let movedAsset = try #require(document.site.assets.first)
        #expect(movedAsset.exportDirectory == ProjectAsset.ExportDirectory.folder(folder.id))
    }

    @Test
    func editsSelectedFolderInformationWithUndoSupport() throws {
        let folder = PageFolder(name: "Original", slug: "original")
        let site = Site(
            name: "Folders",
            pages: [Page(title: "Home", slug: "index")],
            pageFolders: [folder],
            assetLibrary: []
        )
        let document = FoundryDocument(site: site)
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)

        editor.renamePageFolder(id: folder.id, name: "Downloads")
        editor.setPageFolderSlug(id: folder.id, slug: "Customer Files")

        let edited = try #require(document.site.pageFolders.first)
        #expect(edited.name == "Downloads")
        #expect(edited.slug == "customer-files")
        undoManager.undo()
        #expect(document.site.pageFolders.first?.slug == "original")
    }
}
