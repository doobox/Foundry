import Foundation

/// The bundled stylesheet is authoritative. The JSON holds only browser-resolved
/// sRGB previews for native colour wells; web output keeps Bootstrap's live CSS.
nonisolated enum BootstrapColourCatalogue {
    static let hues = ["blue", "indigo", "violet", "purple", "pink", "red", "orange", "amber",
                       "yellow", "lime", "green", "teal", "cyan", "brown", "gray", "pewter"]
    static let themeRoles = ["primary", "accent", "success", "danger", "warning", "info", "inverse", "secondary"]
    static let themeProperties = ["base", "fg", "fg-emphasis", "bg", "bg-subtle", "bg-muted", "border", "focus-ring", "contrast"]
    static let sourceCSS = FoundryWebLibraryRegistry.canvasCSS(for: [])
    static let declarations: [String: String] = {
        let pattern = try! NSRegularExpression(pattern: #"(--bs-[\w-]+):([^;}]+)"#)
        var values: [String: String] = [:]
        for match in pattern.matches(in: sourceCSS, range: NSRange(sourceCSS.startIndex..., in: sourceCSS)) {
            let name = String(sourceCSS[Range(match.range(at: 1), in: sourceCSS)!])
            values[name] = String(sourceCSS[Range(match.range(at: 2), in: sourceCSS)!])
        }
        return values
    }()

    struct Previews: Decodable {
        let cssSHA256: String
        let palettes: [String: [String]]
    }

    static let previews: Previews = {
        guard let data = FoundryWebLibraryRegistry.resourceData(at: "bootstrap-color-previews.json"),
              let result = try? JSONDecoder().decode(Previews.self, from: data),
              hues.allSatisfy({ result.palettes[$0]?.count == ColourShade.allCases.count }) else {
            preconditionFailure("The bundled Bootstrap colour preview catalogue is missing or incomplete")
        }
        return result
    }()

    static func defaultHue(for role: String) -> String {
        switch role {
        case "primary": "blue"
        case "accent": "indigo"
        case "success": "green"
        case "danger": "red"
        case "warning": "yellow"
        case "info": "cyan"
        default: "gray"
        }
    }

    static func tokens(for role: String) -> [String] {
        switch role {
        case "background": ["bg-body", "bg-1", "bg-2", "bg-3", "bg-4"]
        case "foreground": ["fg-body", "fg-1", "fg-2", "fg-3", "fg-4"]
        case "border": ["border-body", "border-subtle", "border-muted", "border-emphasized"]
        default: themeProperties.map { role + "-" + $0 }
        }
    }

    static func palette(role: ThemePaletteColorRole, hue: String? = nil) -> ColourPalette {
        let hue = hue ?? defaultHue(for: role.rawValue)
        precondition(hues.contains(hue))
        let defaults: (ColourShade, ColourShade) = switch role {
        case .inverse, .foreground: (.eleven, .two)
        case .secondary: (.four, .eight)
        case .background: (.one, .thirteen)
        case .border: (.five, .ten)
        default: (.seven, .seven)
        }
        var palette = try! ColourPalette(id: "framework." + role.rawValue, name: role.title, origin: .theme,
            shades: previews.palettes[hue]!, lightDefaultShade: defaults.0, darkDefaultShade: defaults.1)
        palette.bootstrapHue = hue
        return palette
    }

    static func reference(hue: String, shade: ColourShade) -> String {
        if hue == "white" || hue == "black" { return "var(--bs-\(hue))" }
        return "var(--bs-\(hue)-\(shade.bootstrapLabel))"
    }
}
