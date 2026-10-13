import Foundation

/// Edited Bootstrap variables plus utilities for the project's own additions.
///
/// Bootstrap's shipped utilities are never re-emitted here. Its scales are fixed, and
/// only tokens its components read are editable, so an edit is a variable override
/// and an addition is a new class such as `text-hero` or `rounded-soft`.
nonisolated enum BootstrapEditorCSS {
    static let sharedCSS = "@layer utilities{.font-heading{font-family:var(--bs-font-heading,inherit)}}"

    static func render(_ theme: Theme) -> String {
        let settings = theme.bootstrapTokens
        var declarations: [String] = []
        var utilities: [String] = []
        for section in BootstrapEditorSection.allCases {
            guard section != .prose else { continue }
            let custom = settings.custom[section.rawValue] ?? []
            guard settings.isChanged(section) || !custom.isEmpty else { continue }
            for token in settings.tokens(in: section) {
                declarations.append("--bs-\(token.id):\(settings.value(token))")
            }
            func value(_ id: String) -> String { "var(--bs-\(id))" }
            func rule(_ name: String, _ body: String) { utilities.append(".\(name){\(body)}") }
            switch section {
            case .fontSize:
                for name in custom {
                    let size = settings.value(section.customTokens(named: name)[0])
                    declarations.append("--bs-line-height-\(name):\(BootstrapTextSize.lineHeight(for: size).bootstrapCSSNumber)")
                    rule("fs-" + name, "font-size:\(value("font-size-" + name))")
                    rule("text-" + name, "font-size:\(value("font-size-" + name));line-height:\(value("line-height-" + name))")
                }
            case .borderWidth:
                for name in custom { rule("border-" + name, "border-width:\(value("border-width-" + name))") }
            case .borderRadius:
                for name in custom {
                    let radius = value("radius-" + name)
                    rule("rounded-" + name, "--bs-rounded-size:\(radius);border-radius:var(--bs-rounded-size)")
                    rule("rounded-size-" + name, "--bs-rounded-size:\(radius)")
                    for (edge, properties) in [("top", ["start-start", "start-end"]), ("end", ["start-end", "end-end"]), ("bottom", ["end-start", "end-end"]), ("start", ["start-start", "end-start"])] {
                        rule("rounded-\(edge)-\(name)", properties.map { "border-\($0)-radius:\(radius)" }.joined(separator: ";"))
                    }
                }
            case .shadows:
                for token in settings.customTokens(in: section) {
                    // Resolve local shadow colour/opacity on the styled element, not :root.
                    rule(token.id.replacingOccurrences(of: "box-", with: ""), "box-shadow:\(settings.value(token))")
                }
            case .zIndex:
                for name in custom { rule("z-" + name, "z-index:\(value("z-" + name))") }
            default: break
            }
        }
        let fonts = theme.typography
        let defaults = Theme.standard.typography
        if fonts.bodyFont != defaults.bodyFont { declarations.append("--bs-body-font-family:\(fonts.bodyFont.cssFamily)") }
        if fonts.monospacedFont != defaults.monospacedFont { declarations.append("--bs-font-mono:\(fonts.monospacedFont.cssFamily)") }
        var css = declarations.isEmpty ? "" : ":root,:host{\(declarations.joined(separator: ";"))}"
        if fonts.headingFont != defaults.headingFont {
            css += ":root,:host{--bs-font-heading:\(fonts.headingFont.cssFamily)}"
            css += "@layer content{h1,h2,h3,h4,h5,h6,.h1,.h2,.h3,.h4,.h5,.h6{font-family:var(--bs-font-heading)}}"
        }
        let fontClasses = BootstrapCustomTokenClasses.fontClasses(theme: theme)
        for font in fonts.customFonts {
            guard let name = fontClasses["font-custom-" + font.id.uuidString.lowercased()] else { continue }
            css += ":root,:host{--bs-\(name):\(font.font.cssFamily)}"
            utilities.append(".\(name){font-family:var(--bs-\(name))}")
        }
        return css + BootstrapProseCSS.render(settings) + (utilities.isEmpty ? "" : "@layer utilities{\(utilities.joined())}")
    }
}
