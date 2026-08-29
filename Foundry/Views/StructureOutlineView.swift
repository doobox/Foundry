import AppKit
import SwiftUI

struct StructureOutlineView: NSViewRepresentable {
    let components: [ComponentNode]
    @Binding var selectedComponentIDs: Set<UUID>
    @Binding var primarySelectedComponentID: UUID?
    let renameComponent: (UUID, String) -> Void
    let moveComponents: ([UUID], ComponentPlacement) -> Bool
    let insertComponent: (ComponentType, ComponentPlacement) -> Bool
    let insertReusableComponent: (UUID, ComponentPlacement) -> Bool
    let insertGlobalComponent: (UUID, ComponentPlacement) -> Bool
    let duplicateComponent: () -> Void
    let copyComponent: () -> Void
    let pasteComponent: () -> Void
    let canPasteComponent: Bool
    let saveAsReusableComponent: (String) -> Void
    let saveAsGlobalComponent: (String) -> Void
    let moveComponent: (Int) -> Void
    let outdentComponent: () -> Void
    let deleteComponent: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .componentColumn)
        let outlineView = StructureNativeOutlineView()
        outlineView.handleKeyEvent = context.coordinator.handleKeyEvent
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.selectionHighlightStyle = .regular
        outlineView.allowsMultipleSelection = true
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        let contextMenu = NSMenu()
        contextMenu.delegate = context.coordinator
        outlineView.menu = contextMenu
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
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
        var parent: StructureOutlineView
        weak var outlineView: NSOutlineView?
        private var roots: [Item] = []
        private var itemsByID: [UUID: Item] = [:]
        private var displayedSignature: [String] = []
        private var isRestoringSelection = false

        init(parent: StructureOutlineView) {
            self.parent = parent
        }

        func reload(components: [ComponentNode], selectedIDs: Set<UUID>) {
            let signature = flattenedSignature(components)
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
            cell.textField?.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
            cell.textField?.delegate = self
            cell.imageView?.image = componentIcon(for: item.component)
            cell.imageView?.setAccessibilityLabel(item.component.name)
            return cell
        }

        private func componentIcon(for component: ComponentNode) -> NSImage? {
            if let iconURL = component.type.definition.package?.iconURL,
               let icon = NSImage(contentsOf: iconURL) {
                return icon
            }
            return NSImage(
                systemSymbolName: component.type.systemImage,
                accessibilityDescription: component.name
            )
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView else { return }
            let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
            guard row >= 0, let item = outlineView.item(atRow: row) as? Item else { return }
            selectForContextAction(item)
            let generatedMenu = contextMenu(for: item)
            for menuItem in generatedMenu.items {
                generatedMenu.removeItem(menuItem)
                menu.addItem(menuItem)
            }
        }

        private func contextMenu(for item: Item) -> NSMenu {
            let menu = NSMenu()
            menu.addItem(menuItem("Rename", action: #selector(renameFromContextMenu(_:)), item: item, key: "\r", modifiers: []))
            menu.addItem(.separator())
            menu.addItem(menuItem("Duplicate", action: #selector(duplicateFromContextMenu(_:)), item: item, key: "d"))
            menu.addItem(menuItem("Copy", action: #selector(copyFromContextMenu(_:)), item: item, key: "c"))
            let pasteItem = menuItem("Paste", action: #selector(pasteFromContextMenu(_:)), item: item, key: "v")
            pasteItem.isEnabled = parent.canPasteComponent
            menu.addItem(pasteItem)
            menu.addItem(.separator())
            menu.addItem(menuItem("Save as Reusable Component…", action: #selector(saveReusableFromContextMenu(_:)), item: item))
            menu.addItem(menuItem("Save as Global Component…", action: #selector(saveGlobalFromContextMenu(_:)), item: item))
            menu.addItem(.separator())
            menu.addItem(menuItem("Move Up", action: #selector(moveUpFromContextMenu(_:)), item: item, key: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), modifiers: [.command, .option]))
            menu.addItem(menuItem("Move Down", action: #selector(moveDownFromContextMenu(_:)), item: item, key: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), modifiers: [.command, .option]))
            menu.addItem(menuItem("Move Out of Container", action: #selector(outdentFromContextMenu(_:)), item: item, key: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), modifiers: [.command, .option]))
            menu.addItem(.separator())
            menu.addItem(menuItem("Delete", action: #selector(deleteFromContextMenu(_:)), item: item, key: String(Character(UnicodeScalar(NSDeleteCharacter)!)), modifiers: []))
            return menu
        }

        private func menuItem(
            _ title: String,
            action: Selector,
            item: Item,
            key: String = "",
            modifiers: NSEvent.ModifierFlags = .command
        ) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.target = self
            menuItem.representedObject = item.id
            menuItem.keyEquivalentModifierMask = modifiers
            return menuItem
        }

        func handleKeyEvent(_ event: NSEvent) -> Bool {
            guard let outlineView, outlineView.currentEditor() == nil else { return false }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let character = event.charactersIgnoringModifiers?.lowercased()

            if modifiers == .command {
                switch character {
                case "d": parent.duplicateComponent(); return true
                case "c": parent.copyComponent(); return true
                case "v" where parent.canPasteComponent: parent.pasteComponent(); return true
                default: break
                }
            }

            if modifiers == [.command, .option] {
                switch event.keyCode {
                case 126: parent.moveComponent(-1); return true
                case 125: parent.moveComponent(1); return true
                case 123: parent.outdentComponent(); return true
                default: break
                }
            }

            switch event.keyCode {
            case 36, 76:
                beginRenamingSelectedRow()
                return true
            case 51, 117:
                parent.deleteComponent()
                return true
            default:
                return false
            }
        }

        private func beginRenamingSelectedRow() {
            guard let outlineView, outlineView.selectedRow >= 0 else { return }
            outlineView.editColumn(0, row: outlineView.selectedRow, with: nil, select: true)
        }

        @objc private func renameFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender),
                  let outlineView else { return }
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            selectForContextAction(item)
            outlineView.editColumn(0, row: row, with: nil, select: true)
        }

        @objc private func duplicateFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.duplicateComponent)
        }

        @objc private func copyFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.copyComponent)
        }

        @objc private func pasteFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.pasteComponent)
        }

        @objc private func saveReusableFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender) else { return }
            selectForContextAction(item)
            parent.saveAsReusableComponent(item.component.name)
        }

        @objc private func saveGlobalFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender) else { return }
            selectForContextAction(item)
            parent.saveAsGlobalComponent(item.component.name)
        }

        @objc private func moveUpFromContextMenu(_ sender: NSMenuItem) {
            perform(sender) { parent.moveComponent(-1) }
        }

        @objc private func moveDownFromContextMenu(_ sender: NSMenuItem) {
            perform(sender) { parent.moveComponent(1) }
        }

        @objc private func outdentFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.outdentComponent)
        }

        @objc private func deleteFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.deleteComponent)
        }

        private func perform(_ sender: NSMenuItem, action: () -> Void) {
            guard let item = contextItem(from: sender) else { return }
            selectForContextAction(item)
            action()
        }

        private func contextItem(from sender: NSMenuItem) -> Item? {
            guard let componentID = sender.representedObject as? UUID else { return nil }
            return itemsByID[componentID]
        }

        private func selectForContextAction(_ item: Item) {
            guard let outlineView else { return }
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            if parent.selectedComponentIDs.contains(item.id) {
                parent.primarySelectedComponentID = item.id
                return
            }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            parent.selectedComponentIDs = [item.id]
            parent.primarySelectedComponentID = item.id
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField,
                  let identifier = textField.identifier?.rawValue,
                  let componentID = UUID(uuidString: identifier),
                  let item = itemsByID[componentID] else { return }
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                textField.stringValue = item.component.name
                return
            }
            guard name != item.component.name else { return }
            parent.renameComponent(componentID, name)
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
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 18 * 0.16
            imageView.layer?.masksToBounds = true
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

        private func flattenedSignature(_ components: [ComponentNode]) -> [String] {
            components.flatMap { ["\($0.id.uuidString):\($0.name)"] + flattenedSignature($0.children) }
        }
    }
}

private final class StructureNativeOutlineView: NSOutlineView {
    var handleKeyEvent: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if handleKeyEvent?(event) == true { return }
        super.keyDown(with: event)
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
