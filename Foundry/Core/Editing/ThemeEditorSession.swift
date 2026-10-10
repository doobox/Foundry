import Foundation
import Observation

@MainActor
@Observable
final class ThemeEditorSession {
    let document: FoundryDocument
    let editor: ProjectEditor
    private var colourEditSession: UUID?
    private var colourEditRevision: UInt64?

    var canEditTheme: Bool {
        // Edits belong to this project, never to the installed theme bundle.
        true
    }

    func colourIsInUse(_ id: String) -> Bool {
        var probe = document.site
        probe.replacePartThemeReference(id, with: "foundry:usage-check")
        if let palette = document.site.theme.colourPalettes.first(where: { $0.id == id && $0.colourKind != .theme }) {
            for token in palette.colourTokens { probe.replacePartThemeReference("token:" + token, with: "foundry:usage-check") }
        }
        return probe != document.site
    }

    func deleteColour(_ id: String, replacement: String?) {
        guard let palette = document.site.theme.colourPalettes.first(where: { $0.id == id && $0.origin == .custom }) else { return }
        if let replacement {
            guard replacement != id,
                  replacement == "inherit" || document.site.theme.colourPalettes.contains(where: { $0.id == replacement && $0.colourKind == palette.colourKind }) else { return }
        } else if colourIsInUse(id) { return }
        editor.mutate(actionName: "Delete Colour", impact: .theme) { site in
            if let replacement { site.replacePartThemeReference(id, with: replacement) }
            if palette.colourKind != .theme, let replacement {
                let tokens = site.theme.colourPalettes.first(where: { $0.id == replacement })?.colourTokens ?? []
                for (index, token) in palette.colourTokens.enumerated() {
                    site.replacePartThemeReference("token:" + token, with: tokens.indices.contains(index) ? "token:" + tokens[index] : "inherit")
                }
            }
            site.theme.colourPalettes.removeAll { $0.id == id }
            site.projectThemeValues.colours.removeAll { $0.id == id }
            for index in site.themeStates.indices {
                site.themeStates[index].theme.colourPalettes.removeAll { $0.id == id }
            }
        }
    }

    func setColourPalettes(_ palettes: [ColourPalette], session: UUID?) {
        guard document.site.theme.colourPalettes != palettes else { return }
        let coalescing = session != nil && session == colourEditSession
            && colourEditRevision == document.mutationEvent.revision
        let writer = ProjectEditor(document: document, undoManager: coalescing ? nil : editor.undoManager)
        writer.mutate(actionName: "Edit Colours", impact: .theme) { site in
            site.theme.colourPalettes = palettes
        }
        colourEditSession = session
        colourEditRevision = document.mutationEvent.revision
    }

    private(set) var previewReference: ThemeFontReference?
    private(set) var previewFont: ThemeFontDefinition?

    init(document: FoundryDocument, undoManager: UndoManager?) {
        self.document = document
        editor = ProjectEditor(document: document, undoManager: undoManager)
        if document.site.hasNamedThemeOverrides {
            ProjectEditor(document: document, undoManager: nil).mutate(actionName: "Convert Theme Colours", impact: .theme) {
                $0.foldNamedThemeOverrides()
            }
        }
    }

    var hasUncommittedFontPreview: Bool {
        guard let previewReference, let previewFont else { return false }
        return storedFont(for: previewReference) != previewFont
    }

    func font(for reference: ThemeFontReference) -> ThemeFontDefinition {
        if previewReference == reference, let previewFont {
            return previewFont
        }
        return storedFont(for: reference)
    }

    func previewGoogleFont(_ family: String, for reference: ThemeFontReference, configuration: GoogleFontConfiguration? = nil) {
        let normalizedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFamily.isEmpty,
              let stylesheetURL = ThemeFontDefinition.googleStylesheetURL(for: normalizedFamily) else {
            return
        }
        var font = storedFont(for: reference)
        font.family = normalizedFamily
        font.source = .remote(stylesheetURL: stylesheetURL)
        font.googleConfiguration = nil
        if let configuration { font.applyGoogleConfiguration(configuration) }
        previewReference = reference
        previewFont = font
    }

    func previewGoogleConfiguration(_ configuration: GoogleFontConfiguration, for reference: ThemeFontReference) {
        guard !configuration.validIncluded.isEmpty else { return }
        var font = self.font(for: reference)
        font.applyGoogleConfiguration(configuration)
        previewReference = reference
        previewFont = font
    }

    func commitFontPreview() {
        guard let previewReference, let previewFont, hasUncommittedFontPreview else {
            discardFontPreview()
            return
        }
        editor.setThemeFontDefinition(
            previewFont,
            reference: previewReference,
            actionName: "Choose Google Font"
        )
        discardFontPreview()
    }

    func discardFontPreview() {
        previewReference = nil
        previewFont = nil
    }

    private func storedFont(for reference: ThemeFontReference) -> ThemeFontDefinition {
        let typography = document.site.theme.typography
        return switch reference {
        case .role(.body): typography.bodyFont
        case .role(.heading): typography.headingFont
        case .role(.monospaced): typography.monospacedFont
        case .custom(let id):
            typography.customFonts.first(where: { $0.id == id })?.font
                ?? .system(family: "system-ui", weights: [400])
        }
    }
}
