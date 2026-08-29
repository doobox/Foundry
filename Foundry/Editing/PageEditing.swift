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
    case end(parentFolderID: UUID?)
}

@MainActor
extension ProjectEditor {
    @discardableResult
    func addPageFolder(named name: String) -> UUID {
        let folder = PageFolder(
            name: name,
            slug: name,
            order: childItems(of: nil).count
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

    func setPageFolderSlug(id: UUID, slug: String) {
        let normalized = Page.slugify(slug)
        mutate(actionName: "Edit Page Folder Slug") { site in
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
            order: childItems(of: nil).count
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
    func removePage(id: UUID) -> UUID? {
        guard document.site.pages.count > 1,
              let index = document.site.pages.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let remainingPages = document.site.pages.enumerated()
            .filter { $0.offset != index }
            .map(\.element)
        let nextPageID = remainingPages[min(index, remainingPages.count - 1)].id

        mutate(actionName: "Delete Page") { site in
            site.pages.removeAll(where: { $0.id == id })
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

    func setPageSlug(id: UUID, slug: String) {
        let normalized = uniqueSlug(for: slug, excluding: id)
        mutate(actionName: "Edit Page Slug") { site in
            guard let index = site.pages.firstIndex(where: { $0.id == id }) else {
                return
            }
            site.pages[index].slug = normalized
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

    func movePage(id: UUID, offset: Int) {
        guard let source = document.site.pages.firstIndex(where: { $0.id == id }) else {
            return
        }
        let destination = source + offset
        guard document.site.pages.indices.contains(destination) else {
            return
        }
        mutate(actionName: "Move Page") { site in
            let page = site.pages.remove(at: source)
            site.pages.insert(page, at: destination)
        }
    }

    @discardableResult
    func movePageTreeItem(_ item: PageTreeItem, to placement: PageTreePlacement) -> Bool {
        if case .asset(let id) = item,
           !document.site.assets.contains(where: { $0.id == id }) {
            return false
        }
        let destinationParentID: UUID?
        switch placement {
        case .before(let destination):
            destinationParentID = parentID(of: destination)
        case .insideFolder(let folderID):
            destinationParentID = folderID
        case .end(let parentFolderID):
            destinationParentID = parentFolderID
        }

        if case .folder(let folderID) = item {
            guard destinationParentID != folderID,
                  destinationParentID.map({ !isFolder($0, descendantOf: folderID) }) ?? true else {
                return false
            }
        }

        var destinationItems = childItems(of: destinationParentID).filter { $0 != item }
        let destinationIndex: Int
        switch placement {
        case .before(let destination):
            guard let index = destinationItems.firstIndex(of: destination) else { return false }
            destinationIndex = index
        case .insideFolder, .end:
            destinationIndex = destinationItems.endIndex
        }
        destinationItems.insert(item, at: destinationIndex)

        let sourceParentID = parentID(of: item)
        let sourceItems = sourceParentID == destinationParentID
            ? destinationItems
            : childItems(of: sourceParentID).filter { $0 != item }

        mutate(actionName: "Move Page Item") { site in
            if case .asset(let id) = item {
                let directory: ProjectAsset.ExportDirectory = destinationParentID.map {
                    .folder($0)
                } ?? .root
                guard site.assetLibrary.setExportDirectory(directory, forAssetID: id) else { return }
            }
            site.applyPageTreeOrder(sourceItems, parentID: sourceParentID)
            if sourceParentID != destinationParentID {
                site.applyPageTreeOrder(destinationItems, parentID: destinationParentID)
            }
        }
        return true
    }

    private func childItems(of parentID: UUID?) -> [PageTreeItem] {
        let pages = document.site.pages
            .filter { $0.folderID == parentID }
            .map { (PageTreeItem.page($0.id), $0.order) }
        let folders = document.site.pageFolders
            .filter { $0.parentID == parentID }
            .map { (PageTreeItem.folder($0.id), $0.order) }
        let assets = document.site.assets.compactMap { asset -> (PageTreeItem, Int)? in
            switch asset.exportDirectory {
            case .root where parentID == nil:
                return (.asset(asset.id), asset.exportOrder)
            case .folder(let folderID) where folderID == parentID:
                return (.asset(asset.id), asset.exportOrder)
            default:
                return nil
            }
        }
        return (pages + folders + assets)
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0.id.uuidString < rhs.0.id.uuidString : lhs.1 < rhs.1
            }
            .map(\.0)
    }

    private func parentID(of item: PageTreeItem) -> UUID? {
        switch item {
        case .page(let id): document.site.pages.first { $0.id == id }?.folderID
        case .folder(let id): document.site.pageFolders.first { $0.id == id }?.parentID
        case .asset(let id):
            switch document.site.assets.first(where: { $0.id == id })?.exportDirectory {
            case .folder(let folderID): folderID
            default: nil
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
    mutating func applyPageTreeOrder(_ items: [PageTreeItem], parentID: UUID?) {
        for (order, item) in items.enumerated() {
            switch item {
            case .page(let id):
                guard let index = pages.firstIndex(where: { $0.id == id }) else { continue }
                pages[index].folderID = parentID
                pages[index].order = order
            case .folder(let id):
                guard let index = pageFolders.firstIndex(where: { $0.id == id }) else { continue }
                pageFolders[index].parentID = parentID
                pageFolders[index].order = order
            case .asset(let id):
                let directory: ProjectAsset.ExportDirectory = parentID.map { .folder($0) } ?? .root
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
