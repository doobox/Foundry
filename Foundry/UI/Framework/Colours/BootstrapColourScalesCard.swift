import SwiftUI

struct BootstrapColourScalesCard: View {
    let framework: Framework
    let editor: ProjectEditor
    let previews: [String: String]
    @State private var resetGeneration = 0

    var body: some View {
        FrameworkEditorCard {
            HStack {
                Text("Bootstrap Colour Scales").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if framework.bootstrapTokens.isChanged(.colourScales) {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        resetGeneration += 1
                        editor.resetBootstrapTokens(.colourScales)
                    }
                    .help("Restore all Bootstrap colour scales. Theme and custom colour edits are kept.")
                }
            }
            ForEach(BootstrapColourCatalogue.hues, id: \.self) { hue in
                BootstrapColourScaleRow(hue: hue, framework: framework, editor: editor, previews: previews)
                    .id("\(hue)-\(resetGeneration)")
                if hue != BootstrapColourCatalogue.hues.last { Divider() }
            }
        }
    }
}
