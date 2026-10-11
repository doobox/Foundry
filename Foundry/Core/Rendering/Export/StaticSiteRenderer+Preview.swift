import Foundation

extension StaticSiteRenderer {
    func previewSnapshot(site: Site, assets: ProjectAssetContents, identity: PreviewBuildIdentity,
                         invalidation: PreviewInvalidation, previous: PreviewDiskSnapshot?) throws -> PreviewDiskSnapshot {
        let reusable = previous?.reusablePages(for: identity, invalidation: invalidation) ?? [:]
        let currentIDs = Set(site.pages.map(\.id))
        var paths: [UUID: [String]] = [:]
        return try PreviewDiskSnapshot.build(previous: previous, identity: identity,
            pagePaths: { paths }, reusedPageIDs: Set(reusable.keys).intersection(currentIDs)) { emit in
            try generate(site: site, assets: assets, reusingPages: reusable,
                         pageOutput: { paths[$0] = $1 }, emit: emit)
        }
    }
}
