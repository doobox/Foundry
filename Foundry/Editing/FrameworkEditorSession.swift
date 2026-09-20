import Foundation
import Observation

@MainActor
@Observable
final class FrameworkEditorSession {
    let document: FoundryDocument
    let editor: ProjectEditor
    private var colourEditSession: UUID?
    private var colourEditRevision: UInt64?

    var canEditFramework: Bool {
        !FrameworkLibrary.shared.frameworks.contains { $0.id == document.site.frameworkSourceID && $0.isBuiltIn }
    }

    func colourIsInUse(_ id: String) -> Bool {
        var probe = document.site
        probe.replacePartFrameworkReference(id, with: "foundry:usage-check")
        return probe != document.site
    }

    func deleteColour(_ id: String, replacement: String?) {
        guard document.site.framework.colourPalettes.contains(where: { $0.id == id && $0.origin == .custom }) else { return }
        if let replacement {
            guard replacement != id,
                  document.site.framework.colourPalettes.contains(where: { $0.id == replacement }) else { return }
        } else if colourIsInUse(id) { return }
        editor.mutate(actionName: "Delete Colour", impact: .framework) { site in
            if let replacement { site.replacePartFrameworkReference(id, with: replacement) }
            site.framework.colourPalettes.removeAll { $0.id == id }
            site.projectFrameworkValues.colours.removeAll { $0.id == id }
            for index in site.frameworkStates.indices {
                site.frameworkStates[index].framework.colourPalettes.removeAll { $0.id == id }
            }
        }
    }

    func setColourPalettes(_ palettes: [ColourPalette], session: UUID?) {
        guard document.site.framework.colourPalettes != palettes else { return }
        let coalescing = session != nil && session == colourEditSession
            && colourEditRevision == document.mutationEvent.revision
        let writer = ProjectEditor(document: document, undoManager: coalescing ? nil : editor.undoManager)
        writer.mutate(actionName: "Edit Colours", impact: .framework) { site in
            site.framework.colourPalettes = palettes
        }
        colourEditSession = session
        colourEditRevision = document.mutationEvent.revision
    }

    private(set) var previewReference: FrameworkFontReference?
    private(set) var previewFont: FrameworkFontDefinition?

    init(document: FoundryDocument, undoManager: UndoManager?) {
        self.document = document
        editor = ProjectEditor(document: document, undoManager: undoManager)
    }

    var hasUncommittedFontPreview: Bool {
        guard let previewReference, let previewFont else { return false }
        return storedFont(for: previewReference) != previewFont
    }

    func font(for reference: FrameworkFontReference) -> FrameworkFontDefinition {
        if previewReference == reference, let previewFont {
            return previewFont
        }
        return storedFont(for: reference)
    }

    func previewGoogleFont(_ family: String, for reference: FrameworkFontReference, configuration: GoogleFontConfiguration? = nil) {
        let normalizedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFamily.isEmpty,
              let stylesheetURL = FrameworkFontDefinition.googleStylesheetURL(for: normalizedFamily) else {
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

    func previewGoogleConfiguration(_ configuration: GoogleFontConfiguration, for reference: FrameworkFontReference) {
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
        editor.setFrameworkFontDefinition(
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

    private func storedFont(for reference: FrameworkFontReference) -> FrameworkFontDefinition {
        let typography = document.site.framework.typography
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
