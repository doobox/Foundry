import SwiftUI

/// A code editor with regex syntax colouring, shared by the HTML part's
/// source sheet and the Inspector's CSS field. The text is an
/// AttributedString so colours travel with it; whenever the characters
/// change the whole text is re-coloured, which keeps the selection in place
/// because only attributes move.
struct HighlightedCodeEditor: View {
    @Binding var text: AttributedString
    let language: SourceCodeLanguage
    let fontSize: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .autocorrectionDisabled()
            .background(CodeEditingSubstitutionDisabler())
            .task(id: String(text.characters)) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                let highlighted = SourceSyntaxHighlighter.highlight(
                    String(text.characters),
                    language: language,
                    fontSize: fontSize
                )
                if text != highlighted {
                    text = highlighted
                }
            }
    }
}

enum SourceCodeLanguage {
    case html
    case css
    case javaScript
}

/// TextEditor exposes no control over NSTextView's automatic substitutions,
/// which turn typed straight quotes into curly ones — silently invalid in
/// code. This finds the sheet's text views and switches substitutions off.
struct CodeEditingSubstitutionDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { disableSubstitutions(around: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { disableSubstitutions(around: nsView) }
    }

    private func disableSubstitutions(around view: NSView) {
        var root = view as NSView
        while let parent = root.superview { root = parent }
        for textView in textViews(in: root) {
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
        }
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        var result = view.subviews.flatMap(textViews(in:))
        if let textView = view as? NSTextView {
            result.append(textView)
        }
        return result
    }
}

enum SourceSyntaxHighlighter {
    private struct Rule {
        let pattern: String
        let color: Color
        var captureGroup = 0
        var options: NSRegularExpression.Options = []
    }

    static func highlight(
        _ source: String,
        language: SourceCodeLanguage,
        fontSize: CGFloat
    ) -> AttributedString {
        var result = AttributedString(source)
        result.foregroundColor = .primary
        result.font = .system(size: fontSize, design: .monospaced)
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)

        for rule in rules(for: language) {
            guard let expression = try? NSRegularExpression(
                pattern: rule.pattern,
                options: rule.options
            ) else { continue }

            for match in expression.matches(in: source, range: fullRange) {
                let matchedRange = match.range(at: rule.captureGroup)
                guard matchedRange.location != NSNotFound,
                      let stringRange = Range(matchedRange, in: source),
                      let lowerBound = AttributedString.Index(stringRange.lowerBound, within: result),
                      let upperBound = AttributedString.Index(stringRange.upperBound, within: result)
                else { continue }

                result[lowerBound..<upperBound].foregroundColor = rule.color
            }
        }

        return result
    }

    private static func rules(for language: SourceCodeLanguage) -> [Rule] {
        switch language {
        case .html:
            [
                Rule(pattern: "&(?:#\\d+|#x[0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]+);", color: .orange),
                Rule(pattern: "(?:\"[^\"]*\"|'[^']*')", color: .green),
                Rule(pattern: "</?\\s*([A-Za-z][\\w:-]*)", color: .blue, captureGroup: 1),
                Rule(pattern: "\\s([A-Za-z_:][\\w:.-]*)(?=\\s*=)", color: .purple, captureGroup: 1),
                Rule(pattern: "<!--[\\s\\S]*?-->", color: .secondary)
            ]
        case .css:
            [
                Rule(pattern: "#[0-9A-Fa-f]{3,8}\\b|\\b\\d+(?:\\.\\d+)?(?:px|rem|em|%|vh|vw|s|ms|deg)?\\b", color: .orange),
                Rule(pattern: "@[A-Za-z-]+", color: .pink),
                Rule(pattern: "(?m)([A-Za-z-]+)(?=\\s*:)", color: .blue, captureGroup: 1),
                Rule(pattern: "(?:\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*')", color: .green),
                Rule(pattern: "/\\*[\\s\\S]*?\\*/", color: .secondary)
            ]
        case .javaScript:
            [
                Rule(pattern: "\\b(?:break|case|catch|class|const|continue|default|delete|do|else|export|extends|false|finally|for|from|function|if|import|in|instanceof|let|new|null|of|return|static|super|switch|this|throw|true|try|typeof|undefined|var|void|while|with|yield|async|await)\\b", color: .pink),
                Rule(pattern: "\\b\\d+(?:\\.\\d+)?\\b", color: .orange),
                Rule(pattern: "(?:\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`)", color: .green),
                Rule(pattern: "//.*$|/\\*[\\s\\S]*?\\*/", color: .secondary, options: [.anchorsMatchLines])
            ]
        }
    }
}
