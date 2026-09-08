import SwiftUI

struct DividerComponentControl: View {
    var body: some View {
        Divider()
            .padding(.vertical, 10)
            .accessibilityHidden(true)
    }
}

#Preview {
    ComponentControlPreview {
        DividerComponentControl()
    }
}
