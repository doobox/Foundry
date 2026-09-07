import SwiftUI

struct DetailsComponentControl: View {
    let label: String
    let help: String?
    let indicator: InspectorRowIndicator?
    @Binding var isPresented: Bool

    var body: some View {
        InspectorRow(title: "", alignment: .center, indicator: indicator) {
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .help(help ?? label)
            .accessibilityLabel(label.isEmpty ? "Show details" : label)
            .accessibilityValue(isPresented ? "Shown" : "Hidden")
        }
    }
}

#Preview {
    @Previewable @State var isPresented = false
    ComponentControlPreview {
        DetailsComponentControl(label: "Details", help: "Show more settings", indicator: .preview, isPresented: $isPresented)
    }
}
