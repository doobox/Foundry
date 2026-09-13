import Foundation
import Testing
@testable import Foundry

@MainActor
struct ReusablePartTests {
    @Test
    func reusableDefinitionsRoundTripWithStableIdentifiers() throws {
        let definitionID = UUID()
        var site = Site.starter()
        site.reusableParts = [
            ReusablePartDefinition(
                id: definitionID,
                name: "Hero",
                root: PartNode(type: .container, children: [PartNode.make(.paragraph)])
            )
        ]

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.reusableParts.first?.id == definitionID)
        #expect(decoded == site)
    }

    @Test
    func savingAndInsertingReusablePartCreatesFreshTreeIdentifiers() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        let definitionID = try #require(
            editor.saveReusablePart(partID: source.id, name: "Hero")
        )
        let insertedID = try #require(
            editor.insertReusablePart(
                definitionID: definitionID,
                on: site.pages[0].id,
                placement: .end
            )
        )
        let inserted = try #require(document.site.part(withID: insertedID))
        let definition = try #require(document.site.reusableParts.first)

        #expect(inserted.reusableDefinitionID == nil)
        #expect(inserted.id != source.id)
        #expect(inserted.id != definition.root.id)
        #expect(inserted.children.map(\.id) != definition.root.children.map(\.id))
    }

    @Test
    func detachKeepsLocalContentAndRemovesOnlyTheLink() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        _ = editor.saveReusablePart(partID: source.id, name: "Hero")
        let before = try #require(document.site.part(withID: source.id))

        editor.detachReusablePart(partID: source.id)
        let after = try #require(document.site.part(withID: source.id))

        #expect(after.reusableDefinitionID == nil)
        #expect(after.name == before.name)
        #expect(after.children == before.children)
    }

    @Test
    func reusableInstancesRemainIndependentAfterInsertion() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveReusablePart(partID: source.id, name: "Hero")
        )
        let secondID = try #require(
            editor.insertReusablePart(
                definitionID: definitionID,
                on: site.pages[0].id,
                placement: .end
            )
        )
        editor.renamePart(id: source.id, name: "Updated Hero")

        #expect(document.site.part(withID: source.id)?.name == "Updated Hero")
        #expect(document.site.part(withID: secondID)?.name == "Hero")
        #expect(document.site.reusableParts.first?.root.name == "Hero")
    }

    @Test
    func deletingDefinitionDetachesInstancesWithoutDeletingContent() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveReusablePart(partID: source.id, name: "Hero")
        )

        editor.removeReusablePart(definitionID: definitionID)

        #expect(document.site.reusableParts.isEmpty)
        #expect(document.site.part(withID: source.id)?.reusableDefinitionID == nil)
        #expect(document.site.part(withID: source.id)?.children.count == source.children.count)
    }

    @Test
    func globalEditingUpdatesEveryInstanceInOneMutation() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveGlobalPart(partID: source.id, name: "Hero")
        )
        let secondID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        editor.renameSharedReusablePartInstance(partID: source.id, name: "Shared Hero")

        #expect(document.site.part(withID: source.id)?.name == "Shared Hero")
        #expect(document.site.part(withID: secondID)?.name == "Shared Hero")
        #expect(document.site.globalParts.first?.root.name == "Shared Hero")
    }

    @Test
    func globalsRoundTripSeparatelyFromReusableParts() throws {
        var site = Site.starter()
        let global = ReusablePartDefinition(name: "Header", root: PartNode.make(.container))
        site.globalParts = [global]

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.globalParts == [global])
        #expect(decoded.reusableParts.isEmpty)
    }

    @Test
    func editingNestedGlobalContentUpdatesEveryInstanceAndPreservesSelectionIdentity() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let sourceText = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )
        let secondTextID = try #require(document.site.part(withID: secondRootID)?.children.first?.id)

        editor.setSharedReusableProperty(partID: sourceText.id, key: .text, value: .string("Global heading"))

        #expect(document.site.part(withID: sourceText.id)?.property(.text) == "Global heading")
        #expect(document.site.part(withID: secondTextID)?.property(.text) == "Global heading")
        #expect(document.site.part(withID: sourceText.id)?.id == sourceText.id)
        #expect(document.site.part(withID: secondTextID)?.id == secondTextID)
    }

    @Test
    func editingGlobalTextUpdatesAnInstanceOnAnotherPage() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let sourceText = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondPageID = editor.addPage()
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: secondPageID, placement: .end)
        )
        let secondTextID = try #require(document.site.part(withID: secondRootID)?.children.first?.id)

        editor.setSharedReusableProperty(partID: sourceText.id, key: .text, value: .string("Across every page"))

        #expect(document.site.part(withID: sourceText.id)?.property(.text) == "Across every page")
        #expect(document.site.part(withID: secondTextID)?.property(.text) == "Across every page")
    }

    @Test
    func unlockedGlobalChildKeepsLocalContentUntilRelinked() throws {
        let site = TestSiteFixtures.populatedSite()
        let firstRoot = try #require(site.pages.first?.parts.first)
        let firstText = try #require(firstRoot.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: firstRoot.id, name: "Hero"))
        let secondPageID = editor.addPage()
        let secondRootID = try #require(editor.insertGlobalPart(definitionID: definitionID, on: secondPageID, placement: .end))
        let secondTextID = try #require(document.site.part(withID: secondRootID)?.children.first?.id)

        editor.setGlobalPartLinked(partID: secondTextID, isLinked: false)
        editor.setProperty(id: secondTextID, key: .text, value: .string("Page-specific heading"))
        editor.setSharedReusableProperty(partID: firstText.id, key: .text, value: .string("Global heading"))

        #expect(document.site.part(withID: firstText.id)?.property(.text) == "Global heading")
        #expect(document.site.part(withID: secondTextID)?.property(.text) == "Page-specific heading")
        #expect(document.site.globalPartContext(containing: secondTextID)?.isOverridden == true)

        editor.setGlobalPartLinked(partID: secondTextID, isLinked: true)

        #expect(document.site.part(withID: secondTextID)?.property(.text) == "Global heading")
        #expect(document.site.globalPartContext(containing: secondTextID)?.isOverridden == false)
    }

    @Test
    func movingLocalPartIntoGlobalUpdatesEveryInstance() throws {
        var site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let local = PartNode(type: .paragraph, name: "Local addition")
        site.pages[0].parts.append(local)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.movePart(id: local.id, on: site.pages[0].id, to: .inside(source.id)))

        #expect(document.site.part(withID: source.id)?.children.last?.id == local.id)
        #expect(document.site.part(withID: secondRootID)?.children.last?.name == "Local addition")
        #expect(document.site.globalParts.first?.root.children.last?.name == "Local addition")
    }

    @Test
    func insertingNewPartIntoGlobalUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let lastChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        let insertedID = try #require(
            editor.insertPart(type: .paragraph, on: site.pages[0].id, placement: .after(lastChild.id))
        )

        #expect(document.site.part(withID: source.id)?.children.last?.id == insertedID)
        #expect(document.site.part(withID: secondRootID)?.children.last?.type == .paragraph)
        #expect(document.site.globalParts.first?.root.children.last?.type == .paragraph)
    }

    @Test
    func deletingAndDuplicatingNestedGlobalPartsUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let firstChild = try #require(source.children.first)
        let secondChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        let duplicateID = try #require(editor.duplicatePart(id: firstChild.id, on: site.pages[0].id))
        #expect(document.site.part(withID: source.id)?.children.count == 3)
        #expect(document.site.part(withID: secondRootID)?.children.count == 3)

        editor.removePart(id: secondChild.id)
        #expect(document.site.part(withID: source.id)?.children.count == 2)
        #expect(document.site.part(withID: secondRootID)?.children.count == 2)
        #expect(document.site.part(withID: duplicateID) != nil)
    }

    @Test
    func linkedGlobalMetadataAndPropertiesSynchronizeButAnchorRemainsLocal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let sourceChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )
        let secondChildID = try #require(document.site.part(withID: secondRootID)?.children.first?.id)

        editor.renamePart(id: sourceChild.id, name: "Shared name")
        editor.setPartClasses(id: sourceChild.id, classes: "shared-class")
        editor.setPartRootAttributes(
            id: sourceChild.id,
            attributes: [PartHTMLAttribute(name: "data-role", value: "hero")]
        )
        editor.setProperty(id: sourceChild.id, key: .text, value: .string("Shared value"))
        editor.setPartAnchor(id: sourceChild.id, anchor: "local-anchor")

        let secondChild = try #require(document.site.part(withID: secondChildID))
        #expect(secondChild.name == "Shared name")
        #expect(secondChild.customClasses == "shared-class")
        #expect(secondChild.rootAttributes?.first?.name == "data-role")
        #expect(secondChild.property(.text) == "Shared value")
        #expect(secondChild.anchor == nil)
        #expect(document.site.part(withID: sourceChild.id)?.anchor == "local-anchor")
    }

    @Test
    func movingPartOutOfGlobalUpdatesEveryInstanceAndKeepsDraggedNodeLocal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let movedChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.movePart(id: movedChild.id, on: site.pages[0].id, to: .after(source.id)))

        #expect(document.site.part(withID: source.id)?.children.count == 1)
        #expect(document.site.part(withID: secondRootID)?.children.count == 1)
        #expect(document.site.pages[0].parts.contains(where: { $0.id == movedChild.id }))
        #expect(document.site.part(withID: movedChild.id)?.reusableDefinitionID == nil)
    }

    @Test
    func reorderingInsideGlobalUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let firstChild = try #require(source.children.first)
        let secondChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.movePart(id: firstChild.id, on: site.pages[0].id, to: .after(secondChild.id)))

        #expect(document.site.part(withID: source.id)?.children.map(\.name) == ["Call to action", "Paragraph"])
        #expect(document.site.part(withID: secondRootID)?.children.map(\.name) == ["Call to action", "Paragraph"])
    }

    @Test
    func movingBetweenInstancesOfSameGlobalIsRejected() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let sourceChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(!editor.movePart(id: sourceChild.id, on: site.pages[0].id, to: .inside(secondRootID)))
        #expect(document.site.part(withID: source.id)?.children.count == 2)
        #expect(document.site.part(withID: secondRootID)?.children.count == 2)
    }
}
