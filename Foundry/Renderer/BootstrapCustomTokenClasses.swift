import Foundation

nonisolated enum BootstrapCustomTokenClasses {
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
