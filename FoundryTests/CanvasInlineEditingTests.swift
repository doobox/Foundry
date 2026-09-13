import Foundation
import Testing
@testable import Foundry

struct CanvasInlineEditingMessageTests {
    @Test
    func decodesTextEditMessage() {
        let id = UUID()
        let message = CanvasMessage.decode([
            "version": 1,
            "event": "editPart",
            "partID": id.uuidString,
            "propertyKey": "text",
            "propertyValue": "Edited content"
        ])

        #expect(message?.partID == id)
        #expect(message?.propertyKey == .text)
        #expect(message?.propertyValue == "Edited content")
    }

    @Test
    func decodesHTMLModalEditRequest() {
        let id = UUID()
        let source = "<button>Click me</button>\n<style>button { color: red; }</style>"
        let message = CanvasMessage.decode([
            "version": 1,
            "event": "editHTMLPart",
            "partID": id.uuidString,
            "propertyKey": "content",
            "propertyValue": source
        ])

        #expect(message?.event == .editHTMLPart)
        #expect(message?.partID == id)
        #expect(message?.propertyKey?.rawValue == "content")
        #expect(message?.propertyValue == source)
    }

    @Test
    func rejectsIncompleteEditMessage() {
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "editPart",
            "partID": UUID().uuidString,
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
        let part = try #require(page.parts.first?.children.first)
        let original = part.property(.text)

        editor.setProperty(
            id: part.id,
            key: .text,
            value: .string("Edited once")
        )
        #expect(document.site.part(withID: part.id)?.property(.text) == "Edited once")

        undoManager.undo()
        #expect(document.site.part(withID: part.id)?.property(.text) == original)

        undoManager.redo()
        #expect(document.site.part(withID: part.id)?.property(.text) == "Edited once")
    }
}
