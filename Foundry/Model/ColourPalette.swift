import Foundation

/// A persisted theme palette, including resolved colours and optional editing settings.
nonisolated struct ColourPalette: Codable, Equatable, Identifiable, Sendable {
    enum Origin: String, Codable, Sendable { case theme, custom, standard }

    /// Stable across renames. Built-in IDs should be namespaced (e.g. theme.accent).
    let id: String
    var name: String
    let origin: Origin
    private(set) var shades: [String]
    private(set) var lightDefaultShade: ColourShade
    private(set) var darkDefaultShade: ColourShade
    var generation: Generation?
    var single = false

    struct Generation: Codable, Equatable, Sendable {
        /// A versioned identifier, not "latest". Existing shades never regenerate on load.
        var algorithm: String
        var anchor: ColourShade
        var anchorHex: String
        var softening: Double
        var reversed: Bool
        var enabled = true
        var overrides: [Int: String] = [:]
    }

    enum ValidationError: Error { case invalidShadeCount }

    init(id: String, name: String, origin: Origin, shades: [String],
         lightDefaultShade: ColourShade, darkDefaultShade: ColourShade? = nil, generation: Generation? = nil) throws {
        guard shades.count == 11 else { throw ValidationError.invalidShadeCount }
        self.id = id
        self.name = name
        self.origin = origin
        self.shades = shades
        self.lightDefaultShade = lightDefaultShade
        self.darkDefaultShade = darkDefaultShade ?? ColourShade(rawValue: 12 - lightDefaultShade.rawValue)!
        self.generation = generation
    }

    func colour(at selection: ColourShadeSelection) -> String {
        let shade: ColourShade
        switch selection {
        case .default: shade = lightDefaultShade
        case .shade(let value): shade = value
        }
        return shades[shade.rawValue - 1]
    }

    mutating func setLightDefault(_ shade: ColourShade) { lightDefaultShade = shade }
    mutating func setDarkDefault(_ shade: ColourShade) { darkDefaultShade = shade }
    func defaultShade(for appearance: SiteAppearance) -> ColourShade {
        appearance == .light ? lightDefaultShade : darkDefaultShade
    }

    mutating func replaceShades(_ values: [String]) throws {
        guard values.count == 11 else { throw ValidationError.invalidShadeCount }
        shades = values
    }

    func duplicated() throws -> Self {
        // Preserve resolved shades and settings exactly, but create a new identity.
        var copy = try Self(id: "custom.\(UUID().uuidString.lowercased())", name: name + " Copy",
                         origin: .custom, shades: shades, lightDefaultShade: lightDefaultShade, darkDefaultShade: darkDefaultShade, generation: generation)
        copy.single = single
        return copy
    }

    private enum CodingKeys: String, CodingKey { case id, name, origin, shades, lightDefaultShade, darkDefaultShade, generation, single }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let shades = try values.decode([String].self, forKey: .shades)
        guard shades.count == 11 else {
            throw DecodingError.dataCorruptedError(forKey: .shades, in: values,
                debugDescription: "A colour palette must contain exactly 11 resolved shades.")
        }
        try self.init(id: values.decode(String.self, forKey: .id),
                          name: try values.decode(String.self, forKey: .name),
                          origin: try values.decode(Origin.self, forKey: .origin),
                          shades: shades,
                          lightDefaultShade: try values.decode(ColourShade.self, forKey: .lightDefaultShade),
                          darkDefaultShade: try values.decode(ColourShade.self, forKey: .darkDefaultShade),
                          generation: try values.decodeIfPresent(Generation.self, forKey: .generation))
        single = try values.decodeIfPresent(Bool.self, forKey: .single) ?? false
    }

}

/// UI and stored references use the same one-based shade positions.
nonisolated enum ColourShade: Int, Codable, CaseIterable, Sendable {
    case one = 1, two, three, four, five, six, seven, eight, nine, ten, eleven
}

nonisolated enum ColourShadeSelection: Codable, Equatable, Sendable {
    case `default`
    case shade(ColourShade)
}

/// No generic "None": inherited/unset behaviour belongs to the surrounding property.
nonisolated enum PaletteColourValue: Codable, Equatable, Sendable {
    case palette(id: String, selection: ColourShadeSelection)
    case custom(hex: String)

    /// Missing references remain unresolved; never silently substitute another palette.
    func resolve(in palettes: [ColourPalette]) -> String? {
        switch self {
        case .custom(let hex): return hex
        case .palette(let id, let selection):
            return palettes.resolvedPalette(id: id)?.colour(at: selection)
        }
    }
}

nonisolated extension Array where Element == ColourPalette {
    /// Palette identity is explicit; matching display names never override a palette.
    func resolvedPalette(id: String) -> ColourPalette? {
        first { $0.id == id }
    }
}
