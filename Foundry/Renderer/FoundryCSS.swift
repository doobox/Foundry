import Foundation

/// Foundry CSS: the framework compiled from a project's Framework values. It never
/// exists as a downloadable file — the Framework editor is its build configurator,
/// and every project ships a custom build tailored to its design system. The build
/// has three cascade layers (tokens, base, utilities); part and page CSS stay
/// unlayered, so they always take precedence over the framework by architecture.
nonisolated enum FoundryCSS {
    static let version = 1

    /// The complete framework build. `colour` supplies each role's CSS value so the
    /// canvas can resolve one appearance while exports emit light-dark() pairs.
    static func build(
        framework: Framework,
        colour: (FrameworkColorRole) -> String,
        colorScheme: String
    ) -> String {
        """
        /* Foundry CSS \(version) */
        @layer foundry.tokens, foundry.base, foundry.utilities;
        @layer foundry.tokens {
        :root{font-size:16px;color-scheme:\(colorScheme);\(tokenVariables(framework: framework, colour: colour))}
        \(framework.screens.containerCSS)
        @media (prefers-reduced-motion:reduce){:root{--foundry-motion-fast:0ms;--foundry-motion-normal:0ms;--foundry-motion-slow:0ms}}
        }
        @layer foundry.base {
        \(base)
        }
        @layer foundry.utilities {
        \(utilities(framework: framework))
        }
        """
    }

    // MARK: Tokens

    private static func tokenVariables(
        framework: Framework,
        colour: (FrameworkColorRole) -> String
    ) -> String {
        let colours = FrameworkColorRole.allCases.map {
            "--foundry-color-\($0.rawValue):\(colour($0));"
        }.joined()
        let fonts = "--foundry-font-body:\(framework.typography.bodyFont.cssFamily);"
            + "--foundry-font-heading:\(framework.typography.headingFont.cssFamily);"
            + "--foundry-font-monospace:\(framework.typography.monospacedFont.cssFamily);"
        // Motion and focus tokens are part of the Foundry CSS contract ahead of
        // gaining Framework-editor controls; parts may rely on them today.
        let motion = "--foundry-motion-fast:150ms;--foundry-motion-normal:250ms;--foundry-motion-slow:400ms;"
            + "--foundry-motion-ease:cubic-bezier(0.4,0,0.2,1);"
        // An outline value, not a box-shadow: outlines are the one focus channel
        // that nothing else (utility shadows, part box-shadows) can overwrite.
        let focus = "--foundry-focus-ring:2px solid var(--foundry-color-accent);"
        return colours
            + fonts
            + framework.customFontCSSVariables
            + framework.fontSizeCSSVariables
            + framework.spacingCSSVariables
            + framework.shadowCSSVariables
            + framework.borderCSSVariables
            + framework.zIndexCSSVariables
            + motion
            + focus
    }

    // MARK: Base

    /// Reset and token-driven defaults. Every value is a token reference; the base
    /// layer contains no literals so the Framework editor governs the whole page.
    private static var base: String {
        """
        *,*::before,*::after{box-sizing:border-box}
        html,body{min-height:100%}
        body{margin:0;background:var(--foundry-color-page);color:var(--foundry-color-text);font-family:var(--foundry-font-body);font-size:var(--foundry-font-size-base);line-height:var(--foundry-font-size-base-line-height);accent-color:var(--foundry-color-accent);overflow-wrap:break-word;display:flex;flex-direction:column;align-items:stretch}
        img,picture,video,canvas,svg{display:block;max-width:100%}
        input,button,textarea,select{font:inherit}
        a{color:var(--foundry-color-links)}
        :focus-visible{outline:var(--foundry-focus-ring);outline-offset:2px}
        ::selection{background:color-mix(in srgb, var(--foundry-color-accent) 30%, transparent)}
        h1,h2,h3,h4,h5,h6{font-family:var(--foundry-font-heading);text-wrap:balance}
        h1{font-size:var(--foundry-font-size-4xl);line-height:var(--foundry-font-size-4xl-line-height)}
        h2{font-size:var(--foundry-font-size-3xl);line-height:var(--foundry-font-size-3xl-line-height)}
        h3{font-size:var(--foundry-font-size-2xl);line-height:var(--foundry-font-size-2xl-line-height)}
        h4{font-size:var(--foundry-font-size-xl);line-height:var(--foundry-font-size-xl-line-height)}
        h5{font-size:var(--foundry-font-size-lg);line-height:var(--foundry-font-size-lg-line-height)}
        h6{font-size:var(--foundry-font-size-base);line-height:var(--foundry-font-size-base-line-height)}
        code,pre,kbd,samp{font-family:var(--foundry-font-monospace)}
        hr{border:none;border-top:1px solid color-mix(in srgb, var(--foundry-color-text) 20%, transparent);margin-block:var(--foundry-space-lg)}
        blockquote{margin:var(--foundry-space-lg) 0;padding-inline-start:var(--foundry-space-md);border-inline-start:2px solid color-mix(in srgb, var(--foundry-color-text) 20%, transparent);color:var(--foundry-color-muted-text)}
        table{border-collapse:collapse}
        th,td{border:1px solid color-mix(in srgb, var(--foundry-color-text) 20%, transparent);padding:var(--foundry-space-2xs) var(--foundry-space-xs);text-align:start}
        .fd-image{display:block;width:100%;height:auto}
        """
    }

    // MARK: Utilities

    /// Token-mirroring classes: `fd-{property}-{token}`, where the token segment is
    /// always a name that exists in the Framework editor. Responsive variants use
    /// the mobile-first prefix grammar `fd-md:p-sm` for enabled screens, generated
    /// only where responsiveness earns its bytes: spacing, text size and container.
    private static func utilities(framework: Framework) -> String {
        var rules: [String] = []

        rules.append(contentsOf: spacingUtilities(framework: framework, variantPrefix: nil))
        rules.append(contentsOf: textSizeUtilities(framework: framework, variantPrefix: nil))
        rules.append("""
        .fd-container{width:100%;max-width:var(--foundry-container-width);margin-inline:auto}
        """)

        for role in FrameworkColorRole.allCases {
            rules.append(".fd-text-\(role.rawValue){color:var(--foundry-color-\(role.rawValue))}")
            rules.append(".fd-bg-\(role.rawValue){background-color:var(--foundry-color-\(role.rawValue))}")
        }

        rules.append(".fd-font-body{font-family:var(--foundry-font-body)}")
        rules.append(".fd-font-heading{font-family:var(--foundry-font-heading)}")
        rules.append(".fd-font-mono{font-family:var(--foundry-font-monospace)}")
        for font in framework.typography.customFonts {
            rules.append(".fd-font-\(slug(font.name)){font-family:var(--foundry-font-custom-\(font.id.uuidString.lowercased()))}")
        }

        for radius in framework.borderRadii.predefined {
            rules.append(".fd-radius-\(radius.id){border-radius:var(--foundry-border-radius-\(radius.id))}")
        }
        for width in framework.borderWidths.predefined {
            rules.append(".fd-border-\(width.id){border:var(--foundry-border-width-\(width.id)) solid}")
        }
        for shadow in framework.shadows.shadows {
            rules.append(".fd-shadow-\(slug(shadow.id)){box-shadow:var(\(shadow.cssVariable))}")
        }
        for zIndex in framework.zIndexes.predefined {
            rules.append(".fd-z-\(zIndex.id){z-index:var(--foundry-z-index-\(zIndex.id))}")
        }

        // Responsive variants for enabled screens above mobile, mobile-first.
        for screen in framework.screens.screens where screen.isEnabled && screen.id != .mobile {
            let prefix = breakpointPrefix(for: screen.id)
            var variants: [String] = []
            variants.append(contentsOf: spacingUtilities(framework: framework, variantPrefix: prefix))
            variants.append(contentsOf: textSizeUtilities(framework: framework, variantPrefix: prefix))
            rules.append("@media(min-width:\(Int(screen.minimumWidth))px){\n\(variants.joined(separator: "\n"))\n}")
        }

        return rules.joined(separator: "\n")
    }

    private static func spacingUtilities(framework: Framework, variantPrefix: String?) -> [String] {
        var tokens: [(name: String, value: String)] = [
            ("3xs", "var(--foundry-space-3xs)"), ("2xs", "var(--foundry-space-2xs)"),
            ("xs", "var(--foundry-space-xs)"), ("sm", "var(--foundry-space-sm)"),
            ("md", "var(--foundry-space-md)"), ("lg", "var(--foundry-space-lg)"),
            ("xl", "var(--foundry-space-xl)"), ("2xl", "var(--foundry-space-2xl)"),
            ("3xl", "var(--foundry-space-3xl)")
        ]
        tokens.append(contentsOf: framework.spacing.custom.map { (slug($0.name), "var(\($0.cssVariable))") })

        var rules: [String] = []
        for token in tokens {
            for (short, properties) in Self.spacingProperties {
                let declarations = properties.map { "\($0):\(token.value)" }.joined(separator: ";")
                rules.append(".\(className("\(short)-\(token.name)", variantPrefix: variantPrefix)){\(declarations)}")
            }
        }
        for (short, properties) in Self.autoMarginProperties {
            let declarations = properties.map { "\($0):auto" }.joined(separator: ";")
            rules.append(".\(className("\(short)-auto", variantPrefix: variantPrefix)){\(declarations)}")
        }
        return rules
    }

    private static let spacingProperties: [(String, [String])] = [
        ("p", ["padding"]), ("px", ["padding-left", "padding-right"]), ("py", ["padding-top", "padding-bottom"]),
        ("pt", ["padding-top"]), ("pr", ["padding-right"]), ("pb", ["padding-bottom"]), ("pl", ["padding-left"]),
        ("m", ["margin"]), ("mx", ["margin-left", "margin-right"]), ("my", ["margin-top", "margin-bottom"]),
        ("mt", ["margin-top"]), ("mr", ["margin-right"]), ("mb", ["margin-bottom"]), ("ml", ["margin-left"]),
        ("gap", ["gap"]), ("gap-x", ["column-gap"]), ("gap-y", ["row-gap"])
    ]

    private static let autoMarginProperties: [(String, [String])] = [
        ("mx", ["margin-left", "margin-right"]), ("ml", ["margin-left"]), ("mr", ["margin-right"])
    ]

    private static func textSizeUtilities(framework: Framework, variantPrefix: String?) -> [String] {
        framework.typography.fontSizes.map { size in
            ".\(className("text-\(slug(size.id))", variantPrefix: variantPrefix)){font-size:var(--foundry-font-size-\(size.id));line-height:var(--foundry-font-size-\(size.id)-line-height)}"
        }
    }

    /// `fd-p-sm` unqualified, `fd-md\:p-sm` inside a breakpoint's media query.
    private static func className(_ body: String, variantPrefix: String?) -> String {
        guard let variantPrefix else { return "fd-\(body)" }
        return "fd-\(variantPrefix)\\:\(body)"
    }

    private static func breakpointPrefix(for screen: FrameworkScreenID) -> String {
        switch screen {
        case .mobile: "base"
        case .small: "sm"
        case .medium: "md"
        case .large: "lg"
        case .extraLarge: "xl"
        case .doubleExtraLarge: "2xl"
        }
    }

    /// Class-safe slug for user-named tokens: lowercase, non-alphanumerics collapse
    /// to single hyphens.
    static func slug(_ name: String) -> String {
        var result = ""
        var previousWasHyphen = true
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                result.append(character)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                result.append("-")
                previousWasHyphen = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "token" : result
    }
}
