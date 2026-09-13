import Foundation
import Testing
@testable import Foundry

struct BlockPlacementTests {
    @Test
    func insertsBeforeAndAfterTargets() {
        let first = BlockNode.make(.paragraph)
        let second = BlockNode.make(.button)
        let before = BlockNode.make(.paragraph)
        let after = BlockNode.make(.button)
        var tree = [first, second]

        let insertedBefore = tree.insert(before, at: .before(second.id))
        let insertedAfter = tree.insert(after, at: .after(first.id))

        #expect(insertedBefore)
        #expect(insertedAfter)
        #expect(tree.map(\.id) == [first.id, after.id, before.id, second.id])
    }

    @Test
    func movesBlockIntoContainer() {
        let container = BlockNode.make(.container)
        let text = BlockNode.make(.paragraph)
        var tree = [container, text]

        let moved = tree.moveNode(withID: text.id, to: .inside(container.id))

        #expect(moved)
        #expect(tree.count == 1)
        #expect(tree.first?.children.first?.id == text.id)
    }

    @Test
    func rejectsChildrenForLeafBlocks() {
        let text = BlockNode.make(.paragraph)
        let button = BlockNode.make(.button)
        var tree = [text, button]

        let moved = tree.moveNode(withID: button.id, to: .inside(text.id))

        #expect(!moved)
        #expect(tree.map(\.id) == [text.id, button.id])
    }

    @Test
    func sectionAndColumnsAcceptChildren() {
        let heading = BlockNode.make(.heading)
        var tree = [BlockNode.make(.section), BlockNode.make(.columns), heading]

        let movedIntoSection = tree.moveNode(withID: heading.id, to: .inside(tree[0].id))
        let section = tree[0]
        let movedIntoColumns = tree.moveNode(withID: heading.id, to: .inside(tree[1].id))

        #expect(movedIntoSection)
        #expect(section.children.first?.id == heading.id)
        #expect(movedIntoColumns)
        #expect(tree[1].children.first?.id == heading.id)
    }

    @Test
    func rejectsMovingContainerIntoItsDescendant() {
        let childContainer = BlockNode.make(.container)
        let parent = BlockNode(
            type: .container,
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
struct BlockEditingTests {
    @Test
    func movingMultipleBlocksPreservesTheirRequestedOrder() throws {
        let first = BlockNode.make(.paragraph)
        let second = BlockNode.make(.button)
        let third = BlockNode.make(.heading)
        let page = Page(title: "Home", slug: "index", blocks: [first, second, third])
        let document = FoundryDocument(site: Site(name: "Ordering", pages: [page]))
        let editor = ProjectEditor(document: document, undoManager: nil)

        #expect(editor.canMoveBlocks(ids: [second.id, third.id], on: page.id, to: .before(first.id)))
        #expect(editor.moveBlocks(ids: [second.id, third.id], on: page.id, to: .before(first.id)))

        let orderedIDs = try #require(document.site.pages.first).blocks.map(\.id)
        #expect(orderedIDs == [second.id, third.id, first.id])
    }

    @Test
    func moveValidationRejectsSelfAndDescendantDestinations() {
        let child = BlockNode.make(.paragraph)
        let container = BlockNode(type: .container, children: [child])
        let page = Page(title: "Home", slug: "index", blocks: [container])
        let document = FoundryDocument(site: Site(name: "Validation", pages: [page]))
        let editor = ProjectEditor(document: document, undoManager: nil)

        #expect(!editor.canMoveBlocks(ids: [container.id], on: page.id, to: .inside(container.id)))
        #expect(!editor.canMoveBlocks(ids: [container.id], on: page.id, to: .before(child.id)))
    }

    @Test
    func insertingAtEndOfNamedSlotPreservesTheSlot() {
        let existing = BlockNode(type: .paragraph, slotID: "sidebar")
        let parentID = UUID()

        #expect([existing].endPlacement(in: parentID) == .insideSlot(parentID, "sidebar"))
    }

    @Test
    func duplicateCreatesFreshIdentifiers() throws {
        let document = TestSiteFixtures.populatedDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let page = try #require(document.site.pages.first)
        let source = try #require(page.blocks.first)

        let duplicateID = try #require(
            editor.duplicateBlock(id: source.id, on: page.id)
        )
        let duplicate = try #require(
            document.site.pages[0].blocks.node(withID: duplicateID)
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
        let container = try #require(page.blocks.first)
        let child = try #require(container.children.first)

        #expect(editor.outdentBlock(id: child.id, on: page.id))
        #expect(document.site.pages[0].blocks.count == 2)

        undoManager.undo()
        #expect(document.site.pages[0].blocks.count == 1)
        #expect(document.site.pages[0].blocks[0].children.first?.id == child.id)

        undoManager.redo()
        #expect(document.site.pages[0].blocks.count == 2)
    }
}
