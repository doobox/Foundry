import Foundation
import Testing
@testable import Foundry

@MainActor
struct ProjectMutationImpactTests {
    @Test
    func siteCodeSavesAsOneUndoableMutation() {
        var site = Site(name: "Code", pages: [])
        site.headCode = "<!-- original -->"
        let document = FoundryDocument(site: site)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        ProjectEditor(document: document, undoManager: undoManager).setSiteCode(
            isEnabled: false, head: "<style>body { color: red; }</style>",
            bodyStart: "<!-- start -->", bodyEnd: "<!-- end -->", css: "body { color: red; }", javaScript: "console.log('site');"
        )
        undoManager.endUndoGrouping()
        #expect(document.mutationEvent.revision == 1)
        #expect(document.mutationEvent.impact == .page)
        #expect(document.site.customCodeEnabled == false)
        #expect(document.site.headCode == "<style>body { color: red; }</style>")
        #expect(document.site.bodyStartCode == "<!-- start -->")
        #expect(document.site.bodyEndCode == "<!-- end -->")
        #expect(document.site.cssCode == "body { color: red; }")
        #expect(document.site.javaScriptCode == "console.log('site');")
        undoManager.undo()
        #expect(document.site.headCode == site.headCode)
        #expect(document.site.bodyStartCode == site.bodyStartCode)
        #expect(document.site.bodyEndCode == site.bodyEndCode)
        #expect(document.site.cssCode == site.cssCode)
        #expect(document.site.javaScriptCode == site.javaScriptCode)
        #expect(document.site.customCodeEnabled == site.customCodeEnabled)
        #expect(undoManager.canUndo == false)
        undoManager.redo()
        #expect(document.site.customCodeEnabled == false)
        #expect(document.site.cssCode == "body { color: red; }")
        #expect(document.site.javaScriptCode == "console.log('site');")
    }

    @Test
    func partPropertyEditCarriesItsIdentityAndKey() throws {
        let document = TestSiteFixtures.populatedDocument()
        let part = try #require(document.site.pages.first?.parts.first)
        let key = PartProperty.Key(rawValue: "content")

        ProjectEditor(document: document, undoManager: nil).setProperty(
            id: part.id,
            key: key,
            value: "Updated"
        )

        #expect(document.mutationEvent.revision == 1)
        #expect(document.mutationEvent.impact == .partProperty(partID: part.id, propertyKey: key))
    }

    @Test
    func multiPartPropertyEditUpdatesEveryInstanceAsOneUndoableMutation() throws {
        let key = PartProperty.Key(rawValue: "content")
        let first = PartNode(
            type: .paragraph,
            properties: [.init(key: key, value: .string("First"))]
        )
        let second = PartNode(
            type: .paragraph,
            properties: [.init(key: key, value: .string("Second"))]
        )
        let document = FoundryDocument(
            site: Site(name: "Test", pages: [Page(title: "Home", slug: "index", parts: [first, second])])
        )
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        ProjectEditor(document: document, undoManager: undoManager).setProperties(
            ids: [first.id, second.id],
            key: key,
            value: .string("Shared")
        )
        undoManager.endUndoGrouping()

        #expect(document.site.part(withID: first.id)?.propertyValue(key) == .string("Shared"))
        #expect(document.site.part(withID: second.id)?.propertyValue(key) == .string("Shared"))
        guard case .partProperties(let ids, let propertyKey) = document.mutationEvent.impact else {
            Issue.record("Expected a multi-part mutation impact")
            return
        }
        #expect(Set(ids) == Set([first.id, second.id]))
        #expect(propertyKey == key)
        #expect(undoManager.canUndo)

        undoManager.undo()

        #expect(document.site.part(withID: first.id)?.propertyValue(key) == .string("First"))
        #expect(document.site.part(withID: second.id)?.propertyValue(key) == .string("Second"))
        #expect(!undoManager.canUndo)
    }

    @Test
    func publishingEditDoesNotAffectRenderedOutput() {
        let document = TestSiteFixtures.populatedDocument()

        ProjectEditor(document: document, undoManager: nil).setPublishingHost("example.com")

        #expect(document.mutationEvent.impact == .publishingOnly)
        #expect(!document.mutationEvent.impact.affectsRenderedOutput)
    }

    @Test
    func assetContentsReuseSnapshotUntilAssetRevisionChanges() {
        let document = FoundryDocument(site: Site.starter())

        _ = document.assetContents
        _ = document.assetContents
        #expect(document.assetContentsBuildCount == 1)

        _ = document.importAsset(
            data: Data("hello".utf8),
            filename: "hello.txt",
            mediaType: "text/plain",
            undoManager: nil
        )
        _ = document.assetContents

        #expect(document.assetContentsBuildCount == 2)
        #expect(document.mutationEvent.impact == .assets)
    }

    @Test
    func continuousInteractionKeepsModelCurrentAndCreatesOneUndoStep() {
        let document = FoundryDocument(site: Site.starter())
        let originalName = document.site.name
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let transaction = ContinuousUndoTransaction()
        transaction.undoManager = undoManager

        transaction.begin()
        editor.setSiteName("First")
        #expect(document.site.name == "First")
        editor.setSiteName("Second")
        #expect(document.site.name == "Second")
        editor.setSiteName("Final")
        transaction.end()

        #expect(document.site.name == "Final")
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(document.site.name == originalName)
        #expect(!undoManager.canUndo)
    }
}
