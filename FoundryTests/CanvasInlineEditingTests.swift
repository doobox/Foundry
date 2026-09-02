import Foundation
import Testing
@testable import Foundry

struct CanvasInlineEditingMessageTests {
    @Test
    func decodesTextEditMessage() {
        let id = UUID()
        let message = CanvasMessage.decode([
            "version": 1,
            "event": "editComponent",
            "componentID": id.uuidString,
            "propertyKey": "text",
            "propertyValue": "Edited content"
        ])

        #expect(message?.componentID == id)
        #expect(message?.propertyKey == .text)
        #expect(message?.propertyValue == "Edited content")
    }

    @Test
    func decodesHTMLModalEditRequest() {
        let id = UUID()
        let source = "<button>Click me</button>\n<style>button { color: red; }</style>"
        let message = CanvasMessage.decode([
            "version": 1,
            "event": "editHTMLComponent",
            "componentID": id.uuidString,
            "propertyKey": "html1",
            "propertyValue": source
        ])

        #expect(message?.event == .editHTMLComponent)
        #expect(message?.componentID == id)
        #expect(message?.propertyKey?.rawValue == "html1")
        #expect(message?.propertyValue == source)
    }

    @Test
    func rejectsIncompleteEditMessage() {
        #expect(CanvasMessage.decode([
            "version": 1,
            "event": "editComponent",
            "componentID": UUID().uuidString,
            "propertyKey": "text"
        ]) == nil)
    }
}

@MainActor
struct CanvasInlineEditingUndoTests {
    @Test
    func committedEditIsOneUndoableMutation() throws {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let page = try #require(document.site.pages.first)
        let component = try #require(page.components.first?.children.first)
        let original = component.property(.text)

        editor.setProperty(
            id: component.id,
            key: .text,
            value: .string("Edited once")
        )
        #expect(document.site.component(withID: component.id)?.property(.text) == "Edited once")

        undoManager.undo()
        #expect(document.site.component(withID: component.id)?.property(.text) == original)

        undoManager.redo()
        #expect(document.site.component(withID: component.id)?.property(.text) == "Edited once")
    }
}
