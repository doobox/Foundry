import Foundation

nonisolated struct BlockArtifactPlan {
    let nodes: [BlockNode]
    let packages: [LoadedBlockPackage]

    init(page: Page) {
        nodes = page.blocks.flatMap(\.flattened)
        var identifiers = Set<String>()
        packages = nodes.compactMap { node in
            guard let package = node.type.definition.package,
                  identifiers.insert(package.manifest.identifier).inserted else { return nil }
            return package
        }
    }

    static func sitePackages(in site: Site) -> [LoadedBlockPackage] {
        var identifiers = Set<String>()
        return site.pages.flatMap { BlockArtifactPlan(page: $0).packages }.filter {
            identifiers.insert($0.manifest.identifier).inserted
        }
    }

    static func htmlArtifact(for node: BlockNode, suffix: String) -> String {
        guard let package = node.type.definition.package else { return "" }
        let source = BlockTemplateRenderer.htmlPrimitives(in: package.htmlTemplate)
            .map { primitive in
                let key = suffix == "CSS"
                    ? BlockPackageAdapter.htmlCSSKey(for: primitive.key)
                    : BlockPackageAdapter.htmlJavaScriptKey(for: primitive.key)
                return node.property(key)
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return source
    }
}
