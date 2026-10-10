import Foundation

/// Foundry's additions on top of Bootstrap's untouched stylesheet, written as plain CSS.
///
/// Bootstrap ships its utilities with fixed values and no responsive variants for text
/// size, weight or wrapping. These rules add only what Bootstrap does not generate:
/// container caps for disabled breakpoints, responsive `fs-`, `text-` and `fw-`
/// variants, and a wrapping family whose breakpoint overrides also reset truncation.
/// They load after Bootstrap in the same cascade layers, so Bootstrap's own rules are
/// never redefined and need no Sass build.
nonisolated enum BootstrapUtilityExtensionsCSS {
    struct Breakpoint: Sendable {
        let id: ThemeScreenID
        let prefix: String
        var escapedPrefix: String { prefix == "2xl" ? "\\32 xl\\:" : prefix + "\\:" }
        var minimumWidth: Int { Int(ScreenTokens.standard.screen(id).minimumWidth) }
    }

    static let breakpoints: [Breakpoint] = [
        .init(id: .small, prefix: "sm"), .init(id: .medium, prefix: "md"), .init(id: .large, prefix: "lg"),
        .init(id: .extraLarge, prefix: "xl"), .init(id: .doubleExtraLarge, prefix: "2xl")
    ]

    /// One mutually exclusive wrapping family. Every value resets the others, so
    /// `text-truncate md:text-wrap` stops truncating at medium widths.
    static let wrapping: [(name: String, declarations: String)] = [
        ("wrap", "overflow:visible;text-overflow:clip;white-space:normal;text-wrap:wrap"),
        ("nowrap", "overflow:visible;text-overflow:clip;white-space:nowrap;text-wrap:nowrap"),
        ("balance", "overflow:visible;text-overflow:clip;white-space:normal;text-wrap:balance"),
        ("pretty", "overflow:visible;text-overflow:clip;white-space:normal;text-wrap:pretty"),
        ("truncate", "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-wrap:nowrap")
    ]

    static func render(theme: Theme) -> String {
        containerCSS(theme.screens) + typographyCSS(customSizes: theme.bootstrapTokens.custom["fontSize"] ?? [])
    }

    /// Bootstrap grows `.container` at every breakpoint. When a theme disables a
    /// breakpoint, the container keeps the previous enabled width instead.
    ///
    /// From the first breakpoint that differs from Bootstrap, every later breakpoint is
    /// written too, even where it matches. These rules follow Bootstrap's in the cascade,
    /// so a cap written for a disabled size would otherwise outrank Bootstrap's own rule
    /// for a larger size that is still enabled.
    static func containerCSS(_ screens: ScreenTokens) -> String {
        guard let first = breakpoints.firstIndex(where: {
            screens.screen($0.id).container != ScreenTokens.standard.screen($0.id).container
        }) else { return "" }
        let rules = breakpoints[first...].indices.map { index -> String in
            let breakpoint = breakpoints[index]
            let cap = screens.screen(breakpoint.id).container
            let value = cap.unit == .auto ? "none" : "\(Int(cap.value))px"
            let selectors = ([".container"] + breakpoints[...index].map { ".\($0.escapedPrefix)container" }).joined(separator: ",")
            return "@media (width >= \(breakpoint.minimumWidth)px){\(selectors){max-width:\(value)}}"
        }
        return "@layer layout{\(rules.joined())}"
    }

    /// Responsive text size, weight and wrapping. Values read Bootstrap's root tokens, so
    /// the breakpoint variants always match the base utilities Bootstrap ships.
    static func typographyCSS(customSizes: [String]) -> String {
        let sizes = BootstrapEditorSection.sizes + customSizes
        var css = wrapping.map { ".text-\($0.name){\($0.declarations)}" }.joined()
        for breakpoint in breakpoints {
            let prefix = "." + breakpoint.escapedPrefix
            var rules: [String] = []
            for size in sizes {
                rules.append("\(prefix)fs-\(size){font-size:var(--bs-font-size-\(size))}")
                rules.append("\(prefix)text-\(size){font-size:var(--bs-font-size-\(size));line-height:var(--bs-line-height-\(size))}")
            }
            for weight in BootstrapEditorSection.weights {
                rules.append("\(prefix)fw-\(weight){font-weight:var(--bs-font-weight-\(weight))}")
            }
            for wrap in wrapping {
                rules.append("\(prefix)text-\(wrap.name){\(wrap.declarations)}")
            }
            css += "@media (width >= \(breakpoint.minimumWidth)px){\(rules.joined())}"
        }
        return "@layer utilities{\(css)}"
    }
}
