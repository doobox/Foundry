import SwiftUI

struct SiteCodeEditorView: View {
    @State private var snippets: [String]
    @State private var isEnabled: Bool
    private let originalSnippets: [String]
    private let originallyEnabled: Bool
    @State private var closeRequested = false
    @AppStorage("siteCodeEditorSection") private var selection: SiteCodeSection = .head
    @AppStorage("htmlSourceEditorTextSize") private var textSize = 13.0

    let cancel: () -> Void
    let save: (Bool, String, String, String, String, String) -> Void

    init(site: Site, cancel: @escaping () -> Void, save: @escaping (Bool, String, String, String, String, String) -> Void) {
        originalSnippets = [site.headCode, site.bodyStartCode, site.bodyEndCode, site.cssCode, site.javaScriptCode]
        originallyEnabled = site.customCodeEnabled
        _snippets = State(initialValue: originalSnippets)
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
                FoundryCodeEditor(text: $snippets[selection.rawValue], language: selection.codeLanguage, fontSize: CGFloat(textSize))
                    .id(selection)
                    .accessibilityLabel("\(selection.title) code")
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
                if let warning = markupWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(warning)
                } else {
                    Text(selection.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(selection.subtitle)
                }
                Spacer(minLength: 8)
                Button("Cancel", role: .cancel) { closeRequested = true }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: saveChanges)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .rememberedEditorSize("siteCode", minimum: CGSize(width: 820, height: 560), defaultSize: CGSize(width: 980, height: 700))
        .editorCloseHandling(requested: $closeRequested, hasChanges: isEnabled != originallyEnabled || snippets != originalSnippets, close: cancel)
    }

    private func saveChanges() {
        save(isEnabled, snippets[0], snippets[1], snippets[2], snippets[3], snippets[4])
    }

    private var markupWarning: String? {
        guard selection != .css, selection != .javaScript else { return nil }
        let code = snippets[selection.rawValue].lowercased()
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
