import Foundation

nonisolated enum ComponentNavigationTemplateValues {
    static func values(site: Site, currentPage: Page) -> [String: ComponentPackageValue] {
        let childrenByParent = Dictionary(grouping: site.pages, by: \.parentPageID)

        func sortedChildren(of parentID: UUID?) -> [Page] {
            (childrenByParent[parentID] ?? []).sorted {
                if parentID == nil, $0.slug == "index" || $1.slug == "index", $0.slug != $1.slug {
                    return $0.slug == "index"
                }
                return $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
            }
        }

        func item(_ page: Page, depth: Int, visited: Set<UUID>) -> ComponentPackageValue {
            guard !visited.contains(page.id) else { return .object([:]) }
            let nextVisited = visited.union([page.id])
            let childItems = visibleItems(of: page.id, depth: depth + 1, visited: nextVisited)
            let isAncestor = isPage(currentPage.id, descendantOf: page.id, pages: site.pages)
            return .object([
                "id": .string(page.id.uuidString),
                "title": .string(page.title),
                "href": .string(PageRouteResolver.path(for: page, pages: site.pages, folders: site.pageFolders)),
                "slug": .string(page.slug),
                "depth": .number(Double(depth)),
                "current": .boolean(page.id == currentPage.id),
                "ancestor": .boolean(isAncestor && page.id != currentPage.id),
                "home": .boolean(page.slug == "index"),
                "hasChildren": .boolean(!childItems.isEmpty),
                "children": .array(childItems)
            ])
        }

        func visibleItems(of parentID: UUID?, depth: Int, visited: Set<UUID>) -> [ComponentPackageValue] {
            sortedChildren(of: parentID).flatMap { page in
                if page.includeInNavigation {
                    return [item(page, depth: depth, visited: visited)]
                }
                return visibleItems(of: page.id, depth: depth, visited: visited.union([page.id]))
            }
        }

        func visiblePageOrder(from parentID: UUID?, visited: Set<UUID>) -> [Page] {
            sortedChildren(of: parentID).flatMap { page in
                guard !visited.contains(page.id) else { return [Page]() }
                let nextVisited = visited.union([page.id])
                let descendants = visiblePageOrder(from: page.id, visited: nextVisited)
                return page.includeInNavigation ? [page] + descendants : descendants
            }
        }

        let roots = visibleItems(of: nil, depth: 0, visited: [])
        let visiblePages = visiblePageOrder(from: nil, visited: [])
        let currentIndex = visiblePages.firstIndex(where: { $0.id == currentPage.id })
        let previous = currentIndex.flatMap { $0 > 0 ? visiblePages[$0 - 1] : nil }
        let next = currentIndex.flatMap { $0 + 1 < visiblePages.count ? visiblePages[$0 + 1] : nil }
        let breadcrumbs = breadcrumbPages(for: currentPage, pages: site.pages).map {
            item($0, depth: 0, visited: [])
        }
        let siblings = sortedChildren(of: currentPage.parentPageID)
            .filter(\.includeInNavigation)
            .map { item($0, depth: 0, visited: []) }
        let current = item(currentPage, depth: 0, visited: [])
        let pageItems = site.pages.map { item($0, depth: 0, visited: []) }
        let publishedAssets = site.assets.compactMap { asset -> ComponentPackageValue? in
            guard asset.exportDirectory != nil else { return nil }
            return assetValue(asset, site: site)
        }

        var result: [String: ComponentPackageValue] = [
            "navigation.items": .array(roots),
            "navigation.breadcrumbs": .array(breadcrumbs),
            "navigation.ancestors": .array(Array(breadcrumbs.dropLast())),
            "navigation.current": current,
            "navigation.current.siblings": .array(siblings),
            "pages.all": .array(pageItems),
            "pages.current": current,
            "assets.published": .array(publishedAssets),
            "assets.images": .array(publishedAssets.filter { isImage($0) }),
            "assets.documents": .array(publishedAssets.filter { !isImage($0) })
        ]
        if let home = site.pages.first(where: { $0.slug == "index" }) {
            result["pages.home"] = item(home, depth: 0, visited: [])
        }
        if let previous { result["navigation.previous"] = item(previous, depth: 0, visited: []) }
        if let next { result["navigation.next"] = item(next, depth: 0, visited: []) }
        return result
    }

    private static func assetValue(_ asset: ProjectAsset, site: Site) -> ComponentPackageValue {
        .object([
            "id": .string(asset.id.uuidString),
            "filename": .string(asset.filename),
            "href": .string("/" + site.publishedPath(for: asset)),
            "mediaType": .string(asset.mediaType),
            "width": asset.pixelWidth.map { .number(Double($0)) } ?? .number(0),
            "height": asset.pixelHeight.map { .number(Double($0)) } ?? .number(0),
            "isImage": .boolean(asset.mediaType.hasPrefix("image/"))
        ])
    }

    private static func isImage(_ value: ComponentPackageValue) -> Bool {
        guard case .object(let fields) = value else { return false }
        return fields["isImage"] == .boolean(true)
    }

    private static func breadcrumbPages(for page: Page, pages: [Page]) -> [Page] {
        var result = [page]
        var current = page
        var visited: Set<UUID> = [page.id]
        while let parentID = current.parentPageID,
              visited.insert(parentID).inserted,
              let parent = pages.first(where: { $0.id == parentID }) {
            result.insert(parent, at: 0)
            current = parent
        }
        return result
    }

    private static func isPage(_ candidateID: UUID, descendantOf ancestorID: UUID, pages: [Page]) -> Bool {
        var currentID: UUID? = candidateID
        var visited = Set<UUID>()
        while let id = currentID, visited.insert(id).inserted {
            if id == ancestorID { return true }
            currentID = pages.first(where: { $0.id == id })?.parentPageID
        }
        return false
    }
}
