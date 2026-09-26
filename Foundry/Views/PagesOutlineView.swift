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
    @Binding var expandedItemIDs: Set<UUID>
    let addPage: (PageTreePlacement?) -> Void
    let requestAddFolder: (PageTreePlacement?) -> Void
    let renameFolder: (UUID, String) -> Void
    let requestDeleteFolder: (UUID) -> Void
    let duplicatePage: (UUID) -> Void
    let renamePage: (UUID, String) -> Void
    let deletePage: (UUID) -> Void
    let movePage: (UUID, Int) -> Void
    let setHomePage: (UUID) -> Void
    let moveItem: (PageTreeItem, PageTreePlacement) -> Bool
    let importURLs: ([URL], PageTreePlacement) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .pageColumn)
        let outlineView = PagesNativeOutlineView()
        outlineView.handleKeyEvent = context.coordinator.handleKeyEvent
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.selectionHighlightStyle = .regular
        outlineView.backgroundColor = .clear
        outlineView.allowsMultipleSelection = false
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        let contextMenu = NSMenu()
        contextMenu.delegate = context.coordinator
        outlineView.menu = contextMenu
        outlineView.registerForDraggedTypes([.pageTreeItem, .assetNode, .fileURL])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
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
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
        var parent: PagesOutlineView
        weak var outlineView: NSOutlineView?
        private var roots: [PageOutlineItem] = []
        private var itemsByID: [UUID: PageOutlineItem] = [:]
        private var displayedSignature: [String] = []
        private var isRestoringSelection = false
        private var isRestoringExpansion = false

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
            let signature = pages.map { "p:\($0.id):\($0.folderID?.uuidString ?? "root"):\($0.parentPageID?.uuidString ?? "root"):\($0.order):\($0.title):\($0.slug):\(parent.publishingChanges[$0.id]?.rawValue ?? "published")" }
                + folders.map { "f:\($0.id):\($0.parentID?.uuidString ?? "root"):\($0.order):\($0.name)" }
                + assets.compactMap { asset in
                    asset.exportDirectory.map { "a:\(asset.id):\($0):\(asset.exportOrder):\(asset.filename):\(parent.publishingChanges[asset.id]?.rawValue ?? "published")" }
                }
            if signature != displayedSignature {
                let expandedIDs = parent.expandedItemIDs.union(expandedItemIDs())
                displayedSignature = signature
                rebuild(pages: pages, folders: folders, assets: assets)
                outlineView?.reloadData()
                isRestoringExpansion = true
                for id in expandedIDs {
                    if let item = itemsByID[id] { outlineView?.expandItem(item) }
                }
                isRestoringExpansion = false
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
            return !item.children.isEmpty
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? PageOutlineItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier.pageCell
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? PageOutlineCell
                ?? makeCell(identifier: identifier)
            cell.textField?.stringValue = item.title
            cell.textField?.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
            cell.textField?.delegate = self
            cell.textField?.isEditable = item.isPage || item.isFolder
            cell.textField?.isSelectable = item.isPage || item.isFolder
            cell.imageView?.image = NSImage(
                systemSymbolName: item.systemImage,
                accessibilityDescription: item.title
            )
            cell.statusField.stringValue = item.publishingChange == nil ? "" : "●"
            cell.statusField.textColor = .systemBlue
            cell.statusField.isHidden = item.publishingChange == nil
            cell.toolTip = item.publishingChange.map { _ in "Changes awaiting publication" }
            return cell
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView else { return }
            let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
            let item = row >= 0 ? outlineView.item(atRow: row) as? PageOutlineItem : nil
            if let item {
                selectForContextAction(item)
            }

            menu.addItem(menuItem(
                "New Page",
                action: #selector(addPageFromContextMenu(_:)),
                item: item,
                key: "n",
                modifiers: [.command, .option]
            ))
            menu.addItem(menuItem(
                "New Folder…",
                action: #selector(addFolderFromContextMenu(_:)),
                item: item,
                key: "n",
                modifiers: [.command, .shift]
            ))

            guard let item, item.isPage || item.isFolder else { return }
            menu.addItem(.separator())
            menu.addItem(menuItem(
                "Rename",
                action: #selector(renameFromContextMenu(_:)),
                item: item,
                key: "\r",
                modifiers: []
            ))
            if item.isFolder {
                menu.addItem(.separator())
                menu.addItem(menuItem(
                    "Delete Folder…",
                    action: #selector(deleteFolderFromContextMenu(_:)),
                    item: item,
                    key: String(Character(UnicodeScalar(NSDeleteCharacter)!)),
                    modifiers: []
                ))
                return
            }

            menu.addItem(menuItem("Duplicate", action: #selector(duplicateFromContextMenu(_:)), item: item, key: "d"))
            if item.isTopLevelPage {
                let setHome = menuItem(
                    "Set as Homepage",
                    action: #selector(setHomeFromContextMenu(_:)),
                    item: item
                )
                setHome.state = item.isHome ? .on : .off
                setHome.isEnabled = !item.isHome
                menu.addItem(setHome)
            }
            menu.addItem(.separator())
            let moveUp = menuItem(
                "Move Up",
                action: #selector(moveUpFromContextMenu(_:)),
                item: item,
                key: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
                modifiers: [.command, .option]
            )
            moveUp.isEnabled = canMove(item, offset: -1)
            menu.addItem(moveUp)
            let moveDown = menuItem(
                "Move Down",
                action: #selector(moveDownFromContextMenu(_:)),
                item: item,
                key: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)),
                modifiers: [.command, .option]
            )
            moveDown.isEnabled = canMove(item, offset: 1)
            menu.addItem(moveDown)
            menu.addItem(.separator())
            let delete = menuItem(
                "Delete",
                action: #selector(deleteFromContextMenu(_:)),
                item: item,
                key: String(Character(UnicodeScalar(NSDeleteCharacter)!)),
                modifiers: []
            )
            delete.isEnabled = !item.isHome
            menu.addItem(delete)
        }

        private func menuItem(
            _ title: String,
            action: Selector,
            item: PageOutlineItem? = nil,
            key: String = "",
            modifiers: NSEvent.ModifierFlags = .command
        ) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.target = self
            menuItem.representedObject = item?.id
            menuItem.keyEquivalentModifierMask = modifiers
            return menuItem
        }

        func handleKeyEvent(_ event: NSEvent) -> Bool {
            guard let outlineView, outlineView.currentEditor() == nil else { return false }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let character = event.charactersIgnoringModifiers?.lowercased()

            if modifiers == [.command, .option], character == "n" {
                parent.addPage(nil)
                return true
            }
            if modifiers == [.command, .shift], character == "n" {
                parent.requestAddFolder(nil)
                return true
            }
            guard let item = selectedEditableItem else { return false }
            if modifiers.isEmpty, [36, 76].contains(event.keyCode) {
                beginRenaming(item)
                return true
            }
            if [51, 117].contains(event.keyCode), item.isFolder {
                parent.requestDeleteFolder(item.id)
                return true
            }
            guard item.isPage else { return false }
            if modifiers == .command, character == "d" {
                parent.duplicatePage(item.id)
                return true
            }
            if modifiers == [.command, .option] {
                switch event.keyCode {
                case 126 where canMove(item, offset: -1):
                    parent.movePage(item.id, -1)
                    return true
                case 125 where canMove(item, offset: 1):
                    parent.movePage(item.id, 1)
                    return true
                default:
                    break
                }
            }
            if [51, 117].contains(event.keyCode), !item.isHome {
                parent.deletePage(item.id)
                return true
            }
            return false
        }

        @objc private func addPageFromContextMenu(_ sender: NSMenuItem) {
            let item = contextItem(from: sender)
            let placement: PageTreePlacement?
            switch item?.kind {
            case .folder(let id): placement = .insideFolder(id)
            case .page(let id): placement = .insidePage(id)
            case .asset, nil: placement = nil
            }
            parent.addPage(placement)
        }

        @objc private func addFolderFromContextMenu(_ sender: NSMenuItem) {
            let placement: PageTreePlacement?
            if case .folder(let id) = contextItem(from: sender)?.kind {
                placement = .insideFolder(id)
            } else {
                placement = nil
            }
            parent.requestAddFolder(placement)
        }

        @objc private func duplicateFromContextMenu(_ sender: NSMenuItem) {
            performPageAction(sender, action: parent.duplicatePage)
        }

        @objc private func renameFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender), item.isPage || item.isFolder else { return }
            selectForContextAction(item)
            beginRenaming(item)
        }

        @objc private func deleteFolderFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender), item.isFolder else { return }
            selectForContextAction(item)
            parent.requestDeleteFolder(item.id)
        }

        @objc private func setHomeFromContextMenu(_ sender: NSMenuItem) {
            performPageAction(sender, action: parent.setHomePage)
        }

        @objc private func moveUpFromContextMenu(_ sender: NSMenuItem) {
            performPageAction(sender) { parent.movePage($0, -1) }
        }

        @objc private func moveDownFromContextMenu(_ sender: NSMenuItem) {
            performPageAction(sender) { parent.movePage($0, 1) }
        }

        @objc private func deleteFromContextMenu(_ sender: NSMenuItem) {
            performPageAction(sender, action: parent.deletePage)
        }

        private func performPageAction(_ sender: NSMenuItem, action: (UUID) -> Void) {
            guard let item = contextItem(from: sender), case .page = item.kind else { return }
            selectForContextAction(item)
            action(item.id)
        }

        private func contextItem(from sender: NSMenuItem) -> PageOutlineItem? {
            guard let id = sender.representedObject as? UUID else { return nil }
            return itemsByID[id]
        }

        private var selectedEditableItem: PageOutlineItem? {
            guard let outlineView, outlineView.selectedRow >= 0,
                  let item = outlineView.item(atRow: outlineView.selectedRow) as? PageOutlineItem,
                  item.isPage || item.isFolder else { return nil }
            return item
        }

        private func selectForContextAction(_ item: PageOutlineItem) {
            guard let outlineView else { return }
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        private func beginRenaming(_ item: PageOutlineItem) {
            guard let outlineView else { return }
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            outlineView.editColumn(0, row: row, with: nil, select: true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField,
                  let identifier = textField.identifier?.rawValue,
                  let itemID = UUID(uuidString: identifier),
                  let item = itemsByID[itemID] else { return }
            let title = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                textField.stringValue = item.title
                return
            }
            guard title != item.title else { return }
            switch item.kind {
            case .page(let id): parent.renamePage(id, title)
            case .folder(let id): parent.renameFolder(id, title)
            case .asset: break
            }
        }

        private func canMove(_ item: PageOutlineItem, offset: Int) -> Bool {
            guard !item.isHome else { return false }
            guard let siblings = siblings(containing: item, in: roots),
                  let index = siblings.firstIndex(where: { $0 === item }) else { return false }
            let destinationIndex = index + offset
            guard siblings.indices.contains(destinationIndex) else { return false }
            return !(destinationIndex == 0 && siblings.first?.isHome == true)
        }

        private func siblings(
            containing soughtItem: PageOutlineItem,
            in items: [PageOutlineItem]
        ) -> [PageOutlineItem]? {
            if items.contains(where: { $0 === soughtItem }) { return items }
            for item in items {
                if let result = siblings(containing: soughtItem, in: item.children) {
                    return result
                }
            }
            return nil
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

        func outlineViewItemDidExpand(_ notification: Notification) {
            synchronizeExpansionState()
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            synchronizeExpansionState()
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let item = item as? PageOutlineItem else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(item.payload, forType: .pageTreeItem)
            if case .asset = item.kind {
                pasteboardItem.setString("foundry-asset-node:\(item.id.uuidString)", forType: .assetNode)
            }
            if item.isImageAsset {
                pasteboardItem.setString("foundry-image-asset:\(item.id.uuidString)", forType: .string)
            }
            if item.isVideoAsset {
                pasteboardItem.setString("foundry-video-asset:\(item.id.uuidString)", forType: .string)
                pasteboardItem.setString(item.id.uuidString, forType: .videoAsset)
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
            if let draggedItem = draggedItem(from: info),
               case .page(let id) = draggedItem,
               itemsByID[id]?.isHome == true {
                return []
            }
            if item == nil, index == 0, roots.first?.isHome == true {
                return []
            }
            if index == NSOutlineViewDropOnItemIndex {
                guard let target = item as? PageOutlineItem else { return [] }
                if target.isFolder { return draggedItem(from: info) == nil ? .copy : .move }
                guard target.isPage, !target.isHome,
                      let draggedItem = draggedItem(from: info),
                      case .page = draggedItem else { return [] }
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
            let pagesByFolder = Dictionary(grouping: pages.filter { $0.parentPageID == nil }, by: \.folderID)
            let pagesByPage = Dictionary(grouping: pages.compactMap { page in
                page.parentPageID.map { ($0, page) }
            }, by: { $0.0 })
            let foldersByParent = Dictionary(grouping: folders, by: \.parentID)
            let assetsByParent = Dictionary(grouping: assets.compactMap { asset -> (UUID?, ProjectAsset)? in
                switch asset.exportDirectory {
                case .root: return (nil, asset)
                case .folder(let id): return (id, asset)
                case nil: return nil
                }
            }, by: { $0.0 })
            var visitedFolders = Set<UUID>()
            var visitedPages = Set<UUID>()

            func pageItem(_ page: Page) -> PageOutlineItem? {
                guard visitedPages.insert(page.id).inserted else { return nil }
                let item = PageOutlineItem(
                    kind: .page(page.id),
                    title: page.title,
                    order: page.order,
                    isHome: page.slug == "index",
                    isTopLevelPage: page.folderID == nil && page.parentPageID == nil,
                    publishingChange: parent.publishingChanges[page.id]
                )
                item.children = (pagesByPage[page.id] ?? [])
                    .map(\.1)
                    .compactMap(pageItem)
                    .sorted(by: PageOutlineItem.sort)
                return item
            }

            func children(parentID: UUID?) -> [PageOutlineItem] {
                let pageItems = (pagesByFolder[parentID] ?? []).compactMap(pageItem)
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
                        isVideoAsset: $0.1.mediaType.hasPrefix("video/"),
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
                guard let item else { return nil }
                switch item.kind {
                case .folder(let id): return .insideFolder(id)
                case .page(let id) where !item.isHome: return .insidePage(id)
                case .page, .asset: return nil
                }
            }
            if siblings.indices.contains(index) {
                return .before(siblings[index].kind)
            }
            let parentFolderID: UUID?
            if let item {
                switch item.kind {
                case .folder(let id): parentFolderID = id
                case .page(let id): return .endPage(id)
                case .asset: parentFolderID = nil
                }
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
            textField.isEditable = true
            textField.isSelectable = true
            let statusField = cell.statusField
            statusField.font = .systemFont(ofSize: 8, weight: .semibold)
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

        private func expandedItemIDs() -> Set<UUID> {
            guard let outlineView else { return [] }
            return Set(itemsByID.values.compactMap {
                ($0.isFolder || $0.isPage) && outlineView.isItemExpanded($0) ? $0.id : nil
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
            isRestoringExpansion = true
            expandAncestors(of: item.id, in: roots)
            isRestoringExpansion = false
            let row = outlineView.row(forItem: item)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
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

        private func synchronizeExpansionState() {
            guard !isRestoringExpansion else { return }
            parent.expandedItemIDs = expandedItemIDs()
        }
    }
}

private final class PageOutlineItem: NSObject {
    let kind: PageTreeItem
    let title: String
    let order: Int
    let isHome: Bool
    let isTopLevelPage: Bool
    let isImageAsset: Bool
    let isVideoAsset: Bool
    var publishingChange: PublishingChange?
    var children: [PageOutlineItem] = []
    var id: UUID { kind.id }
    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }
    var isPage: Bool {
        if case .page = kind { return true }
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
        case .page: isHome ? "house" : "doc"
        case .folder: "folder"
        case .asset: isImageAsset ? "photo" : "doc.richtext"
        }
    }

    init(
        kind: PageTreeItem,
        title: String,
        order: Int,
        isHome: Bool = false,
        isTopLevelPage: Bool = false,
        isImageAsset: Bool = false,
        isVideoAsset: Bool = false,
        publishingChange: PublishingChange? = nil
    ) {
        self.kind = kind
        self.title = title
        self.order = order
        self.isHome = isHome
        self.isTopLevelPage = isTopLevelPage
        self.isImageAsset = isImageAsset
        self.isVideoAsset = isVideoAsset
        self.publishingChange = publishingChange
    }

    static func sort(_ lhs: PageOutlineItem, _ rhs: PageOutlineItem) -> Bool {
        if lhs.isHome != rhs.isHome { return lhs.isHome }
        return lhs.order == rhs.order
            ? lhs.id.uuidString < rhs.id.uuidString
            : lhs.order < rhs.order
    }
}

private final class PageOutlineCell: NSTableCellView {
    let statusField = NSTextField(labelWithString: "")
}

private final class PagesNativeOutlineView: NSOutlineView {
    var handleKeyEvent: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if handleKeyEvent?(event) == true { return }
        super.keyDown(with: event)
    }
}

private extension NSPasteboard.PasteboardType {
    static let pageTreeItem = NSPasteboard.PasteboardType("uk.co.garysimpson.foundry.page-tree-item")
}

private extension NSUserInterfaceItemIdentifier {
    static let pageColumn = NSUserInterfaceItemIdentifier("PagesColumn")
    static let pageCell = NSUserInterfaceItemIdentifier("PagesCell")
}
