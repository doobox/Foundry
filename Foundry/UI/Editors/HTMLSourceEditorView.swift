import SwiftUI

struct HTMLSourceEditorView: View {
    private static let textSizeDefaultsKey = "htmlSourceEditorTextSize"
    private static let defaultTextSize = 13.0
    private static let sectionDefaultsKey = "htmlSourceEditorSection"

    @State private var html: String
    @State private var css: String
    @State private var javaScript: String
    @State private var controls: String
    @State private var pageCSS: String
    @State private var siteCSS: String
    @State private var pageJavaScript: String
    @State private var diagnostics: [PartPackageDiagnostic] = []
    @State private var pendingSource: HTMLPartSource?
    @State private var closeRequested = false
    @State private var showingDiagnostics = false
    private let originalSource: HTMLPartSource
    private let supportsControls: Bool
    @State private var selection: HTMLSourceSection = .html
    @AppStorage(textSizeDefaultsKey) private var textSize = defaultTextSize

    let cancel: () -> Void
    let save: (HTMLPartSource) -> Void

    init(source: HTMLPartSource, cancel: @escaping () -> Void, save: @escaping (HTMLPartSource) -> Void) {
        originalSource = source
        _html = State(initialValue: source.html)
        _css = State(initialValue: source.css)
        _javaScript = State(initialValue: source.javaScript)
        _controls = State(initialValue: HTMLPartControlsEditorText.body(from: source.controls ?? "[]"))
        _pageCSS = State(initialValue: source.pageCSS)
        _siteCSS = State(initialValue: source.siteCSS)
        _pageJavaScript = State(initialValue: source.pageJavaScript)
        supportsControls = source.controls != nil
        let remembered = UserDefaults.standard.string(forKey: Self.sectionDefaultsKey).flatMap(HTMLSourceSection.init(rawValue:)) ?? .html
        _selection = State(initialValue: source.controls != nil || remembered.isBasic ? remembered : .html)
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
                    pageCSS: $pageCSS,
                    siteCSS: $siteCSS,
                    pageJavaScript: $pageJavaScript,
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

                if let diagnostic = diagnostics.first {
                    Button {
                        showingDiagnostics = true
                    } label: {
                        Label(
                            "\(diagnostic.location): \(diagnostic.message)"
                                + (diagnostics.count > 1 ? " (+\(diagnostics.count - 1) more)" : ""),
                            systemImage: diagnostic.severity == .error ? "exclamationmark.circle" : "exclamationmark.triangle"
                        )
                        .lineLimit(1)
                        .foregroundStyle(diagnostic.severity == .error ? Color.red : Color.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Show validation messages")
                    .popover(isPresented: $showingDiagnostics) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, item in
                                    Label(
                                        "\(item.location): \(item.message)",
                                        systemImage: item.severity == .error ? "exclamationmark.circle" : "exclamationmark.triangle"
                                    )
                                    .foregroundStyle(item.severity == .error ? Color.red : Color.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(16)
                        }
                        .frame(width: 520, height: CGFloat(min(260, 44 + diagnostics.count * 58)))
                    }
                } else if selection == .controls {
                    Text("Enter controls or sections separated by commas, without outer brackets. Leave empty for no controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Enter controls or sections separated by commas, without outer brackets. Leave empty for no controls.")
                }

                Spacer(minLength: 8)
                Button("Cancel", role: .cancel) { closeRequested = true }
                    .keyboardShortcut(.cancelAction)
                Button(pendingSource == currentSource ? "Save with Warnings" : "Save", action: validateAndSave)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .rememberedEditorSize("html", minimum: CGSize(width: 820, height: 560), defaultSize: CGSize(width: 980, height: 700))
        .editorCloseHandling(requested: $closeRequested, hasChanges: currentSource != originalSource, close: cancel)
        .onChange(of: selection) { _, section in
            UserDefaults.standard.set(section.rawValue, forKey: Self.sectionDefaultsKey)
        }
    }

    private var currentSource: HTMLPartSource {
        .init(html: html, css: css, javaScript: javaScript, controls: supportsControls ? HTMLPartControlsEditorText.storedArray(from: controls) : nil,
              pageCSS: pageCSS, siteCSS: siteCSS, pageJavaScript: pageJavaScript)
    }

    private func validateAndSave() {
        let source = currentSource
        guard source.controls != nil else { save(source); return }
        let compiled = HTMLPartPrototype.compile(source: source)
        diagnostics = compiled.diagnostics
        guard compiled.definition != nil else { pendingSource = nil; return }
        if diagnostics.isEmpty || pendingSource == source { save(source) }
        else { pendingSource = source }
    }

}

private enum HTMLSourceSection: String, CaseIterable, Identifiable {
    case html = "HTML"
    case controls = "Controls"
    case css = "Instance CSS"
    case pageCSS = "Page CSS"
    case siteCSS = "Site CSS"
    case javaScript = "Instance JavaScript"
    case pageJavaScript = "Page JavaScript"

    var isBasic: Bool { self == .html || self == .css || self == .javaScript }

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
                ForEach(HTMLSourceSection.allCases.filter { supportsControls || $0.isBasic }) { section in
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
    @Binding var html: String
    @Binding var css: String
    @Binding var javaScript: String
    @Binding var controls: String
    @Binding var pageCSS: String
    @Binding var siteCSS: String
    @Binding var pageJavaScript: String
    let selection: HTMLSourceSection
    let textSize: CGFloat

    var body: some View {
        FoundryCodeEditor(text: selectedText, language: selectedLanguage, fontSize: textSize)
            .id(selection)
    }

    private var selectedText: Binding<String> {
        switch selection {
        case .html: $html
        case .controls: $controls
        case .css: $css
        case .pageCSS: $pageCSS
        case .siteCSS: $siteCSS
        case .javaScript: $javaScript
        case .pageJavaScript: $pageJavaScript
        }
    }

    private var selectedLanguage: FoundryCodeLanguage {
        switch selection {
        case .html: .html
        case .controls: .json
        case .css, .pageCSS, .siteCSS: .css
        case .javaScript, .pageJavaScript: .javaScript
        }
    }
}
