import Foundation

nonisolated struct BootstrapColourSource: Identifiable {
    let id: String
    let title: String
    let expression: String

    static func choices(for section: BootstrapEditorSection) -> [Self] {
        guard section == .linkColours || section == .shadowColours else { return [] }
        let links = section == .linkColours
        let native = section.tokens[0].defaultValue
        return [Self(id: "default", title: links ? "Primary (default)" : "Black (default)", expression: native)]
            + BootstrapColourCatalogue.themeRoles.filter { !links || $0 != "primary" }.map { role in
                Self(id: "theme-" + role, title: role.capitalized,
                     expression: links ? "light-dark(var(--bs-\(role)-base),var(--bs-\(role)-fg))" : "var(--bs-\(role)-base)")
            }
            + BootstrapColourCatalogue.hues.map { hue in
                Self(id: "hue-" + hue, title: hue.capitalized,
                     expression: links ? "light-dark(var(--bs-\(hue)-500),var(--bs-\(hue)-400))" : "var(--bs-\(hue)-500)")
            }
            + ["black", "white"].map { Self(id: $0, title: $0.capitalized, expression: "var(--bs-\($0))") }
    }

    static func selected(in theme: Theme, section: BootstrapEditorSection) -> String {
        guard let token = section.tokens.first else { return "custom" }
        let value = theme.bootstrapTokens.value(token).filter { !$0.isWhitespace }
        return choices(for: section).first { $0.expression.filter { !$0.isWhitespace } == value }?.id ?? "custom"
    }
}
