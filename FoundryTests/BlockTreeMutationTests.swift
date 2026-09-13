import Foundation
import Testing
@testable import Foundry

struct BlockTreeMutationTests {
    @Test
    func appendsChildToRequestedContainer() {
        let container = BlockNode.make(.container)
        let child = BlockNode.make(.paragraph)
        var tree = [container]

        let changed = tree.append(child, to: container.id)

        #expect(changed)
        #expect(tree.node(withID: child.id) == child)
        #expect(tree.first?.children.count == 1)
    }

    @Test
    func updatesNestedBlockWithoutChangingIdentity() {
        let child = BlockNode.make(.paragraph)
        var tree = [BlockNode(type: .container, children: [child])]

        let changed = tree.updateNode(withID: child.id) {
            $0.setProperty(.text, value: "Edited")
        }

        #expect(changed)
        #expect(tree.node(withID: child.id)?.id == child.id)
        #expect(tree.node(withID: child.id)?.property(.text) == "Edited")
    }

    @Test
    func removesNestedBlock() {
        let child = BlockNode.make(.button)
        var tree = [BlockNode(type: .container, children: [child])]

        let changed = tree.removeNode(withID: child.id)

        #expect(changed)
        #expect(tree.node(withID: child.id) == nil)
        #expect(tree.first?.children.isEmpty == true)
    }

    @Test
    func findsEveryAncestorNeededToRevealNestedSelection() {
        let selected = BlockNode.make(.paragraph)
        let innerContainer = BlockNode(type: .container, children: [selected])
        let outerContainer = BlockNode(type: .container, children: [innerContainer])
        let tree = [outerContainer]

        #expect(tree.ancestorIDs(of: selected.id) == [outerContainer.id, innerContainer.id])
        #expect(tree.ancestorIDs(of: outerContainer.id).isEmpty)
        #expect(tree.ancestorIDs(of: UUID()).isEmpty)
    }

    @Test
    func structureProjectionShowsExpandedChildrenAtTheirDepth() {
        let grandchild = BlockNode.make(.paragraph)
        let child = BlockNode(type: .container, children: [grandchild])
        let parent = BlockNode(type: .container, children: [child])

        let items = StructureTreeItem.flatten(
            [parent],
            expandedIDs: [parent.id, child.id]
        )

        #expect(items.map(\.id) == [parent.id, child.id, grandchild.id])
        #expect(items.map(\.depth) == [0, 1, 2])
    }

    @Test
    func structureProjectionHidesOnlyCollapsedDescendants() {
        let child = BlockNode.make(.button)
        let parent = BlockNode(type: .container, children: [child])
        let sibling = BlockNode.make(.paragraph)

        let items = StructureTreeItem.flatten(
            [parent, sibling],
            expandedIDs: []
        )

        #expect(items.map(\.id) == [parent.id, sibling.id])
        #expect(items.map(\.depth) == [0, 0])
    }
}
