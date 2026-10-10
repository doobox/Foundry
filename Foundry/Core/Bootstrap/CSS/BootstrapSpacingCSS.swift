import Foundation

/// Bootstrap 6 alpha.1 spacing utility definitions, emitted without runtime Sass.
/// Only sites with custom spacers need this. The complete family is re-emitted then,
/// so a responsive Bootstrap step still beats a custom base value in the cascade
/// (and vice versa); Bootstrap's own values are unchanged.
nonisolated enum BootstrapSpacingCSS {
    static func render(_ spacing: SpacingTokens) -> String {
        guard !spacing.custom.isEmpty else { return "" }
        let families: [(String, String)] = [
            ("m", "margin"), ("mx", "margin-inline"), ("my", "margin-block"),
            ("mt", "margin-block-start"), ("me", "margin-inline-end"),
            ("mb", "margin-block-end"), ("ms", "margin-inline-start"),
            ("p", "padding"), ("px", "padding-inline"), ("py", "padding-block"),
            ("pt", "padding-block-start"), ("pe", "padding-inline-end"),
            ("pb", "padding-block-end"), ("ps", "padding-inline-start"),
            ("gap", "gap"), ("row-gap", "row-gap"), ("column-gap", "column-gap"),
            ("space-x", "margin-inline-end"), ("space-y", "margin-block-end")
        ]
        let breakpoints: [(String, Int)] = [("", 0), ("sm", 576), ("md", 768), ("lg", 1024), ("xl", 1280), ("2xl", 1536)]
        var css = "\n@layer utilities {\n"
        for (breakpoint, width) in breakpoints {
            if width > 0 { css += "@media (min-width: \(width)px) {\n" }
            let prefix = breakpoint.isEmpty ? "" : (breakpoint == "2xl" ? "\\32 xl\\:" : breakpoint + "\\:")
            for (family, property) in families {
                var values = spacing.choices.map { ($0.id, $0.css) }
                if family.hasPrefix("m") { values.append(("auto", "auto")) }
                if family == "ms" || family == "me" {
                    values += [("-1", "calc(var(--bs-spacer) * -.25)"), ("-2", "calc(var(--bs-spacer) * -.5)")]
                }
                for (name, value) in values {
                    let selector = ".\(prefix)\(family)-\(name)"
                    let target = family.hasPrefix("space-") ? ":where(\(selector) > :not(:last-child))" : selector
                    css += "\(target){\(property):\(value)}\n"
                }
            }
            if width > 0 { css += "}\n" }
        }
        return css + "}\n"
    }
}
