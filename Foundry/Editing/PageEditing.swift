import Foundation

enum PageTreeItem: Equatable, Sendable {
    case page(UUID)
    case folder(UUID)
    case asset(UUID)

    var id: UUID {
        switch self {
        case .page(let id), .folder(let id), .asset(let id): id
        }
    }
}

enum PageTreePlacement: Equatable, Sendable {
    case before(PageTreeItem)
    case insideFolder(UUID)
    case insidePage(UUID)
    case end(parentFolderID: UUID?)
    case endPage(UUID)
}

private enum PageTreeParent: Equatable {
    case root
    case folder(UUID)
    case page(UUID)
}

@MainActor
extension ProjectEditor {
    @discardableResult
    func addPageFolder(named name: String) -> UUID {
        let folder = PageFolder(
            name: name,
            slug: name,
            order: childItems(of: .root).count
        )
        mutate(actionName: "Add Page Folder") { $0.pageFolders.append(folder) }
        return folder.id
    }

    func renamePageFolder(id: UUID, name: String) {
        mutate(actionName: "Rename Page Folder") { site in
            guard let index = site.pageFolders.firstIndex(where: { $0.id == id }) else { return }
            site.pageFolders[index].name = name
        }
    }

    func setPageFolderIncludeInNavigation(id: UUID, value: Bool) {
        mutate(actionName: "Edit Folder Navigation") { site in
            guard let index = site.pageFolders.firstIndex(where: { $0.id == id }) else { return }
            site.pageFolders[index].includeInNavigation = value
        }
    }

    func removePageFolder(id: UUID, includingContents: Bool = false) {
        let item = PageTreeItem.folder(id)
        guard document.site.pageFolders.contains(where: { $0.id == id }) else { return }
        let folderParent = parent(of: item)
        var replacementSiblings = childItems(of: folderParent)
        guard let folderIndex = replacementSiblings.firstIndex(of: item) else { return }
        if includingContents {
            replacementSiblings.remove(at: folderIndex)
        } else {
            replacementSiblings.replaceSubrange(
                folderIndex...folderIndex,
                with: childItems(of: .folder(id))
            )
        }

        var removedFolderIDs: Set<UUID> = [id]
        var removedPageIDs = Set<UUID>()
        if includingContents {
            var foundAnotherLevel = true
            while foundAnotherLevel {
                foundAnotherLevel = false
                for folder in document.site.pageFolders where
                    folder.parentID.map(removedFolderIDs.contains) == true
                    && removedFolderIDs.insert(folder.id).inserted {
                    foundAnotherLevel = true
                }
            }

            removedPageIDs = Set(document.site.pages.compactMap { page in
                page.folderID.map(removedFolderIDs.contains) == true ? page.id : nil
            })
            foundAnotherLevel = true
            while foundAnotherLevel {
                foundAnotherLevel = false
                for page in document.site.pages where
                    page.parentPageID.map(removedPageIDs.contains) == true
                    && removedPageIDs.insert(page.id).inserted {
                    foundAnotherLevel = true
                }
            }
        }

        mutate(actionName: includingContents ? "Delete Page Folder and Contents" : "Delete Page Folder") { site in
            site.pageFolders.removeAll(where: { removedFolderIDs.contains($0.id) })
            site.pages.removeAll(where: { removedPageIDs.contains($0.id) })
            if includingContents {
                for asset in site.assets {
                    guard case .folder(let folderID) = asset.exportDirectory,
                          removedFolderIDs.contains(folderID) else { continue }
                    _ = site.assetLibrary.clearExportDirectory(forAssetID: asset.id)
                }
            }
            site.applyPageTreeOrder(replacementSiblings, parent: folderParent)
        }
    }

    func setPageFolderSlug(id: UUID, slug: String) {
        let normalized = Page.slugify(slug)
        mutate(actionName: "Edit Folder URL Name") { site in
            guard let index = site.pageFolders.firstIndex(where: { $0.id == id }) else { return }
            site.pageFolders[index].slug = normalized
        }
    }

    @discardableResult
    func addPage() -> UUID {
        let title = "Page \(document.site.pages.count + 1)"
        let page = Page(
            title: title,
            slug: uniqueSlug(for: title),
            order: childItems(of: .root).count,
            preferredExtension: document.site.defaultPageExtension
        )
        mutate(actionName: "Add Page") { $0.pages.append(page) }
        return page.id
    }

