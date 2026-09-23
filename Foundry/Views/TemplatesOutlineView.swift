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

/// One source group in the outline: the project, an editable pack, or a
/// read-only installed pack. A nil title renders the section headerless —
/// the flat presentation the Globals panel and search results use.
struct TemplatePanelSection: Equatable, Identifiable {
    let id: String
    let title: String?
    let isEditable: Bool
    let nodes: [ReusablePartNode]

    static let projectSectionID = "project"
}

struct TemplatesOutlineView: NSViewRepresentable {
    let kind: TemplatesOutlineKind
    let sections: [TemplatePanelSection]
    @Binding var selectedNodeID: UUID?
    /// A node dropped at a placement inside the identified section. The
    /// caller decides whether that is a reorder, a move between sources, or
    /// a copy out of a read-only pack.
    let moveNode: (UUID, String, ReusablePartPlacement) -> Bool
    /// Canvas or Structure part payloads dropped on a section; returns whether
    /// they were saved as templates there.
    let saveDroppedParts: ([UUID], String) -> Bool
    let renameDefinition: (UUID, String) -> Void
    let renameFolder: (UUID, String) -> Void
    let duplicateDefinition: (UUID) -> Void
    /// Templates live on disk and can reveal their bundle; globals pass nil.
    let revealDefinition: ((UUID) -> Void)?
    /// Whether a given template has a bundle to reveal — project templates
    /// live inside the document and offer no Finder item. Nil means all do.
    let canRevealDefinition: ((UUID) -> Bool)?
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
        context.coordinator.reload(sections: sections, selectedNodeID: selectedNodeID)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload(sections: sections, selectedNodeID: selectedNodeID)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
        var parent: TemplatesOutlineView
        weak var outlineView: NSOutlineView?
        private var sectionItems: [TemplateSectionOutlineItem] = []
        private var itemsByID: [UUID: ReusablePartOutlineItem] = [:]
        private var displayedSignature: [String] = []
        private var isRestoringSelection = false

        init(parent: TemplatesOutlineView) { self.parent = parent }

        /// One anonymous section renders flat — no header row, items at root.
        private var isFlat: Bool {
            sectionItems.count == 1 && sectionItems[0].title == nil
        }

