import SwiftUI

struct BootstrapHuePicker: View {
    let palette: PreviewColourPalette
    let canEdit: Bool
    let select: (String) -> Void
    @State private var selectedHue = ""

    var body: some View {
        Picker(palette.name, selection: $selectedHue) {
            if palette.bootstrapHue == nil { Text("Custom shades").tag("") }
            ForEach(BootstrapColourCatalogue.hues, id: \.self) { hue in
                Text(hue.capitalized).tag(hue)
            }
        }
        .disabled(!canEdit)
        .onAppear { selectedHue = palette.bootstrapHue ?? "" }
        .onChange(of: palette.bootstrapHue) { _, hue in selectedHue = hue ?? "" }
        .onChange(of: selectedHue) { _, hue in
            guard canEdit, !hue.isEmpty, hue != palette.bootstrapHue else { return }
            select(hue)
        }
    }
}
