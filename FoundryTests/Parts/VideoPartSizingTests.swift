import Foundation
import Testing
@testable import Foundry

struct VideoPartSizingTests {
    private var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Video")
    }

    @Test func usesSharedSizingAndDedicatedVideoSection() throws {
        let manifest = try PartPackageLoader.load(from: directory).manifest
        #expect(manifest.controlSections.first?.name == "Video")
        #expect(manifest.controlGroups.contains { $0.type == .sizing && $0.id == "sizing" })
        #expect(manifest.resolvedProperties.contains { $0.id == "maxWidth" || $0.id == "alignment" } == false)
        #expect(manifest.resolvedProperties.contains { $0.id == "sizing.heightMode" })
        #expect(manifest.controlGroups.contains { $0.type == .linkOverlay } == false)
        let css = try String(contentsOf: directory.appending(path: "Resources/part.css"), encoding: .utf8)
        #expect(css.contains("{{ control.sizing.css }}"))
        #expect(css.contains("control.maxWidth") == false)
        #expect(css.contains("object-fit: contain"))
        #expect(css.contains(":instance { overflow: hidden; }") == false)
    }

    @Test func sharedCustomDimensionsResolve() throws {
        let manifest = try PartPackageLoader.load(from: directory).manifest
        var values: [String: PartPackageValue] = [
            "sizing.widthMode": .string("custom"), "sizing.customWidth": .number(640),
            "sizing.heightMode": .string("custom"), "sizing.customHeight": .number(360)
        ]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: manifest.resolvedProperties)
        let css = try #require(values["sizing.css"]?.stringValue)
        #expect(css.contains("max-width: min(100%, 640px)"))
        #expect(css.contains("height: 360px"))
    }
}
