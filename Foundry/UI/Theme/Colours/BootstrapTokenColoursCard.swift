import SwiftUI

struct BootstrapTokenColoursCard: View {
    let section: BootstrapEditorSection
    let theme: Theme
    let editor: ProjectEditor
    var mode: SiteAppearance = .light
    @State private var previews: [String: String] = [:]
    @State private var picker = BootstrapColourPicker()
    @State private var error: String?

    private var css: String {
        BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(theme: theme, mode: .both) + BootstrapThemeCSS.render(theme: theme)
    }

    var body: some View {
        ThemeEditorCard {
            HStack {
                Text("Bootstrap \(section.title)").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if theme.bootstrapTokens.isChanged(section) {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        picker.stop()
                        editor.resetBootstrapTokens(section)
                    }
                    .help("Restore this section's Bootstrap colours. Other settings are kept.")
                }
            }
            HStack {
                Text("Default").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if section == .linkColours || section == .shadowColours {
                    Button {
                        if let token = section.tokens.first { open(token, wholeGroup: true) }
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: previews[section.tokens[0].id] ?? "") ?? .clear)
                                .frame(width: 22, height: 18)
                            Text("Customise…")
                        }
                    }
                    .disabled(previews[section.tokens[0].id] == nil)
                    .help(section == .linkColours ? "Choose a base colour and regenerate hover. Replaces individual link colour edits." : "Choose a shadow colour.")
                    BootstrapColourSourcePicker(section: section, theme: theme) { expression in
                        picker.stop()
                        editor.setBootstrapColourGroup(section, base: expression)
                    }
                    .frame(width: 150)
                }
            }
            ColourSwatchStrip(swatches: section.tokens.map { token in
                ColourSwatchStrip.Swatch(
                    id: token.id,
                    label: token.label,
                    hex: previews[token.id],
                    accessibilityLabel: "Edit \(token.label) colour",
                    help: "--bs-\(token.id). Click to edit this colour.")
            }) { swatch in
                if let token = section.tokens.first(where: { $0.id == swatch.id }) { open(token) }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
        }
        .task(id: css + mode.rawValue) { await resolvePreviews() }
        .onChange(of: mode) { picker.stop() }
        .onDisappear { picker.stop() }
    }

    private func open(_ token: BootstrapEditorToken, wholeGroup: Bool = false) {
        guard let hex = previews[token.id], let colour = Color(hex: hex) else { return }
        picker.open(colour: NSColor(colour)) { picked in
            guard let scale = BootstrapColourScale.picked(picked) else { return }
            if wholeGroup { editor.setBootstrapColourGroup(section, base: scale.base) }
            else { editor.setBootstrapToken(token, value: scale.base) }
        }
    }

    private func resolvePreviews() async {
        do {
            let colours = try await BootstrapScalePreviewResolver().resolve(
                expressions: section.tokens.map { theme.bootstrapTokens.value($0) },
                css: css, mode: mode.rawValue)
            try Task.checkCancellation()
            previews = Dictionary(uniqueKeysWithValues: zip(section.tokens.map(\.id), colours))
            error = nil
        } catch is CancellationError {
            return
        } catch {
            previews = [:]
            self.error = "Could not load colour previews. Reopen Colours to retry."
        }
    }
}
