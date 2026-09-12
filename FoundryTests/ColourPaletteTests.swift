import Foundation
import Testing
@testable import Foundry

struct ColourPaletteTests {
    @Test func defaultReferencesFollowButExplicitShadesDoNot() throws {
        var palette = try ColourPalette(id: "theme.accent", name: "Accent", origin: .theme,
            shades: (1...11).map { String(format: "#%06X", $0) }, defaultShade: .six)
        let following = PaletteColourValue.palette(id: palette.id, selection: .default)
        let fixed = PaletteColourValue.palette(id: palette.id, selection: .shade(.six))
        #expect(following.resolve(in: [palette]) == fixed.resolve(in: [palette]))
        palette.name = "Renamed"
        palette.setDefault(.eleven)
        #expect(following.resolve(in: [palette]) == "#00000B")
        #expect(fixed.resolve(in: [palette]) == "#000006")
        #expect(following.resolve(in: []) == nil)
        #expect(PaletteColourValue.custom(hex: "#123456").resolve(in: []) == "#123456")
    }

    @Test func storageAndDuplicationPreserveResolvedColours() throws {
        let palette = try ColourPalette(id: "theme.accent", name: "Accent", origin: .theme,
            shades: Array(repeating: "#123456", count: 11), defaultShade: .six,
            generation: .init(algorithm: "foundry.rgb-soften.v1", anchor: .six,
                              anchorHex: "#123456", softening: 0.5, reversed: false))
        let restored = try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(palette))
        #expect(restored == palette)
        let duplicate = try palette.duplicated()
        #expect(duplicate.id != palette.id)
        #expect(duplicate.origin == .custom)
        #expect(duplicate.shades == palette.shades)
        #expect(duplicate.generation == palette.generation)
        #expect(duplicate.defaultShade == palette.defaultShade)
    }

    @Test func invalidShadePositionsAndCountsAreRejected() throws {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ColourShade.self, from: Data("12".utf8))
        }
        #expect(throws: (any Error).self) {
            try ColourPalette(id: "bad", name: "Bad", origin: .custom, shades: [], defaultShade: .one)
        }
    }
}
