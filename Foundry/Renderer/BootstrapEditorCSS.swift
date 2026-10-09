import Foundation

nonisolated enum BootstrapEditorCSS {
    static func render(_ framework: Framework) -> String {
        let settings = framework.bootstrapTokens
        var declarations: [String] = []
        var utilities: [String] = []
        for section in BootstrapEditorSection.allCases {
            let custom = settings.custom[section.rawValue] ?? []
            guard settings.isChanged(section) || !custom.isEmpty else { continue }
            let tokens = settings.tokens(in: section)
            for token in tokens where !token.id.hasPrefix("shadow-strength-") {
                declarations.append("--bs-\(token.id):\(settings.value(token))")
            }
            func value(_ id: String) -> String { "var(--bs-\(id))" }
            func rule(_ name: String, _ body: String) { utilities.append(".\(name){\(body)}") }
            switch section {
            case .fontSize:
                for name in BootstrapEditorSection.sizes + custom {
                    rule("fs-" + name, "font-size:\(value("font-size-" + name))")
                    rule("text-" + name, "font-size:\(value("font-size-" + name));line-height:\(value("line-height-" + name))")
                }
            case .fontWeight:
                for name in BootstrapEditorSection.weights { rule("fw-" + name, "font-weight:\(value("font-weight-" + name))") }
            case .borderWidth:
                for name in ["keyline", "1", "2", "3", "4", "5"] + custom { rule("border-" + name, "border-width:\(value("border-width-" + name))") }
            case .borderRadius:
                for name in (0...9).map(String.init) + ["pill"] + custom {
                    let radius = value("radius-" + name)
                    rule("rounded-" + name, "--bs-rounded-size:\(radius);border-radius:var(--bs-rounded-size)")
                    rule("rounded-size-" + name, "--bs-rounded-size:\(radius)")
                    for (edge, properties) in [("top", ["start-start", "start-end"]), ("end", ["start-end", "end-end"]), ("bottom", ["end-start", "end-end"]), ("start", ["start-start", "end-start"])] {
                        rule("rounded-\(edge)-\(name)", properties.map { "border-\($0)-radius:\(radius)" }.joined(separator: ";"))
                    }
                }
                rule("rounded", "--bs-rounded-size:var(--bs-radius-5);border-radius:var(--bs-rounded-size)")
                rule("rounded-size", "--bs-rounded-size:var(--bs-radius-5)")
            case .shadows:
                for token in tokens where token.id.hasPrefix("box-shadow") && token.id != "box-shadow-inset" {
                    // Resolve local shadow colour/opacity on the styled element, not :root.
                    rule(token.id.replacingOccurrences(of: "box-", with: ""), "box-shadow:\(settings.value(token))")
                }
            case .zIndex:
                for name in BootstrapEditorSection.levels + custom { rule("z-" + name, "z-index:\(value("z-" + name))") }
            default: break
            }
        }
        let fonts = framework.typography
        let defaults = Framework.standard.typography
        if fonts.bodyFont != defaults.bodyFont { declarations.append("--bs-body-font-family:\(fonts.bodyFont.cssFamily)") }
        if fonts.monospacedFont != defaults.monospacedFont { declarations.append("--bs-font-mono:\(fonts.monospacedFont.cssFamily)") }
        var css = declarations.isEmpty ? "" : ":root,:host{\(declarations.joined(separator: ";"))}"
        if fonts.headingFont != defaults.headingFont {
            css += "@layer content{h1,h2,h3,h4,h5,h6,.h1,.h2,.h3,.h4,.h5,.h6{font-family:\(fonts.headingFont.cssFamily)}}"
        }
        for font in fonts.customFonts {
            css += ":root,:host{--bs-font-custom-\(font.id.uuidString.lowercased()):\(font.font.cssFamily)}"
            utilities.append(".font-custom-\(font.id.uuidString.lowercased()){font-family:var(--bs-font-custom-\(font.id.uuidString.lowercased()))}")
        }
        if let light = settings.values["shadow-strength-light"] {
            css += ":root,:host,[data-bs-theme=light]{--bs-shadow-strength:\(light)}"
        }
        if settings.values["shadow-strength-light"] != nil || settings.values["shadow-strength-dark"] != nil {
            let dark = settings.values["shadow-strength-dark"] ?? "2.4"
            css += "@media(prefers-color-scheme:dark){:root:not([data-bs-theme]),:host:not([data-bs-theme]){--bs-shadow-strength:\(dark)}}[data-bs-theme=dark]{--bs-shadow-strength:\(dark)}"
        }
        return css + (utilities.isEmpty ? "" : "@layer utilities{\(utilities.joined())}")
    }
}