        func reload(sections: [TemplatePanelSection], selectedNodeID: UUID?) {
            let signature = sections.flatMap { section in
                ["s:\(section.id):\(section.title ?? ""):\(section.isEditable)"]
                    + flattenedSignature(section.nodes)
            }
            if signature != displayedSignature {
                let expandedIDs = expandedFolderIDs()
                displayedSignature = signature
                itemsByID.removeAll(keepingCapacity: true)
                sectionItems = sections.map { section in
                    let item = TemplateSectionOutlineItem(section: section)
                    item.children = section.nodes.map { makeItem($0, section: item) }
                    return item
                }
                outlineView?.reloadData()
                for section in sectionItems where !isFlat {
                    outlineView?.expandItem(section)
                }
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
            if item is TemplateSectionOutlineItem { return true }
            return (item as? ReusablePartOutlineItem)?.isFolder == true
        }

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            item is TemplateSectionOutlineItem
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            !(item is TemplateSectionOutlineItem)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
            !(item is TemplateSectionOutlineItem)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
            !(item is TemplateSectionOutlineItem)
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            if let section = item as? TemplateSectionOutlineItem {
                let identifier = NSUserInterfaceItemIdentifier.templateSectionCell
                let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                    ?? makeSectionCell(identifier: identifier)
                cell.textField?.stringValue = section.title ?? ""
                cell.imageView?.image = section.isEditable ? nil : NSImage(
                    systemSymbolName: "lock.fill",
                    accessibilityDescription: "Read-only"
                )
                return cell
            }
            guard let item = item as? ReusablePartOutlineItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier.reusablePartCell
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                ?? makeCell(identifier: identifier)
            cell.textField?.stringValue = item.title
            cell.textField?.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
            cell.textField?.delegate = self
            cell.textField?.isEditable = item.section?.isEditable ?? true
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
            let targetsAreEditable = targetIDs.allSatisfy {
                itemsByID[$0]?.section?.isEditable ?? true
            }
            if targetIDs.count == 1, let id = targetIDs.first, let item = itemsByID[id] {
                if targetsAreEditable {
                    let renameItem = NSMenuItem(title: "Rename", action: #selector(renameFromContextMenu(_:)), keyEquivalent: "\r")
                    renameItem.keyEquivalentModifierMask = []
                    renameItem.target = self
                    renameItem.representedObject = item.id
                    menu.addItem(renameItem)
                }
                if !item.isFolder {
                    let duplicateItem = NSMenuItem(
                        title: targetsAreEditable ? "Duplicate" : "Duplicate to My Library",
                        action: #selector(duplicateFromContextMenu(_:)),
                        keyEquivalent: ""
                    )
                    duplicateItem.target = self
                    duplicateItem.representedObject = item.id
                    menu.addItem(duplicateItem)
                    if parent.revealDefinition != nil, parent.canRevealDefinition?(item.id) != false {
                        let revealItem = NSMenuItem(title: "Show in Finder", action: #selector(revealFromContextMenu(_:)), keyEquivalent: "")
                        revealItem.target = self
                        revealItem.representedObject = item.id
                        menu.addItem(revealItem)
                    }
                }
                if menu.items.isEmpty == false, targetsAreEditable {
                    menu.addItem(.separator())
                }
            }
            guard targetsAreEditable else { return }
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
                  let item = outlineView.item(atRow: outlineView.selectedRow) as? ReusablePartOutlineItem,
                  item.section?.isEditable != false else { return }
            beginRenaming(item)
        }

        func deleteSelectedNodes() {
            let ids = selectedItemIDs().filter { itemsByID[$0]?.section?.isEditable ?? true }
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
            let draggedIDs = internalNodeIDs(from: info)
            let isInternal = !draggedIDs.isEmpty
            guard isInternal || !droppedPartIDs(from: info).isEmpty else { return [] }
            guard let target = dropTarget(in: outlineView, info: info, proposedItem: item, proposedChildIndex: index) else {
                return []
            }
            guard target.section.isEditable else { return [] }
            guard !isInternal else {
                let draggedItems = draggedIDs.compactMap { itemsByID[$0] }
                let sourcesAreEditable = draggedItems.allSatisfy { $0.section?.isEditable ?? true }
                return sourcesAreEditable ? .move : .copy
            }
            return .copy
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let target = dropTarget(in: outlineView, info: info, proposedItem: item, proposedChildIndex: index),
                  let placement = placement(in: target) else {
                return false
            }
            let nodeIDs = internalNodeIDs(from: info)
            if !nodeIDs.isEmpty {
                var moved = false
                for nodeID in nodeIDs {
                    moved = parent.moveNode(nodeID, target.section.sectionID, placement) || moved
                }
                return moved
            }
            let partIDs = droppedPartIDs(from: info)
            guard !partIDs.isEmpty else { return false }
            return parent.saveDroppedParts(partIDs, target.section.sectionID)
        }

        private struct DropTarget {
            let section: TemplateSectionOutlineItem
            let parentFolder: ReusablePartOutlineItem?
            let childIndex: Int
        }

        /// Normalizes AppKit's proposed drop into a section-scoped target:
        /// blank space maps to the end of the last section, section headers to
        /// their own child list, and rows to their containing section.
        private func dropTarget(
            in outlineView: NSOutlineView,
            info: any NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> DropTarget? {
            if let section = item as? TemplateSectionOutlineItem {
                let childIndex = index == NSOutlineViewDropOnItemIndex ? section.children.count : index
                return DropTarget(section: section, parentFolder: nil, childIndex: childIndex)
            }
            if let nodeItem = item as? ReusablePartOutlineItem {
                guard let section = nodeItem.section else { return nil }
                if index == NSOutlineViewDropOnItemIndex {
                    guard nodeItem.isFolder else { return nil }
                    return DropTarget(section: section, parentFolder: nodeItem, childIndex: nodeItem.children.count)
                }
                guard nodeItem.isFolder else { return nil }
                return DropTarget(section: section, parentFolder: nodeItem, childIndex: index)
            }
            // Root level: flat mode drops directly; sectioned mode retargets
            // blank space and between-section gaps to a concrete section.
            if isFlat, let section = sectionItems.first {
                let childIndex = index == NSOutlineViewDropOnItemIndex || index < 0
                    ? section.children.count
                    : index
                outlineView.setDropItem(nil, dropChildIndex: min(childIndex, section.children.count))
                return DropTarget(section: section, parentFolder: nil, childIndex: childIndex)
            }
            let candidate: TemplateSectionOutlineItem? = index > 0 && sectionItems.indices.contains(index - 1)
                ? sectionItems[index - 1]
                : sectionItems.last
            guard let section = candidate else { return nil }
            outlineView.setDropItem(section, dropChildIndex: section.children.count)
            return DropTarget(section: section, parentFolder: nil, childIndex: section.children.count)
        }

        private func placement(in target: DropTarget) -> ReusablePartPlacement? {
            let siblings = target.parentFolder?.children ?? target.section.children
            if siblings.indices.contains(target.childIndex) {
                return .before(nodeID: siblings[target.childIndex].id)
            }
            if let folder = target.parentFolder {
                return .inside(folderID: folder.id)
            }
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

        private func children(of item: Any?) -> [NSObject] {
            if let section = item as? TemplateSectionOutlineItem { return section.children }
            if let nodeItem = item as? ReusablePartOutlineItem { return nodeItem.children }
            return isFlat ? sectionItems[0].children : sectionItems
        }

        private func makeItem(_ node: ReusablePartNode, section: TemplateSectionOutlineItem) -> ReusablePartOutlineItem {
            let item = ReusablePartOutlineItem(node: node, section: section)
            itemsByID[item.id] = item
            if case .folder(let folder) = node {
                item.children = folder.children.map { makeItem($0, section: section) }
            }
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
            expandAncestors(of: item)
            let row = outlineView.row(forItem: item)
            if row >= 0 { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }

        private func expandAncestors(of item: ReusablePartOutlineItem) {
            guard let section = item.section else { return }
            if !isFlat { outlineView?.expandItem(section) }
            expandFolderAncestors(of: item.id, in: section.children)
        }

        @discardableResult
        private func expandFolderAncestors(of id: UUID, in items: [ReusablePartOutlineItem]) -> Bool {
            for item in items {
                if item.id == id { return true }
                if expandFolderAncestors(of: id, in: item.children) {
                    outlineView?.expandItem(item)
                    return true
                }
            }
            return false
        }

        /// Depth is part of each entry: without it, moving a node into an
        /// adjacent folder flattens to the same sequence and the outline
        /// would silently skip its reload.
        private func flattenedSignature(_ nodes: [ReusablePartNode], depth: Int = 0) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node {
                case .part(let definition):
                    return ["p:\(depth):\(definition.id):\(definition.name):\(definition.root.type.rawValue)"]
                case .folder(let folder):
                    return ["f:\(depth):\(folder.id):\(folder.name)"]
                        + flattenedSignature(folder.children, depth: depth + 1)
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

private final class TemplateSectionOutlineItem: NSObject {
    let sectionID: String
    let title: String?
    let isEditable: Bool
    var children: [ReusablePartOutlineItem] = []

    init(section: TemplatePanelSection) {
        sectionID = section.id
        title = section.title
        isEditable = section.isEditable
    }
}

private final class ReusablePartOutlineItem: NSObject {
    let node: ReusablePartNode
    weak var section: TemplateSectionOutlineItem?
    var children: [ReusablePartOutlineItem] = []
    var id: UUID { node.id }
    var isFolder: Bool { if case .folder = node { true } else { false } }
    var title: String {
        switch node {
        case .part(let definition): definition.name
        case .folder(let folder): folder.name
        }
    }

    init(node: ReusablePartNode, section: TemplateSectionOutlineItem?) {
        self.node = node
        self.section = section
    }
}

extension NSPasteboard.PasteboardType {
    static let reusablePartNode = NSPasteboard.PasteboardType("uk.co.garysimpson.foundry.reusable-part-node")
}

private extension NSUserInterfaceItemIdentifier {
    static let reusablePartColumn = NSUserInterfaceItemIdentifier("ReusablePartsColumn")
    static let reusablePartCell = NSUserInterfaceItemIdentifier("ReusablePartsCell")
    static let templateSectionCell = NSUserInterfaceItemIdentifier("TemplateSectionCell")
}
