import Foundation

/// Uses the group's identity, not a built-in part's particular namespace.
nonisolated struct PartBackgroundInspectorContext {
    let localID: String
    let namespace: String

    init?(property: PartPackageProperty?) {
        guard let source = property?.controlGroupSource, source.type == .background else { return nil }
        localID = source.localID
        namespace = source.namespace
    }

    var modeKey: PartProperty.Key { .init(rawValue: namespace + ".backgroundMode") }
    var styleKey: PartProperty.Key { .init(rawValue: namespace + ".backgroundStyle") }

    func choices(_ choices: [PartPropertyChoice], mode: String) -> [PartPropertyChoice] {
        guard mode == "hover", ["backgroundStyle", "backgroundHoverStyle"].contains(localID) else { return choices }
        return choices.filter { $0.value != "video" }
    }

    func replacementStyle(newMode: String, currentStyle: String, choices: [PartPropertyChoice]) -> String? {
        guard localID == "backgroundMode", newMode == "hover", currentStyle == "video" else { return nil }
        return choices.first { $0.value != "video" }?.value
    }
}
