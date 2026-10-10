import Foundation

nonisolated enum BootstrapCustomTokenClasses {
    /// Saved selections use identity; exported utility names follow the editable name.
    static func fontClasses(framework: Framework) -> [String: String] {
        var result: [String: String] = [:]
        var used: Set<String> = ["body", "monospace", "heading"]
        for font in framework.typography.customFonts.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let folded = font.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
            let slug = folded.components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }.joined(separator: "-")
            let base = slug.isEmpty ? "custom" : slug
            var name = base
            var suffix = 2
            while used.contains(name) {
                name = "\(base)-\(suffix)"
                suffix += 1
            }
            used.insert(name)
            result["font-custom-" + font.id.uuidString.lowercased()] = "font-" + name
        }
        return result
    }

    static func label(for value: String, framework: Framework) -> String {
        guard let font = framework.typography.customFonts.first(where: { "font-custom-" + $0.id.uuidString.lowercased() == value }),
              let utility = fontClasses(framework: framework)[value] else { return value }
        return "\(font.name) — \(utility)"
    }

    static func choices(existing: [String], framework: Framework) -> [String] {
        var result: [String] = []
        let families: [(String, String, BootstrapEditorSection)] = [
            ("fs-md", "fs-", .fontSize), ("text-md", "text-", .fontSize),
            ("border-1", "border-", .borderWidth), ("rounded-1", "rounded-", .borderRadius),
            ("rounded-size-1", "rounded-size-", .borderRadius), ("rounded-top-1", "rounded-top-", .borderRadius),
            ("rounded-end-1", "rounded-end-", .borderRadius), ("rounded-bottom-1", "rounded-bottom-", .borderRadius),
            ("rounded-start-1", "rounded-start-", .borderRadius), ("shadow-sm", "shadow-", .shadows), ("z-1", "z-", .zIndex)
        ]
        for (marker, prefix, section) in families where existing.contains(marker) {
            result += (framework.bootstrapTokens.custom[section.rawValue] ?? []).map { prefix + $0 }
        }
        if existing.contains("font-body") {
            result += framework.typography.customFonts.map { "font-custom-" + $0.id.uuidString.lowercased() }
        }
        return result.filter { !existing.contains($0) }
    }
}
