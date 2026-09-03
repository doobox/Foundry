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
            "event": "insertComponent",
            "componentType": "foundry.content.button",
            "placement": ["kind": "inside", "targetID": targetID.uuidString]
        ])
        let move = CanvasMessage.decode([
            "version": 1,
            "event": "moveComponent",
            "componentID": sourceID.uuidString,
            "placement": ["kind": "after", "targetID": targetID.uuidString]
        ])

        #expect(insert?.componentType == .button)
        #expect(insert?.placement?.componentPlacement == .inside(targetID))
        #expect(move?.componentID == sourceID)
        #expect(move?.placement?.componentPlacement == .after(targetID))
    }

    @Test
    func decodesExistingAndFinderImageInsertMessages() {
        let assetID = UUID()
        let existing = CanvasMessage.decode([
            "version": 1,
            "event": "insertImageComponent",
            "assetID": assetID.uuidString,
            "placement": ["kind": "end"]
        ])
        let finder = CanvasMessage.decode([
            "version": 1,
            "event": "insertImageComponent",
            "assetFilename": "photo.png",
            "assetMediaType": "image/png",
            "assetData": Data([1, 2, 3]).base64EncodedString(),
            "placement": ["kind": "end"]
        ])

        #expect(existing?.assetID == assetID)
        #expect(existing?.event == .insertImageComponent)
        #expect(finder?.assetFilename == "photo.png")
        #expect(finder?.event == .insertImageComponent)
    }

    @Test
    func rejectsIncompletePlacementMessages() {
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "insertComponent",
            "componentType": "text",
            "placement": ["kind": "inside"]
        ]) == nil)
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "moveComponent",
            "componentID": UUID().uuidString,
            "placement": ["kind": "unknown"]
        ]) == nil)
    }

    @Test
    func structureDragPayloadDistinguishesLibraryComponentsFromExistingNodes() {
        let nodeID = UUID()
        let libraryValue = ComponentDragPayload.library(.columns).stringValue
        let nodeValue = ComponentDragPayload.node(nodeID).stringValue

        #expect(ComponentDragPayload(libraryValue) == .library(.columns))
        #expect(ComponentDragPayload(nodeValue) == .node(nodeID))
        #expect(nodeValue == "foundry-node:\(nodeID.uuidString)")
        #expect(ComponentDragPayload(nodeID.uuidString) == nil)
        #expect(ComponentDragPayload("foundry-component-type:") == nil)
        #expect(ComponentDragPayload("not-a-component") == nil)
    }

    @Test @MainActor
    func canvasRendersExplicitDropZonesForEmptyTargets() {
        let emptyPage = Page(title: "Empty", slug: "empty", components: [])
        let container = ComponentNode.make(.container)
        let section = ComponentNode.make(.section)
        let columns = ComponentNode.make(.columns)
        let spacer = ComponentNode.make(.spacer)
        let componentPage = Page(
            title: "Drop zones",
            slug: "drop-zones",
            components: [container, section, columns, spacer]
        )
        let renderer = HTMLPageRenderer()

        let emptyHTML = renderer.render(page: emptyPage, theme: .standard)
        let componentHTML = renderer.render(page: componentPage, theme: .standard)

        #expect(emptyHTML.contains("data-foundry-root-drop-zone"))
        #expect(componentHTML.contains("data-foundry-empty-parent=\"\(container.id.uuidString)\""))
        #expect(componentHTML.contains("data-foundry-empty-parent=\"\(section.id.uuidString)\""))
        #expect(componentHTML.contains("data-foundry-empty-parent=\"\(columns.id.uuidString)\""))
        #expect(componentHTML.contains("data-foundry-adjacent-target=\"\(spacer.id.uuidString)\""))
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
        #expect(script.contains("insertImageComponent"))
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
        let originalCount = page.components.count

        let insertedID = try #require(
            editor.insertComponent(type: .button, on: page.id, placement: .end)
        )
        #expect(document.site.pages[0].components.node(withID: insertedID) != nil)
        #expect(document.site.pages[0].components.count == originalCount + 1)

        undoManager.undo()
        #expect(document.site.pages[0].components.count == originalCount)

        undoManager.redo()
        #expect(document.site.pages[0].components.node(withID: insertedID) != nil)
    }

    @Test
    func libraryInsertionSupportsInsideAfterAndRootPlacements() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let page = try #require(document.site.pages.first)
        let container = try #require(page.components.first)
        let leaf = try #require(container.children.first)

        let insideID = try #require(editor.insertComponent(type: .image, on: page.id, placement: .inside(container.id)))
        let afterID = try #require(editor.insertComponent(type: .divider, on: page.id, placement: .after(leaf.id)))
        let rootID = try #require(editor.insertComponent(type: .section, on: page.id, placement: .end))
        let updated = document.site.pages[0]

        #expect(updated.components[0].children.node(withID: insideID) != nil)
        #expect(updated.components[0].children.node(withID: afterID) != nil)
        #expect(updated.components.last?.id == rootID)
    }

    @Test
    func adjacentAndInsidePlacementsNormalizeSlotMembership() {
        var target = ComponentNode.make(.paragraph)
        target.slotID = "secondary"
        var parent = ComponentNode.make(.container)
        parent.children = [target]
        var moving = ComponentNode.make(.image)
        moving.slotID = "stale-slot"
        var components = [moving, parent]

        let inserted = ComponentNode.make(.button)
        let didInsert = components.insert(inserted, at: .before(target.id))
        #expect(didInsert)
        #expect(components.node(withID: inserted.id)?.slotID == "secondary")

        let didMove = components.moveNode(withID: moving.id, to: .inside(parent.id))
        #expect(didMove)
        #expect(components.node(withID: moving.id)?.slotID == nil)
    }
}
