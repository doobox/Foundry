import SwiftUI

struct InfoComponentControl: View {
    let text: String

    var body: some View {
        InspectorRow(title: "", alignment: .top) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ComponentControlPreview {
        InfoComponentControl(text: "Helpful information supplied by the component developer.")
    }
}
