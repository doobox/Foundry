import SwiftUI

struct MarkdownSourceEditorView: View {
    @State private var source: String
    @State private var closeRequested = false
    @AppStorage("htmlSourceEditorTextSize") private var textSize = 13.0
    private let originalSource: String
    let cancel: () -> Void
    let save: (String) -> Void

    init(source: String, cancel: @escaping () -> Void, save: @escaping (String) -> Void) {
        originalSource = source
        _source = State(initialValue: source)
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            FoundryCodeEditor(text: $source, language: .markdown, fontSize: CGFloat(textSize))
                .accessibilityLabel("Markdown source")
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
                Text("Headings, lists, links, images, tables and fenced code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { closeRequested = true }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(source) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .rememberedEditorSize("markdown", minimum: CGSize(width: 640, height: 420), defaultSize: CGSize(width: 880, height: 640))
        .editorCloseHandling(requested: $closeRequested, hasChanges: source != originalSource, close: cancel)
    }
}
