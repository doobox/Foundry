import Foundation

/// Background paint reads Bootstrap tokens without applying a theme to children.
nonisolated enum BootstrapBackgroundColour {
    static func paint(_ theme: String, role: String = "bg", opacity: Double = 100) -> String {
        if let token = PartColourToken.parse(theme) {
            let amount = opacity.isFinite ? min(100, max(0, opacity)) : 100
            return role == "transparent" ? "transparent" : amount == 100 ? token.expression : "color-mix(in oklch, \(token.expression) \(Int(amount))%, transparent)"
        }
        guard theme.hasPrefix("theme-"), theme != "theme-reset", ["bg", "bg-subtle", "bg-muted"].contains(role) else { return "transparent" }
        let name = String(theme.dropFirst(6))
        guard name.range(of: #"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil else { return "transparent" }
        let colour = "var(--bs-\(name)-\(role))"
        let amount = opacity.isFinite ? min(100, max(0, opacity)) : 100
        return amount == 100 ? colour : "color-mix(in oklch, \(colour) \(Int(amount))%, transparent)"
    }
}
