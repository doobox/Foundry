import Foundation

/// Memoizes per-page template values for the lifetime of one renderer.
/// Navigation values walk the whole site, and the renderers build a template
/// context per part instance — recomputing them per part scales the cost by
/// pages × parts. Renderers are created per render pass and their site is
/// fixed at init, so an instance-lifetime cache can never serve stale values.
nonisolated final class PartTemplateValuesCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: [String: PartPackageValue]] = [:]

    func values(
        for pageID: UUID,
        compute: () -> [String: PartPackageValue]
    ) -> [String: PartPackageValue] {
        lock.lock()
        if let cached = storage[pageID] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let computed = compute()
        lock.lock()
        storage[pageID] = computed
        lock.unlock()
        return computed
    }
}

nonisolated enum PartBreakpointTemplateValues {
    static func values(screens: ScreenTokens) -> [String: PartPackageValue] {
        let breakpoints = Dictionary(uniqueKeysWithValues: ResponsiveBreakpoint.allCases.map { breakpoint in
            let screen = screens.screen(breakpoint.screenID)
            return (breakpoint.rawValue, PartPackageValue.object([
                "enabled": .boolean(screen.isEnabled),
                "minimumWidth": .number(screen.minimumWidth)
            ]))
        })
        return ["breakpoints": .object(breakpoints)]
    }
}

