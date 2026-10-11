import Foundation

nonisolated enum PreviewPageNavigation {
    static func pageID(for path: String, in site: Site) -> UUID? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let resolved = PreviewHTTPRouter.safeBundlePath(path) else { return nil }
        let cleanPath = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        return site.pages.first { page in
            let output = StaticSiteRenderer.outputPath(for: page, in: site)
            return output == resolved || (cleanPath.hasSuffix("/") && output == String(resolved.dropLast(4)) + "php")
        }?.id
    }
}
