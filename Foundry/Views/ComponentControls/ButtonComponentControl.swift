import SwiftUI

struct ButtonComponentControl: View {
    let label: String
    let systemImage: String?
    let indicator: InspectorRowIndicator?
    @Binding var isActive: Bool

    var body: some View {
        InspectorRow(title: label, alignment: .center, indicator: indicator) {
            Button {
                isActive.toggle()
            } label: {
                if let systemImage {
                    Label(label, systemImage: systemImage)
                } else {
                    Text(label)
                }
            }
            .buttonStyle(.bordered)
            .accessibilityValue(isActive ? "On" : "Off")
        }
    }
}

#Preview {
    @Previewable @State var isActive = false
    ComponentControlPreview {
        ButtonComponentControl(label: "Action", systemImage: "sparkles", indicator: .preview, isActive: $isActive)
    }
}
