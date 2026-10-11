import AppKit
import Testing
@testable import Foundry

@MainActor
struct StructureNameCellTests {
    @Test func renameEditorDisablesTextCheckingAfterSetup() throws {
        let cell = StructureNameCell(textCell: "Part name")
        let field = NSTextField()
        let editor = try #require(cell.fieldEditor(for: field))
        #expect(editor.isFieldEditor)
        #expect(cell.setUpFieldEditorAttributes(editor) === editor)
        #expect(editor.enabledTextCheckingTypes == 0)
        #expect(editor.isContinuousSpellCheckingEnabled == false)
        #expect(editor.isGrammarCheckingEnabled == false)
        #expect(editor.isAutomaticDataDetectionEnabled == false)
        #expect(editor.isAutomaticLinkDetectionEnabled == false)
        #expect(editor.isAutomaticSpellingCorrectionEnabled == false)
        #expect(editor.isAutomaticTextCompletionEnabled == false)
        #expect(cell.fieldEditor(for: field) === editor)
    }

    @Test func renameEditorDoesNotUseTheWindowSharedEditor() throws {
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        let field = NSTextField()
        let shared = try #require(window.fieldEditor(true, for: field) as? NSTextView)
        let originalTypes = shared.enabledTextCheckingTypes
        let originalSpelling = shared.isContinuousSpellCheckingEnabled
        let cell = StructureNameCell(textCell: "Part name")
        let editor = try #require(cell.fieldEditor(for: field))
        _ = cell.setUpFieldEditorAttributes(editor)
        #expect(editor !== shared)
        #expect(shared.enabledTextCheckingTypes == originalTypes)
        #expect(shared.isContinuousSpellCheckingEnabled == originalSpelling)
    }
}
