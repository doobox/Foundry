import SwiftUI

struct ProjectColourSettings: View {
    let session: ThemeEditorSession
    @ObservedObject private var document: FoundryDocument
    @State private var model: ThemeColourPreviewModel
    @State private var deleting: PreviewColourPalette?
    @State private var replacement = ""

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
        ThemeColoursPreview(model: model, canEditTheme: session.canEditTheme, requestDelete: { palette in
            replacement = ""
            deleting = palette
        })
            .sheet(item: $deleting) { palette in
                let inUse = session.colourIsInUse(palette.id)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Delete \(palette.name)?").font(.headline)
                    if inUse {
                        Text("This colour is in use. Choose a replacement. Each block’s currently selected shade will be kept.")
                        Picker("Replace with", selection: $replacement) {
                            Text("Choose a colour").tag("")
                            ForEach(document.site.theme.colourPalettes.filter { $0.id != palette.id }) { value in
                                Text("\(value.name) — \(String(describing: value.origin).capitalized)").tag(value.id)
                            }
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") { deleting = nil }.keyboardShortcut(.cancelAction)
                        Button("Delete Colour", role: .destructive) {
                            session.deleteColour(palette.id, replacement: replacement.isEmpty ? nil : replacement)
                            model.synchronize(document.site.theme.colourPalettes)
                            deleting = nil
                        }
                        .disabled(inUse && replacement.isEmpty)
                    }
                }
                .padding(20)
                .frame(width: 380)
                .controlSize(.small)
            }
            .onChange(of: document.site.theme.colourPalettes) { _, values in
                model.synchronize(values)
            }
            .onAppear { model.synchronize(document.site.theme.colourPalettes) }
    }
}
