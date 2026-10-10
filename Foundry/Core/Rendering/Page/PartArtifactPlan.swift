import Foundation

nonisolated struct PartArtifactPlan {
    let nodes: [PartNode]
    let packages: [LoadedPartPackage]

    init(page: Page) {
        nodes = page.parts.flatMap(\.flattened)
        var identifiers = Set<String>()
        packages = nodes.compactMap { node in
            guard let package = node.type.definition.package,
                  identifiers.insert(package.manifest.identifier).inserted else { return nil }
            return package
        }
    }

    static func sitePackages(in site: Site) -> [LoadedPartPackage] {
        var identifiers = Set<String>()
        return site.pages.flatMap { PartArtifactPlan(page: $0).packages }.filter {
            identifiers.insert($0.manifest.identifier).inserted
        }
    }

    static func htmlArtifact(for node: PartNode, suffix: String) -> String {
        guard let package = node.type.definition.package else { return "" }
        let source = PartTemplateRenderer.htmlPrimitives(in: package.htmlTemplate)
            .map { primitive in
                let key = suffix == "CSS"
                    ? PartPackageAdapter.htmlCSSKey(for: primitive.key)
                    : PartPackageAdapter.htmlJavaScriptKey(for: primitive.key)
                return node.property(key)
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return source
    }
}
