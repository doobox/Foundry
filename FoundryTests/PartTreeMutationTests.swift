import Foundation
import Testing
@testable import Foundry

struct PartTreeMutationTests {
    @Test
    func appendsChildToRequestedContainer() {
        let container = PartNode.make(.section)
        let child = PartNode.make(.paragraph)
        var tree = [container]

        let changed = tree.append(child, to: container.id)

        #expect(changed)
        #expect(tree.node(withID: child.id) == child)
        #expect(tree.first?.children.count == 1)
    }

    @Test
    func updatesNestedPartWithoutChangingIdentity() {
        let child = PartNode.make(.paragraph)
        var tree = [PartNode(type: .section, children: [child])]

        let changed = tree.updateNode(withID: child.id) {
            $0.setProperty(.text, value: "Edited")
        }

        #expect(changed)
        #expect(tree.node(withID: child.id)?.id == child.id)
        #expect(tree.node(withID: child.id)?.property(.text) == "Edited")
    }

    @Test
    func removesNestedPart() {
        let child = PartNode.make(.button)
        var tree = [PartNode(type: .section, children: [child])]

        let changed = tree.removeNode(withID: child.id)

        #expect(changed)
        #expect(tree.node(withID: child.id) == nil)
        #expect(tree.first?.children.isEmpty == true)
    }

    @Test
    func findsEveryAncestorNeededToRevealNestedSelection() {
        let selected = PartNode.make(.paragraph)
        let innerContainer = PartNode(type: .section, children: [selected])
        let outerContainer = PartNode(type: .section, children: [innerContainer])
        let tree = [outerContainer]

        #expect(tree.ancestorIDs(of: selected.id) == [outerContainer.id, innerContainer.id])
        #expect(tree.ancestorIDs(of: outerContainer.id).isEmpty)
        #expect(tree.ancestorIDs(of: UUID()).isEmpty)
    }

    @Test
    func structureProjectionShowsExpandedChildrenAtTheirDepth() {
        let grandchild = PartNode.make(.paragraph)
        let child = PartNode(type: .section, children: [grandchild])
        let parent = PartNode(type: .section, children: [child])

        let items = StructureTreeItem.flatten(
            [parent],
            expandedIDs: [parent.id, child.id]
        )

        #expect(items.map(\.id) == [parent.id, child.id, grandchild.id])
        #expect(items.map(\.depth) == [0, 1, 2])
    }

    @Test
    func structureProjectionHidesOnlyCollapsedDescendants() {
        let child = PartNode.make(.button)
        let parent = PartNode(type: .section, children: [child])
        let sibling = PartNode.make(.paragraph)

        let items = StructureTreeItem.flatten(
            [parent, sibling],
            expandedIDs: []
        )

        #expect(items.map(\.id) == [parent.id, sibling.id])
        #expect(items.map(\.depth) == [0, 0])
    }
}
