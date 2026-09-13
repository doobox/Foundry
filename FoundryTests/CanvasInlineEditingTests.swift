import Foundation
import Testing
@testable import Foundry

struct CanvasInlineEditingMessageTests {
    @Test
    func decodesTextEditMessage() {
        let id = UUID()
        let message = CanvasMessage.decode([
            "version": 1,
            "event": "editBlock",
            "blockID": id.uuidString,
            "propertyKey": "text",
            "propertyValue": "Edited content"
        ])

        #expect(message?.blockID == id)
        #expect(message?.propertyKey == .text)
        #expect(message?.propertyValue == "Edited content")
    }

    @Test
    func decodesHTMLModalEditRequest() {
        let id = UUID()
        let source = "<button>Click me</button>\n<style>button { color: red; }</style>"
        let message = CanvasMessage.decode([
            "version": 1,
            "event": "editHTMLBlock",
            "blockID": id.uuidString,
            "propertyKey": "content",
            "propertyValue": source
        ])

        #expect(message?.event == .editHTMLBlock)
        #expect(message?.blockID == id)
        #expect(message?.propertyKey?.rawValue == "content")
        #expect(message?.propertyValue == source)
    }

    @Test
    func rejectsIncompleteEditMessage() {
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "editBlock",
            "blockID": UUID().uuidString,
            "propertyKey": "text"
        ]) == nil)
    }
}

@MainActor
struct CanvasInlineEditingUndoTests {
    @Test
    func committedEditIsOneUndoableMutation() throws {
        let document = TestSiteFixtures.populatedDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let page = try #require(document.site.pages.first)
        let block = try #require(page.blocks.first?.children.first)
        let original = block.property(.text)

        editor.setProperty(
            id: block.id,
            key: .text,
            value: .string("Edited once")
        )
        #expect(document.site.block(withID: block.id)?.property(.text) == "Edited once")

        undoManager.undo()
        #expect(document.site.block(withID: block.id)?.property(.text) == original)

        undoManager.redo()
        #expect(document.site.block(withID: block.id)?.property(.text) == "Edited once")
    }
}
