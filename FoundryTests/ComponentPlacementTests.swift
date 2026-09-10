import Foundation
import Testing
@testable import Foundry

struct ComponentPlacementTests {
    @Test
    func insertsBeforeAndAfterTargets() {
        let first = ComponentNode.make(.paragraph)
        let second = ComponentNode.make(.button)
        let before = ComponentNode.make(.paragraph)
        let after = ComponentNode.make(.button)
        var tree = [first, second]

        let insertedBefore = tree.insert(before, at: .before(second.id))
        let insertedAfter = tree.insert(after, at: .after(first.id))

        #expect(insertedBefore)
        #expect(insertedAfter)
        #expect(tree.map(\.id) == [first.id, after.id, before.id, second.id])
    }

    @Test
    func movesComponentIntoContainer() {
        let container = ComponentNode.make(.container)
        let text = ComponentNode.make(.paragraph)
        var tree = [container, text]

        let moved = tree.moveNode(withID: text.id, to: .inside(container.id))

        #expect(moved)
        #expect(tree.count == 1)
        #expect(tree.first?.children.first?.id == text.id)
    }

    @Test
    func rejectsChildrenForLeafComponents() {
        let text = ComponentNode.make(.paragraph)
        let button = ComponentNode.make(.button)
        var tree = [text, button]

        let moved = tree.moveNode(withID: button.id, to: .inside(text.id))

        #expect(!moved)
        #expect(tree.map(\.id) == [text.id, button.id])
    }

    @Test
    func sectionAndColumnsAcceptChildren() {
        let heading = ComponentNode.make(.heading)
        var tree = [ComponentNode.make(.section), ComponentNode.make(.columns), heading]

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
        let childContainer = ComponentNode.make(.container)
        let parent = ComponentNode(
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
struct ComponentEditingTests {
    @Test
    func movingMultipleComponentsPreservesTheirRequestedOrder() throws {
        let first = ComponentNode.make(.paragraph)
        let second = ComponentNode.make(.button)
        let third = ComponentNode.make(.heading)
        let page = Page(title: "Home", slug: "index", components: [first, second, third])
        let document = FoundryDocument(site: Site(name: "Ordering", pages: [page]))
        let editor = ProjectEditor(document: document, undoManager: nil)

        #expect(editor.canMoveComponents(ids: [second.id, third.id], on: page.id, to: .before(first.id)))
        #expect(editor.moveComponents(ids: [second.id, third.id], on: page.id, to: .before(first.id)))

        let orderedIDs = try #require(document.site.pages.first).components.map(\.id)
        #expect(orderedIDs == [second.id, third.id, first.id])
    }

    @Test
    func moveValidationRejectsSelfAndDescendantDestinations() {
        let child = ComponentNode.make(.paragraph)
        let container = ComponentNode(type: .container, children: [child])
        let page = Page(title: "Home", slug: "index", components: [container])
        let document = FoundryDocument(site: Site(name: "Validation", pages: [page]))
        let editor = ProjectEditor(document: document, undoManager: nil)

        #expect(!editor.canMoveComponents(ids: [container.id], on: page.id, to: .inside(container.id)))
        #expect(!editor.canMoveComponents(ids: [container.id], on: page.id, to: .before(child.id)))
    }

    @Test
    func insertingAtEndOfNamedSlotPreservesTheSlot() {
        let existing = ComponentNode(type: .paragraph, slotID: "sidebar")
        let parentID = UUID()

        #expect([existing].endPlacement(in: parentID) == .insideSlot(parentID, "sidebar"))
    }

    @Test
    func duplicateCreatesFreshIdentifiers() throws {
        let document = TestSiteFixtures.populatedDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let page = try #require(document.site.pages.first)
        let source = try #require(page.components.first)

        let duplicateID = try #require(
            editor.duplicateComponent(id: source.id, on: page.id)
        )
        let duplicate = try #require(
            document.site.pages[0].components.node(withID: duplicateID)
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
        let container = try #require(page.components.first)
        let child = try #require(container.children.first)

        #expect(editor.outdentComponent(id: child.id, on: page.id))
        #expect(document.site.pages[0].components.count == 2)

        undoManager.undo()
        #expect(document.site.pages[0].components.count == 1)
        #expect(document.site.pages[0].components[0].children.first?.id == child.id)

        undoManager.redo()
        #expect(document.site.pages[0].components.count == 2)
    }
}
