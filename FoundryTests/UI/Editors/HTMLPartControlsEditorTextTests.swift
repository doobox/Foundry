import Foundation
import Testing
@testable import Foundry

@MainActor
struct HTMLPartControlsEditorTextTests {
    @Test(arguments: ["[]", "[\n]"])
    func emptyArrayOpensAsEmptyEditor(stored: String) {
        #expect(HTMLPartControlsEditorText.body(from: stored).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(HTMLPartControlsEditorText.storedArray(from: HTMLPartControlsEditorText.body(from: stored)) == "[]")
    }

    @Test
    func multipleEntriesCompileWithoutTypedBrackets() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let editorText = #"{"type":"text","id":"title","defaults":{"xs":"Hello"}}, {"type":"toggle","id":"visible","defaults":{"xs":true}}"#
        let stored = HTMLPartControlsEditorText.storedArray(from: editorText)
        #expect(HTMLPartControlsEditorText.body(from: stored) == editorText)
        let compiled = HTMLPartPrototype.compile(html: "<p>{{ control.title }}</p>", css: "", javaScript: "", controls: stored)
        let definition = try #require(compiled.definition, "\(compiled.diagnostics)")
        #expect(definition.property(for: .init(rawValue: "title")) != nil)
        #expect(definition.property(for: .init(rawValue: "visible")) != nil)
    }

    @Test
    func prettyPrintedArrayKeepsItsInteriorFormatting() {
        let stored = "[\n  {\"type\":\"text\",\"id\":\"title\"}\n]"
        #expect(HTMLPartControlsEditorText.storedArray(from: HTMLPartControlsEditorText.body(from: stored)) == stored)
    }
}
