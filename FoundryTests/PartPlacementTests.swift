import Foundation
import Testing
@testable import Foundry

struct PartPlacementTests {
    @Test
    func insertsBeforeAndAfterTargets() {
        let first = PartNode.make(.paragraph)
        let second = PartNode.make(.button)
        let before = PartNode.make(.paragraph)
        let after = PartNode.make(.button)
        var tree = [first, second]

        let insertedBefore = tree.insert(before, at: .before(second.id))
        let insertedAfter = tree.insert(after, at: .after(first.id))

        #expect(insertedBefore)
        #expect(insertedAfter)
        #expect(tree.map(\.id) == [first.id, after.id, before.id, second.id])
    }

    @Test
    func movesPartIntoContainer() {
        let container = PartNode.make(.section)
        let text = PartNode.make(.paragraph)
        var tree = [container, text]

        let moved = tree.moveNode(withID: text.id, to: .inside(container.id))

        #expect(moved)
        #expect(tree.count == 1)
        #expect(tree.first?.children.first?.id == text.id)
    }

    @Test
    func rejectsChildrenForLeafParts() {
        let text = PartNode.make(.paragraph)
        let button = PartNode.make(.button)
        var tree = [text, button]

        let moved = tree.moveNode(withID: button.id, to: .inside(text.id))

        #expect(!moved)
        #expect(tree.map(\.id) == [text.id, button.id])
    }

    @Test
    func flexAndGridAcceptChildren() {
        let heading = PartNode.make(.heading)
        var tree = [PartNode.make(.flex), PartNode.make(.grid), heading]

        let movedIntoFlex = tree.moveNode(withID: heading.id, to: .inside(tree[0].id))
        let flex = tree[0]
        let movedIntoGrid = tree.moveNode(withID: heading.id, to: .inside(tree[1].id))

        // Both start with three items, so the heading lands after them.
        #expect(movedIntoFlex)
        #expect(flex.children.last?.id == heading.id)
        #expect(movedIntoGrid)
        #expect(tree[1].children.last?.id == heading.id)
    }

    @Test
    func rejectsMovingContainerIntoItsDescendant() {
        let childContainer = PartNode.make(.section)
        let parent = PartNode(
            type: .section,
            children: [childContainer]
        )
        var tree = [parent]

        let moved = tree.moveNode(
            withID: parent.id,
            to: .inside(childContainer.id)
        )

        #expect(!moved)
        #expect(tree == [parent])
    }
}

@MainActor
struct PartEditingTests {
    @Test
    func customizingDirectLayoutChildrenAddsTheMatchingItemWrapper() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()

        for (layoutType, wrapperType) in [(PartType.grid, PartType.gridItem), (.flex, .flexItem)] {
            var child = PartNode.make(.paragraph)
            child.slotID = "content"
            var layout = PartNode.make(layoutType)
            layout.children = [child]
            let page = Page(title: "Home", slug: "index", parts: [layout])
            let document = FoundryDocument(site: Site(name: "Customization", pages: [page]))
            let editor = ProjectEditor(document: document, undoManager: nil)

            let wrapperID = try #require(editor.customizeLayoutItem(id: child.id, on: page.id))
            let updatedLayout = try #require(document.site.pages[0].parts.first)
            let wrapper = try #require(updatedLayout.children.first)
            #expect(wrapper.id == wrapperID)
            #expect(wrapper.type == wrapperType)
            #expect(wrapper.slotID == "content")
            #expect(wrapper.children.first?.id == child.id)
            #expect(wrapper.children.first?.slotID == wrapper.type.definition.package?.dropZoneSlotID(for: "content"))
            #expect(editor.customizeLayoutItem(id: wrapperID, on: page.id) == nil)
        }
    }

    @Test
    func movingMultiplePartsPreservesTheirRequestedOrder() throws {
        let first = PartNode.make(.paragraph)
        let second = PartNode.make(.button)
        let third = PartNode.make(.heading)
        let page = Page(title: "Home", slug: "index", parts: [first, second, third])
        let document = FoundryDocument(site: Site(name: "Ordering", pages: [page]))
        let editor = ProjectEditor(document: document, undoManager: nil)

        #expect(editor.canMoveParts(ids: [second.id, third.id], on: page.id, to: .before(first.id)))
        #expect(editor.moveParts(ids: [second.id, third.id], on: page.id, to: .before(first.id)))

        let orderedIDs = try #require(document.site.pages.first).parts.map(\.id)
        #expect(orderedIDs == [second.id, third.id, first.id])
    }

    @Test
    func moveValidationRejectsSelfAndDescendantDestinations() {
        let child = PartNode.make(.paragraph)
        let container = PartNode(type: .section, children: [child])
        let page = Page(title: "Home", slug: "index", parts: [container])
        let document = FoundryDocument(site: Site(name: "Validation", pages: [page]))
        let editor = ProjectEditor(document: document, undoManager: nil)

        #expect(!editor.canMoveParts(ids: [container.id], on: page.id, to: .inside(container.id)))
        #expect(!editor.canMoveParts(ids: [container.id], on: page.id, to: .before(child.id)))
    }

    @Test
    func insertingAtEndOfNamedSlotPreservesTheSlot() {
        let existing = PartNode(type: .paragraph, slotID: "sidebar")
        let parentID = UUID()

        #expect([existing].endPlacement(in: parentID) == .insideSlot(parentID, "sidebar"))
    }

    @Test
    func duplicateCreatesFreshIdentifiers() throws {
        let document = TestSiteFixtures.populatedDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let page = try #require(document.site.pages.first)
        let source = try #require(page.parts.first)

        let duplicateID = try #require(
            editor.duplicatePart(id: source.id, on: page.id)
        )
        let duplicate = try #require(
            document.site.pages[0].parts.node(withID: duplicateID)
        )

        #expect(duplicate.id != source.id)
        #expect(duplicate.children.first?.id != source.children.first?.id)
        #expect(duplicate.children.first?.properties.first?.id !=
                source.children.first?.properties.first?.id)
    }

    @Test
    func moveParticipatesInUndoAndRedo() throws {
        let document = TestSiteFixtures.populatedDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let page = try #require(document.site.pages.first)
        let container = try #require(page.parts.first)
        let child = try #require(container.children.first)

        #expect(editor.outdentPart(id: child.id, on: page.id))
        #expect(document.site.pages[0].parts.count == 2)

        undoManager.undo()
        #expect(document.site.pages[0].parts.count == 1)
        #expect(document.site.pages[0].parts[0].children.first?.id == child.id)

        undoManager.redo()
        #expect(document.site.pages[0].parts.count == 2)
    }
}
