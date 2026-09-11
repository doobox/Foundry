import Foundation

nonisolated struct ComponentArtifactPlan {
    let nodes: [ComponentNode]
    let packages: [LoadedComponentPackage]

    init(page: Page) {
        nodes = page.components.flatMap(\.flattened)
        var identifiers = Set<String>()
        packages = nodes.compactMap { node in
            guard let package = node.type.definition.package,
                  identifiers.insert(package.manifest.identifier).inserted else { return nil }
            return package
        }
    }

    static func sitePackages(in site: Site) -> [LoadedComponentPackage] {
        var identifiers = Set<String>()
        return site.pages.flatMap { ComponentArtifactPlan(page: $0).packages }.filter {
            identifiers.insert($0.manifest.identifier).inserted
        }
    }

    static func htmlArtifact(for node: ComponentNode, suffix: String) -> String {
        guard let package = node.type.definition.package else { return "" }
        let source = ComponentTemplateRenderer.htmlPrimitives(in: package.htmlTemplate)
            .map { primitive in
                let key = suffix == "CSS"
                    ? ComponentPackageAdapter.htmlCSSKey(for: primitive.key)
                    : ComponentPackageAdapter.htmlJavaScriptKey(for: primitive.key)
                return node.property(key)
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return source
    }
}
