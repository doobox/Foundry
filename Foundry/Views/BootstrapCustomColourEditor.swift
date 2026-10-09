import SwiftUI

struct BootstrapCustomColourEditor: View {
    let palette: PreviewColourPalette
    let update: (PreviewColourPalette, UUID) -> Void
    @State private var name = ""
    @State private var base = ""
    @State private var pendingScale: BootstrapColourScale?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Colour name", text: $name).onSubmit(saveName)
                TextField("500 base · oklch(L% C H)", text: $base).onSubmit(applyBase)
                    .frame(minWidth: 220)
                Button("Apply base", action: applyBase)
                    .disabled(BootstrapColourScale(base: base) == nil || pendingScale != nil)
            }.textFieldStyle(.roundedBorder)
                .disabled(pendingScale != nil)
            if palette.storedValue.bootstrapScale == nil {
                Text("Stored shades are preserved. Applying a 500 base replaces them with a Bootstrap scale.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear(perform: synchronize)
        .onChange(of: palette) { _, _ in synchronize() }
        .task(id: pendingScale) { await resolvePendingScale() }
    }

    private func synchronize() {
        name = palette.name
        base = palette.storedValue.bootstrapScale?.base ?? ""
        pendingScale = nil
        error = nil
    }

    private func saveName() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var edited = palette
        edited.name = name
        update(edited, UUID())
    }

    private func applyBase() {
        guard let scale = BootstrapColourScale(base: base) else {
            error = "Use oklch(L% C H): L 0–100, C 0–1, H 0–360."
            return
        }
        error = nil
        pendingScale = scale
    }

    private func resolvePendingScale() async {
        guard let scale = pendingScale else { return }
        do {
            let shades = try await BootstrapScalePreviewResolver().resolve(scale)
            try Task.checkCancellation()
            var stored = palette.storedValue
            try stored.setBootstrapScale(scale, previews: shades)
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { stored.name = name }
            update(PreviewColourPalette(stored: stored), UUID())
            pendingScale = nil
        } catch is CancellationError {
            // A newer edit, undo, or closed editor superseded this conversion.
        } catch {
            self.error = "Could not generate the Bootstrap colour preview. Please try again."
            pendingScale = nil
        }
    }
}
