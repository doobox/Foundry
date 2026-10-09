import SwiftUI

struct BootstrapCustomColourEditor: View {
    let palette: PreviewColourPalette
    let update: (PreviewColourPalette, UUID) -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @State private var name = ""
    @State private var pendingScale: BootstrapColourScale?
    @State private var lastApplied: ColourPalette?
    @State private var session = UUID()
    @State private var picker = BootstrapColourPicker()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Colour name", text: $name).onSubmit(saveName)
                .textFieldStyle(.roundedBorder)
            PreviewColourRibbon(palette: palette, duplicate: duplicate, delete: delete, editBase: openPicker)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { name = palette.name }
        .onChange(of: palette) { _, value in
            name = value.name
            if value.storedValue != lastApplied {
                pendingScale = nil
                picker.stop()
            }
        }
        .onDisappear { picker.stop() }
        .task(id: pendingScale) { await resolvePendingScale() }
    }

    private func saveName() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var edited = palette
        edited.name = name
        lastApplied = edited.storedValue
        update(edited, UUID())
    }

    private func openPicker() {
        session = UUID()
        picker.open(colour: NSColor(palette.colour(at: 6))) { colour in
            guard let scale = BootstrapColourScale.picked(colour) else { return }
            error = nil
            pendingScale = scale
        }
    }

    private func resolvePendingScale() async {
        guard let scale = pendingScale else { return }
        let editSession = session
        do {
            let shades = try await BootstrapScalePreviewResolver().resolve(scale)
            try Task.checkCancellation()
            guard pendingScale == scale, session == editSession else { return }
            var stored = palette.storedValue
            try stored.setBootstrapScale(scale, previews: shades)
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { stored.name = name }
            lastApplied = stored
            update(PreviewColourPalette(stored: stored), editSession)
        } catch is CancellationError {
            // A newer selection, undo, or closed editor superseded this conversion.
        } catch {
            guard !Task.isCancelled, pendingScale == scale else { return }
            self.error = "Could not generate the colour preview. Please choose the colour again."
        }
    }
}
