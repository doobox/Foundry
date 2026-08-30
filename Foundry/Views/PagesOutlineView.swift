import AppKit
import SwiftUI

struct PagesOutlineView: NSViewRepresentable {
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let publishingChanges: [UUID: PublishingChange]
    @Binding var selectedPageID: UUID?
    @Binding var selectedFolderID: UUID?
    @Binding var selectedAssetID: UUID?
    let moveItem: (PageTreeItem, PageTreePlacement) -> Bool
    let importURLs: ([URL], PageTreePlacement) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .pageColumn)
        let outlineView = NSOutlineView()
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.selectionHighlightStyle = .regular
        outlineView.allowsMultipleSelection = false
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.registerForDraggedTypes([.pageTreeItem, .assetNode, .fileURL])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        context.coordinator.outlineView = outlineView
        context.coordinator.reload(
            pages: pages,
            folders: folders,
            assets: assets,
            selectedPageID: selectedPageID,
            selectedFolderID: selectedFolderID,
            selectedAssetID: selectedAssetID
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload(
            pages: pages,
            folders: folders,
            assets: assets,
            selectedPageID: selectedPageID,
            selectedFolderID: selectedFolderID,
            selectedAssetID: selectedAssetID
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: PagesOutlineView
        weak var outlineView: NSOutlineView?
        private var roots: [PageOutlineItem] = []
        private var itemsByID: [UUID: PageOutlineItem] = [:]
        private var displayedSignature: [String] = []
        private var isRestoringSelection = false

        init(parent: PagesOutlineView) {
            self.parent = parent
        }

        func reload(
            pages: [Page],
            folders: [PageFolder],
            assets: [ProjectAsset],
            selectedPageID: UUID?,
            selectedFolderID: UUID?,
            selectedAssetID: UUID?
        ) {
            let signature = pages.map { "p:\($0.id):\($0.folderID?.uuidString ?? "root"):\($0.order):\($0.title):\(parent.publishingChanges[$0.id]?.rawValue ?? "published")" }
                + folders.map { "f:\($0.id):\($0.parentID?.uuidString ?? "root"):\($0.order):\($0.name)" }
                + assets.compactMap { asset in
                    asset.exportDirectory.map { "a:\(asset.id):\($0):\(asset.exportOrder):\(asset.filename):\(parent.publishingChanges[asset.id]?.rawValue ?? "published")" }
                }
            if signature != displayedSignature {
                let expandedIDs = expandedFolderIDs()
                displayedSignature = signature
                rebuild(pages: pages, folders: folders, assets: assets)
                outlineView?.reloadData()
                for id in expandedIDs {
                    if let item = itemsByID[id] { outlineView?.expandItem(item) }
                }
            }
            restoreSelectionIfNeeded(
                pageID: selectedPageID,
                folderID: selectedFolderID,
                assetID: selectedAssetID
            )
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? PageOutlineItem else { return false }
            if case .folder = item.kind { return true }
            return false
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? PageOutlineItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier.pageCell
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? PageOutlineCell
                ?? makeCell(identifier: identifier)
            cell.textField?.stringValue = item.title
            cell.imageView?.image = NSImage(
                systemSymbolName: item.systemImage,
                accessibilityDescription: item.title
            )
            cell.statusField.stringValue = item.publishingChange?.title ?? ""
            cell.statusField.textColor = item.publishingChange == .new ? .systemBlue : .systemOrange
            cell.statusField.isHidden = item.publishingChange == nil
            cell.toolTip = item.publishingChange.map { "\($0.title) since the last successful publish" }
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRestoringSelection, let outlineView else { return }
            let row = outlineView.selectedRow
            guard row >= 0, let item = outlineView.item(atRow: row) as? PageOutlineItem else {
                parent.selectedFolderID = nil
                parent.selectedAssetID = nil
                return
            }
            if case .page(let id) = item.kind {
                parent.selectedPageID = id
                parent.selectedFolderID = nil
                parent.selectedAssetID = nil
            } else if case .folder(let id) = item.kind {
                parent.selectedFolderID = id
                parent.selectedAssetID = nil
            } else if case .asset(let id) = item.kind {
                parent.selectedFolderID = nil
                parent.selectedAssetID = id
            } else {
                parent.selectedFolderID = nil
                parent.selectedAssetID = nil
            }
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let item = item as? PageOutlineItem else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(item.payload, forType: .pageTreeItem)
            if item.isImageAsset {
                pasteboardItem.setString("foundry-image-asset:\(item.id.uuidString)", forType: .string)
            }
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard draggedItem(from: info) != nil || !fileURLs(from: info).isEmpty else { return [] }
            if index == NSOutlineViewDropOnItemIndex,
               (item as? PageOutlineItem)?.isFolder != true {
                return []
            }
            return draggedItem(from: info) == nil ? .copy : .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let placement = placement(parent: item as? PageOutlineItem, childIndex: index) else {
                return false
            }
            if let draggedItem = draggedItem(from: info) {
                return parent.moveItem(draggedItem, placement)
            }
            let urls = fileURLs(from: info)
            guard !urls.isEmpty else { return false }
            parent.importURLs(urls, placement)
            return true
        }

        private func rebuild(pages: [Page], folders: [PageFolder], assets: [ProjectAsset]) {
            itemsByID.removeAll(keepingCapacity: true)
            let pagesByParent = Dictionary(grouping: pages, by: \.folderID)
            let foldersByParent = Dictionary(grouping: folders, by: \.parentID)
            let assetsByParent = Dictionary(grouping: assets.compactMap { asset -> (UUID?, ProjectAsset)? in
                switch asset.exportDirectory {
                case .root: return (nil, asset)
                case .folder(let id): return (id, asset)
                case nil: return nil
                }
            }, by: { $0.0 })
            var visitedFolders = Set<UUID>()

            func children(parentID: UUID?) -> [PageOutlineItem] {
                let pageItems = (pagesByParent[parentID] ?? []).map {
                    PageOutlineItem(
                        kind: .page($0.id),
                        title: $0.title,
                        order: $0.order,
                        publishingChange: parent.publishingChanges[$0.id]
                    )
                }
                let folderItems = (foldersByParent[parentID] ?? []).compactMap { folder -> PageOutlineItem? in
                    guard visitedFolders.insert(folder.id).inserted else { return nil }
                    let item = PageOutlineItem(kind: .folder(folder.id), title: folder.name, order: folder.order)
                    item.children = children(parentID: folder.id)
                    item.publishingChange = Self.aggregateChange(in: item.children)
                    return item
                }
                let assetItems = (assetsByParent[parentID] ?? []).map {
                    PageOutlineItem(
                        kind: .asset($0.1.id), title: $0.1.filename, order: $0.1.exportOrder,
                        isImageAsset: $0.1.mediaType.hasPrefix("image/"),
                        publishingChange: parent.publishingChanges[$0.1.id]
                    )
                }
                return (pageItems + folderItems + assetItems).sorted(by: PageOutlineItem.sort)
            }

            roots = children(parentID: nil)
            func index(_ items: [PageOutlineItem]) {
                for item in items {
                    itemsByID[item.id] = item
                    index(item.children)
                }
            }
            index(roots)
        }

        private func placement(parent item: PageOutlineItem?, childIndex index: Int) -> PageTreePlacement? {
            let siblings = item?.children ?? roots
            if index == NSOutlineViewDropOnItemIndex {
                guard let item, case .folder(let id) = item.kind else { return nil }
                return .insideFolder(id)
            }
            if siblings.indices.contains(index) {
                return .before(siblings[index].kind)
            }
            let parentFolderID: UUID?
            if let item, case .folder(let id) = item.kind {
                parentFolderID = id
            } else {
                parentFolderID = nil
            }
            return .end(parentFolderID: parentFolderID)
        }

        private func draggedItem(from info: any NSDraggingInfo) -> PageTreeItem? {
            if let assetValue = info.draggingPasteboard.string(forType: .assetNode),
               assetValue.hasPrefix("foundry-asset-node:"),
               let id = UUID(uuidString: String(assetValue.dropFirst("foundry-asset-node:".count))) {
                return .asset(id)
            }
            guard let value = info.draggingPasteboard.string(forType: .pageTreeItem) else { return nil }
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
            switch parts[0] {
            case "page": return .page(id)
            case "folder": return .folder(id)
            case "asset": return .asset(id)
            default: return nil
            }
        }

        private func fileURLs(from info: any NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
            return objects.compactMap { ($0 as? NSURL).map { $0 as URL } }
        }

        private func children(of item: Any?) -> [PageOutlineItem] {
            (item as? PageOutlineItem)?.children ?? roots
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> PageOutlineCell {
            let cell = PageOutlineCell()
            cell.identifier = identifier
            let imageView = NSImageView()
            imageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            let textField = NSTextField(labelWithString: "")
            let statusField = cell.statusField
            statusField.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            statusField.alignment = .right
            textField.lineBreakMode = .byTruncatingTail
            imageView.translatesAutoresizingMaskIntoConstraints = false
            textField.translatesAutoresizingMaskIntoConstraints = false
            statusField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.addSubview(statusField)
            cell.imageView = imageView
            cell.textField = textField
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: statusField.leadingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                statusField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                statusField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private static func aggregateChange(in items: [PageOutlineItem]) -> PublishingChange? {
            if items.contains(where: { $0.publishingChange == .new }) { return .new }
            if items.contains(where: { $0.publishingChange == .modified }) { return .modified }
            return nil
        }

        private func expandedFolderIDs() -> Set<UUID> {
            guard let outlineView else { return [] }
            return Set(itemsByID.values.compactMap {
                $0.isFolder && outlineView.isItemExpanded($0) ? $0.id : nil
            })
        }

        private func restoreSelectionIfNeeded(
            pageID selectedPageID: UUID?,
            folderID selectedFolderID: UUID?,
            assetID selectedAssetID: UUID?
        ) {
            guard let outlineView else { return }
            let selectedItem = outlineView.selectedRow >= 0
                ? outlineView.item(atRow: outlineView.selectedRow) as? PageOutlineItem
                : nil
            let requestedItem: PageTreeItem? = selectedFolderID.map(PageTreeItem.folder)
                ?? selectedAssetID.map(PageTreeItem.asset)
                ?? selectedPageID.map(PageTreeItem.page)
            guard selectedItem?.kind != requestedItem else { return }

            isRestoringSelection = true
            defer { isRestoringSelection = false }
            guard let requestedItem, let item = itemsByID[requestedItem.id] else {
                outlineView.deselectAll(nil)
                return
            }
            expandAncestors(of: item.id, in: roots)
            let row = outlineView.row(forItem: item)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }

        @discardableResult
        private func expandAncestors(of id: UUID, in items: [PageOutlineItem]) -> Bool {
            for item in items {
                if item.id == id { return true }
                if expandAncestors(of: id, in: item.children) {
                    outlineView?.expandItem(item)
                    return true
                }
            }
            return false
        }
    }
}

private final class PageOutlineItem: NSObject {
    let kind: PageTreeItem
    let title: String
    let order: Int
    let isImageAsset: Bool
    var publishingChange: PublishingChange?
    var children: [PageOutlineItem] = []
    var id: UUID { kind.id }
    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }
    var payload: String {
        switch kind {
        case .page(let id): "page:\(id.uuidString)"
        case .folder(let id): "folder:\(id.uuidString)"
        case .asset(let id): "asset:\(id.uuidString)"
        }
    }
    var systemImage: String {
        switch kind {
        case .page: "doc"
        case .folder: "folder"
        case .asset: isImageAsset ? "photo" : "doc.richtext"
        }
    }

    init(
        kind: PageTreeItem,
        title: String,
        order: Int,
        isImageAsset: Bool = false,
        publishingChange: PublishingChange? = nil
    ) {
        self.kind = kind
        self.title = title
        self.order = order
        self.isImageAsset = isImageAsset
        self.publishingChange = publishingChange
    }

    static func sort(_ lhs: PageOutlineItem, _ rhs: PageOutlineItem) -> Bool {
        lhs.order == rhs.order ? lhs.id.uuidString < rhs.id.uuidString : lhs.order < rhs.order
    }
}

private final class PageOutlineCell: NSTableCellView {
    let statusField = NSTextField(labelWithString: "")
}

private extension NSPasteboard.PasteboardType {
    static let pageTreeItem = NSPasteboard.PasteboardType("uk.co.garysimpson.foundry.page-tree-item")
}

private extension NSUserInterfaceItemIdentifier {
    static let pageColumn = NSUserInterfaceItemIdentifier("PagesColumn")
    static let pageCell = NSUserInterfaceItemIdentifier("PagesCell")
}
