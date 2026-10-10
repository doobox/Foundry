import SwiftUI

/// Project-named spacers that extend Bootstrap's fixed spacing steps.
struct ThemeCustomSpacingCard: View {
    let theme: Theme
    let session: ThemeEditorSession
    @State private var pendingDeletion: CustomSpacingToken?

    var body: some View {
        ThemeEditorCard {
            HStack(spacing: 8) {
                Text("Custom Spacing").font(.headline).accessibilityAddTraits(.isHeader)
                ThemeAddButton(title: "Add Spacing Size", action: session.editor.addCustomSpacing)
            }
            if theme.spacing.custom.isEmpty {
                Text("Extend the scale for your project.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(theme.spacing.custom) { token in
                        ThemeCustomSpacingRow(token: token, editor: session.editor) { pendingDeletion = token }
                        if token.id != theme.spacing.custom.last?.id { Divider() }
                    }
                }
            }
        }
        .confirmationDialog("Replace \(pendingDeletion?.name ?? "") with", isPresented: deletionPresented, titleVisibility: .visible) {
            ForEach(theme.spacing.choices.filter { $0.id != pendingDeletion?.name }) { choice in
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
