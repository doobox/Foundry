import Foundation
import Testing
@testable import Foundry

@MainActor
struct ReusableComponentTests {
    @Test
    func reusableDefinitionsRoundTripWithStableIdentifiers() throws {
        let definitionID = UUID()
        var site = Site.starter()
        site.reusableComponents = [
            ReusableComponentDefinition(
                id: definitionID,
                name: "Hero",
                root: ComponentNode(type: .container, children: [ComponentNode.make(.paragraph)])
            )
        ]

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.reusableComponents.first?.id == definitionID)
        #expect(decoded == site)
    }

    @Test
    func savingAndInsertingReusableComponentCreatesFreshTreeIdentifiers() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        let definitionID = try #require(
            editor.saveReusableComponent(componentID: source.id, name: "Hero")
        )
        let insertedID = try #require(
            editor.insertReusableComponent(
                definitionID: definitionID,
                on: site.pages[0].id,
                placement: .end
            )
        )
        let inserted = try #require(document.site.component(withID: insertedID))
        let definition = try #require(document.site.reusableComponents.first)

        #expect(inserted.reusableDefinitionID == nil)
        #expect(inserted.id != source.id)
        #expect(inserted.id != definition.root.id)
        #expect(inserted.children.map(\.id) != definition.root.children.map(\.id))
    }

    @Test
    func detachKeepsLocalContentAndRemovesOnlyTheLink() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        _ = editor.saveReusableComponent(componentID: source.id, name: "Hero")
        let before = try #require(document.site.component(withID: source.id))

        editor.detachReusableComponent(componentID: source.id)
        let after = try #require(document.site.component(withID: source.id))

        #expect(after.reusableDefinitionID == nil)
        #expect(after.name == before.name)
        #expect(after.children == before.children)
    }

    @Test
    func reusableInstancesRemainIndependentAfterInsertion() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveReusableComponent(componentID: source.id, name: "Hero")
        )
        let secondID = try #require(
            editor.insertReusableComponent(
                definitionID: definitionID,
                on: site.pages[0].id,
                placement: .end
            )
        )
        editor.renameComponent(id: source.id, name: "Updated Hero")

        #expect(document.site.component(withID: source.id)?.name == "Updated Hero")
        #expect(document.site.component(withID: secondID)?.name == "Hero")
        #expect(document.site.reusableComponents.first?.root.name == "Hero")
    }

    @Test
    func deletingDefinitionDetachesInstancesWithoutDeletingContent() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveReusableComponent(componentID: source.id, name: "Hero")
        )

        editor.removeReusableComponent(definitionID: definitionID)

        #expect(document.site.reusableComponents.isEmpty)
        #expect(document.site.component(withID: source.id)?.reusableDefinitionID == nil)
        #expect(document.site.component(withID: source.id)?.children.count == source.children.count)
    }

    @Test
    func globalEditingUpdatesEveryInstanceInOneMutation() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveGlobalComponent(componentID: source.id, name: "Hero")
        )
        let secondID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        editor.renameSharedReusableComponentInstance(componentID: source.id, name: "Shared Hero")

        #expect(document.site.component(withID: source.id)?.name == "Shared Hero")
        #expect(document.site.component(withID: secondID)?.name == "Shared Hero")
        #expect(document.site.globalComponents.first?.root.name == "Shared Hero")
    }

    @Test
    func globalsRoundTripSeparatelyFromReusableComponents() throws {
        var site = Site.starter()
        let global = ReusableComponentDefinition(name: "Header", root: ComponentNode.make(.container))
        site.globalComponents = [global]

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.globalComponents == [global])
        #expect(decoded.reusableComponents.isEmpty)
    }

    @Test
    func editingNestedGlobalContentUpdatesEveryInstanceAndPreservesSelectionIdentity() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let sourceText = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )
        let secondTextID = try #require(document.site.component(withID: secondRootID)?.children.first?.id)

        editor.setSharedReusableProperty(componentID: sourceText.id, key: .text, value: .string("Global heading"))

        #expect(document.site.component(withID: sourceText.id)?.property(.text) == "Global heading")
        #expect(document.site.component(withID: secondTextID)?.property(.text) == "Global heading")
        #expect(document.site.component(withID: sourceText.id)?.id == sourceText.id)
        #expect(document.site.component(withID: secondTextID)?.id == secondTextID)
    }

    @Test
    func editingGlobalTextUpdatesAnInstanceOnAnotherPage() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let sourceText = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondPageID = editor.addPage()
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: secondPageID, placement: .end)
        )
        let secondTextID = try #require(document.site.component(withID: secondRootID)?.children.first?.id)

        editor.setSharedReusableProperty(componentID: sourceText.id, key: .text, value: .string("Across every page"))

        #expect(document.site.component(withID: sourceText.id)?.property(.text) == "Across every page")
        #expect(document.site.component(withID: secondTextID)?.property(.text) == "Across every page")
    }

    @Test
    func unlockedGlobalChildKeepsLocalContentUntilRelinked() throws {
        let site = TestSiteFixtures.populatedSite()
        let firstRoot = try #require(site.pages.first?.components.first)
        let firstText = try #require(firstRoot.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: firstRoot.id, name: "Hero"))
        let secondPageID = editor.addPage()
        let secondRootID = try #require(editor.insertGlobalComponent(definitionID: definitionID, on: secondPageID, placement: .end))
        let secondTextID = try #require(document.site.component(withID: secondRootID)?.children.first?.id)

        editor.setGlobalComponentLinked(componentID: secondTextID, isLinked: false)
        editor.setProperty(id: secondTextID, key: .text, value: .string("Page-specific heading"))
        editor.setSharedReusableProperty(componentID: firstText.id, key: .text, value: .string("Global heading"))

        #expect(document.site.component(withID: firstText.id)?.property(.text) == "Global heading")
        #expect(document.site.component(withID: secondTextID)?.property(.text) == "Page-specific heading")
        #expect(document.site.globalComponentContext(containing: secondTextID)?.isOverridden == true)

        editor.setGlobalComponentLinked(componentID: secondTextID, isLinked: true)

        #expect(document.site.component(withID: secondTextID)?.property(.text) == "Global heading")
        #expect(document.site.globalComponentContext(containing: secondTextID)?.isOverridden == false)
    }
}
