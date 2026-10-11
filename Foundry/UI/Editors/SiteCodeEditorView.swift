import SwiftUI

struct SiteCodeEditorView: View {
    @State private var snippets: [AttributedString]
    @State private var isEnabled: Bool
    private let originalSnippets: [String]
    private let originallyEnabled: Bool
    @State private var closeRequested = false
    @State private var selection: SiteCodeSection = .head
    @AppStorage("htmlSourceEditorTextSize") private var textSize = 13.0

    let cancel: () -> Void
    let save: (Bool, String, String, String, String, String) -> Void

    init(site: Site, cancel: @escaping () -> Void, save: @escaping (Bool, String, String, String, String, String) -> Void) {
        originalSnippets = [site.headCode, site.bodyStartCode, site.bodyEndCode, site.cssCode, site.javaScriptCode]
        originallyEnabled = site.customCodeEnabled
        let size = UserDefaults.standard.object(forKey: "htmlSourceEditorTextSize") as? Double ?? 13
        _snippets = State(initialValue: [site.headCode, site.bodyStartCode, site.bodyEndCode, site.cssCode, site.javaScriptCode].enumerated().map { index, source in
            SourceSyntaxHighlighter.highlight(source, language: SiteCodeSection.allCases[index].language, fontSize: CGFloat(size))
        })
        _isEnabled = State(initialValue: site.customCodeEnabled)
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Site Code")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                    VStack(spacing: 4) {
                        ForEach(SiteCodeSection.allCases) { section in
                            Button {
                                selection = section
                            } label: {
                                Label(section.title, systemImage: "chevron.left.forwardslash.chevron.right")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(selection == section ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityAddTraits(selection == section ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 8)
                    Spacer()
                }
                .frame(width: 180)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text(selection.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(16)
                    Divider()
                    HighlightedCodeEditor(text: $snippets[selection.rawValue], language: selection.language, fontSize: CGFloat(textSize))
                        .id(selection)
                        .accessibilityLabel("\(selection.title) code")
                        .padding(8)
                    if let warning = markupWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(12)
                    }
                }
            }
            Divider()
            HStack {
                ControlGroup {
                    Button("Decrease text size", systemImage: "minus") { textSize = max(12, textSize - 1) }
                        .disabled(textSize <= 12)
                    Button("Reset text size", systemImage: "text.magnifyingglass") { textSize = 13 }
                    Button("Increase text size", systemImage: "plus") { textSize = min(18, textSize + 1) }
                        .disabled(textSize >= 18)
                }
                .labelStyle(.iconOnly)
                .controlGroupStyle(.navigation)
                .fixedSize()
                Toggle("Enable site code", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Disabled code stays saved but is not included in pages.")
                Spacer()
                Button("Cancel", role: .cancel) { closeRequested = true }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: saveChanges)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .rememberedEditorSize("siteCode", minimum: CGSize(width: 820, height: 560), defaultSize: CGSize(width: 980, height: 700))
        .editorCloseHandling(requested: $closeRequested, hasChanges: isEnabled != originallyEnabled || snippets.map { String($0.characters) } != originalSnippets, close: cancel)
        .onChange(of: textSize) { _, size in
            snippets = snippets.enumerated().map { index, snippet in
                SourceSyntaxHighlighter.highlight(String(snippet.characters), language: SiteCodeSection.allCases[index].language, fontSize: CGFloat(size))
            }
        }
    }

    private func saveChanges() {
        let values = snippets.map { String($0.characters) }
        save(isEnabled, values[0], values[1], values[2], values[3], values[4])
    }

    private var markupWarning: String? {
        guard selection != .css, selection != .javaScript else { return nil }
        let code = String(snippets[selection.rawValue].characters).lowercased()
        if ["<html", "<head", "<body"].contains(where: code.contains) {
            return "Paste only this location’s contents, without html, head or body wrapper tags."
        }
        for tag in ["script", "style"] {
            if code.components(separatedBy: "<" + tag).count != code.components(separatedBy: "</" + tag + ">").count {
                return "This snippet appears to contain an unclosed \(tag) element."
            }
        }
        return nil
    }
}
