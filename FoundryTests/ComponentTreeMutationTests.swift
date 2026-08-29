import Foundation
import Testing
@testable import Foundry

struct ComponentTreeMutationTests {
    @Test
    func appendsChildToRequestedContainer() {
        let container = ComponentNode.make(.container)
        let child = ComponentNode.make(.paragraph)
        var tree = [container]

        let changed = tree.append(child, to: container.id)

        #expect(changed)
        #expect(tree.node(withID: child.id) == child)
        #expect(tree.first?.children.count == 1)
    }

    @Test
    func updatesNestedComponentWithoutChangingIdentity() {
        let child = ComponentNode.make(.paragraph)
        var tree = [ComponentNode(type: .container, children: [child])]

        let changed = tree.updateNode(withID: child.id) {
            $0.setProperty(.text, value: "Edited")
        }

        #expect(changed)
        #expect(tree.node(withID: child.id)?.id == child.id)
        #expect(tree.node(withID: child.id)?.property(.text) == "Edited")
    }

    @Test
    func removesNestedComponent() {
        let child = ComponentNode.make(.button)
        var tree = [ComponentNode(type: .container, children: [child])]

        let changed = tree.removeNode(withID: child.id)

        #expect(changed)
        #expect(tree.node(withID: child.id) == nil)
        #expect(tree.first?.children.isEmpty == true)
    }

    @Test
    func findsEveryAncestorNeededToRevealNestedSelection() {
        let selected = ComponentNode.make(.paragraph)
        let innerContainer = ComponentNode(type: .container, children: [selected])
        let outerContainer = ComponentNode(type: .container, children: [innerContainer])
        let tree = [outerContainer]

        #expect(tree.ancestorIDs(of: selected.id) == [outerContainer.id, innerContainer.id])
        #expect(tree.ancestorIDs(of: outerContainer.id).isEmpty)
        #expect(tree.ancestorIDs(of: UUID()).isEmpty)
    }

    @Test
    func structureProjectionShowsExpandedChildrenAtTheirDepth() {
        let grandchild = ComponentNode.make(.paragraph)
        let child = ComponentNode(type: .container, children: [grandchild])
        let parent = ComponentNode(type: .container, children: [child])

        let items = StructureTreeItem.flatten(
            [parent],
            expandedIDs: [parent.id, child.id]
        )

        #expect(items.map(\.id) == [parent.id, child.id, grandchild.id])
        #expect(items.map(\.depth) == [0, 1, 2])
    }

    @Test
    func structureProjectionHidesOnlyCollapsedDescendants() {
        let child = ComponentNode.make(.button)
        let parent = ComponentNode(type: .container, children: [child])
        let sibling = ComponentNode.make(.paragraph)

        let items = StructureTreeItem.flatten(
            [parent, sibling],
            expandedIDs: []
        )

        #expect(items.map(\.id) == [parent.id, sibling.id])
        #expect(items.map(\.depth) == [0, 0])
    }
}
