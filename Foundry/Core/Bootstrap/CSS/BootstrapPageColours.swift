import Foundation

/// Page defaults: inherited text/border values and a low-specificity link scope.
nonisolated enum BootstrapPageColours {
    static func css(page: Page, theme: Theme) -> String {
        var declarations: [String] = []
        if let value = page.foregroundOverride {
            let adjustment = page.colourAdjustments[PartColourPurpose.foreground.rawValue] ?? PageColourAdjustment()
            let resolved = PartColourPurpose.foreground.resolve(value, theme: theme,
                variant: adjustment.variant, opacity: adjustment.opacity)
            if !resolved.color.isEmpty { declarations.append("color:\(resolved.color)") }
        }
        if let value = page.borderOverride {
            let adjustment = page.colourAdjustments[PartColourPurpose.border.rawValue] ?? PageColourAdjustment()
            let resolved = PartColourPurpose.border.resolve(value, theme: theme,
                variant: adjustment.variant, opacity: adjustment.opacity)
            if !resolved.color.isEmpty { declarations.append("--bs-border-color:\(resolved.color)") }
        }
        var links = ""
        if let value = page.linksOverride {
            var normal: String?
            var hover: String?
            if value == "token:link-color" {
                // Resolve defaults directly, never create a self-referencing variable.
                let tokens = BootstrapEditorSection.linkColours.tokens
                normal = theme.bootstrapTokens.value(tokens[0])
                hover = theme.bootstrapTokens.value(tokens[1])
            } else if let palette = theme.colourPalettes.first(where: {
                $0.origin == .custom && $0.colourKind == .link && value == "token:" + $0.colourTokens[0]
            }) {
                normal = "var(--bs-\(palette.colourTokens[0]))"
                hover = "var(--bs-\(palette.colourTokens[1]))"
            } else if let palette = BootstrapPaletteTheme.effectivePalette(value, in: theme),
                      let role = BootstrapPaletteTheme.nativeRole(palette) {
                normal = "var(--bs-\(role)-fg)"
                hover = "var(--bs-\(role)-fg-emphasis)"
            }
            if let normal, let hover {
                let opacity = page.colourAdjustments[PartColourPurpose.link.rawValue]?.opacity ?? 100
                func faded(_ colour: String) -> String {
                    opacity >= 100 ? colour : "color-mix(in oklch, \(colour) \(Int(min(100, max(0, opacity)).rounded()))%, transparent)"
                }
                declarations += ["--bs-link-color:\(faded(normal))", "--bs-link-hover-color:\(faded(hover))"]
                // Part link groups use the same layer and a nearer scope, so win naturally.
                links = "@scope(body){:where(a[href]:not(.btn)){color:var(--bs-link-color)}@media(hover:hover){:where(a[href]:not(.btn)):hover{color:var(--bs-link-hover-color)}}}"
            }
        }
        guard !declarations.isEmpty else { return "" }
        return "@layer utilities{:where(body){\(declarations.joined(separator: ";"))}\(links)}"
    }
}
