import Foundation
import Testing
@testable import Foundry

struct ComponentPlacementTests {
    @Test
    func insertsBeforeAndAfterTargets() {
        let first = ComponentNode.make(.text)
        let second = ComponentNode.make(.button)
        let before = ComponentNode.make(.text)
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
        let text = ComponentNode.make(.text)
        var tree = [container, text]

        let moved = tree.moveNode(withID: text.id, to: .inside(container.id))

        #expect(moved)
        #expect(tree.count == 1)
        #expect(tree.first?.children.first?.id == text.id)
    }

    @Test
    func rejectsChildrenForLeafComponents() {
        let text = ComponentNode.make(.text)
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
    func duplicateCreatesFreshIdentifiers() throws {
        let document = FoundryDocument()
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
        let document = FoundryDocument()
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
