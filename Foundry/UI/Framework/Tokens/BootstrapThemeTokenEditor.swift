import SwiftUI

/// The swatches are Bootstrap roles, not a second colour-scale system.
struct BootstrapThemeTokenEditor: View {
    @Bindable var model: FrameworkColourPreviewModel
    let palette: PreviewColourPalette
    let mode: SiteAppearance
    let previews: [String: String]
    let canEdit: Bool
    var delete: (() -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @State private var picker = BootstrapColourPicker()
    @State private var lastApplied: ColourPalette?
    @State private var renaming = false
    @State private var editedName = ""

    private var role: String { BootstrapPaletteTheme.nativeRole(palette.storedValue) ?? BootstrapPaletteTheme.definitionRole(palette.storedValue) }
    private var isTheme: Bool { BootstrapPaletteTheme.nativeRole(palette.storedValue) != nil }
    private var tokens: [String] { palette.storedValue.colourTokens }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(palette.name).font(.headline)
                if palette.storedValue.origin == .custom {
                    Button("Rename colour", systemImage: "pencil") {
                        editedName = palette.name
                        renaming = true
                    }.labelStyle(.iconOnly).disabled(!canEdit)
                }
                Spacer()
                BootstrapThemeColourPicker(model: model, palette: palette, canEdit: canEdit)
                BootstrapHuePicker(palette: palette, canEdit: canEdit, select: selectHue)
                    .labelsHidden().frame(width: 130)
                    .help("Change the underlying scale for this whole group. Explicit token edits are retained.")
                if let delete {
                    Button("Delete colour", systemImage: "trash", action: delete)
                        .labelStyle(.iconOnly).disabled(!canEdit)
                }
            }
            ColourSwatchStrip(swatches: tokens.map { token in
                ColourSwatchStrip.Swatch(
                    id: token,
                    label: label(token),
                    hex: previews[token],
                    isEnabled: canEdit,
                    accessibilityLabel: "Edit \(palette.name) \(label(token)), \(mode.rawValue) mode",
                    help: "\(token) · \(mode.rawValue) mode. Edit this token independently.")
            }) { open(token: $0.id) }
        }
        .padding(.vertical, 8)
        .onChange(of: palette.storedValue) { _, value in
            if value != lastApplied { picker.stop() }
        }
        .onChange(of: mode) { picker.stop() }
        .onDisappear { picker.stop() }
        .sheet(isPresented: $renaming) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename custom colour").font(.headline)
                TextField("Colour name", text: $editedName)
                Text("Use a unique lowercase name with letters, numbers and hyphens, starting with a letter. Bootstrap names are reserved. Existing part selections are preserved. Update any hand-written CSS or HTML that uses the old name.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = false }.keyboardShortcut(.cancelAction)
                    Button("Rename") {
                        model.renameTheme(id: palette.id, name: editedName, undoManager: undoManager)
                        renaming = false
                    }
                    .disabled(!canEdit || !model.canAddTheme(named: editedName, excluding: palette.id))
                    .keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 400)
        }
    }

    private func label(_ token: String) -> String {
        if palette.storedValue.origin == .custom, palette.storedValue.colourKind != .theme {
            let source = String(token.dropFirst(palette.storedValue.customTokenPrefix.count))
            if palette.storedValue.colourKind == .link { return source == "link-color" ? "Link" : "Link hover" }
            return source
        }
        return isTheme ? String(token.dropFirst(role.count + 1)) : token
    }

    private func open(token: String) {
        guard canEdit, let hex = previews[token], let color = Color(hex: hex) else { return }
        let session = UUID()
        picker.open(colour: NSColor(color)) { color in
            guard let value = BootstrapColourScale.picked(color),
                  var current = model.storedPalettes.first(where: { $0.id == palette.id }) else { return }
            var override = current.bootstrapTokens[token] ?? BootstrapTokenColour()
            if mode == .light { override.light = value } else { override.dark = value }
            current.bootstrapTokens[token] = override
            lastApplied = current
            model.update(PreviewColourPalette(stored: current), session: session, undoManager: undoManager)
        }
    }

    private func selectHue(_ hue: String) {
        guard let sourceRole = FrameworkColorRole(rawValue: BootstrapPaletteTheme.definitionRole(palette.storedValue)) else { return }
        var selected = BootstrapPaletteTheme.applying(BootstrapColourCatalogue.palette(role: sourceRole, hue: hue), to: palette.storedValue)
        selected.bootstrapTokens = palette.storedValue.bootstrapTokens
        model.update(PreviewColourPalette(stored: selected), session: UUID(), undoManager: undoManager)
    }

}
