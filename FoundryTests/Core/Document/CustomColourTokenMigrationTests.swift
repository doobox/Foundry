import Foundation
import Testing
@testable import Foundry

struct CustomColourTokenMigrationTests {
    private let identity = "637573746f6d2e6d696e65"

    @Test(arguments: ["bg-body", "bg-1", "bg-4", "fg-body", "fg-2", "border-muted", "link-color", "link-hover-color"])
    func convertsKeysAndReferencesOnce(role: String) throws {
        let old = "custom-custom-\(identity)-\(role)"
        let current = "custom-\(identity)-\(role)"
        let data = try JSONEncoder().encode([
            old: "token:" + old,
            "css": "color:var(--bs-\(old))",
            "markup": "<span class=\"fd-fg--\(old)\">Mine</span>",
            "unrelated": "custom-custom-not-an-encoded-id-bg-1"
        ])
        let migrated = CustomColourTokenMigration.migrate(data)
        let values = try JSONDecoder().decode([String: String].self, from: migrated)
        #expect(values[current] == "token:" + current)
        #expect(values["css"] == "color:var(--bs-\(current))")
        #expect(values["markup"] == "<span class=\"fd-fg--\(current)\">Mine</span>")
        #expect(values["unrelated"] == "custom-custom-not-an-encoded-id-bg-1")
        #expect(CustomColourTokenMigration.migrate(migrated) == migrated)
        #expect(PartColourToken.parse("token:" + old) == nil)
        #expect(PartColourToken.parse("token:" + current)?.id == current)
    }

    @Test @MainActor
    func openingProjectPreservesEditedSwatchesAndSelections() throws {
        let current = "custom-\(identity)-bg-1"
        let old = "custom-custom-\(identity)-bg-1"
        var palette = try ColourPalette(id: "custom.mine", name: "mine", origin: .custom,
            shades: Array(repeating: "#123456", count: ColourShade.allCases.count), lightDefaultShade: .one)
        palette.customKind = .surface
        palette.bootstrapTokens[current] = .init(light: .native("black"), dark: .native("white"))
        #expect(palette.colourToken("bg-1") == current)
        #expect(PartColourToken.label(current, palettes: [palette]) == "bg-mine-1")
        var site = Site.starter()
        site.projectThemeValues.colours = [palette]
        site.theme.colourPalettes.append(palette)
        var part = PartNode(type: .container)
        part.setProperty(.init(rawValue: "background.backgroundTheme"), value: .choice("token:" + current))
        site.pages = [Page(title: "Home", slug: "index", parts: [part])]
        site.cssCode = ".mine { background: var(--bs-\(current)); }"
        let saved = String(decoding: try FoundryDocument.encoder.encode(site), as: UTF8.self)
            .replacingOccurrences(of: current, with: old)
        let opened = try FoundryDocument.decodeProject(from: Data(saved.utf8))
        #expect(opened.projectThemeValues.colours.first?.bootstrapTokens[current] == palette.bootstrapTokens[current])
        #expect(opened.pages[0].parts[0].property(.init(rawValue: "background.backgroundTheme")) == "token:" + current)
        #expect(opened.cssCode.contains("var(--bs-\(current))"))
        let resaved = String(decoding: try FoundryDocument.encoder.encode(opened), as: UTF8.self)
        #expect(resaved.contains("custom-custom-") == false)
    }
}
