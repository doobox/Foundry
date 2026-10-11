import AppKit

/// Part names are labels, not prose. Use a private field editor so disabling
/// AppKit's text-checking services never changes other fields in the window.
final class StructureNameCell: NSTextFieldCell {
    private lazy var renameEditor: NSTextView = {
        let editor = NSTextView()
        editor.isFieldEditor = true
        configure(editor)
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        renameEditor
    }

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        if let editor = editor as? NSTextView { configure(editor) }
        return editor
    }

    private func configure(_ editor: NSTextView) {
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.enabledTextCheckingTypes = 0
    }
}
