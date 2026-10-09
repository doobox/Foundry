import Foundation

nonisolated enum ColourPaletteDefaults {
    static func make(colors: ColorTokens) -> [ColourPalette] {
        let roles: [(String, String, String, Int)] = [
            ("primary", "Primary", colors.accent, 6),
            ("accent", "Accent", "#6366F1", 6),
            ("success", "Success", "#22C55E", 6),
            ("danger", "Danger", "#EF4444", 6),
            ("warning", "Warning", "#EAB308", 6),
            ("info", "Info", "#06B6D4", 6),
            ("inverse", "Inverse", colors.text, 10),
            ("secondary", "Secondary", "#64748B", 6),
            ("background", "Background", colors.surface, 0),
            ("foreground", "Foreground", colors.text, 10),
            ("border", "Border", "#94A3B8", 4)
        ]
        return roles.map { make(id: "framework." + $0.0, name: $0.1, hex: $0.2, origin: .framework, anchor: $0.3) } + standard
    }

    static let standard: [ColourPalette] = {
        let values = [("Black", "#000000"), ("White", "#FFFFFF"), ("Red", "#EF4444"),
            ("Orange", "#F97316"), ("Amber", "#F59E0B"), ("Yellow", "#EAB308"),
            ("Lime", "#84CC16"), ("Green", "#22C55E"), ("Emerald", "#10B981"),
            ("Teal", "#14B8A6"), ("Cyan", "#06B6D4"), ("Sky", "#0EA5E9"),
            ("Blue", "#3B82F6"), ("Indigo", "#6366F1"), ("Violet", "#8B5CF6"),
            ("Purple", "#A855F7"), ("Fuchsia", "#D946EF"), ("Pink", "#EC4899"),
            ("Rose", "#F43F5E"), ("Slate", "#64748B"), ("Grey", "#6B7280"),
            ("Zinc", "#71717A"), ("Neutral", "#737373"), ("Stone", "#78716C")]
        return values.map { make(id: "standard." + $0.0.lowercased(), name: $0.0, hex: $0.1,
                                 origin: .standard, anchor: 6, single: $0.0 == "Black" || $0.0 == "White") }
    }()

    private static func make(id: String, name: String, hex: String, origin: ColourPalette.Origin,
                             anchor: Int, single: Bool = false) -> ColourPalette {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        let channels = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)]
        let finalIndex = ColourShade.allCases.count - 1
        let shades = (0..<ColourShade.allCases.count).map { index -> String in
            if single || index == anchor { return hex }
            let light = index < anchor
            let fraction = light ? Double(anchor - index) / Double(max(anchor, 1)) * 0.94
                : Double(index - anchor) / Double(max(finalIndex - anchor, 1)) * 0.94
            let target = light ? 255.0 : 0.0
            let rgb = channels.map { Int(($0 + (target - $0) * fraction).rounded()) }
            return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
        }
        var result = try! ColourPalette(id: id, name: name, origin: origin, shades: shades,
            lightDefaultShade: ColourShade(rawValue: anchor + 1)!,
            generation: .init(algorithm: "bootstrap.runtime-scale.v1", anchor: ColourShade(rawValue: anchor + 1)!,
                              anchorHex: hex, softening: 0, reversed: false))
        result.single = single
        return result
    }
}
