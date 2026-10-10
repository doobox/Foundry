import SwiftUI

struct BootstrapThemeColourPicker: View {
    @Bindable var model: ThemeColourPreviewModel
    let palette: PreviewColourPalette
    let canEdit: Bool
    @Environment(\.undoManager) private var undoManager
    @State private var picker = BootstrapColourPicker()
    @State private var pendingScale: BootstrapColourScale?
    @State private var lastApplied: ColourPalette?
    @State private var session = UUID()
    @State private var confirmsReplacement = false
    @State private var error: String?

    var body: some View {
        Button(action: requestPicker) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.colour(at: 6)).frame(width: 22, height: 18)
                Text("Customise…")
            }
        }
        .disabled(!canEdit)
        .accessibilityLabel("Customise \(palette.name) from one colour")
        .help("Choose a 500 base colour to regenerate this group's shades for both light and dark modes")
        .confirmationDialog("Replace manual token edits?", isPresented: $confirmsReplacement, titleVisibility: .visible) {
            Button("Choose Colour and Regenerate", action: openPicker)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choosing a new base colour replaces this group's individual token edits in both modes. Opening the picker alone makes no changes. You can undo the generated change.")
        }
        .alert("Could not generate theme", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .task(id: pendingScale) { await generate() }
        .onChange(of: palette.storedValue) { _, value in
            if value != lastApplied { stop() }
        }
        .onChange(of: canEdit) { if !canEdit { stop() } }
        .onDisappear(perform: stop)
    }

    private func requestPicker() {
        guard canEdit else { return }
        if palette.storedValue.bootstrapTokens.isEmpty { openPicker() }
        else { confirmsReplacement = true }
    }

    private func openPicker() {
        guard canEdit else { return }
        session = UUID()
        pendingScale = nil
        picker.open(colour: NSColor(palette.colour(at: 6))) { colour in
            pendingScale = BootstrapColourScale.picked(colour)
        }
    }

    private func stop() {
        pendingScale = nil
        session = UUID()
        picker.stop()
    }

    private func generate() async {
        guard let scale = pendingScale,
              let role = ThemePaletteColorRole(rawValue: BootstrapPaletteTheme.definitionRole(palette.storedValue)) else { return }
        let editSession = session
        let original = model.storedPalettes.first { $0.id == palette.id }
        do {
            let native = try await BootstrapThemeGenerator.generate(role: role, scale: scale)
            let generated = BootstrapPaletteTheme.applying(native, to: palette.storedValue)
            try Task.checkCancellation()
            guard canEdit, pendingScale == scale, session == editSession,
                  model.storedPalettes.first(where: { $0.id == palette.id }) == original else { return }
            lastApplied = generated
            model.update(PreviewColourPalette(stored: generated), session: editSession, undoManager: undoManager)
        } catch is CancellationError {
            // A newer pick, external edit, undo or closed editor superseded this result.
        } catch {
            guard !Task.isCancelled, session == editSession else { return }
            self.error = "Your previous colours are unchanged. Please choose the colour again."
        }
    }
}
