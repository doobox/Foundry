import Foundation
import Testing
@testable import Foundry

struct ColumnsPartTests {
    private func package() throws -> LoadedPartPackage {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: root.appending(path:
            "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Columns"))
        try package.preparePayload()
        return package
    }

    private func css(layout: String, stacked: Bool, reversed: Bool) throws -> String {
        let package = try package()
        var values = Dictionary(uniqueKeysWithValues: package.manifest.resolvedProperties.map { ($0.id, $0.defaultValue) })
        values["columnLayout"] = .string(layout)
        values["stacked"] = .boolean(stacked)
        values["reversed"] = .boolean(reversed)
        PartPackageControlGroupCSSResolver.resolve(&values, properties: package.manifest.resolvedProperties)
        return PartTemplateRenderer.render(package.css, context: .init(
            instanceID: UUID(), packageIdentifier: package.manifest.identifier, properties: values, slots: [:]))
    }

    @Test
    func builtInColumnsValidatesWithFourColumnDropZones() throws {
        let package = try package()
        let diagnostics = PartPackageValidator.validate(package.manifest, rootURL: package.rootURL.appending(path: "Resources"))
        #expect(diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(package.manifest.identifier == "foundry.layout.columns")
        #expect(package.dropZoneNames == ["column1", "column2", "column3", "column4"])
        let reversed = try #require(package.manifest.resolvedProperties.first { $0.id == "reversed" })
        #expect(reversed.defaultValue == .boolean(false))
        #expect(reversed.responsive)
    }

    @Test
    func reverseOrderMirrorsBothOrderAndWidths() throws {
        let normal = try css(layout: "33-67", stacked: false, reversed: false)
        #expect(normal.contains("grid-template-columns: minmax(0, 1fr) minmax(0, 2fr);"))
        #expect(normal.contains("nth-child(1) { order: 0; }"))

        // The wide column keeps its width when it moves to the other side.
        let reversed = try css(layout: "33-67", stacked: false, reversed: true)
        #expect(reversed.contains("grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);"))
        #expect(reversed.contains("nth-child(1) { order: 4; }"))
        #expect(reversed.contains("nth-child(2) { order: 3; }"))

        // Stacked columns reverse too, which puts the last column on top.
        let stacked = try css(layout: "33-67", stacked: true, reversed: true)
        #expect(stacked.contains("grid-template-columns: minmax(0, 1fr);"))
        #expect(stacked.contains("nth-child(1) { order: 4; }"))
    }
}
