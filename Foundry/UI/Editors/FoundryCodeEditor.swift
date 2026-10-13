import SwiftUI

struct FoundryCodeEditor: View {
    @Binding var text: String
    let language: FoundryCodeLanguage
    let fontSize: CGFloat

    var body: some View {
        CodeEditPartEditor(text: $text, language: language, fontSize: fontSize)
    }
}
