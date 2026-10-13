import AppKit
import CodeEditLanguages
import CodeEditTextView
import Testing
@testable import CodeEditSourceEditor

struct MarkdownHighlightingTests {
    @Test func markdownCaptureNamesAreRecognized() {
        #expect(CaptureName.fromString("text.title") == .markupHeading)
        #expect(CaptureName.fromString("text.strong") == .markupStrong)
        #expect(CaptureName.fromString("text.emphasis") == .markupEmphasis)
        #expect(CaptureName.fromString("text.literal") == .markupCode)
        #expect(CaptureName.fromString("text.uri") == .markupLink)
        #expect(CaptureName.fromString("punctuation.special") == .markupPunctuation)
    }

    @Test @MainActor func markdownInlineGrammarProducesHighlights() throws {
        let textView = Mock.textView()
        textView.setText("# Heading\n\n**bold** *italic* [link](https://example.com) `code`\n")

        let state = TreeSitterState(
            codeLanguage: .markdown,
            readCallback: textView.createReadCallback(),
            readBlock: textView.createReadBlock()
        )
        #expect(state.layers.first?.languageQuery != nil)
        #expect(state.layers.contains(where: { $0.id == .markdownInline }))

        let client = TreeSitterClient()
        client.state = state
        client.readCallback = textView.createReadCallback()
        let highlights = client.queryHighlightsForRange(range: textView.documentRange)
        let headingText = (textView.string as NSString).range(of: "Heading")
        #expect(highlights.contains(where: {
            $0.capture == .markupHeading && $0.range.intersection(headingText) != nil
        }))
        #expect(highlights.contains(where: { $0.capture == .markupStrong }))
        #expect(highlights.contains(where: { $0.capture == .markupEmphasis }))
        #expect(highlights.contains(where: { $0.capture == .markupLink }))
        #expect(highlights.contains(where: { $0.capture == .markupCode }))
    }

    @Test func markdownThemeStylesSemanticCaptures() {
        let theme = Mock.theme()
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        #expect(theme.colorFor(.markupHeading) != theme.colorFor(nil))
        #expect(theme.colorFor(.markupLink) != theme.colorFor(nil))
        #expect(theme.fontFor(for: .markupStrong, from: font).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(theme.fontFor(for: .markupEmphasis, from: font).fontDescriptor.symbolicTraits.contains(.italic))
    }
}
