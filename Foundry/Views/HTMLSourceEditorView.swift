import SwiftUI

struct HTMLComponentSource: Equatable {
    var html: String
    var css: String
    var javaScript: String
}

struct HTMLSourceEditorView: View {
    @State private var html: String
    @State private var css: String
    @State private var javaScript: String
    @State private var selection: HTMLSourceSection = .html

    let cancel: () -> Void
    let save: (HTMLComponentSource) -> Void

    init(source: HTMLComponentSource, cancel: @escaping () -> Void, save: @escaping (HTMLComponentSource) -> Void) {
        _html = State(initialValue: source.html)
        _css = State(initialValue: source.css)
        _javaScript = State(initialValue: source.javaScript)
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
                    selection: selection
                )
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(.init(html: html, css: css, javaScript: javaScript))
                }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 820, idealWidth: 980, minHeight: 560, idealHeight: 700)
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
            Text("Component Code")
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
    @Binding var html: String
    @Binding var css: String
    @Binding var javaScript: String
    let selection: HTMLSourceSection

    var body: some View {
        switch selection {
        case .html: editor(text: $html)
        case .css: editor(text: $css)
        case .javaScript: editor(text: $javaScript)
        }
    }

    private func editor(text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.system(.body, design: .monospaced))
            .padding(12)
    }
}
