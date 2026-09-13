import SwiftUI

struct DividerBlockControl: View {
    var body: some View {
        Divider()
            .padding(.vertical, 10)
            .accessibilityHidden(true)
    }
}

#Preview {
    BlockControlPreview {
        DividerBlockControl()
    }
}
