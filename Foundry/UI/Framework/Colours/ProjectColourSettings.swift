import SwiftUI

struct ProjectColourSettings: View {
    let session: FrameworkEditorSession
    @ObservedObject private var document: FoundryDocument
    @State private var model: FrameworkColourPreviewModel
    @State private var deleting: PreviewColourPalette?
    @State private var replacement = ""

    init(session: FrameworkEditorSession) {
        self.session = session
        document = session.document
        let model = FrameworkColourPreviewModel(storedPalettes: session.document.site.framework.colourPalettes)
        model.onChange = { [weak session] palettes, editSession in
            session?.setColourPalettes(palettes, session: editSession)
        }
        _model = State(initialValue: model)
    }

    var body: some View {
        FrameworkColoursPreview(model: model, canEditFramework: session.canEditFramework, requestDelete: { palette in
            replacement = ""
            deleting = palette
        }, tokenEditor: session.editor, framework: document.site.framework)
            .sheet(item: $deleting) { palette in
                let inUse = session.colourIsInUse(palette.id)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Delete \(palette.name)?").font(.headline)
                    if inUse {
                        Text("This colour is in use. Choose a replacement. Each part’s currently selected shade will be kept.")
                        Picker("Replace with", selection: $replacement) {
                            Text("Choose a colour").tag("")
                            Text("Inherit").tag("inherit")
                            ForEach(document.site.framework.colourPalettes.filter { $0.id != palette.id && $0.origin != .standard && $0.colourKind == palette.storedValue.colourKind }) { value in
                                Text("\(value.name) — \(String(describing: value.origin).capitalized)").tag(value.id)
                            }
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") { deleting = nil }.keyboardShortcut(.cancelAction)
                        Button("Delete Colour", role: .destructive) {
                            session.deleteColour(palette.id, replacement: replacement.isEmpty ? nil : replacement)
                            model.synchronize(document.site.framework.colourPalettes)
                            deleting = nil
                        }
                        .disabled(inUse && replacement.isEmpty)
                    }
                }
                .padding(20)
                .frame(width: 380)
                .controlSize(.small)
            }
            .onChange(of: document.site.framework.colourPalettes) { _, values in
                model.synchronize(values)
            }
            .onAppear { model.synchronize(document.site.framework.colourPalettes) }
    }
}
