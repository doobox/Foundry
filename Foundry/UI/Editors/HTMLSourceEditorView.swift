import SwiftUI

struct HTMLSourceEditorView: View {
    private static let textSizeDefaultsKey = "htmlSourceEditorTextSize"
    private static let defaultTextSize = 13.0

    @State private var html: AttributedString
    @State private var css: AttributedString
    @State private var javaScript: AttributedString
    @State private var controls: AttributedString
    @State private var diagnostics: [PartPackageDiagnostic] = []
    @State private var pendingSource: HTMLPartSource?
    @State private var closeRequested = false
    private let originalSource: HTMLPartSource
    private let supportsControls: Bool
    @State private var selection: HTMLSourceSection = .html
    @AppStorage(textSizeDefaultsKey) private var textSize = defaultTextSize

    let cancel: () -> Void
    let save: (HTMLPartSource) -> Void

    init(source: HTMLPartSource, cancel: @escaping () -> Void, save: @escaping (HTMLPartSource) -> Void) {
        originalSource = source
        let storedTextSize = UserDefaults.standard.object(forKey: Self.textSizeDefaultsKey) as? Double
            ?? Self.defaultTextSize
        let fontSize = CGFloat(storedTextSize)
        _html = State(initialValue: SourceSyntaxHighlighter.highlight(source.html, language: .html, fontSize: fontSize))
        _css = State(initialValue: SourceSyntaxHighlighter.highlight(source.css, language: .css, fontSize: fontSize))
        _javaScript = State(initialValue: SourceSyntaxHighlighter.highlight(source.javaScript, language: .javaScript, fontSize: fontSize))
        _controls = State(initialValue: SourceSyntaxHighlighter.highlight(source.controls ?? "[]", language: .javaScript, fontSize: fontSize))
        supportsControls = source.controls != nil
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HTMLSourceSidebar(selection: $selection, supportsControls: supportsControls)
                Divider()
                HTMLSourceCodeEditor(
                    html: $html,
                    css: $css,
                    javaScript: $javaScript,
                    controls: $controls,
                    selection: selection,
                    textSize: CGFloat(textSize)
                )
            }
            Divider()
            if !diagnostics.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                            Label("\(diagnostic.location): \(diagnostic.message)", systemImage: diagnostic.severity == .error ? "exclamationmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(diagnostic.severity == .error ? Color.red : Color.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(maxHeight: 130)
            }
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
                Button("Cancel", role: .cancel) { closeRequested = true }
                    .keyboardShortcut(.cancelAction)
                Button(pendingSource == currentSource ? "Save with Warnings" : "Save", action: validateAndSave)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .rememberedEditorSize("html", minimum: CGSize(width: 820, height: 560), defaultSize: CGSize(width: 980, height: 700))
        .editorCloseHandling(requested: $closeRequested, hasChanges: currentSource != originalSource, close: cancel)
        .onChange(of: textSize) { _, newSize in
            applyTextSize(CGFloat(newSize))
        }
    }

    private var currentSource: HTMLPartSource {
        .init(html: String(html.characters), css: String(css.characters), javaScript: String(javaScript.characters), controls: supportsControls ? String(controls.characters) : nil)
    }

    private func validateAndSave() {
        let source = currentSource
        guard let declarations = source.controls else { save(source); return }
        let compiled = HTMLPartPrototype.compile(html: source.html, css: source.css, javaScript: source.javaScript, controls: declarations)
        diagnostics = compiled.diagnostics
        guard compiled.definition != nil else { pendingSource = nil; return }
        if diagnostics.isEmpty || pendingSource == source { save(source) }
        else { pendingSource = source }
    }

    private func applyTextSize(_ fontSize: CGFloat) {
        html = SourceSyntaxHighlighter.highlight(String(html.characters), language: .html, fontSize: fontSize)
        css = SourceSyntaxHighlighter.highlight(String(css.characters), language: .css, fontSize: fontSize)
        javaScript = SourceSyntaxHighlighter.highlight(
            String(javaScript.characters),
            language: .javaScript,
            fontSize: fontSize
        )
        controls = SourceSyntaxHighlighter.highlight(String(controls.characters), language: .javaScript, fontSize: fontSize)
    }
}

private enum HTMLSourceSection: String, CaseIterable, Identifiable {
    case html = "HTML"
    case css = "CSS"
    case javaScript = "JS"
    case controls = "Controls"

    var id: Self { self }
}

private struct HTMLSourceSidebar: View {
    @Binding var selection: HTMLSourceSection
    let supportsControls: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Part Code")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 18)
            VStack(spacing: 4) {
                ForEach(HTMLSourceSection.allCases.filter { supportsControls || $0 != .controls }) { section in
                    Button {
                        selection = section
                    } label: {
                        Label(section.rawValue, systemImage: section == .controls ? "slider.horizontal.3" : "chevron.left.forwardslash.chevron.right")
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
    @Binding var controls: AttributedString
    let selection: HTMLSourceSection
    let textSize: CGFloat

    var body: some View {
        switch selection {
        case .html: editor(text: $html, language: .html)
        case .css: editor(text: $css, language: .css)
        case .javaScript: editor(text: $javaScript, language: .javaScript)
        case .controls:
            VStack(alignment: .leading, spacing: 0) {
                Text("Declare Inspector controls and groups using a manifest’s inspector array. Leave [] for no controls.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                editor(text: $controls, language: .javaScript)
            }
        }
    }

    private func editor(text: Binding<AttributedString>, language: SourceCodeLanguage) -> some View {
        HighlightedCodeEditor(text: text, language: language, fontSize: textSize)
            .padding(12)
    }
}
