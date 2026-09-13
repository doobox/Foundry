import Foundation
import Testing
@testable import Foundry

struct GoogleFontConfigurationTests {
    @Test func fileSizeMeasurementDeduplicatesSharedURLs() throws {
        let css = """
        @font-face { src: url(https://fonts.gstatic.com/s/test/a.woff2) format('woff2'); }
        @font-face { src: url('https://fonts.gstatic.com/s/test/a.woff2'); }
        @font-face { src: url("https://fonts.gstatic.com/s/test/b.woff2"); }
        /* Non-font hosts are not downloaded. */
        x { background: url(https://example.com/image.png); }
        """
        #expect(try GoogleFontFileSize.fontURLs(in: css).map(\.lastPathComponent) == ["a.woff2", "b.woff2"])
        #expect(try GoogleFontFileSize.fontURLs(in: "").isEmpty)
    }

    @Test func specimensIncludeStaticFacesAndBoundedVariableSamples() {
        let faces: [GoogleFontFace] = [.init(italic: false, minimum: 700, maximum: 700), .init(italic: true, minimum: 500, maximum: 900)]
        let samples = GoogleFontSpecimenView.specimenFaces(faces)
        #expect(samples.map(\.minimum) == [700, 500, 900])
        #expect(samples.map(\.italic) == [false, true, true])
        #expect(samples.allSatisfy { !$0.isVariable })
    }

    @Test @MainActor func directSelectionAppliesWithoutRetainingDraftAndSupportsUndo() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        let session = ThemeEditorSession(document: document, undoManager: undo)
        let original = document.site.theme.typography.bodyFont
        let family = try GoogleFontsService.decodeFamilies(from: metadata)[0]
        session.editor.setThemeGoogleFont(family.family, reference: .role(.body), configuration: .init(available: family.faces, included: family.faces))
        #expect(document.site.theme.typography.bodyFont.family == family.family)
        #expect(!session.hasUncommittedFontPreview)
        undo.undo()
        #expect(document.site.theme.typography.bodyFont == original)
    }

    private var metadata: Data {
        Data("""
        {"familyMetadataList":[
          {"family":"Static","category":"SERIF","fonts":{"400":{},"700":{},"700i":{}},"axes":[]},
          {"family":"Variable","fonts":{"100":{},"900":{},"100i":{},"900i":{}},"axes":[{"tag":"wght","min":100,"max":900}]}
        ]}
        """.utf8)
    }

    @Test func decodesStaticFacesAndVariableRanges() throws {
        let families = try GoogleFontsService.decodeFamilies(from: metadata)
        #expect(families[0].faces == [.init(italic: false, minimum: 400, maximum: 400), .init(italic: false, minimum: 700, maximum: 700), .init(italic: true, minimum: 700, maximum: 700)])
        #expect(families[1].faces == [.init(italic: false, minimum: 100, maximum: 900), .init(italic: true, minimum: 100, maximum: 900)])
    }

    @Test func requestsOnlyIncludedFacesAndEscapesFamilyNames() throws {
        let family = try GoogleFontsService.decodeFamilies(from: metadata)[1]
        let config = GoogleFontConfiguration(available: family.faces, included: [.init(italic: true, minimum: 300, maximum: 650)])
        let url = try #require(config.stylesheetURL(family: "M PLUS+ One"))
        #expect(url.absoluteString.contains("%2B"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "family" }?.value == "M PLUS+ One:ital,wght@1,300..650")
        #expect(GoogleFontConfiguration(available: family.faces, included: []).stylesheetURL(family: family.family) == nil)
        let invalid = GoogleFontConfiguration(available: family.faces, included: [.init(italic: false, minimum: 50, maximum: 900)])
        #expect(invalid.validIncluded.isEmpty)
    }

    @Test @MainActor func configurationPersistsCommitsAndUndoes() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        let session = ThemeEditorSession(document: document, undoManager: undo)
        let original = document.site.theme.typography.bodyFont
        let family = try GoogleFontsService.decodeFamilies(from: metadata)[1]
        var config = GoogleFontConfiguration(available: family.faces, included: family.faces)
        session.previewGoogleFont(family.family, for: .role(.body), configuration: config)
        config.included = [.init(italic: true, minimum: 300, maximum: 650)]
        session.previewGoogleConfiguration(config, for: .role(.body))
        #expect(document.site.theme.typography.bodyFont == original)
        session.commitFontPreview()
        let theme = document.site.theme
        #expect(theme.typography.bodyFont.googleConfiguration == config)
        let restored = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
        #expect(restored.typography.bodyFont.googleConfiguration == config)
        let options = FontFaceOptions(reference: "body", theme: restored, assets: [:])
        #expect(options.verified)
        #expect(options.variableWeight)
        #expect(options.weights.first == 300)
        #expect(options.weights.last == 650)
        #expect(options.styles == ["italic"])
        #expect(restored.fontSourceCSS(assets: [:], destination: .export).contains("1,300..650"))
        undo.undo()
        #expect(document.site.theme.typography.bodyFont == original)
    }

    @Test func oldDefinitionsStillDecodeWithoutConfiguration() throws {
        let data = try JSONEncoder().encode(Theme.standard.typography.bodyFont)
        let decoded = try JSONDecoder().decode(ThemeFontDefinition.self, from: data)
        #expect(decoded.googleConfiguration == nil)
    }
}
