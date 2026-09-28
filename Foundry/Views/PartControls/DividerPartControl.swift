import SwiftUI

struct DividerPartControl: View {
    var body: some View {
        Divider()
            .padding(.vertical, 5)
            .accessibilityHidden(true)
    }
}

#Preview {
    PartControlPreview {
        DividerPartControl()
    }
}
