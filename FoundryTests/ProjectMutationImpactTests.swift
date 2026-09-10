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
}
