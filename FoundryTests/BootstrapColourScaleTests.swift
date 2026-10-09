import AppKit
import SwiftUI
import Testing
@testable import Foundry

@MainActor
struct BootstrapColourScaleTests {
    @Test(.timeLimit(.minutes(1)), arguments: BootstrapColourCatalogue.hues)
    func nativeCopiesMatchEveryBootstrapStop(hue: String) async throws {
        let scale = try #require(BootstrapColourScale.native(hue))
        for shade in ColourShade.allCases {
            #expect(scale.expression(at: shade) == BootstrapColourCatalogue.declarations["--bs-\(hue)-\(shade.bootstrapLabel)"])
        }
        let previews = try await BootstrapScalePreviewResolver().resolve(scale)
        #expect(previews == BootstrapColourCatalogue.previews.palettes[hue])
        let native = try #require(ColourPaletteDefaults.standard.first { $0.bootstrapHue == hue })
        let copy = try native.duplicated()
        #expect(copy.bootstrapHue == nil)
        #expect(copy.bootstrapScale == scale)
        #expect(copy.shades == previews)
        #expect(copy.generation == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func customBaseStorageOutputOpacityAndUndoUseOneDefinition() async throws {
        let scale = try #require(BootstrapColourScale(base: "oklch(58.125% 0.213456 252.75)"))
        let shades = try await BootstrapScalePreviewResolver().resolve(scale)
        let model = FrameworkColourPreviewModel()
        model.add()
        let original = try #require(model.storedPalettes.first)
        var edited = original
        try edited.setBootstrapScale(scale, previews: shades)
        edited.name = "Brand"
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.update(PreviewColourPalette(stored: edited), session: UUID(), undoManager: undo)
        undo.endUndoGrouping()
        #expect(model.storedPalettes[0] == edited)
        undo.undo()
        #expect(model.storedPalettes[0] == original)
        undo.redo()
        #expect(model.storedPalettes[0] == edited)
        let restored = try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(edited))
        #expect(restored == edited)
        #expect(restored.bootstrapScale?.base == "oklch(58.125% 0.213456 252.75)")
        #expect(restored.lightDefaultShade == .seven)
        #expect(restored.darkDefaultShade == .seven)
        var framework = Framework.standard
        framework.colourPalettes.insert(restored, at: 0)
        let selected = PartPackageColorValue(source: restored.id, customColor: "#000000", opacity: 0.5,
                                            shade: .three, darkShade: .eleven)
        #expect(PartPackageColorResolver.resolve(selected, framework: framework, opacity: false) == scale.expression(at: .three))
        #expect(PartPackageColorResolver.resolve(selected, framework: framework, opacity: true) ==
            "color-mix(in oklch, \(scale.expression(at: .three)) 50%, transparent)")
        #expect(PartPackageColorResolver.resolve(selected, framework: framework, opacity: false, appearance: .dark) == scale.expression(at: .eleven))
        #expect(PreviewColourPalette(stored: restored).storedValue == restored)
        let reference = RichTextColourReference(source: restored.id, lightShade: .three, darkShade: .eleven)
        let rich = FoundryRichTextCodec.resolvingColours(in: "<span data-foundry-color=\"\(reference.marker)\">Brand</span>",
            context: .init(palettes: framework.colourPalettes, mode: .both))
        #expect(rich.contains("light-dark(\(scale.expression(at: .three)), \(scale.expression(at: .eleven)))"))
        var page = Page(title: "Custom scale", slug: "index")
        page.backgroundOverride = selected
        var site = Site(name: "Custom scale", pages: [page])
        site.framework = framework
        site.appearanceMode = .both
        let exported = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(exported.contains("background-color: light-dark(\(scale.expression(at: .three)), \(scale.expression(at: .eleven)))"))
        let canvas = HTMLPageRenderer(appearance: .dark).render(page: page, framework: framework)
        #expect(canvas.contains("background: \(scale.expression(at: .eleven))"))
    }

    @Test func namesDuplicationAndDeletedBindingsPreserveScales() throws {
        let model = FrameworkColourPreviewModel()
        let native = try #require(model.palettes.first { $0.name == "Blue" })
        model.duplicate(native)
        var copy = try #require(model.palettes.first)
        let scale = copy.storedValue.bootstrapScale
        copy.name = "My blue"
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.update(copy, session: UUID(), undoManager: undo)
        undo.endUndoGrouping()
        #expect(model.storedPalettes[0].bootstrapScale == scale)
        let binding = model.binding(for: copy)
        model.delete(id: copy.id)
        binding.wrappedValue = copy
        #expect(model.palettes.contains { $0.id == copy.id } == false)
        #expect(model.palettes.contains { $0.id == native.id })
    }

    @Test func legacyShadesDoNotRegenerateUntilExplicitlyConverted() throws {
        let legacy = try ColourPalette(id: "custom.legacy", name: "Saved", origin: .custom,
            shades: Array(repeating: "#123456", count: 13), lightDefaultShade: .three,
            generation: .init(algorithm: "foundry.rgb-soften.v1", anchor: .three, anchorHex: "#123456", softening: 0.5, reversed: true))
        var displayed = PreviewColourPalette(stored: legacy)
        displayed.name = "Renamed"
        #expect(displayed.storedValue.shades == legacy.shades)
        #expect(displayed.storedValue.generation == legacy.generation)
        #expect(displayed.storedValue.bootstrapScale == nil)
        #expect(displayed.storedValue.cssColour(at: .seven) == "#123456")
    }

    @Test(arguments: ["", "#123456", "oklch(101% .2 240)", "oklch(50% -1 20)",
                      "oklch(50% .2 361)", "oklch(50% .2 20);color:red", "oklch(NaN% 0 0)"])
    func invalidBasesAreRejected(base: String) {
        #expect(BootstrapColourScale(base: base) == nil)
    }
}
