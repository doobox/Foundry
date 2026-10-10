import Foundation

/// Immutable manifest-derived rendering inputs, expanded once per package load.
nonisolated struct PartPackageRenderDefinition: Sendable {
    let properties: [PartPackageProperty]
    let propertiesByID: [String: PartPackageProperty]
    let slots: [PartPackageSlot]
    let controlGroupCSS: String
    let controlGroupJavaScript: String
    let htmlContributions: [PartPackageHTMLContribution]
    let loopMaximums: [String: Int]

    init(manifest: PartPackageManifest) {
        properties = manifest.resolvedProperties
        propertiesByID = Dictionary(properties.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        slots = properties.compactMap(\.childSlot)
        controlGroupCSS = manifest.controlGroupCSS
        controlGroupJavaScript = manifest.controlGroupJavaScript
        htmlContributions = manifest.htmlContributions
        loopMaximums = Dictionary(properties.compactMap { property -> (String, Int)? in
            guard property.control.type == .number || property.control.type == .slider,
                  let maximum = property.control.maximum, maximum.isFinite, maximum >= 0,
                  maximum <= Double(PartTemplateLoop.maximumIterationCount) else { return nil }
            return (property.id, Int(maximum.rounded(.down)))
        }, uniquingKeysWith: { first, _ in first })
    }
}
