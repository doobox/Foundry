import SwiftUI

struct InspectorControlResetMenu: ViewModifier {
    @Environment(\.inspectorControlReset) private var reset

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reset {
            content
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Reset", action: reset.action)
                        .disabled(!reset.isEnabled)
                }
        } else {
            content
        }
    }
}
