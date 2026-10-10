import SwiftUI

struct BootstrapTokenColoursCard: View {
    let section: BootstrapEditorSection
    let framework: Framework
    let editor: ProjectEditor
    var mode: SiteAppearance = .light
    var model: FrameworkColourPreviewModel? = nil
    var customPreviews: [String: String] = [:]
    var requestDelete: ((PreviewColourPalette) -> Void)? = nil
    var addCustom: (() -> Void)? = nil
    @State private var previews: [String: String] = [:]
    @State private var picker = BootstrapColourPicker()
    @State private var error: String?

    private var css: String {
        BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(framework: framework, mode: .both) + BootstrapThemeCSS.render(framework: framework)
    }

    var body: some View {
        FrameworkEditorCard {
            HStack {
                Text("Bootstrap \(section.title)").font(.headline).accessibilityAddTraits(.isHeader)
                if let addCustom {
                    Button("Add custom colour", systemImage: "plus", action: addCustom)
                        .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 24, height: 24)
                }
                Spacer()
                if framework.bootstrapTokens.isChanged(section) {
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
                    BootstrapColourSourcePicker(section: section, framework: framework) { expression in
                        picker.stop()
                        editor.setBootstrapColourGroup(section, base: expression)
                    }
                    .frame(width: 150)
                }
            }
            HStack(spacing: 0) {
                ForEach(section.tokens) { token in
                    Button { open(token) } label: {
                        VStack(spacing: 4) {
                            Rectangle().fill(Color(hex: previews[token.id] ?? "") ?? .clear)
                                .frame(height: 34)
                                .clipShape(UnevenRoundedRectangle(
                                    topLeadingRadius: token.id == section.tokens.first?.id ? 6 : 0,
                                    bottomLeadingRadius: token.id == section.tokens.first?.id ? 6 : 0,
                                    bottomTrailingRadius: token.id == section.tokens.last?.id ? 6 : 0,
                                    topTrailingRadius: token.id == section.tokens.last?.id ? 6 : 0))
                            Text(token.label).font(.caption2).lineLimit(1)
                            Image(systemName: framework.bootstrapTokens.values[token.id] == nil ? "circle" : "pencil.circle.fill")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(previews[token.id] == nil)
                    .accessibilityLabel("Edit \(token.label) colour")
                    .help("--bs-\(token.id). Click to edit this colour.")
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
            if let model {
                ForEach(model.palettes.filter { $0.storedValue.origin == .custom && $0.storedValue.colourKind == .link }) { palette in
                    Divider()
                    BootstrapThemeTokenEditor(model: model, palette: palette, mode: mode, previews: customPreviews,
                        canEdit: true, delete: { requestDelete?(palette) })
                }
            }
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
                expressions: section.tokens.map { framework.bootstrapTokens.value($0) },
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
