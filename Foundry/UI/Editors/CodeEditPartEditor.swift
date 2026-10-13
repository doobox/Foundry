import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import SwiftUI

struct CodeEditPartEditor: View {
    @Binding var text: String
    let language: FoundryCodeLanguage
    let fontSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var editorState = SourceEditorState()

    var body: some View {
        SourceEditor(
            $text,
            language: codeLanguage,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: colorScheme == .dark ? Self.darkTheme : Self.lightTheme,
                    font: .monospacedSystemFont(ofSize: fontSize, weight: .regular),
                    wrapLines: false
                ),
                layout: .init(additionalTextInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)),
                peripherals: .init(showGutter: true, showMinimap: true)
            ),
            state: $editorState
        )
    }

    private var codeLanguage: CodeLanguage {
        switch language {
        case .html: .html
        case .css: .css
        case .javaScript: .javascript
        case .json: .json
        case .markdown: .markdown
        }
    }

    private static let darkTheme = makeTheme(dark: true)
    private static let lightTheme = makeTheme(dark: false)

    private static func makeTheme(dark: Bool) -> EditorTheme {
        let text = color(dark ? 0xE8E8EB : 0x202124)
        let background = color(dark ? 0x202124 : 0xFFFFFF)
        return EditorTheme(
            text: .init(color: text),
            insertionPoint: text,
            invisibles: .init(color: color(dark ? 0x60636A : 0xB2B4B9)),
            background: background,
            lineHighlight: color(dark ? 0x2A2C30 : 0xF1F5FA),
            selection: color(dark ? 0x44546B : 0xC6DFFF),
            keywords: .init(color: color(dark ? 0xF087A6 : 0xA42C60)),
            commands: .init(color: color(dark ? 0x78C2B3 : 0x326D74)),
            types: .init(color: color(dark ? 0x8BBCEB : 0x21518A)),
            attributes: .init(color: color(dark ? 0xD9AE78 : 0x806000)),
            variables: .init(color: color(dark ? 0x91C7E8 : 0x176394)),
            values: .init(color: color(dark ? 0xC4A2E9 : 0x7139A0)),
            numbers: .init(color: color(dark ? 0xD9CA82 : 0x5B49B0)),
            strings: .init(color: color(dark ? 0xEC9A83 : 0xB33929)),
            characters: .init(color: color(dark ? 0xD9CA82 : 0x5B49B0)),
            comments: .init(color: color(dark ? 0x8B929A : 0x578257))
        )
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
