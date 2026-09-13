import SwiftUI

struct HTMLPartSource: Equatable {
    var html: String
    var css: String
    var javaScript: String
}

struct HTMLSourceEditorView: View {
    private static let textSizeDefaultsKey = "htmlSourceEditorTextSize"
    private static let defaultTextSize = 13.0

    @State private var html: AttributedString
    @State private var css: AttributedString
    @State private var javaScript: AttributedString
    @State private var selection: HTMLSourceSection = .html
    @AppStorage(textSizeDefaultsKey) private var textSize = defaultTextSize

    let cancel: () -> Void
    let save: (HTMLPartSource) -> Void

    init(source: HTMLPartSource, cancel: @escaping () -> Void, save: @escaping (HTMLPartSource) -> Void) {
        let storedTextSize = UserDefaults.standard.object(forKey: Self.textSizeDefaultsKey) as? Double
            ?? Self.defaultTextSize
        let fontSize = CGFloat(storedTextSize)
        _html = State(initialValue: SourceSyntaxHighlighter.highlight(source.html, language: .html, fontSize: fontSize))
        _css = State(initialValue: SourceSyntaxHighlighter.highlight(source.css, language: .css, fontSize: fontSize))
        _javaScript = State(initialValue: SourceSyntaxHighlighter.highlight(source.javaScript, language: .javaScript, fontSize: fontSize))
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HTMLSourceSidebar(selection: $selection)
                Divider()
                HTMLSourceCodeEditor(
                    html: $html,
                    css: $css,
                    javaScript: $javaScript,
                    selection: selection,
                    textSize: CGFloat(textSize)
                )
            }
            Divider()
            HStack {
                ControlGroup {
                    Button {
                        textSize = max(12, textSize - 1)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(textSize <= 12)
                    .help("Decrease text size")

                    Button {
                        textSize = 13
                    } label: {
                        Image(systemName: "text.magnifyingglass")
                    }
                    .help("Reset text size to 13 pt")
                    .accessibilityLabel("Text size: \(Int(textSize)) points")

                    Button {
                        textSize = min(18, textSize + 1)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(textSize >= 18)
                    .help("Increase text size")
                }
                .controlGroupStyle(.navigation)
                .fixedSize()

                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(.init(
                        html: String(html.characters),
                        css: String(css.characters),
                        javaScript: String(javaScript.characters)
                    ))
                }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 820, idealWidth: 980, minHeight: 560, idealHeight: 700)
        .onChange(of: textSize) { _, newSize in
            applyTextSize(CGFloat(newSize))
        }
    }

    private func applyTextSize(_ fontSize: CGFloat) {
        html = SourceSyntaxHighlighter.highlight(String(html.characters), language: .html, fontSize: fontSize)
        css = SourceSyntaxHighlighter.highlight(String(css.characters), language: .css, fontSize: fontSize)
        javaScript = SourceSyntaxHighlighter.highlight(
            String(javaScript.characters),
            language: .javaScript,
            fontSize: fontSize
        )
    }
}

private enum HTMLSourceSection: String, CaseIterable, Identifiable {
    case html = "HTML"
    case css = "CSS"
    case javaScript = "JS"

    var id: Self { self }
}

private struct HTMLSourceSidebar: View {
    @Binding var selection: HTMLSourceSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Part Code")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 18)
            VStack(spacing: 4) {
                ForEach(HTMLSourceSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        Label(section.rawValue, systemImage: "chevron.left.forwardslash.chevron.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == section ? Color.white : Color.primary)
                    .background(selection == section ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(.horizontal, 10)
            Spacer()
        }
        .frame(width: 220)
    }
}

private struct HTMLSourceCodeEditor: View {
    @Binding var html: AttributedString
    @Binding var css: AttributedString
    @Binding var javaScript: AttributedString
    let selection: HTMLSourceSection
    let textSize: CGFloat

    var body: some View {
        switch selection {
        case .html: editor(text: $html, language: .html)
        case .css: editor(text: $css, language: .css)
        case .javaScript: editor(text: $javaScript, language: .javaScript)
        }
    }

    private func editor(text: Binding<AttributedString>, language: SourceCodeLanguage) -> some View {
        TextEditor(text: text)
            .padding(12)
            .task(id: String(text.wrappedValue.characters)) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                let source = String(text.wrappedValue.characters)
                let highlighted = SourceSyntaxHighlighter.highlight(
                    source,
                    language: language,
                    fontSize: textSize
                )
                if text.wrappedValue != highlighted {
                    text.wrappedValue = highlighted
                }
            }
    }
}

private enum SourceCodeLanguage {
    case html
    case css
    case javaScript
}

private enum SourceSyntaxHighlighter {
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
