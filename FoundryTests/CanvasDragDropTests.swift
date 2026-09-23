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
            "event": "insertPart",
            "partType": "foundry.content.button",
            "placement": ["kind": "inside", "targetID": targetID.uuidString]
        ])
        let move = CanvasMessage.decode([
            "version": 1,
            "event": "movePart",
            "partID": sourceID.uuidString,
            "placement": ["kind": "after", "targetID": targetID.uuidString]
        ])

        #expect(insert?.partType == .button)
        #expect(insert?.placement?.partPlacement == .inside(targetID))
        #expect(move?.partID == sourceID)
        #expect(move?.placement?.partPlacement == .after(targetID))
    }

    @Test
    func decodesExistingAndFinderImageInsertMessages() {
        let assetID = UUID()
        let existing = CanvasMessage.decode([
            "version": 1,
            "event": "insertImagePart",
            "assetID": assetID.uuidString,
            "placement": ["kind": "end"]
        ])
        let finder = CanvasMessage.decode([
            "version": 1,
            "event": "insertImagePart",
            "assetFilename": "photo.png",
            "assetMediaType": "image/png",
            "assetData": Data([1, 2, 3]).base64EncodedString(),
            "placement": ["kind": "end"]
        ])

        #expect(existing?.assetID == assetID)
        #expect(existing?.event == .insertImagePart)
        #expect(finder?.assetFilename == "photo.png")
        #expect(finder?.event == .insertImagePart)
    }

    @Test
    func rejectsIncompletePlacementMessages() {
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "insertPart",
            "partType": "text",
            "placement": ["kind": "inside"]
        ]) == nil)
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "movePart",
            "partID": UUID().uuidString,
            "placement": ["kind": "unknown"]
        ]) == nil)
    }

    @Test
    func structureDragPayloadDistinguishesLibraryPartsFromExistingNodes() {
        let nodeID = UUID()
        let libraryValue = PartDragPayload.library(.grid).stringValue
        let nodeValue = PartDragPayload.node(nodeID).stringValue

        #expect(PartDragPayload(libraryValue) == .library(.grid))
        #expect(PartDragPayload(nodeValue) == .node(nodeID))
        #expect(nodeValue == "foundry-node:\(nodeID.uuidString)")
        #expect(PartDragPayload(nodeID.uuidString) == nil)
        #expect(PartDragPayload("foundry-part-type:") == nil)
        #expect(PartDragPayload("not-a-part") == nil)
    }

    @Test @MainActor
    func canvasRendersExplicitDropZonesForEmptyTargets() {
        let emptyPage = Page(title: "Empty", slug: "empty", parts: [])
        let container = PartNode.make(.container)
        let section = PartNode.make(.section)
        let grid = PartNode.make(.grid)
        let paragraph = PartNode.make(.paragraph)
        let partPage = Page(
            title: "Drop zones",
            slug: "drop-zones",
            parts: [container, section, grid, paragraph]
        )
        let renderer = HTMLPageRenderer()

        let emptyHTML = renderer.render(page: emptyPage, framework: .standard)
        let partHTML = renderer.render(page: partPage, framework: .standard)

        #expect(emptyHTML.contains("data-foundry-root-drop-zone"))
        #expect(partHTML.contains("data-foundry-empty-parent=\"\(container.id.uuidString)\""))
        #expect(partHTML.contains("data-foundry-empty-parent=\"\(section.id.uuidString)\""))
        #expect(partHTML.contains("data-foundry-empty-parent=\"\(grid.id.uuidString)\""))
        #expect(partHTML.contains("data-foundry-adjacent-target=\"\(paragraph.id.uuidString)\""))
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
        #expect(script.contains("insertImagePart"))
        #expect(script.contains("const insertionFlow = element =>"))
        #expect(script.contains("style.flexDirection === 'row-reverse'"))
        #expect(script.contains("style.gridTemplateColumns"))
        #expect(script.contains("candidate.axis === 'inline'"))
        #expect(script.contains("dropChrome.style.setProperty('width', '4px'"))
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
        let originalCount = page.parts.count

        let insertedID = try #require(
            editor.insertPart(type: .button, on: page.id, placement: .end)
        )
        #expect(document.site.pages[0].parts.node(withID: insertedID) != nil)
        #expect(document.site.pages[0].parts.count == originalCount + 1)

        undoManager.undo()
        #expect(document.site.pages[0].parts.count == originalCount)

        undoManager.redo()
        #expect(document.site.pages[0].parts.node(withID: insertedID) != nil)
    }

    @Test
    func libraryInsertionSupportsInsideAfterAndRootPlacements() throws {
        let document = TestSiteFixtures.populatedDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let page = try #require(document.site.pages.first)
        let container = try #require(page.parts.first)
        let leaf = try #require(container.children.first)

        let insideID = try #require(editor.insertPart(type: .image, on: page.id, placement: .inside(container.id)))
        let afterID = try #require(editor.insertPart(type: .divider, on: page.id, placement: .after(leaf.id)))
        let rootID = try #require(editor.insertPart(type: .section, on: page.id, placement: .end))
        let updated = document.site.pages[0]

        #expect(updated.parts[0].children.node(withID: insideID) != nil)
        #expect(updated.parts[0].children.node(withID: afterID) != nil)
        #expect(updated.parts.last?.id == rootID)
    }

    @Test
    func adjacentAndInsidePlacementsNormalizeSlotMembership() {
        var target = PartNode.make(.paragraph)
        target.slotID = "secondary"
        var parent = PartNode.make(.container)
        parent.children = [target]
        var moving = PartNode.make(.image)
        moving.slotID = "stale-slot"
        var parts = [moving, parent]

        let inserted = PartNode.make(.button)
        let didInsert = parts.insert(inserted, at: .before(target.id))
        #expect(didInsert)
        #expect(parts.node(withID: inserted.id)?.slotID == "secondary")

        let didMove = parts.moveNode(withID: moving.id, to: .inside(parent.id))
        #expect(didMove)
        #expect(parts.node(withID: moving.id)?.slotID == LoadedPartPackage.dropZoneSlotPrefix + "content")
    }
}
