import SwiftUI

struct ThemeProseSettings: View {
    let theme: Theme
    let session: ThemeEditorSession
    private let tokens = BootstrapEditorSection.prose.tokens

    var body: some View {
        ThemeEditorPage(title: "Prose", subtitle: "Defaults for Markdown and other content using Bootstrap’s prose styling.") {
            Button("Reset", systemImage: "arrow.counterclockwise") {
                session.editor.resetBootstrapTokens(.prose)
            }
            .disabled(!theme.bootstrapTokens.isChanged(.prose))
        } content: {
            ThemeEditorCard(title: "Text") { rows(0..<2) }
            ThemeEditorCard(title: "Larger Screens", subtitle: "Used at viewport widths of 1024px and above.") { rows(2..<4) }
            ThemeEditorCard(title: "Content Spacing", subtitle: "By default, spacing follows text size × line height. Enter a CSS length to override it, such as 1.5rem.") { rows(4..<5) }
            ThemeEditorCard(title: "Heading Colours", subtitle: "These follow the website’s light and dark modes.") { rows(5..<7) }
        }
        .disabled(!session.canEditTheme)
    }

    private func rows(_ range: Range<Int>) -> some View {
        ForEach(range, id: \.self) { index in
            BootstrapTokenRow(token: tokens[index], value: theme.bootstrapTokens.value(tokens[index]), editor: session.editor)
        }
    }
}
