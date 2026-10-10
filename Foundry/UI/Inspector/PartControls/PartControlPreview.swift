import SwiftUI

struct PartControlPreview<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Grid(horizontalSpacing: InspectorMetrics.columnSpacing, verticalSpacing: 10) {
            content()
        }
        .controlSize(.small)
        .padding()
        .frame(width: 420)
    }
}

extension InspectorRowIndicator {
    static var preview: Self {
        .init(isVisible: true, isOverridden: false, breakpointName: "Desktop", toggle: {})
    }
}
