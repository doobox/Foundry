import Foundation
import Testing
@testable import Foundry

struct ColourPaletteTests {
    @Test func twoDefaultsSurviveDuplicationAndStorage() throws {
        var palette = Framework.standard.colourPalettes[0]
        palette.setLightDefault(.two)
        palette.setDarkDefault(.nine)
        let duplicate = try palette.duplicated()
        let restored = try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(duplicate))
        #expect(restored.lightDefaultShade == .two)
        #expect(restored.darkDefaultShade == .nine)
        #expect(restored.shades == palette.shades)
    }

    @Test func matchingNamesNeverOverrideOriginalReferences() throws {
        for original in [Framework.standard.colourPalettes[0], ColourPaletteDefaults.standard[2]] {
            var custom = try original.duplicated()
            #expect(custom.name == original.name + " Copy")
            custom.name = original.name
            try custom.replaceShades((1...ColourShade.allCases.count).map { String(format: "#1234%02X", $0) })
            custom.setLightDefault(.four)
            let following = PaletteColourValue.palette(id: original.id, selection: .default)
            let fixed = PaletteColourValue.palette(id: original.id, selection: .shade(.eight))
            #expect(following.resolve(in: [custom, original]) == original.colour(at: .default))
            #expect(fixed.resolve(in: [custom, original]) == original.colour(at: .shade(.eight)))
            #expect(PaletteColourValue.palette(id: custom.id, selection: .shade(.eight)).resolve(in: [custom, original]) == "#123408")
            #expect(following.resolve(in: [original]) == original.colour(at: .default))
            custom.name += " Different"
            #expect(following.resolve(in: [custom, original]) == original.colour(at: .default))
        }
    }

    @Test func primaryIsTheFirstFixedRoleAndCustomColoursRemainIndependent() throws {
        var framework = Framework.standard
        #expect(FrameworkColorRole.allCases.first == .primary)
        #expect(framework.colourPalettes.first?.id == "framework.primary")
        let original = try #require(framework.colourPalettes.first)
        var custom = try original.duplicated()
        try custom.replaceShades(Array(repeating: "#ABCDEF", count: ColourShade.allCases.count))
        framework.colourPalettes.insert(custom, at: 0)
        #expect(framework.color(for: .primary) == original.colour(at: .default))
        #expect(framework.fixedFrameworkColourPalettes.first == original)
    }
    @Test func defaultReferencesFollowButExplicitShadesDoNot() throws {
        var palette = try ColourPalette(id: "framework.accent", name: "Accent", origin: .framework,
            shades: (1...ColourShade.allCases.count).map { String(format: "#%06X", $0) }, lightDefaultShade: .six)
        let following = PaletteColourValue.palette(id: palette.id, selection: .default)
        let fixed = PaletteColourValue.palette(id: palette.id, selection: .shade(.six))
        #expect(following.resolve(in: [palette]) == fixed.resolve(in: [palette]))
        palette.name = "Renamed"
        palette.setLightDefault(.eleven)
        #expect(following.resolve(in: [palette]) == "#00000B")
        #expect(fixed.resolve(in: [palette]) == "#000006")
        #expect(following.resolve(in: []) == nil)
        #expect(PaletteColourValue.custom(hex: "#123456").resolve(in: []) == "#123456")
    }

    @Test func storageAndDuplicationPreserveResolvedColours() throws {
        let palette = try ColourPalette(id: "framework.accent", name: "Accent", origin: .framework,
            shades: Array(repeating: "#123456", count: ColourShade.allCases.count), lightDefaultShade: .six,
            generation: .init(algorithm: "foundry.rgb-soften.v1", anchor: .six,
                              anchorHex: "#123456", softening: 0.5, reversed: false))
        let restored = try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(palette))
        #expect(restored == palette)
        let duplicate = try palette.duplicated()
        #expect(duplicate.id != palette.id)
        #expect(duplicate.origin == .custom)
        #expect(duplicate.shades == palette.shades)
        #expect(duplicate.generation == palette.generation)
        #expect(duplicate.lightDefaultShade == palette.lightDefaultShade)
    }

    @Test func invalidShadePositionsAndCountsAreRejected() throws {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ColourShade.self, from: Data("14".utf8))
        }
        #expect(throws: (any Error).self) {
            try ColourPalette(id: "bad", name: "Bad", origin: .custom, shades: [], lightDefaultShade: .one)
        }
    }
}
