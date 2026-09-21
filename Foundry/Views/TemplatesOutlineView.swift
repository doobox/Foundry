import AppKit
import SwiftUI

/// Which library the outline presents — decides how part rows serialize onto
/// the pasteboard when dragged to the canvas or Structure.
enum TemplatesOutlineKind {
    case templates
    case globals

    fileprivate var internalDragPrefix: String {
        switch self {
        case .templates: "foundry-reusable-node:"
        case .globals: "foundry-global-node:"
        }
    }

    fileprivate func insertPayload(for id: UUID) -> String {
        switch self {
        case .templates: PartDragPayload.reusable(id).stringValue
        case .globals: PartDragPayload.global(id).stringValue
        }
    }

    /// Rows wear the library's identity, not the root part's type: the same
    /// symbol as the panel's own tab.
    fileprivate var partSystemImage: String {
        switch self {
        case .templates: WorkspacePanel.reusableParts.systemImage
        case .globals: WorkspacePanel.globalParts.systemImage
        }
    }

    fileprivate var partNoun: String {
        switch self {
        case .templates: "Template"
        case .globals: "Global"
        }
    }
}

struct TemplatesOutlineView: NSViewRepresentable {
    let kind: TemplatesOutlineKind
    let nodes: [ReusablePartNode]
    @Binding var selectedNodeID: UUID?
    let moveNode: (UUID, ReusablePartPlacement) -> Bool
    /// Canvas or Structure part payloads dropped on the panel; returns whether
    /// they were saved as reusable parts.
    let saveDroppedParts: ([UUID]) -> Bool
    let renameDefinition: (UUID, String) -> Void
    let renameFolder: (UUID, String) -> Void
    let duplicateDefinition: (UUID) -> Void
    /// Templates live on disk and can reveal their bundle; globals pass nil.
    let revealDefinition: ((UUID) -> Void)?
    /// Deletion is confirmed by the panel, not performed here.
    let requestDelete: ([UUID]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .reusablePartColumn)
        let outlineView = LibraryListOutlineView()
        outlineView.onDeleteKey = { [weak coordinator = context.coordinator] in
            coordinator?.deleteSelectedNodes()
        }
        outlineView.onRenameKey = { [weak coordinator = context.coordinator] in
            coordinator?.renameSelectedNode()
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
        outlineView.registerForDraggedTypes([.reusablePartNode, .string])
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
        context.coordinator.reload(nodes: nodes, selectedNodeID: selectedNodeID)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload(nodes: nodes, selectedNodeID: selectedNodeID)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
        var parent: TemplatesOutlineView
        weak var outlineView: NSOutlineView?
        private var roots: [ReusablePartOutlineItem] = []
        private var itemsByID: [UUID: ReusablePartOutlineItem] = [:]
        private var displayedSignature: [String] = []
        private var isRestoringSelection = false

        init(parent: TemplatesOutlineView) { self.parent = parent }

        func reload(nodes: [ReusablePartNode], selectedNodeID: UUID?) {
            let signature = flattenedSignature(nodes)
            if signature != displayedSignature {
                let expandedIDs = expandedFolderIDs()
                displayedSignature = signature
                itemsByID.removeAll(keepingCapacity: true)
                roots = nodes.map(makeItem)
                outlineView?.reloadData()
                for id in expandedIDs {
                    if let item = itemsByID[id] { outlineView?.expandItem(item) }
                }
            }
            restoreSelection(selectedNodeID)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? ReusablePartOutlineItem)?.isFolder == true
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? ReusablePartOutlineItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier.reusablePartCell
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                ?? makeCell(identifier: identifier)
            cell.textField?.stringValue = item.title
            cell.textField?.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
            cell.textField?.delegate = self
            cell.imageView?.image = NSImage(
                systemSymbolName: item.isFolder ? "folder" : parent.kind.partSystemImage,
                accessibilityDescription: item.title
            )
            return cell
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
            if item.isFolder {
                parent.renameFolder(item.id, title)
            } else {
                parent.renameDefinition(item.id, title)
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let targetIDs = contextMenuTargetIDs()
            guard !targetIDs.isEmpty else { return }
            if targetIDs.count == 1, let id = targetIDs.first, let item = itemsByID[id] {
                let renameItem = NSMenuItem(title: "Rename", action: #selector(renameFromContextMenu(_:)), keyEquivalent: "\r")
                renameItem.keyEquivalentModifierMask = []
                renameItem.target = self
                renameItem.representedObject = item.id
                menu.addItem(renameItem)
                if !item.isFolder {
                    let duplicateItem = NSMenuItem(title: "Duplicate", action: #selector(duplicateFromContextMenu(_:)), keyEquivalent: "")
                    duplicateItem.target = self
                    duplicateItem.representedObject = item.id
                    menu.addItem(duplicateItem)
                    if parent.revealDefinition != nil {
                        let revealItem = NSMenuItem(title: "Show in Finder", action: #selector(revealFromContextMenu(_:)), keyEquivalent: "")
                        revealItem.target = self
                        revealItem.representedObject = item.id
                        menu.addItem(revealItem)
                    }
                }
                menu.addItem(.separator())
            }
            let deleteTitle: String
            if targetIDs.count > 1 {
                deleteTitle = "Delete \(targetIDs.count) Items…"
            } else if let item = targetIDs.first.flatMap({ itemsByID[$0] }) {
                deleteTitle = item.isFolder ? "Delete Folder…" : "Delete \(parent.kind.partNoun)…"
            } else {
                deleteTitle = "Delete…"
            }
            let deleteItem = NSMenuItem(title: deleteTitle, action: #selector(deleteFromContextMenu(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = targetIDs
            menu.addItem(deleteItem)
        }

        // A right-click inside the selection acts on the whole selection; a
        // right-click outside it acts only on the clicked row.
        private func contextMenuTargetIDs() -> [UUID] {
            guard let outlineView,
                  outlineView.clickedRow >= 0,
                  let clicked = outlineView.item(atRow: outlineView.clickedRow) as? ReusablePartOutlineItem else {
                return []
            }
            if outlineView.selectedRowIndexes.contains(outlineView.clickedRow) {
                return selectedItemIDs()
            }
            return [clicked.id]
        }

        private func selectedItemIDs() -> [UUID] {
            guard let outlineView else { return [] }
            return outlineView.selectedRowIndexes.compactMap {
                (outlineView.item(atRow: $0) as? ReusablePartOutlineItem)?.id
            }
        }

        @objc private func renameFromContextMenu(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID, let item = itemsByID[id] else { return }
            beginRenaming(item)
        }

        @objc private func duplicateFromContextMenu(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            parent.duplicateDefinition(id)
        }

        @objc private func revealFromContextMenu(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            parent.revealDefinition?(id)
        }

        @objc private func deleteFromContextMenu(_ sender: NSMenuItem) {
            guard let ids = sender.representedObject as? [UUID], !ids.isEmpty else { return }
            parent.requestDelete(ids)
        }

        func renameSelectedNode() {
            guard let outlineView, outlineView.selectedRow >= 0,
                  let item = outlineView.item(atRow: outlineView.selectedRow) as? ReusablePartOutlineItem else { return }
            beginRenaming(item)
        }

        func deleteSelectedNodes() {
            let ids = selectedItemIDs()
            guard !ids.isEmpty else { return }
            parent.requestDelete(ids)
        }

        private func beginRenaming(_ item: ReusablePartOutlineItem) {
            guard let outlineView else { return }
            selectRow(of: item)
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            outlineView.editColumn(0, row: row, with: nil, select: true)
        }

        private func selectRow(of item: ReusablePartOutlineItem) {
            guard let outlineView else { return }
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRestoringSelection, let outlineView else { return }
            let row = outlineView.selectedRow
            parent.selectedNodeID = row >= 0
                ? (outlineView.item(atRow: row) as? ReusablePartOutlineItem)?.id
                : nil
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let item = item as? ReusablePartOutlineItem else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(parent.kind.internalDragPrefix + item.id.uuidString, forType: .reusablePartNode)
            if !item.isFolder {
                // Parts also drag onto the canvas and Structure as inserts.
                pasteboardItem.setString(parent.kind.insertPayload(for: item.id), forType: .string)
            }
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            let isInternal = !internalNodeIDs(from: info).isEmpty
            guard isInternal || !droppedPartIDs(from: info).isEmpty else { return [] }
            // Blank space below the last row targets the root, not the level
            // AppKit proposes from the nearest row.
            let point = outlineView.convert(info.draggingLocation, from: nil)
            if outlineView.row(at: point) < 0 {
                outlineView.setDropItem(nil, dropChildIndex: roots.count)
                return isInternal ? .move : .copy
            }
            if index == NSOutlineViewDropOnItemIndex,
               (item as? ReusablePartOutlineItem)?.isFolder != true {
                return []
            }
            return isInternal ? .move : .copy
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let placement = placement(parent: item as? ReusablePartOutlineItem, childIndex: index) else {
                return false
            }
            let nodeIDs = internalNodeIDs(from: info)
            if !nodeIDs.isEmpty {
                var moved = false
                for nodeID in nodeIDs {
                    moved = parent.moveNode(nodeID, placement) || moved
                }
                return moved
            }
            let partIDs = droppedPartIDs(from: info)
            guard !partIDs.isEmpty else { return false }
            return parent.saveDroppedParts(partIDs)
        }

        private func placement(parent item: ReusablePartOutlineItem?, childIndex index: Int) -> ReusablePartPlacement? {
            let siblings = item?.children ?? roots
            if index == NSOutlineViewDropOnItemIndex {
                guard let item, item.isFolder else { return nil }
                return .inside(folderID: item.id)
            }
            if siblings.indices.contains(index) { return .before(nodeID: siblings[index].id) }
            if let item, item.isFolder { return .inside(folderID: item.id) }
            return .end
        }

        private func internalNodeIDs(from info: any NSDraggingInfo) -> [UUID] {
            let prefix = parent.kind.internalDragPrefix
            return (info.draggingPasteboard.pasteboardItems ?? []).compactMap { item in
                guard let value = item.string(forType: .reusablePartNode),
                      value.hasPrefix(prefix) else { return nil }
                return UUID(uuidString: String(value.dropFirst(prefix.count)))
            }
        }

        private func droppedPartIDs(from info: any NSDraggingInfo) -> [UUID] {
            guard let value = info.draggingPasteboard.string(forType: .string),
                  let payload = PartDragPayload(value) else { return [] }
            switch payload {
            case .node(let id): return [id]
            case .nodes(let ids): return ids
            case .library, .reusable, .global: return []
            }
        }

        private func children(of item: Any?) -> [ReusablePartOutlineItem] {
            (item as? ReusablePartOutlineItem)?.children ?? roots
        }

        private func makeItem(_ node: ReusablePartNode) -> ReusablePartOutlineItem {
            let item = ReusablePartOutlineItem(node: node)
            itemsByID[item.id] = item
            if case .folder(let folder) = node { item.children = folder.children.map(makeItem) }
            return item
        }

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

        private func expandedFolderIDs() -> Set<UUID> {
            guard let outlineView else { return [] }
            return Set(itemsByID.values.compactMap {
                $0.isFolder && outlineView.isItemExpanded($0) ? $0.id : nil
            })
        }

        private func restoreSelection(_ selectedNodeID: UUID?) {
            guard let outlineView else { return }
            let displayedID = outlineView.selectedRow >= 0
                ? (outlineView.item(atRow: outlineView.selectedRow) as? ReusablePartOutlineItem)?.id
                : nil
            guard displayedID != selectedNodeID else { return }
            isRestoringSelection = true
            defer { isRestoringSelection = false }
            guard let selectedNodeID, let item = itemsByID[selectedNodeID] else {
                outlineView.deselectAll(nil)
                return
            }
            expandAncestors(of: selectedNodeID, in: roots)
            let row = outlineView.row(forItem: item)
            if row >= 0 { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }

        @discardableResult
        private func expandAncestors(of id: UUID, in items: [ReusablePartOutlineItem]) -> Bool {
            for item in items {
                if item.id == id { return true }
                if expandAncestors(of: id, in: item.children) {
                    outlineView?.expandItem(item)
                    return true
                }
            }
            return false
        }

        private func flattenedSignature(_ nodes: [ReusablePartNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node {
                case .part(let definition):
                    return ["p:\(definition.id):\(definition.name):\(definition.root.type.rawValue)"]
                case .folder(let folder):
                    return ["f:\(folder.id):\(folder.name)"] + flattenedSignature(folder.children)
                }
            }
        }
    }
}

/// Outline view that forwards Delete / forward-delete and Return key presses
/// so the panel can remove or rename the selected item.
private final class LibraryListOutlineView: NSOutlineView {
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
            // Return and keypad Enter begin renaming, matching the Pages panel.
            if [36, 76].contains(event.keyCode) {
                onRenameKey?()
                return
            }
        }
        super.keyDown(with: event)
    }
}

private final class ReusablePartOutlineItem: NSObject {
    let node: ReusablePartNode
    var children: [ReusablePartOutlineItem] = []
    var id: UUID { node.id }
    var isFolder: Bool { if case .folder = node { true } else { false } }
    var title: String {
        switch node {
        case .part(let definition): definition.name
        case .folder(let folder): folder.name
        }
    }

    init(node: ReusablePartNode) { self.node = node }
}

extension NSPasteboard.PasteboardType {
    static let reusablePartNode = NSPasteboard.PasteboardType("uk.co.garysimpson.foundry.reusable-part-node")
}

private extension NSUserInterfaceItemIdentifier {
    static let reusablePartColumn = NSUserInterfaceItemIdentifier("ReusablePartsColumn")
    static let reusablePartCell = NSUserInterfaceItemIdentifier("ReusablePartsCell")
}
