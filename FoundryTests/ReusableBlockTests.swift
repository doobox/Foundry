import Foundation
import Testing
@testable import Foundry

@MainActor
struct ReusableBlockTests {
    @Test
    func reusableDefinitionsRoundTripWithStableIdentifiers() throws {
        let definitionID = UUID()
        var site = Site.starter()
        site.reusableBlocks = [
            ReusableBlockDefinition(
                id: definitionID,
                name: "Hero",
                root: BlockNode(type: .container, children: [BlockNode.make(.paragraph)])
            )
        ]

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.reusableBlocks.first?.id == definitionID)
        #expect(decoded == site)
    }

    @Test
    func savingAndInsertingReusableBlockCreatesFreshTreeIdentifiers() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        let definitionID = try #require(
            editor.saveReusableBlock(blockID: source.id, name: "Hero")
        )
        let insertedID = try #require(
            editor.insertReusableBlock(
                definitionID: definitionID,
                on: site.pages[0].id,
                placement: .end
            )
        )
        let inserted = try #require(document.site.block(withID: insertedID))
        let definition = try #require(document.site.reusableBlocks.first)

        #expect(inserted.reusableDefinitionID == nil)
        #expect(inserted.id != source.id)
        #expect(inserted.id != definition.root.id)
        #expect(inserted.children.map(\.id) != definition.root.children.map(\.id))
    }

    @Test
    func detachKeepsLocalContentAndRemovesOnlyTheLink() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        _ = editor.saveReusableBlock(blockID: source.id, name: "Hero")
        let before = try #require(document.site.block(withID: source.id))

        editor.detachReusableBlock(blockID: source.id)
        let after = try #require(document.site.block(withID: source.id))

        #expect(after.reusableDefinitionID == nil)
        #expect(after.name == before.name)
        #expect(after.children == before.children)
    }

    @Test
    func reusableInstancesRemainIndependentAfterInsertion() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveReusableBlock(blockID: source.id, name: "Hero")
        )
        let secondID = try #require(
            editor.insertReusableBlock(
                definitionID: definitionID,
                on: site.pages[0].id,
                placement: .end
            )
        )
        editor.renameBlock(id: source.id, name: "Updated Hero")

        #expect(document.site.block(withID: source.id)?.name == "Updated Hero")
        #expect(document.site.block(withID: secondID)?.name == "Hero")
        #expect(document.site.reusableBlocks.first?.root.name == "Hero")
    }

    @Test
    func deletingDefinitionDetachesInstancesWithoutDeletingContent() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveReusableBlock(blockID: source.id, name: "Hero")
        )

        editor.removeReusableBlock(definitionID: definitionID)

        #expect(document.site.reusableBlocks.isEmpty)
        #expect(document.site.block(withID: source.id)?.reusableDefinitionID == nil)
        #expect(document.site.block(withID: source.id)?.children.count == source.children.count)
    }

    @Test
    func globalEditingUpdatesEveryInstanceInOneMutation() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveGlobalBlock(blockID: source.id, name: "Hero")
        )
        let secondID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        editor.renameSharedReusableBlockInstance(blockID: source.id, name: "Shared Hero")

        #expect(document.site.block(withID: source.id)?.name == "Shared Hero")
        #expect(document.site.block(withID: secondID)?.name == "Shared Hero")
        #expect(document.site.globalBlocks.first?.root.name == "Shared Hero")
    }

    @Test
    func globalsRoundTripSeparatelyFromReusableBlocks() throws {
        var site = Site.starter()
        let global = ReusableBlockDefinition(name: "Header", root: BlockNode.make(.container))
        site.globalBlocks = [global]

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.globalBlocks == [global])
        #expect(decoded.reusableBlocks.isEmpty)
    }

    @Test
    func editingNestedGlobalContentUpdatesEveryInstanceAndPreservesSelectionIdentity() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let sourceText = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )
        let secondTextID = try #require(document.site.block(withID: secondRootID)?.children.first?.id)

        editor.setSharedReusableProperty(blockID: sourceText.id, key: .text, value: .string("Global heading"))

        #expect(document.site.block(withID: sourceText.id)?.property(.text) == "Global heading")
        #expect(document.site.block(withID: secondTextID)?.property(.text) == "Global heading")
        #expect(document.site.block(withID: sourceText.id)?.id == sourceText.id)
        #expect(document.site.block(withID: secondTextID)?.id == secondTextID)
    }

    @Test
    func editingGlobalTextUpdatesAnInstanceOnAnotherPage() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let sourceText = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondPageID = editor.addPage()
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: secondPageID, placement: .end)
        )
        let secondTextID = try #require(document.site.block(withID: secondRootID)?.children.first?.id)

        editor.setSharedReusableProperty(blockID: sourceText.id, key: .text, value: .string("Across every page"))

        #expect(document.site.block(withID: sourceText.id)?.property(.text) == "Across every page")
        #expect(document.site.block(withID: secondTextID)?.property(.text) == "Across every page")
    }

    @Test
    func unlockedGlobalChildKeepsLocalContentUntilRelinked() throws {
        let site = TestSiteFixtures.populatedSite()
        let firstRoot = try #require(site.pages.first?.blocks.first)
        let firstText = try #require(firstRoot.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: firstRoot.id, name: "Hero"))
        let secondPageID = editor.addPage()
        let secondRootID = try #require(editor.insertGlobalBlock(definitionID: definitionID, on: secondPageID, placement: .end))
        let secondTextID = try #require(document.site.block(withID: secondRootID)?.children.first?.id)

        editor.setGlobalBlockLinked(blockID: secondTextID, isLinked: false)
        editor.setProperty(id: secondTextID, key: .text, value: .string("Page-specific heading"))
        editor.setSharedReusableProperty(blockID: firstText.id, key: .text, value: .string("Global heading"))

        #expect(document.site.block(withID: firstText.id)?.property(.text) == "Global heading")
        #expect(document.site.block(withID: secondTextID)?.property(.text) == "Page-specific heading")
        #expect(document.site.globalBlockContext(containing: secondTextID)?.isOverridden == true)

        editor.setGlobalBlockLinked(blockID: secondTextID, isLinked: true)

        #expect(document.site.block(withID: secondTextID)?.property(.text) == "Global heading")
        #expect(document.site.globalBlockContext(containing: secondTextID)?.isOverridden == false)
    }

    @Test
    func movingLocalBlockIntoGlobalUpdatesEveryInstance() throws {
        var site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let local = BlockNode(type: .paragraph, name: "Local addition")
        site.pages[0].blocks.append(local)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.moveBlock(id: local.id, on: site.pages[0].id, to: .inside(source.id)))

        #expect(document.site.block(withID: source.id)?.children.last?.id == local.id)
        #expect(document.site.block(withID: secondRootID)?.children.last?.name == "Local addition")
        #expect(document.site.globalBlocks.first?.root.children.last?.name == "Local addition")
    }

    @Test
    func insertingNewBlockIntoGlobalUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let lastChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        let insertedID = try #require(
            editor.insertBlock(type: .paragraph, on: site.pages[0].id, placement: .after(lastChild.id))
        )

        #expect(document.site.block(withID: source.id)?.children.last?.id == insertedID)
        #expect(document.site.block(withID: secondRootID)?.children.last?.type == .paragraph)
        #expect(document.site.globalBlocks.first?.root.children.last?.type == .paragraph)
    }

    @Test
    func deletingAndDuplicatingNestedGlobalBlocksUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let firstChild = try #require(source.children.first)
        let secondChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        let duplicateID = try #require(editor.duplicateBlock(id: firstChild.id, on: site.pages[0].id))
        #expect(document.site.block(withID: source.id)?.children.count == 3)
        #expect(document.site.block(withID: secondRootID)?.children.count == 3)

        editor.removeBlock(id: secondChild.id)
        #expect(document.site.block(withID: source.id)?.children.count == 2)
        #expect(document.site.block(withID: secondRootID)?.children.count == 2)
        #expect(document.site.block(withID: duplicateID) != nil)
    }

    @Test
    func linkedGlobalMetadataAndPropertiesSynchronizeButAnchorRemainsLocal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let sourceChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )
        let secondChildID = try #require(document.site.block(withID: secondRootID)?.children.first?.id)

        editor.renameBlock(id: sourceChild.id, name: "Shared name")
        editor.setBlockClasses(id: sourceChild.id, classes: "shared-class")
        editor.setBlockRootAttributes(
            id: sourceChild.id,
            attributes: [BlockHTMLAttribute(name: "data-role", value: "hero")]
        )
        editor.setProperty(id: sourceChild.id, key: .text, value: .string("Shared value"))
        editor.setBlockAnchor(id: sourceChild.id, anchor: "local-anchor")

        let secondChild = try #require(document.site.block(withID: secondChildID))
        #expect(secondChild.name == "Shared name")
        #expect(secondChild.customClasses == "shared-class")
        #expect(secondChild.rootAttributes?.first?.name == "data-role")
        #expect(secondChild.property(.text) == "Shared value")
        #expect(secondChild.anchor == nil)
        #expect(document.site.block(withID: sourceChild.id)?.anchor == "local-anchor")
    }

    @Test
    func movingBlockOutOfGlobalUpdatesEveryInstanceAndKeepsDraggedNodeLocal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let movedChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.moveBlock(id: movedChild.id, on: site.pages[0].id, to: .after(source.id)))

        #expect(document.site.block(withID: source.id)?.children.count == 1)
        #expect(document.site.block(withID: secondRootID)?.children.count == 1)
        #expect(document.site.pages[0].blocks.contains(where: { $0.id == movedChild.id }))
        #expect(document.site.block(withID: movedChild.id)?.reusableDefinitionID == nil)
    }

    @Test
    func reorderingInsideGlobalUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let firstChild = try #require(source.children.first)
        let secondChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.moveBlock(id: firstChild.id, on: site.pages[0].id, to: .after(secondChild.id)))

        #expect(document.site.block(withID: source.id)?.children.map(\.name) == ["Call to action", "Paragraph"])
        #expect(document.site.block(withID: secondRootID)?.children.map(\.name) == ["Call to action", "Paragraph"])
    }

    @Test
    func movingBetweenInstancesOfSameGlobalIsRejected() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.blocks.first)
        let sourceChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalBlock(blockID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalBlock(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(!editor.moveBlock(id: sourceChild.id, on: site.pages[0].id, to: .inside(secondRootID)))
        #expect(document.site.block(withID: source.id)?.children.count == 2)
        #expect(document.site.block(withID: secondRootID)?.children.count == 2)
    }
}
