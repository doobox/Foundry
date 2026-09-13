import SwiftUI

struct DividerPartControl: View {
    var body: some View {
        Divider()
            .padding(.vertical, 10)
            .accessibilityHidden(true)
    }
}

#Preview {
    PartControlPreview {
        DividerPartControl()
    }
}
