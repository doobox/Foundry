import AppKit
import SwiftUI

/// Which library the outline presents — decides how part rows serialize onto
/// the pasteboard when dragged to the canvas or Structure.
enum ReusablePartsOutlineKind {
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
}

struct ReusablePartsOutlineView: NSViewRepresentable {
    let kind: ReusablePartsOutlineKind
    let nodes: [ReusablePartNode]
    @Binding var selectedNodeID: UUID?
    let moveNode: (UUID, ReusablePartPlacement) -> Bool
    /// Canvas or Structure part payloads dropped on the panel; returns whether
    /// they were saved as reusable parts.
    let saveDroppedParts: ([UUID]) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .reusablePartColumn)
        let outlineView = NSOutlineView()
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
        outlineView.registerForDraggedTypes([.reusablePartNode, .string])
        outlineView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

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
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: ReusablePartsOutlineView
        weak var outlineView: NSOutlineView?
        private var roots: [ReusablePartOutlineItem] = []
        private var itemsByID: [UUID: ReusablePartOutlineItem] = [:]
        private var displayedSignature: [String] = []
        private var isRestoringSelection = false

        init(parent: ReusablePartsOutlineView) { self.parent = parent }

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
            cell.imageView?.image = NSImage(
                systemSymbolName: item.isFolder ? "folder" : parent.kind.partSystemImage,
                accessibilityDescription: item.title
            )
            return cell
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
            let isInternal = internalNodeID(from: info) != nil
            guard isInternal || !droppedPartIDs(from: info).isEmpty else { return [] }
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
            if let nodeID = internalNodeID(from: info) {
                return parent.moveNode(nodeID, placement)
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

        private func internalNodeID(from info: any NSDraggingInfo) -> UUID? {
            let prefix = parent.kind.internalDragPrefix
            guard let value = info.draggingPasteboard.string(forType: .reusablePartNode),
                  value.hasPrefix(prefix) else { return nil }
            return UUID(uuidString: String(value.dropFirst(prefix.count)))
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
