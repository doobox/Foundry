import SwiftUI

/// Project-named spacers that extend Bootstrap's fixed spacing steps.
struct FrameworkCustomSpacingCard: View {
    let framework: Framework
    let session: FrameworkEditorSession
    @State private var pendingDeletion: CustomSpacingToken?

    var body: some View {
        FrameworkEditorCard {
            HStack(spacing: 8) {
                Text("Custom Spacing").font(.headline).accessibilityAddTraits(.isHeader)
                Button("Add Spacing Size", systemImage: "plus", action: session.editor.addCustomSpacing)
                    .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 24, height: 24)
            }
            if framework.spacing.custom.isEmpty {
                Text("Extend the scale for your project.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(framework.spacing.custom) { token in
                        FrameworkCustomSpacingRow(token: token, editor: session.editor) { pendingDeletion = token }
                        if token.id != framework.spacing.custom.last?.id { Divider() }
                    }
                }
            }
        }
        .confirmationDialog("Replace \(pendingDeletion?.name ?? "") with", isPresented: deletionPresented, titleVisibility: .visible) {
            ForEach(framework.spacing.choices.filter { $0.id != pendingDeletion?.name }) { choice in
                Button("\(choice.label) — \(choice.amount.formatted()) rem") {
                    guard let token = pendingDeletion else { return }
                    session.editor.removeCustomSpacing(token.id, replacingWith: choice.id)
                    pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Existing spacing selections will use the replacement. You can undo this change.")
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}
