import Foundation

/// Page defaults: inherited text/border values and a low-specificity link scope.
nonisolated enum BootstrapPageColours {
    static func css(page: Page, theme: Theme) -> String {
        var declarations: [String] = []
        if let value = page.foregroundOverride, let token = PartColourToken.parse(value) {
            declarations.append("color:\(token.expression)")
        }
        if let value = page.borderOverride, let token = PartColourToken.parse(value) {
            declarations.append("--bs-border-color:\(token.expression)")
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
            }
            if let normal, let hover {
                declarations += ["--bs-link-color:\(normal)", "--bs-link-hover-color:\(hover)"]
                // Part link groups use the same layer and a nearer scope, so win naturally.
                links = "@scope(body){:where(a[href]:not(.btn)){color:var(--bs-link-color)}@media(hover:hover){:where(a[href]:not(.btn)):hover{color:var(--bs-link-hover-color)}}}"
            }
        }
        guard !declarations.isEmpty else { return "" }
        return "@layer utilities{:where(body){\(declarations.joined(separator: ";"))}\(links)}"
    }
}
