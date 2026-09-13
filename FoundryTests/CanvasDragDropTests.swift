import Foundation
import Testing
@testable import Foundry

struct CanvasDragDropTests {
    @Test
    func decodesInsertAndMoveMessages() throws {
        let targetID = UUID()
        let sourceID = UUID()
        let insert = CanvasMessage.decode([
            "version": 1,
            "event": "insertBlock",
            "blockType": "foundry.content.button",
            "placement": ["kind": "inside", "targetID": targetID.uuidString]
        ])
        let move = CanvasMessage.decode([
            "version": 1,
            "event": "moveBlock",
            "blockID": sourceID.uuidString,
            "placement": ["kind": "after", "targetID": targetID.uuidString]
        ])

        #expect(insert?.blockType == .button)
        #expect(insert?.placement?.blockPlacement == .inside(targetID))
        #expect(move?.blockID == sourceID)
        #expect(move?.placement?.blockPlacement == .after(targetID))
    }

    @Test
    func decodesExistingAndFinderImageInsertMessages() {
        let assetID = UUID()
        let existing = CanvasMessage.decode([
            "version": 1,
            "event": "insertImageBlock",
            "assetID": assetID.uuidString,
            "placement": ["kind": "end"]
        ])
        let finder = CanvasMessage.decode([
            "version": 1,
            "event": "insertImageBlock",
            "assetFilename": "photo.png",
            "assetMediaType": "image/png",
            "assetData": Data([1, 2, 3]).base64EncodedString(),
            "placement": ["kind": "end"]
        ])

        #expect(existing?.assetID == assetID)
        #expect(existing?.event == .insertImageBlock)
        #expect(finder?.assetFilename == "photo.png")
        #expect(finder?.event == .insertImageBlock)
    }

    @Test
    func rejectsIncompletePlacementMessages() {
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "insertBlock",
            "blockType": "text",
            "placement": ["kind": "inside"]
        ]) == nil)
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "moveBlock",
            "blockID": UUID().uuidString,
            "placement": ["kind": "unknown"]
        ]) == nil)
    }

    @Test
    func structureDragPayloadDistinguishesLibraryBlocksFromExistingNodes() {
        let nodeID = UUID()
        let libraryValue = BlockDragPayload.library(.columns).stringValue
        let nodeValue = BlockDragPayload.node(nodeID).stringValue

        #expect(BlockDragPayload(libraryValue) == .library(.columns))
        #expect(BlockDragPayload(nodeValue) == .node(nodeID))
        #expect(nodeValue == "foundry-node:\(nodeID.uuidString)")
        #expect(BlockDragPayload(nodeID.uuidString) == nil)
        #expect(BlockDragPayload("foundry-block-type:") == nil)
        #expect(BlockDragPayload("not-a-block") == nil)
    }

    @Test @MainActor
    func canvasRendersExplicitDropZonesForEmptyTargets() {
        let emptyPage = Page(title: "Empty", slug: "empty", blocks: [])
        let container = BlockNode.make(.container)
        let section = BlockNode.make(.section)
        let columns = BlockNode.make(.columns)
        let spacer = BlockNode.make(.spacer)
        let blockPage = Page(
            title: "Drop zones",
            slug: "drop-zones",
            blocks: [container, section, columns, spacer]
        )
        let renderer = HTMLPageRenderer()

        let emptyHTML = renderer.render(page: emptyPage, theme: .standard)
        let blockHTML = renderer.render(page: blockPage, theme: .standard)

        #expect(emptyHTML.contains("data-foundry-root-drop-zone"))
        #expect(blockHTML.contains("data-foundry-empty-parent=\"\(container.id.uuidString)\""))
        #expect(blockHTML.contains("data-foundry-empty-parent=\"\(section.id.uuidString)\""))
        #expect(blockHTML.contains("data-foundry-empty-parent=\"\(columns.id.uuidString)\""))
        #expect(blockHTML.contains("data-foundry-adjacent-target=\"\(spacer.id.uuidString)\""))
    }

    @Test @MainActor
    func canvasScriptMapsExplicitZonesToPlacementKinds() {
        let script = WebCanvasView.Coordinator.interactionScript

        #expect(script.contains("data-foundry-empty-parent"))
        #expect(script.contains("kind: 'inside'"))
        #expect(script.contains("data-foundry-root-drop-zone"))
        #expect(script.contains("kind: 'end'"))
        #expect(script.contains("data-foundry-adjacent-target"))
        #expect(script.contains("foundry-image-asset:"))
        #expect(script.contains("insertImageBlock"))
    }
}

@MainActor
struct CanvasInsertionEditingTests {
    @Test
    func insertionParticipatesInUndoAndRedo() throws {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let page = try #require(document.site.pages.first)
        let originalCount = page.blocks.count

        let insertedID = try #require(
            editor.insertBlock(type: .button, on: page.id, placement: .end)
        )
        #expect(document.site.pages[0].blocks.node(withID: insertedID) != nil)
        #expect(document.site.pages[0].blocks.count == originalCount + 1)

        undoManager.undo()
        #expect(document.site.pages[0].blocks.count == originalCount)

        undoManager.redo()
        #expect(document.site.pages[0].blocks.node(withID: insertedID) != nil)
    }

    @Test
    func libraryInsertionSupportsInsideAfterAndRootPlacements() throws {
        let document = TestSiteFixtures.populatedDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let page = try #require(document.site.pages.first)
        let container = try #require(page.blocks.first)
        let leaf = try #require(container.children.first)

        let insideID = try #require(editor.insertBlock(type: .image, on: page.id, placement: .inside(container.id)))
        let afterID = try #require(editor.insertBlock(type: .divider, on: page.id, placement: .after(leaf.id)))
        let rootID = try #require(editor.insertBlock(type: .section, on: page.id, placement: .end))
        let updated = document.site.pages[0]

        #expect(updated.blocks[0].children.node(withID: insideID) != nil)
        #expect(updated.blocks[0].children.node(withID: afterID) != nil)
        #expect(updated.blocks.last?.id == rootID)
    }

    @Test
    func adjacentAndInsidePlacementsNormalizeSlotMembership() {
        var target = BlockNode.make(.paragraph)
        target.slotID = "secondary"
        var parent = BlockNode.make(.container)
        parent.children = [target]
        var moving = BlockNode.make(.image)
        moving.slotID = "stale-slot"
        var blocks = [moving, parent]

        let inserted = BlockNode.make(.button)
        let didInsert = blocks.insert(inserted, at: .before(target.id))
        #expect(didInsert)
        #expect(blocks.node(withID: inserted.id)?.slotID == "secondary")

        let didMove = blocks.moveNode(withID: moving.id, to: .inside(parent.id))
        #expect(didMove)
        #expect(blocks.node(withID: moving.id)?.slotID == LoadedBlockPackage.dropZoneSlotPrefix + "content")
    }
}
