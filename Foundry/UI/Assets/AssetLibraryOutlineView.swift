import AppKit
import SwiftUI

/// A pack a collection or template can be sent to from the context menu —
/// destinations span every tab, which drags cannot.
struct LibraryMoveDestination: Equatable {
    let sectionID: String
    let title: String
}

/// The Assets panel's Library and Dev tabs: the same outline presentation as
/// the Project tab — 24-point rows, symbol icons, inline rename, delete key —
/// with one padlockable section per pack, collections as top-level groups,
/// the collection's real Resources folder tree beneath, and files as rows
/// that drag out as file URLs.
struct AssetLibraryOutlineView: NSViewRepresentable {
    let sources: [AssetCollectionSource]
    /// Filters to matching file rows while searching, flattening folders;
    /// collections always show.
    let searchQuery: String
    @Binding var selectedItemID: String?
    let renameCollection: (String, String) -> Void
    /// Renames a Resources folder; passes the folder's new id back so
    /// selection can follow the path change.
    let renameFolder: (String, String) -> Void
    /// Adds every file under a collection or folder id to the project.
    let addAllToProject: (String) -> Void
    /// Opens the file importer targeting a collection or folder id.
    let addFilesRequested: (String) -> Void
    /// Asks for a new folder inside (collectionID, parentFolderID?).
    let createFolderRequested: (String, String?) -> Void
    let editDetailsRequested: (String) -> Void
    let requestDeleteCollection: (String) -> Void
    let requestDeleteFolder: (String) -> Void
    let addFilesToProject: ([String]) -> Void
    let removeFiles: ([String]) -> Void
    /// Moves files within their own collection: (fileIDs, collectionID,
    /// folderID or nil for the Resources root).
    let moveFiles: ([String], String, String?) -> Void
    let showInFinder: (String) -> Void
    /// Copies external or cross-collection files in: (urls, collectionID,
    /// folderID?).
    let dropFileURLs: ([URL], String, String?) -> Bool
    /// Drops a dragged collection onto another pack's section: moved out of
    /// editable packs, copied out of read-only ones.
    let transferCollection: (String, String) -> Bool
    /// Every editable pack the Move/Copy to submenu can send a collection to,
    /// across all tabs; the collection's own pack is filtered per item.
    let moveDestinations: [LibraryMoveDestination]
    /// Shown as a quiet row inside an empty editable section — a per-section
    /// hint. Nil shows empty sections with bare headers.
    let emptySectionPlaceholder: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .assetLibraryColumn)
        let outlineView = AssetLibraryListOutlineView()
        outlineView.onDeleteKey = { [weak coordinator = context.coordinator] in
            coordinator?.deleteSelection()
        }
        outlineView.onRenameKey = { [weak coordinator = context.coordinator] in
            coordinator?.renameSelection()
        }
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.selectionHighlightStyle = .regular
        outlineView.backgroundColor = .clear
        outlineView.allowsMultipleSelection = true
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.registerForDraggedTypes([.fileURL, .assetLibraryCollection])
        outlineView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        let contextMenu = NSMenu()
        contextMenu.delegate = context.coordinator
        outlineView.menu = contextMenu

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        context.coordinator.outlineView = outlineView
        context.coordinator.reload(sources: sources, query: searchQuery, selectedItemID: selectedItemID)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload(sources: sources, query: searchQuery, selectedItemID: selectedItemID)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
        var parent: AssetLibraryOutlineView
        weak var outlineView: NSOutlineView?
        private var sectionItems: [SectionItem] = []
        private var itemsByID: [String: NSObject] = [:]
        private var displayedSignature: [String] = []
        private var isRestoringSelection = false

        init(parent: AssetLibraryOutlineView) { self.parent = parent }

        func reload(sources: [AssetCollectionSource], query: String, selectedItemID: String?) {
            var signature: [String] = ["q:\(query)"]
            for source in sources {
                signature.append("s:\(source.id):\(source.title):\(source.isEditable)")
                for collection in source.collections {
                    signature.append("c:\(collection.identifier):\(collection.title)")
                    signature += nodeSignature(collection.nodes, depth: 1, query: query)
                }
            }
            if signature != displayedSignature {
                let expandedIDs = expandedItemIDs()
                displayedSignature = signature
                itemsByID.removeAll(keepingCapacity: true)
                sectionItems = sources.map { source in
                    let section = SectionItem(source: source)
                    section.children = source.collections.map { collection in
                        let item = CollectionItem(collection: collection, section: section)
                        if query.isEmpty {
                            item.children = buildNodes(collection.nodes, collection: item, parentFolder: nil)
                        } else {
                            // Searching flattens the tree to matching files,
                            // like the Project tab's filtered list.
                            item.children = collection.files
                                .filter { $0.filename.localizedCaseInsensitiveContains(query) }
                                .map { file in
                                    let fileItem = FileItem(file: file, collection: item, parentFolder: nil)
                                    itemsByID[fileItem.itemID] = fileItem
                                    return fileItem
                                }
                        }
                        itemsByID[item.itemID] = item
                        return item
                    }
                    return section
                }
                outlineView?.reloadData()
                for section in sectionItems { outlineView?.expandItem(section) }
                for id in expandedIDs {
                    if let item = itemsByID[id] { outlineView?.expandItem(item) }
                }
            }
            restoreSelection(selectedItemID)
        }

        private func nodeSignature(_ nodes: [AssetCollectionNode], depth: Int, query: String) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node {
                case .file(let file):
                    return ["a:\(depth):\(file.id):\(file.byteCount)"]
                case .folder(let folder):
                    return ["f:\(depth):\(folder.id):\(folder.name)"]
                        + nodeSignature(folder.nodes, depth: depth + 1, query: query)
                }
            }
        }

        private func buildNodes(
            _ nodes: [AssetCollectionNode],
            collection: CollectionItem,
            parentFolder: FolderItem?
        ) -> [NSObject] {
            nodes.map { node in
                switch node {
                case .file(let file):
                    let item = FileItem(file: file, collection: collection, parentFolder: parentFolder)
                    itemsByID[item.itemID] = item
                    return item
                case .folder(let folder):
                    let item = FolderItem(folder: folder, collection: collection, parentFolder: parentFolder)
                    item.children = buildNodes(folder.nodes, collection: collection, parentFolder: item)
                    itemsByID[item.itemID] = item
                    return item
                }
            }
        }

        // MARK: Items

        final class SectionItem: NSObject {
            let sectionID: String
            let title: String
            let isEditable: Bool
            var children: [CollectionItem] = []
            /// The section's empty-state row, created once so NSOutlineView
            /// sees a stable item identity across data-source calls.
            lazy var placeholderItem = PlaceholderItem(section: self)

            init(source: AssetCollectionSource) {
                sectionID = source.id
                title = source.title
                isEditable = source.isEditable
            }
        }

        /// The quiet hint row inside an empty editable section — not
        /// selectable, not draggable.
        final class PlaceholderItem: NSObject {
            weak var section: SectionItem?

            init(section: SectionItem) {
                self.section = section
            }
        }

        final class CollectionItem: NSObject {
            let collection: AssetCollection
            weak var section: SectionItem?
            var children: [NSObject] = []
            var itemID: String { collection.identifier }
            var isEditable: Bool { section?.isEditable ?? false }

            init(collection: AssetCollection, section: SectionItem) {
                self.collection = collection
                self.section = section
            }
        }

        final class FolderItem: NSObject {
            let folder: AssetCollectionFolder
            weak var collection: CollectionItem?
            weak var parentFolder: FolderItem?
            var children: [NSObject] = []
            var itemID: String { folder.id }
            var isEditable: Bool { collection?.isEditable ?? false }

            init(folder: AssetCollectionFolder, collection: CollectionItem, parentFolder: FolderItem?) {
                self.folder = folder
                self.collection = collection
                self.parentFolder = parentFolder
            }
        }

        final class FileItem: NSObject {
            let file: AssetCollectionFile
            weak var collection: CollectionItem?
            weak var parentFolder: FolderItem?
            var itemID: String { file.id }
            var isEditable: Bool { collection?.isEditable ?? false }

            init(file: AssetCollectionFile, collection: CollectionItem, parentFolder: FolderItem?) {
                self.file = file
                self.collection = collection
                self.parentFolder = parentFolder
            }
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            if item is SectionItem { return true }
            if let collection = item as? CollectionItem { return !collection.children.isEmpty }
            if let folder = item as? FolderItem { return !folder.children.isEmpty }
            return false
        }

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            item is SectionItem
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            !(item is SectionItem) && !(item is PlaceholderItem)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
            !(item is SectionItem)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
            !(item is SectionItem)
        }

        private func children(of item: Any?) -> [NSObject] {
            if let section = item as? SectionItem {
                if section.children.isEmpty, section.isEditable,
                   parent.emptySectionPlaceholder != nil {
                    return [section.placeholderItem]
                }
                return section.children
            }
            if let collection = item as? CollectionItem { return collection.children }
            if let folder = item as? FolderItem { return folder.children }
            return sectionItems
        }

        // MARK: Cells

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            if let section = item as? SectionItem {
                let identifier = NSUserInterfaceItemIdentifier.assetLibrarySectionCell
                let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                    ?? makeSectionCell(identifier: identifier)
                cell.textField?.stringValue = section.title
                cell.imageView?.image = section.isEditable ? nil : NSImage(
                    systemSymbolName: "lock.fill",
                    accessibilityDescription: "Read-only"
                )
                return cell
            }
            if item is PlaceholderItem {
                let identifier = NSUserInterfaceItemIdentifier.assetLibraryPlaceholderCell
                let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                    ?? makePlaceholderCell(identifier: identifier)
                cell.textField?.stringValue = parent.emptySectionPlaceholder ?? ""
                return cell
            }
            let identifier = NSUserInterfaceItemIdentifier.assetLibraryCell
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                ?? makeCell(identifier: identifier)
            if let collection = item as? CollectionItem {
                cell.textField?.stringValue = collection.collection.title
                cell.textField?.identifier = NSUserInterfaceItemIdentifier(collection.itemID)
                cell.textField?.isEditable = collection.isEditable
                cell.textField?.delegate = self
                cell.imageView?.image = NSImage(
                    systemSymbolName: "photo.on.rectangle.angled",
                    accessibilityDescription: nil
                )
            } else if let folderItem = item as? FolderItem {
                cell.textField?.stringValue = folderItem.folder.name
                cell.textField?.identifier = NSUserInterfaceItemIdentifier(folderItem.itemID)
                cell.textField?.isEditable = folderItem.isEditable
                cell.textField?.delegate = self
                cell.imageView?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            } else if let fileItem = item as? FileItem {
                cell.textField?.stringValue = fileItem.file.filename
                cell.textField?.identifier = nil
                cell.textField?.isEditable = false
                cell.imageView?.image = NSImage(
                    systemSymbolName: fileItem.file.systemImageName,
                    accessibilityDescription: nil
                )
            }
            return cell
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField,
                  let identifier = textField.identifier?.rawValue else { return }
            let title = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let item = itemsByID[identifier] as? CollectionItem {
                guard !title.isEmpty else {
                    textField.stringValue = item.collection.title
                    return
                }
                guard title != item.collection.title else { return }
                parent.renameCollection(item.itemID, title)
            } else if let item = itemsByID[identifier] as? FolderItem {
                guard !title.isEmpty else {
                    textField.stringValue = item.folder.name
                    return
                }
                guard title != item.folder.name else { return }
                parent.renameFolder(item.itemID, title)
            }
        }

        // MARK: Selection

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRestoringSelection, let outlineView else { return }
            let row = outlineView.selectedRow
            parent.selectedItemID = row >= 0 ? itemID(outlineView.item(atRow: row)) : nil
        }

        private func itemID(_ item: Any?) -> String? {
            (item as? CollectionItem)?.itemID
                ?? (item as? FolderItem)?.itemID
                ?? (item as? FileItem)?.itemID
        }

        private func selectedIDs() -> [String] {
            guard let outlineView else { return [] }
            return outlineView.selectedRowIndexes.compactMap {
                itemID(outlineView.item(atRow: $0))
            }
        }

        private func restoreSelection(_ selectedItemID: String?) {
            guard let outlineView else { return }
            let displayed = selectedIDs()
            if let selectedItemID, displayed.contains(selectedItemID) { return }
            if selectedItemID == nil, displayed.isEmpty { return }
            isRestoringSelection = true
            defer { isRestoringSelection = false }
            guard let selectedItemID, let item = itemsByID[selectedItemID] else {
                outlineView.deselectAll(nil)
                return
            }
            for ancestor in ancestors(of: item).reversed() {
                outlineView.expandItem(ancestor)
            }
            let row = outlineView.row(forItem: item)
            if row >= 0 { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }

        /// Nearest first: parent folders up to the containing collection.
        private func ancestors(of item: NSObject) -> [NSObject] {
            var chain: [NSObject] = []
            var folder = (item as? FileItem)?.parentFolder ?? (item as? FolderItem)?.parentFolder
            let collection = (item as? FileItem)?.collection ?? (item as? FolderItem)?.collection
            while let current = folder {
                chain.append(current)
                folder = current.parentFolder
            }
            if let collection { chain.append(collection) }
            return chain
        }

        // MARK: Keys

        func deleteSelection() {
            let ids = selectedIDs()
            let files = ids.compactMap { itemsByID[$0] as? FileItem }.filter(\.isEditable)
            if !files.isEmpty {
                parent.removeFiles(files.map(\.itemID))
                return
            }
            if let folder = ids.compactMap({ itemsByID[$0] as? FolderItem }).first(where: \.isEditable) {
                parent.requestDeleteFolder(folder.itemID)
                return
            }
            if let collection = ids.compactMap({ itemsByID[$0] as? CollectionItem }).first(where: \.isEditable) {
                parent.requestDeleteCollection(collection.itemID)
            }
        }

        func renameSelection() {
            guard let outlineView, outlineView.selectedRow >= 0 else { return }
            let item = outlineView.item(atRow: outlineView.selectedRow)
            let isRenamable = (item as? CollectionItem)?.isEditable == true
                || (item as? FolderItem)?.isEditable == true
            guard isRenamable else { return }
            outlineView.editColumn(0, row: outlineView.selectedRow, with: nil, select: true)
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView, outlineView.clickedRow >= 0 else { return }
            let clicked = outlineView.item(atRow: outlineView.clickedRow)
            if let collection = clicked as? CollectionItem {
                if collection.isEditable {
                    menu.addItem(makeItem("Rename", #selector(renameItemAction(_:)), collection.itemID, "\r"))
                }
                menu.addItem(makeItem("Add All to Project", #selector(addAllAction(_:)), collection.itemID))
                if collection.isEditable {
                    menu.addItem(makeItem("Add Files…", #selector(addFilesAction(_:)), collection.itemID))
                    menu.addItem(makeItem(
                        "New Folder…",
                        #selector(createFolderAction(_:)),
                        FolderTarget(collectionID: collection.itemID, folderID: nil)
                    ))
                    menu.addItem(makeItem("Collection Details…", #selector(detailsAction(_:)), collection.itemID))
                }
                if let transferMenu = transferSubmenu(for: collection) {
                    menu.addItem(transferMenu)
                }
                if collection.isEditable {
                    menu.addItem(.separator())
                    menu.addItem(makeItem("Delete Collection…", #selector(deleteCollectionAction(_:)), collection.itemID))
                }
                menu.addItem(.separator())
                menu.addItem(makeItem("Show in Finder", #selector(finderAction(_:)), collection.itemID))
            } else if let folderItem = clicked as? FolderItem {
                if folderItem.isEditable {
                    menu.addItem(makeItem("Rename", #selector(renameItemAction(_:)), folderItem.itemID, "\r"))
                }
                menu.addItem(makeItem("Add All to Project", #selector(addAllAction(_:)), folderItem.itemID))
                if folderItem.isEditable, let collectionID = folderItem.collection?.itemID {
                    menu.addItem(makeItem("Add Files…", #selector(addFilesAction(_:)), folderItem.itemID))
                    menu.addItem(makeItem(
                        "New Folder…",
                        #selector(createFolderAction(_:)),
                        FolderTarget(collectionID: collectionID, folderID: folderItem.itemID)
                    ))
                    menu.addItem(.separator())
                    menu.addItem(makeItem("Delete Folder…", #selector(deleteFolderAction(_:)), folderItem.itemID))
                }
                menu.addItem(.separator())
                menu.addItem(makeItem("Show in Finder", #selector(finderAction(_:)), folderItem.itemID))
            } else if let fileItem = clicked as? FileItem {
                let targets = selectedFileTargets(including: fileItem)
                let noun = targets.count == 1 ? "" : " \(targets.count) Files"
                menu.addItem(makeItem("Add\(noun.isEmpty ? "" : noun) to Project", #selector(addToProjectAction(_:)), targets))
                if fileItem.isEditable {
                    menu.addItem(makeItem(
                        targets.count == 1 ? "Remove from Collection" : "Remove \(targets.count) Files",
                        #selector(removeFilesAction(_:)),
                        targets
                    ))
                }
                menu.addItem(.separator())
                menu.addItem(makeItem("Show in Finder", #selector(finderAction(_:)), fileItem.itemID))
            }
        }

        /// A right-click inside the selection acts on all selected files; a
        /// right-click outside it acts only on the clicked row.
        private func selectedFileTargets(including clicked: FileItem) -> [String] {
            guard let outlineView,
                  outlineView.selectedRowIndexes.contains(outlineView.clickedRow) else {
                return [clicked.itemID]
            }
            let selected = selectedIDs().filter { itemsByID[$0] is FileItem }
            return selected.isEmpty ? [clicked.itemID] : selected
        }

        private final class FolderTarget: NSObject {
            let collectionID: String
            let folderID: String?

            init(collectionID: String, folderID: String?) {
                self.collectionID = collectionID
                self.folderID = folderID
            }
        }

        private final class TransferTarget: NSObject {
            let collectionID: String
            let sectionID: String

            init(collectionID: String, sectionID: String) {
                self.collectionID = collectionID
                self.sectionID = sectionID
            }
        }

        /// "Move to" for editable collections, "Copy to" out of read-only
        /// packs — the menu reaches packs on other tabs, which drags cannot.
        private func transferSubmenu(for collection: CollectionItem) -> NSMenuItem? {
            let destinations = parent.moveDestinations.filter {
                $0.sectionID != collection.section?.sectionID
            }
            guard !destinations.isEmpty else { return nil }
            let submenu = NSMenu()
            for destination in destinations {
                submenu.addItem(makeItem(
                    destination.title,
                    #selector(transferCollectionAction(_:)),
                    TransferTarget(collectionID: collection.itemID, sectionID: destination.sectionID)
                ))
            }
            let item = NSMenuItem(
                title: collection.isEditable ? "Move to" : "Copy to",
                action: nil,
                keyEquivalent: ""
            )
            item.submenu = submenu
            return item
        }

        @objc private func transferCollectionAction(_ sender: NSMenuItem) {
            guard let target = sender.representedObject as? TransferTarget else { return }
            _ = parent.transferCollection(target.collectionID, target.sectionID)
        }

        private func makeItem(
            _ title: String,
            _ action: Selector,
            _ represented: Any,
            _ key: String = ""
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            if !key.isEmpty { item.keyEquivalentModifierMask = [] }
            item.target = self
            item.representedObject = represented
            return item
        }

        @objc private func renameItemAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let item = itemsByID[id],
                  let outlineView else { return }
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.editColumn(0, row: row, with: nil, select: true)
        }

        @objc private func addAllAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            parent.addAllToProject(id)
        }

        @objc private func addFilesAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            parent.addFilesRequested(id)
        }

        @objc private func createFolderAction(_ sender: NSMenuItem) {
            guard let target = sender.representedObject as? FolderTarget else { return }
            parent.createFolderRequested(target.collectionID, target.folderID)
        }

        @objc private func detailsAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            parent.editDetailsRequested(id)
        }

        @objc private func deleteCollectionAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            parent.requestDeleteCollection(id)
        }

        @objc private func deleteFolderAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            parent.requestDeleteFolder(id)
        }

        @objc private func addToProjectAction(_ sender: NSMenuItem) {
            guard let ids = sender.representedObject as? [String] else { return }
            parent.addFilesToProject(ids)
        }

        @objc private func removeFilesAction(_ sender: NSMenuItem) {
            guard let ids = sender.representedObject as? [String] else { return }
            parent.removeFiles(ids)
        }

        @objc private func finderAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            parent.showInFinder(id)
        }

        // MARK: Dragging

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            if let collection = item as? CollectionItem {
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(collection.itemID, forType: .assetLibraryCollection)
                return pasteboardItem
            }
            guard let fileItem = item as? FileItem else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(fileItem.file.url.absoluteString, forType: .fileURL)
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            if let draggedID = draggedCollectionID(from: info) {
                guard let dragged = itemsByID[draggedID] as? CollectionItem,
                      let target = dropSection(for: item),
                      target.isEditable,
                      target !== dragged.section else { return [] }
                outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
                return dragged.isEditable ? .move : .copy
            }
            let urls = fileURLs(from: info)
            guard !urls.isEmpty, let container = dropContainer(for: item), container.isEditable else {
                return []
            }
            outlineView.setDropItem(container.item, dropChildIndex: NSOutlineViewDropOnItemIndex)
            if let dragged = internalFileItems(from: info, urls: urls) {
                // Files moving within their own collection; landing in
                // another collection is a copy, like any external source.
                let sameCollection = dragged.allSatisfy { $0.collection === container.collection }
                if sameCollection {
                    let sameLocation = dragged.allSatisfy { $0.parentFolder === container.folder }
                    return sameLocation ? [] : .move
                }
                return .copy
            }
            return .copy
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            if let draggedID = draggedCollectionID(from: info) {
                guard let target = dropSection(for: item), target.isEditable else { return false }
                return parent.transferCollection(draggedID, target.sectionID)
            }
            let urls = fileURLs(from: info)
            guard !urls.isEmpty, let container = dropContainer(for: item), container.isEditable else {
                return false
            }
            let collectionID = container.collection?.itemID ?? ""
            if let dragged = internalFileItems(from: info, urls: urls),
               dragged.allSatisfy({ $0.collection === container.collection }) {
                parent.moveFiles(dragged.map(\.itemID), collectionID, container.folder?.itemID)
                return true
            }
            return parent.dropFileURLs(urls, collectionID, container.folder?.itemID)
        }

        private func draggedCollectionID(from info: any NSDraggingInfo) -> String? {
            info.draggingPasteboard.string(forType: .assetLibraryCollection)
        }

        /// Where a file drop lands: a collection root or one of its folders.
        private struct DropContainer {
            let item: NSObject
            let collection: CollectionItem?
            let folder: FolderItem?
            var isEditable: Bool { collection?.isEditable ?? false }
        }

        private func dropContainer(for item: Any?) -> DropContainer? {
            if let collection = item as? CollectionItem {
                return DropContainer(item: collection, collection: collection, folder: nil)
            }
            if let folder = item as? FolderItem {
                return DropContainer(item: folder, collection: folder.collection, folder: folder)
            }
            if let fileItem = item as? FileItem {
                let container: NSObject = fileItem.parentFolder ?? fileItem.collection ?? fileItem
                return DropContainer(
                    item: container,
                    collection: fileItem.collection,
                    folder: fileItem.parentFolder
                )
            }
            return nil
        }

        private func dropSection(for item: Any?) -> SectionItem? {
            if let section = item as? SectionItem { return section }
            if let placeholder = item as? PlaceholderItem { return placeholder.section }
            if let collection = item as? CollectionItem { return collection.section }
            if let folder = item as? FolderItem { return folder.collection?.section }
            if let fileItem = item as? FileItem { return fileItem.collection?.section }
            return nil
        }

        /// Resolves a drag that started in this outline back to its file
        /// items; nil for drags from Finder or other views.
        private func internalFileItems(from info: any NSDraggingInfo, urls: [URL]) -> [FileItem]? {
            guard info.draggingSource as? NSOutlineView === outlineView else { return nil }
            let items = urls.compactMap { itemsByID[$0.standardizedFileURL.path] as? FileItem }
            return items.count == urls.count ? items : nil
        }

        private func fileURLs(from info: any NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        }

        // MARK: Cell construction

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let imageView = NSImageView()
            imageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            let textField = NSTextField(labelWithString: "")
            textField.isEditable = true
            textField.isSelectable = true
            textField.lineBreakMode = .byTruncatingTail
            imageView.translatesAutoresizingMaskIntoConstraints = false
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.imageView = imageView
            cell.textField = textField
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func makePlaceholderCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: 11)
            textField.textColor = .tertiaryLabelColor
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func makeSectionCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: 11, weight: .semibold)
            textField.textColor = .secondaryLabelColor
            textField.lineBreakMode = .byTruncatingTail
            textField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            textField.translatesAutoresizingMaskIntoConstraints = false
            let imageView = NSImageView()
            imageView.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
            imageView.contentTintColor = .tertiaryLabelColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.addSubview(imageView)
            cell.textField = textField
            cell.imageView = imageView
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 5),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4)
            ])
            return cell
        }

        private func expandedItemIDs() -> Set<String> {
            guard let outlineView else { return [] }
            return Set(itemsByID.values.compactMap { item -> String? in
                let id = (item as? CollectionItem)?.itemID ?? (item as? FolderItem)?.itemID
                guard let id else { return nil }
                return outlineView.isItemExpanded(item) ? id : nil
            })
        }
    }
}

/// Outline view that forwards Delete / forward-delete and Return key presses
/// so the panel can remove files or rename collections and folders, and that
/// remembers when it is the source of the drag in flight.
private final class AssetLibraryListOutlineView: NSOutlineView {
    var onDeleteKey: (() -> Void)?
    var onRenameKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let hasPlainModifiers = event.modifierFlags
            .intersection([.command, .option, .control, .shift])
            .isEmpty
        if hasPlainModifiers, selectedRow >= 0, currentEditor() == nil {
            if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
               scalar == "\u{7F}" || scalar.value == UInt32(NSDeleteFunctionKey) {
                onDeleteKey?()
                return
            }
            if [36, 76].contains(event.keyCode) {
                onRenameKey?()
                return
            }
        }
        super.keyDown(with: event)
    }
}

private extension NSPasteboard.PasteboardType {
    static let assetLibraryCollection = NSPasteboard.PasteboardType("com.foundry.asset-library-collection")
}

private extension NSUserInterfaceItemIdentifier {
    static let assetLibraryColumn = NSUserInterfaceItemIdentifier("AssetLibraryColumn")
    static let assetLibraryCell = NSUserInterfaceItemIdentifier("AssetLibraryCell")
    static let assetLibrarySectionCell = NSUserInterfaceItemIdentifier("AssetLibrarySectionCell")
    static let assetLibraryPlaceholderCell = NSUserInterfaceItemIdentifier("AssetLibraryPlaceholderCell")
}
