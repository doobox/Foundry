import Foundation
import Testing
@testable import Foundry

@MainActor
struct ProjectMutationImpactTests {
    @Test
    func componentPropertyEditCarriesItsIdentityAndKey() throws {
        let document = TestSiteFixtures.populatedDocument()
        let component = try #require(document.site.pages.first?.components.first)
        let key = ComponentProperty.Key(rawValue: "content1")

        ProjectEditor(document: document, undoManager: nil).setProperty(
            id: component.id,
            key: key,
            value: "Updated"
        )

        #expect(document.mutationEvent.revision == 1)
        #expect(document.mutationEvent.impact == .componentProperty(componentID: component.id, propertyKey: key))
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
