import SwiftUI

struct EditorCloseHandling: ViewModifier {
    @Binding var requested: Bool
    let hasChanges: Bool
    let close: () -> Void
    @State private var confirmsDiscard = false

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled()
            .background(SheetBackdropClose { requested = true })
            .onChange(of: requested) { _, requested in
                guard requested else { return }
                self.requested = false
                if hasChanges { confirmsDiscard = true } else { close() }
            }
            .alert("Discard unsaved changes?", isPresented: $confirmsDiscard) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard and Close", role: .destructive, action: close)
            } message: {
                Text("Your changes have not been saved.")
            }
    }
}

extension View {
    func editorCloseHandling(requested: Binding<Bool>, hasChanges: Bool, close: @escaping () -> Void) -> some View {
        modifier(EditorCloseHandling(requested: requested, hasChanges: hasChanges, close: close))
    }
}
