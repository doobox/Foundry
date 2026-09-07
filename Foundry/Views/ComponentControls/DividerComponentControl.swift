import SwiftUI

struct DividerComponentControl: View {
    var body: some View {
        Divider()
            .padding(.vertical, 6)
            .accessibilityHidden(true)
    }
}

#Preview {
    ComponentControlPreview {
        DividerComponentControl()
    }
}
