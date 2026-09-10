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

    @Test
    func movingLocalComponentIntoGlobalUpdatesEveryInstance() throws {
        var site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let local = ComponentNode(type: .paragraph, name: "Local addition")
        site.pages[0].components.append(local)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.moveComponent(id: local.id, on: site.pages[0].id, to: .inside(source.id)))

        #expect(document.site.component(withID: source.id)?.children.last?.id == local.id)
        #expect(document.site.component(withID: secondRootID)?.children.last?.name == "Local addition")
        #expect(document.site.globalComponents.first?.root.children.last?.name == "Local addition")
    }

    @Test
    func insertingNewComponentIntoGlobalUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let lastChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        let insertedID = try #require(
            editor.insertComponent(type: .paragraph, on: site.pages[0].id, placement: .after(lastChild.id))
        )

        #expect(document.site.component(withID: source.id)?.children.last?.id == insertedID)
        #expect(document.site.component(withID: secondRootID)?.children.last?.type == .paragraph)
        #expect(document.site.globalComponents.first?.root.children.last?.type == .paragraph)
    }

    @Test
    func deletingAndDuplicatingNestedGlobalComponentsUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let firstChild = try #require(source.children.first)
        let secondChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        let duplicateID = try #require(editor.duplicateComponent(id: firstChild.id, on: site.pages[0].id))
        #expect(document.site.component(withID: source.id)?.children.count == 3)
        #expect(document.site.component(withID: secondRootID)?.children.count == 3)

        editor.removeComponent(id: secondChild.id)
        #expect(document.site.component(withID: source.id)?.children.count == 2)
        #expect(document.site.component(withID: secondRootID)?.children.count == 2)
        #expect(document.site.component(withID: duplicateID) != nil)
    }

    @Test
    func linkedGlobalMetadataAndPropertiesSynchronizeButAnchorRemainsLocal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let sourceChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )
        let secondChildID = try #require(document.site.component(withID: secondRootID)?.children.first?.id)

        editor.renameComponent(id: sourceChild.id, name: "Shared name")
        editor.setComponentClasses(id: sourceChild.id, classes: "shared-class")
        editor.setComponentRootAttributes(
            id: sourceChild.id,
            attributes: [ComponentHTMLAttribute(name: "data-role", value: "hero")]
        )
        editor.setProperty(id: sourceChild.id, key: .text, value: .string("Shared value"))
        editor.setComponentAnchor(id: sourceChild.id, anchor: "local-anchor")

        let secondChild = try #require(document.site.component(withID: secondChildID))
        #expect(secondChild.name == "Shared name")
        #expect(secondChild.customClasses == "shared-class")
        #expect(secondChild.rootAttributes?.first?.name == "data-role")
        #expect(secondChild.property(.text) == "Shared value")
        #expect(secondChild.anchor == nil)
        #expect(document.site.component(withID: sourceChild.id)?.anchor == "local-anchor")
    }

    @Test
    func movingComponentOutOfGlobalUpdatesEveryInstanceAndKeepsDraggedNodeLocal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let movedChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.moveComponent(id: movedChild.id, on: site.pages[0].id, to: .after(source.id)))

        #expect(document.site.component(withID: source.id)?.children.count == 1)
        #expect(document.site.component(withID: secondRootID)?.children.count == 1)
        #expect(document.site.pages[0].components.contains(where: { $0.id == movedChild.id }))
        #expect(document.site.component(withID: movedChild.id)?.reusableDefinitionID == nil)
    }

    @Test
    func reorderingInsideGlobalUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let firstChild = try #require(source.children.first)
        let secondChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.moveComponent(id: firstChild.id, on: site.pages[0].id, to: .after(secondChild.id)))

        #expect(document.site.component(withID: source.id)?.children.map(\.name) == ["Call to action", "Paragraph"])
        #expect(document.site.component(withID: secondRootID)?.children.map(\.name) == ["Call to action", "Paragraph"])
    }

    @Test
    func movingBetweenInstancesOfSameGlobalIsRejected() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.components.first)
        let sourceChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalComponent(componentID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalComponent(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(!editor.moveComponent(id: sourceChild.id, on: site.pages[0].id, to: .inside(secondRootID)))
        #expect(document.site.component(withID: source.id)?.children.count == 2)
        #expect(document.site.component(withID: secondRootID)?.children.count == 2)
    }
}
