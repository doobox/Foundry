import SwiftUI

struct ProjectColourSettings: View {
    let session: ThemeEditorSession
    @ObservedObject private var document: FoundryDocument
    @State private var model: ThemeColourPreviewModel

    init(session: ThemeEditorSession) {
        self.session = session
        document = session.document
        let model = ThemeColourPreviewModel(storedPalettes: session.document.site.theme.colourPalettes)
        model.onChange = { [weak session] palettes, editSession in
            session?.setColourPalettes(palettes, session: editSession)
        }
        _model = State(initialValue: model)
    }

    var body: some View {
        ThemeColoursPreview(model: model)
            .onChange(of: document.site.theme.colourPalettes) { _, values in
                model.synchronize(values)
            }
            .onAppear { model.synchronize(document.site.theme.colourPalettes) }
    }
}