    @discardableResult
    func duplicatePage(id: UUID) -> UUID? {
        guard let source = document.site.pages.first(where: { $0.id == id }) else {
            return nil
        }
        let page = source.duplicated(
            title: "\(source.title) Copy",
            slug: uniqueSlug(for: source.slug)
        )
        mutate(actionName: "Duplicate Page") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else {
                return
            }
            site.pages.insert(page, at: index + 1)
        }
        return page.id
    }

    @discardableResult
    func removePage(id: UUID, includingSubpages: Bool = false) -> UUID? {
        guard document.site.pages.count > 1,
              let index = document.site.pages.firstIndex(where: { $0.id == id }),
              document.site.pages[index].slug != "index" else {
            return nil
        }
        var removedIDs: Set<UUID> = [id]
        if includingSubpages {
            var foundAnotherLevel = true
            while foundAnotherLevel {
                foundAnotherLevel = false
                for page in document.site.pages where
                    page.parentPageID.map(removedIDs.contains) == true
                    && removedIDs.insert(page.id).inserted {
                    foundAnotherLevel = true
                }
            }
        }
        let remainingPages = document.site.pages.enumerated()
            .filter { !removedIDs.contains($0.element.id) }
            .map(\.element)
        guard !remainingPages.isEmpty else { return nil }
        let parentPageID = document.site.pages[index].parentPageID
        let nextPageID = parentPageID.flatMap { parentID in
            remainingPages.first(where: { $0.id == parentID })?.id
        } ?? remainingPages[min(index, remainingPages.count - 1)].id

        let deletedItem = PageTreeItem.page(id)
        let deletedParent = parent(of: deletedItem)
        var replacementSiblings = childItems(of: deletedParent)
        if let deletedIndex = replacementSiblings.firstIndex(of: deletedItem) {
            if includingSubpages {
                replacementSiblings.remove(at: deletedIndex)
            } else {
                replacementSiblings.replaceSubrange(
                    deletedIndex...deletedIndex,
                    with: childItems(of: .page(id))
                )
            }
        }

        mutate(actionName: includingSubpages ? "Delete Page and Subpages" : "Delete Page") { site in
            site.pages.removeAll(where: { removedIDs.contains($0.id) })
            site.applyPageTreeOrder(replacementSiblings, parent: deletedParent)
        }
        return nextPageID
    }

    func renamePage(id: UUID, title: String) {
        mutate(actionName: "Rename Page") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else {
                return
            }
            site.pages[index].title = title
        }
    }

    func setPageIncludedInNavigation(id: UUID, included: Bool) {
        mutate(actionName: "Change Page Navigation Visibility") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else { return }
            site.pages[index].includeInNavigation = included
        }
    }

    func renamePageFromOutline(id: UUID, title: String) {
        guard let page = document.site.pages.first(where: { $0.id == id }) else { return }
        let slug = page.slug == "index"
            ? "index"
            : uniqueSlug(for: title, excluding: id)
        mutate(actionName: "Rename Page") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else { return }
            site.pages[index].title = title
            site.pages[index].slug = slug
        }
    }

    /// Stores the page's folder override and returns the normalized value the
    /// field should display; nil clears the override (empty input) or means
    /// the page is the home page, which always publishes at the root.
    @discardableResult
    func setPageFolderOverride(id: UUID, value: String) -> String? {
        guard document.site.pages.first(where: { $0.id == id })?.slug != "index" else { return nil }
        let normalized = Self.normalizedFolderOverride(value)
        mutate(actionName: "Edit Page Folder") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else { return }
            site.pages[index].folderOverride = normalized
        }
        return normalized
    }

    /// Slash-separated segments, each slugified; segments with no letters or
    /// numbers drop. "/" alone normalizes to the empty string — the site root.
    static func normalizedFolderOverride(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .split(separator: "/")
            .filter { $0.rangeOfCharacter(from: .alphanumerics) != nil }
            .map { Page.slugify(String($0)) }
            .joined(separator: "/")
    }

    /// Stores the page's filename override and returns the normalized value
    /// the field should display; nil restores the standard `index` filename.
    @discardableResult
    func setPageFilename(id: UUID, value: String) -> String? {
        guard document.site.pages.first(where: { $0.id == id })?.slug != "index" else { return nil }
        let normalized = Self.normalizedFilenameOverride(value)
        mutate(actionName: "Edit Page Filename") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else { return }
            site.pages[index].filenameOverride = normalized
        }
        return normalized
    }

    /// A slugified base name plus an optional explicit html/php extension;
    /// other extensions drop so the page's normal extension rules decide.
    static func normalizedFilenameOverride(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let declared = (trimmed as NSString).pathExtension
        let base = Page.slugify((trimmed as NSString).deletingPathExtension)
        let result = ["html", "php"].contains(declared) ? "\(base).\(declared)" : base
        return result == "index" ? nil : result
    }

    func setPageLanguage(id: UUID, language: String?) {
        mutate(actionName: "Edit Page Language") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else { return }
            site.pages[index].language = language
        }
    }

    func setPageIncludedInSearch(id: UUID, included: Bool) {
        mutate(actionName: included ? "Include Page in Search" : "Exclude Page from Search") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else { return }
            site.pages[index].includeInSearch = included
        }
    }

    func setPageIncludedInSitemap(id: UUID, included: Bool) {
        mutate(actionName: included ? "Include Page in Sitemap" : "Exclude Page from Sitemap") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else { return }
            site.pages[index].includeInSitemap = included
        }
    }

    func setPageSlug(id: UUID, slug: String) {
        guard document.site.pages.first(where: { $0.id == id })?.slug != "index" else {
            return
        }
        let normalized = uniqueSlug(for: slug, excluding: id)
        mutate(actionName: "Edit Page URL Name") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else {
                return
            }
            site.pages[index].slug = normalized
        }
    }

    func setHomePage(id: UUID) {
        guard let target = document.site.pages.first(where: { $0.id == id }),
              target.folderID == nil,
              target.parentPageID == nil,
              target.slug != "index" else { return }
        let previousSlug = target.slug
        let targetItem = PageTreeItem.page(id)
        let promotedChildren = childItems(of: .page(id))
        let reorderedRootItems = [targetItem]
            + promotedChildren
            + childItems(of: .root).filter { $0 != targetItem }
        mutate(actionName: "Set Home Page") { site in
            guard let targetIndex = site.pages.firstIndex(where: { $0.id == id }) else { return }
            if let homeIndex = site.pages.firstIndex(where: { $0.slug == "index" }),
               homeIndex != targetIndex {
                site.pages[homeIndex].slug = previousSlug
            }
            site.pages[targetIndex].slug = "index"
            site.applyPageTreeOrder(reorderedRootItems, parent: .root)
        }
    }

    func setPageMetadata(id: UUID, _ update: (inout PageMetadata) -> Void) {
        mutate(actionName: "Edit Page Metadata") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else {
                return
            }
            update(&site.pages[index].metadata)
        }
    }

    func setPageBackground(id: UUID, value: PartPackageColorValue?) {
        mutate(actionName: value == nil ? "Reset Page Background" : "Change Page Background", impact: .page) { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else { return }
            site.pages[index].backgroundOverride = value
        }
    }

    func movePage(id: UUID, offset: Int) {
        let item = PageTreeItem.page(id)
        guard document.site.pages.first(where: { $0.id == id })?.slug != "index" else {
            return
        }
        let itemParent = parent(of: item)
        let siblings = childItems(of: itemParent)
        guard let sourceIndex = siblings.firstIndex(of: item) else { return }
        let destinationIndex = sourceIndex + offset
        guard siblings.indices.contains(destinationIndex) else { return }
        let placement: PageTreePlacement
        if offset < 0 {
            placement = .before(siblings[destinationIndex])
        } else if siblings.indices.contains(destinationIndex + 1) {
            placement = .before(siblings[destinationIndex + 1])
        } else {
            switch itemParent {
            case .root: placement = .end(parentFolderID: nil)
            case .folder(let id): placement = .end(parentFolderID: id)
            case .page(let id): placement = .endPage(id)
            }
        }
        _ = movePageTreeItem(item, to: placement)
    }

    @discardableResult
    func movePageTreeItem(_ item: PageTreeItem, to placement: PageTreePlacement) -> Bool {
        if case .asset(let id) = item,
           !document.site.assets.contains(where: { $0.id == id }) {
            return false
        }
        if case .page(let id) = item,
           document.site.pages.first(where: { $0.id == id })?.slug == "index" {
            return false
        }
        let destinationParent: PageTreeParent
        switch placement {
        case .before(let destination):
            destinationParent = parent(of: destination)
        case .insideFolder(let folderID):
            destinationParent = .folder(folderID)
        case .insidePage(let pageID), .endPage(let pageID):
            destinationParent = .page(pageID)
        case .end(let parentFolderID):
            destinationParent = parentFolderID.map(PageTreeParent.folder) ?? .root
        }

        if destinationParent == .root,
           case .before(.page(let destinationID)) = placement,
           document.site.pages.first(where: { $0.id == destinationID })?.slug == "index" {
            return false
        }

        if case .folder(let folderID) = item {
            switch destinationParent {
            case .page:
                return false
            case .folder(let destinationFolderID)
                where destinationFolderID == folderID
                    || isFolder(destinationFolderID, descendantOf: folderID):
                return false
            case .root, .folder:
                break
            }
        }

        if case .page(let pageID) = item,
           case .page(let destinationPageID) = destinationParent {
            guard pageID != destinationPageID,
                  !isPage(destinationPageID, descendantOf: pageID),
                  document.site.pages.first(where: { $0.id == destinationPageID })?.slug != "index" else {
                return false
            }
        }

        if case .page = destinationParent,
           case .page = item {
            // Pages are the only tree items that may be nested under another page.
        } else if case .page = destinationParent {
            return false
        }

        var destinationItems = childItems(of: destinationParent).filter { $0 != item }
        let destinationIndex: Int
        switch placement {
        case .before(let destination):
            guard let index = destinationItems.firstIndex(of: destination) else { return false }
            destinationIndex = index
        case .insideFolder, .insidePage, .end, .endPage:
            destinationIndex = destinationItems.endIndex
        }
        destinationItems.insert(item, at: destinationIndex)

        if destinationParent == .root,
           let homeID = document.site.pages.first(where: { $0.slug == "index" })?.id {
            let homeItem = PageTreeItem.page(homeID)
            destinationItems = [homeItem] + destinationItems.filter { $0 != homeItem }
        }

        let sourceParent = parent(of: item)
        let sourceItems = sourceParent == destinationParent
            ? destinationItems
            : childItems(of: sourceParent).filter { $0 != item }

        mutate(actionName: "Move Page Item") { site in
            if case .asset(let id) = item {
                let directory: ProjectAsset.ExportDirectory
                switch destinationParent {
                case .root: directory = .root
                case .folder(let id): directory = .folder(id)
                case .page: return
                }
                guard site.assetLibrary.setExportDirectory(directory, forAssetID: id) else { return }
            }
            site.applyPageTreeOrder(sourceItems, parent: sourceParent)
            if sourceParent != destinationParent {
                site.applyPageTreeOrder(destinationItems, parent: destinationParent)
            }
        }
        return true
    }

    private func childItems(of parent: PageTreeParent) -> [PageTreeItem] {
        let pages = document.site.pages
            .filter { page in
                switch parent {
                case .root: page.folderID == nil && page.parentPageID == nil
                case .folder(let id): page.folderID == id && page.parentPageID == nil
                case .page(let id): page.parentPageID == id
                }
            }
            .map { (PageTreeItem.page($0.id), $0.order) }
        let folders = document.site.pageFolders
            .filter { folder in
                switch parent {
                case .root: folder.parentID == nil
                case .folder(let id): folder.parentID == id
                case .page: false
                }
            }
            .map { (PageTreeItem.folder($0.id), $0.order) }
        let assets = document.site.assets.compactMap { asset -> (PageTreeItem, Int)? in
            switch (parent, asset.exportDirectory) {
            case (.root, .root):
                return (.asset(asset.id), asset.exportOrder)
            case (.folder(let parentID), .folder(let folderID)) where folderID == parentID:
                return (.asset(asset.id), asset.exportOrder)
            default:
                return nil
            }
        }
        let homeID = parent == .root
            ? document.site.pages.first(where: { $0.slug == "index" })?.id
            : nil
        return (pages + folders + assets)
            .sorted { lhs, rhs in
                let lhsIsHome = lhs.0.id == homeID
                let rhsIsHome = rhs.0.id == homeID
                if lhsIsHome != rhsIsHome { return lhsIsHome }
                return lhs.1 == rhs.1
                    ? lhs.0.id.uuidString < rhs.0.id.uuidString
                    : lhs.1 < rhs.1
            }
            .map(\.0)
    }

    private func parent(of item: PageTreeItem) -> PageTreeParent {
        switch item {
        case .page(let id):
            guard let page = document.site.pages.first(where: { $0.id == id }) else { return .root }
            if let parentPageID = page.parentPageID { return .page(parentPageID) }
            if let folderID = page.folderID { return .folder(folderID) }
            return .root
        case .folder(let id):
            return document.site.pageFolders.first { $0.id == id }?.parentID.map(PageTreeParent.folder) ?? .root
        case .asset(let id):
            switch document.site.assets.first(where: { $0.id == id })?.exportDirectory {
            case .folder(let folderID): return .folder(folderID)
            default: return .root
            }
        }
    }

    private func isFolder(_ candidateID: UUID, descendantOf folderID: UUID) -> Bool {
        var currentID: UUID? = candidateID
        while let id = currentID {
            if id == folderID { return true }
            currentID = document.site.pageFolders.first { $0.id == id }?.parentID
        }
        return false
    }

    private func isPage(_ candidateID: UUID, descendantOf pageID: UUID) -> Bool {
        var currentID: UUID? = candidateID
        var visited = Set<UUID>()
        while let id = currentID, visited.insert(id).inserted {
            if id == pageID { return true }
            currentID = document.site.pages.first { $0.id == id }?.parentPageID
        }
        return false
    }

    private func uniqueSlug(for value: String, excluding pageID: UUID? = nil) -> String {
        let base = Page.slugify(value)
        let used = Set(
            document.site.pages
                .filter { $0.id != pageID }
                .map(\.slug)
        )
        guard used.contains(base) else {
            return base
        }

        var suffix = 2
        while used.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }
}