nonisolated enum PartNavigationTemplateValues {
    // Canvas uses its virtual root. Export supplies the path back to the
    // site's root so navigation remains portable to any deployment folder.
    static func values(site: Site, currentPage: Page, rootPrefix: String = "/") -> [String: PartPackageValue] {
        let childrenByParent = Dictionary(grouping: site.pages, by: \.parentPageID)

        func sortedChildren(of parentID: UUID?) -> [Page] {
            (childrenByParent[parentID] ?? []).sorted {
                if parentID == nil, $0.slug == "index" || $1.slug == "index", $0.slug != $1.slug {
                    return $0.slug == "index"
                }
                return $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
            }
        }

        func item(_ page: Page, depth: Int, visited: Set<UUID>) -> PartPackageValue {
            guard !visited.contains(page.id) else { return .object([:]) }
            let nextVisited = visited.union([page.id])
            let childItems = visibleItems(of: page.id, depth: depth + 1, visited: nextVisited)
            let isAncestor = isPage(currentPage.id, descendantOf: page.id, pages: site.pages)
            return .object([
                "id": .string(page.id.uuidString),
                "title": .string(page.title),
                "href": .string(rootPrefix + StaticSiteRenderer.urlPath(for: page, pages: site.pages, folders: site.pageFolders).dropFirst()),
                "slug": .string(page.slug),
                "depth": .number(Double(depth)),
                "current": .boolean(page.id == currentPage.id),
                "ancestor": .boolean(isAncestor && page.id != currentPage.id),
                "home": .boolean(page.slug == "index"),
                "hasChildren": .boolean(!childItems.isEmpty),
                "children": .array(childItems)
            ])
        }

        func visibleItems(of parentID: UUID?, depth: Int, visited: Set<UUID>) -> [PartPackageValue] {
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

        // The top of the menu mirrors the Pages panel: pages and folders share
        // one ordering space per container. A navigation folder becomes a
        // non-link group holding its contents; other folders promote their
        // contents in place, exactly like pages excluded from navigation.
        func pages(inFolder folderID: UUID?) -> [Page] {
            site.pages.filter { $0.parentPageID == nil && $0.folderID == folderID }
        }

        func folders(inFolder folderID: UUID?) -> [PageFolder] {
            site.pageFolders.filter { $0.parentID == folderID }
        }

        func currentPageIsInside(_ folder: PageFolder) -> Bool {
            var page = currentPage
            var visitedPages: Set<UUID> = [page.id]
            while let parentID = page.parentPageID, visitedPages.insert(parentID).inserted,
                  let parent = site.pages.first(where: { $0.id == parentID }) {
                page = parent
            }
            var folderID = page.folderID
            var visitedFolders = Set<UUID>()
            while let id = folderID, visitedFolders.insert(id).inserted {
                if id == folder.id { return true }
                folderID = site.pageFolders.first(where: { $0.id == id })?.parentID
            }
            return false
        }

        func folderItem(_ folder: PageFolder, depth: Int, visitedFolders: Set<UUID>) -> PartPackageValue? {
            let children = containerItems(inFolder: folder.id, depth: depth + 1, visitedFolders: visitedFolders)
            guard !children.isEmpty else { return nil }
            return .object([
                "id": .string(folder.id.uuidString),
                "title": .string(folder.name),
                "href": .string(""),
                "slug": .string(folder.slug),
                "depth": .number(Double(depth)),
                "current": .boolean(false),
                "ancestor": .boolean(currentPageIsInside(folder)),
                "home": .boolean(false),
                "folder": .boolean(true),
                "hasChildren": .boolean(true),
                "children": .array(children)
            ])
        }

        func containerItems(inFolder folderID: UUID?, depth: Int, visitedFolders: Set<UUID>) -> [PartPackageValue] {
            struct Entry {
                let order: Int
                let isHome: Bool
                let id: UUID
                let values: [PartPackageValue]
            }
            let isRoot = folderID == nil
            let pageEntries = pages(inFolder: folderID).map { page in
                Entry(
                    order: page.order,
                    isHome: isRoot && page.slug == "index",
                    id: page.id,
                    values: page.includeInNavigation
                        ? [item(page, depth: depth, visited: [])]
                        : visibleItems(of: page.id, depth: depth, visited: [page.id])
                )
            }
            let folderEntries = folders(inFolder: folderID).compactMap { folder -> Entry? in
                guard !visitedFolders.contains(folder.id) else { return nil }
                let nextVisited = visitedFolders.union([folder.id])
                let values = folder.includeInNavigation
                    ? [folderItem(folder, depth: depth, visitedFolders: nextVisited)].compactMap { $0 }
                    : containerItems(inFolder: folder.id, depth: depth, visitedFolders: nextVisited)
                return Entry(order: folder.order, isHome: false, id: folder.id, values: values)
            }
            return (pageEntries + folderEntries)
                .sorted { lhs, rhs in
                    if isRoot, lhs.isHome != rhs.isHome { return lhs.isHome }
                    return lhs.order == rhs.order
                        ? lhs.id.uuidString < rhs.id.uuidString
                        : lhs.order < rhs.order
                }
                .flatMap(\.values)
        }

        func containerPageOrder(inFolder folderID: UUID?, visitedFolders: Set<UUID>) -> [Page] {
            struct Entry {
                let order: Int
                let isHome: Bool
                let id: UUID
                let pages: [Page]
            }
            let isRoot = folderID == nil
            let pageEntries = pages(inFolder: folderID).map { page in
                Entry(
                    order: page.order,
                    isHome: isRoot && page.slug == "index",
                    id: page.id,
                    pages: page.includeInNavigation
                        ? [page] + visiblePageOrder(from: page.id, visited: [page.id])
                        : visiblePageOrder(from: page.id, visited: [page.id])
                )
            }
            // Pages remain reachable whether their folder is a menu group or
            // promotes them in place, so both traverse identically.
            let folderEntries = folders(inFolder: folderID).compactMap { folder -> Entry? in
                guard !visitedFolders.contains(folder.id) else { return nil }
                return Entry(
                    order: folder.order,
                    isHome: false,
                    id: folder.id,
                    pages: containerPageOrder(inFolder: folder.id, visitedFolders: visitedFolders.union([folder.id]))
                )
            }
            return (pageEntries + folderEntries)
                .sorted { lhs, rhs in
                    if isRoot, lhs.isHome != rhs.isHome { return lhs.isHome }
                    return lhs.order == rhs.order
                        ? lhs.id.uuidString < rhs.id.uuidString
                        : lhs.order < rhs.order
                }
                .flatMap(\.pages)
        }

        let roots = containerItems(inFolder: nil, depth: 0, visitedFolders: [])
        let visiblePages = containerPageOrder(inFolder: nil, visitedFolders: [])
        // Every non-empty folder is addressable as a menu source, whether or
        // not it joins the site navigation itself.
        let folderGroups = site.pageFolders
            .sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
            .compactMap { folderItem($0, depth: 0, visitedFolders: [$0.id]) }
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
        let publishedAssets = site.assets.compactMap { asset -> PartPackageValue? in
            guard asset.exportDirectory != nil else { return nil }
            return assetValue(asset, site: site, rootPrefix: rootPrefix)
        }

        var result: [String: PartPackageValue] = [
            "navigation.items": .array(roots),
            "navigation.folders": .array(folderGroups),
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
        return result.merging(PartBreakpointTemplateValues.values(screens: site.theme.screens)) { current, _ in current }
    }

    private static func assetValue(_ asset: ProjectAsset, site: Site, rootPrefix: String) -> PartPackageValue {
        .object([
            "id": .string(asset.id.uuidString),
            "filename": .string(asset.filename),
            "href": .string(rootPrefix + site.publishedPath(for: asset)),
            "mediaType": .string(asset.mediaType),
            "width": asset.pixelWidth.map { .number(Double($0)) } ?? .number(0),
            "height": asset.pixelHeight.map { .number(Double($0)) } ?? .number(0),
            "isImage": .boolean(asset.mediaType.hasPrefix("image/"))
        ])
    }

    private static func isImage(_ value: PartPackageValue) -> Bool {
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
