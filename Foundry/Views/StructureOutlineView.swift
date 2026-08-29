import AppKit
import SwiftUI

struct StructureOutlineView: NSViewRepresentable {
    let components: [ComponentNode]
    @Binding var selectedComponentIDs: Set<UUID>
    @Binding var primarySelectedComponentID: UUID?
    let moveComponents: ([UUID], ComponentPlacement) -> Bool
    let insertComponent: (ComponentType, ComponentPlacement) -> Bool
    let insertReusableComponent: (UUID, ComponentPlacement) -> Bool
    let insertGlobalComponent: (UUID, ComponentPlacement) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .componentColumn)
        let outlineView = NSOutlineView()
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.selectionHighlightStyle = .regular
        outlineView.allowsMultipleSelection = true
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.registerForDraggedTypes([.string])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        context.coordinator.outlineView = outlineView
        context.coordinator.reload(components: components, selectedIDs: selectedComponentIDs)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload(components: components, selectedIDs: selectedComponentIDs)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: StructureOutlineView
        weak var outlineView: NSOutlineView?
        private var roots: [Item] = []
        private var itemsByID: [UUID: Item] = [:]
        private var displayedSignature: [UUID] = []
        private var isRestoringSelection = false

        init(parent: StructureOutlineView) {
            self.parent = parent
        }

        func reload(components: [ComponentNode], selectedIDs: Set<UUID>) {
            let signature = flattenedIDs(components)
            if signature != displayedSignature {
                let expandedIDs = expandedItemIDs()
                displayedSignature = signature
                itemsByID.removeAll(keepingCapacity: true)
                roots = components.map(makeItem)
                outlineView?.reloadData()
                for id in expandedIDs {
                    if let item = itemsByID[id] {
                        outlineView?.expandItem(item)
                    }
                }
            }
            restoreSelection(selectedIDs)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Item)?.children.isEmpty == false
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item else { return nil }
            let identifier = NSUserInterfaceItemIdentifier.componentCell
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                ?? makeCell(identifier: identifier)
            cell.textField?.stringValue = item.component.name
            cell.imageView?.image = NSImage(
                systemSymbolName: item.component.type.systemImage,
                accessibilityDescription: item.component.name
            )
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRestoringSelection, let outlineView else { return }
            let selectedIDs = Set(outlineView.selectedRowIndexes.compactMap { row in
                (outlineView.item(atRow: row) as? Item)?.id
            })
            parent.selectedComponentIDs = selectedIDs
            let primaryRow = outlineView.selectedRow
            parent.primarySelectedComponentID = primaryRow >= 0
                ? (outlineView.item(atRow: primaryRow) as? Item)?.id
                : nil
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let item = item as? Item else { return nil }
            let pasteboardItem = NSPasteboardItem()
            let selectedIDs = parent.selectedComponentIDs
            let payload: ComponentDragPayload = selectedIDs.count > 1 && selectedIDs.contains(item.id)
                ? .nodes(Array(selectedIDs))
                : .node(item.id)
            pasteboardItem.setString(payload.stringValue, forType: .string)
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard payload(from: info) != nil else { return [] }
            if index == NSOutlineViewDropOnItemIndex,
               let item = item as? Item,
               !item.component.type.definition.allowsChildren {
                return []
            }
            return payload(from: info)?.isNode == true ? .move : .copy
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let payload = payload(from: info),
                  let placement = placement(parent: item as? Item, childIndex: index) else { return false }
            switch payload {
            case .library(let type):
                return parent.insertComponent(type, placement)
            case .reusable(let id):
                return parent.insertReusableComponent(id, placement)
            case .global(let id):
                return parent.insertGlobalComponent(id, placement)
            case .node(let id):
                return parent.moveComponents([id], placement)
            case .nodes(let ids):
                return parent.moveComponents(ids, placement)
            }
        }

        private func placement(parent item: Item?, childIndex index: Int) -> ComponentPlacement? {
            let siblings = item?.children ?? roots
            if index == NSOutlineViewDropOnItemIndex {
                guard let item, item.component.type.definition.allowsChildren else { return nil }
                return .inside(item.id)
            }
            if siblings.indices.contains(index) {
                return .before(siblings[index].id)
            }
            if let item {
                return .inside(item.id)
            }
            return .end
        }

        private func payload(from info: any NSDraggingInfo) -> ComponentDragPayload? {
            guard let value = info.draggingPasteboard.string(forType: .string) else { return nil }
            return ComponentDragPayload(value)
        }

        private func children(of item: Any?) -> [Item] {
            (item as? Item)?.children ?? roots
        }

        private func makeItem(_ component: ComponentNode) -> Item {
            let item = Item(component: component)
            itemsByID[item.id] = item
            item.children = component.children.map(makeItem)
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

        private func expandedItemIDs() -> Set<UUID> {
            guard let outlineView else { return [] }
            return Set(itemsByID.values.compactMap { outlineView.isItemExpanded($0) ? $0.id : nil })
        }

        private func restoreSelection(_ selectedIDs: Set<UUID>) {
            guard let outlineView else { return }
            isRestoringSelection = true
            defer { isRestoringSelection = false }
            for id in selectedIDs {
                expandAncestors(of: id, in: roots)
            }
            let rows = IndexSet(selectedIDs.compactMap { id in
                guard let item = itemsByID[id] else { return nil }
                let row = outlineView.row(forItem: item)
                return row >= 0 ? row : nil
            })
            guard outlineView.selectedRowIndexes != rows else { return }
            outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        }

        @discardableResult
        private func expandAncestors(of id: UUID, in items: [Item]) -> Bool {
            for item in items {
                if item.id == id { return true }
                if expandAncestors(of: id, in: item.children) {
                    outlineView?.expandItem(item)
                    return true
                }
            }
            return false
        }

        private func flattenedIDs(_ components: [ComponentNode]) -> [UUID] {
            components.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
    }
}

private final class Item: NSObject {
    let component: ComponentNode
    var children: [Item] = []
    var id: UUID { component.id }

    init(component: ComponentNode) {
        self.component = component
    }
}

private extension ComponentDragPayload {
    var isNode: Bool {
        switch self {
        case .node, .nodes: true
        case .library, .reusable, .global: false
        }
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let componentColumn = NSUserInterfaceItemIdentifier("StructureComponentColumn")
    static let componentCell = NSUserInterfaceItemIdentifier("StructureComponentCell")
}