private extension Site {
    mutating func applyPageTreeOrder(_ items: [PageTreeItem], parent: PageTreeParent) {
        for (order, item) in items.enumerated() {
            switch item {
            case .page(let id):
                guard let index = pages.firstIndex(where: { $0.id == id }) else { continue }
                switch parent {
                case .root:
                    pages[index].folderID = nil
                    pages[index].parentPageID = nil
                case .folder(let parentID):
                    pages[index].folderID = parentID
                    pages[index].parentPageID = nil
                case .page(let parentID):
                    pages[index].folderID = nil
                    pages[index].parentPageID = parentID
                }
                pages[index].order = order
            case .folder(let id):
                guard let index = pageFolders.firstIndex(where: { $0.id == id }) else { continue }
                switch parent {
                case .root: pageFolders[index].parentID = nil
                case .folder(let parentID): pageFolders[index].parentID = parentID
                case .page: continue
                }
                pageFolders[index].order = order
            case .asset(let id):
                let directory: ProjectAsset.ExportDirectory
                switch parent {
                case .root: directory = .root
                case .folder(let parentID): directory = .folder(parentID)
                case .page: continue
                }
                _ = assetLibrary.setExportDirectory(directory, order: order, forAssetID: id)
            }
        }
    }
}

private extension Array where Element == ProjectAssetNode {
    mutating func setExportDirectory(
        _ directory: ProjectAsset.ExportDirectory,
        order: Int? = nil,
        forAssetID id: UUID
    ) -> Bool {
        for index in indices {
            switch self[index] {
            case .asset(var asset) where asset.id == id:
                asset.exportDirectory = directory
                if let order { asset.exportOrder = order }
                self[index] = .asset(asset)
                return true
            case .folder(var folder):
                if folder.children.setExportDirectory(directory, order: order, forAssetID: id) {
                    self[index] = .folder(folder)
                    return true
                }
            case .asset:
                continue
            }
        }
        return false
    }
}
