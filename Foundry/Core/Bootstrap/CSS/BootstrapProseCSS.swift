import Foundation

/// Prose declares its variables locally, including different defaults at 1024px.
nonisolated enum BootstrapProseCSS {
    static func render(_ settings: BootstrapEditorTokens) -> String {
        let tokens = BootstrapEditorSection.prose.tokens
        func edited(_ index: Int) -> Bool { settings.values[tokens[index].id] != nil }
        func value(_ index: Int) -> String { settings.value(tokens[index]) }
        var base: [String] = []
        var wide: [String] = []
        for (index, variable) in [(0, "content-font-size"), (1, "content-line-height")] {
            if edited(index) { base.append("--bs-\(variable):\(value(index))") }
            // Preserve Bootstrap's larger-screen default when only the base is edited.
            if edited(index) || edited(index + 2) {
                wide.append("--bs-\(variable):\(value(index + 2))")
            }
        }
        if edited(4) { base.append("--bs-content-gap:\(value(4))") }
        if edited(5) || edited(6) {
            base.append("--bs-heading-color:light-dark(\(value(5)),\(value(6)))")
        }
        var rules = base.isEmpty ? "" : ".prose{\(base.joined(separator: ";"))}"
        if !wide.isEmpty { rules += "@media (width>=1024px){.prose{\(wide.joined(separator: ";"))}}" }
        return rules.isEmpty ? "" : "@layer content{\(rules)}"
    }
}
