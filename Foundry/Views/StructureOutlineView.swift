import AppKit
import SwiftUI

struct StructureOutlineView: NSViewRepresentable {
    private static let dropGuidance = "Drag between parts to reorder, or onto a container to place inside it."

    let parts: [PartNode]
    let globalPartNames: [UUID: String]
    @Binding var selectedPartIDs: Set<UUID>
    @Binding var primarySelectedPartID: UUID?
    @Binding var expandedItemIDs: Set<UUID>
    let renamePart: (UUID, String) -> Void
    let canMoveParts: ([UUID], PartPlacement) -> Bool
    let moveParts: ([UUID], PartPlacement) -> Bool
    let insertPart: (PartType, PartPlacement) -> Bool
    let insertReusablePart: (UUID, PartPlacement) -> Bool
    let insertGlobalPart: (UUID, PartPlacement) -> Bool
    let duplicatePart: () -> Void
    let copyPart: () -> Void
    let pastePart: () -> Void
    let canPastePart: Bool
    let saveAsReusablePart: (String) -> Void
    let saveAsGlobalPart: (String) -> Void
    let setGlobalPartLinked: (UUID, Bool) -> Void
    let movePart: (Int) -> Void
    let outdentPart: () -> Void
    let deletePart: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .partColumn)
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
        outlineView.toolTip = Self.dropGuidance
        outlineView.setAccessibilityHelp(Self.dropGuidance)

        let scrollView = StructureScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        context.coordinator.outlineView = outlineView
        context.coordinator.reload(parts: parts, selectedIDs: selectedPartIDs)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload(parts: parts, selectedIDs: selectedPartIDs)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
        var parent: StructureOutlineView
        weak var outlineView: NSOutlineView?
        private var roots: [Item] = []
        private var itemsByID: [UUID: Item] = [:]
        private var displayedSignature: [String] = []
        private var lastRequestedSelectedIDs: Set<UUID>?
        private var lastRequestedPrimaryID: UUID?
        private var isRestoringSelection = false
        private var isRestoringExpansion = false

        init(parent: StructureOutlineView) {
            self.parent = parent
        }

        func reload(parts: [PartNode], selectedIDs: Set<UUID>) {
            let signature = flattenedSignature(parts, parentID: nil)
            if signature != displayedSignature {
                let expandedIDs = parent.expandedItemIDs.union(expandedItemIDs())
                displayedSignature = signature
                itemsByID.removeAll(keepingCapacity: true)
                roots = parts.map { makeItem($0) }
                outlineView?.reloadData()
                isRestoringExpansion = true
                restoreExpansion(in: roots, expandedIDs: expandedIDs)
                isRestoringExpansion = false
            }
            let shouldRevealSelection = lastRequestedSelectedIDs != selectedIDs
                || lastRequestedPrimaryID != parent.primarySelectedPartID
            restoreSelection(selectedIDs, reveal: shouldRevealSelection)
            lastRequestedSelectedIDs = selectedIDs
            lastRequestedPrimaryID = parent.primarySelectedPartID
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
            let identifier = NSUserInterfaceItemIdentifier.partCell
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? StructureOutlineCell
                ?? makeCell(identifier: identifier)
            let name = displayName(for: item.part)
            cell.textField?.stringValue = name
            cell.textField?.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
            cell.textField?.delegate = self
            cell.imageView?.image = partIcon(for: item.part)
            cell.imageView?.setAccessibilityLabel(name)
            let isLinkedToGlobal = globalContext(for: item)?.isLinked == true
            let isGlobalRoot = item.part.reusableDefinitionID != nil
            cell.globalIndicator.image = isLinkedToGlobal
                ? NSImage(
                    systemSymbolName: "globe",
                    accessibilityDescription: isGlobalRoot ? "Global part" : "Global part child"
                )
                : nil
            cell.globalIndicator.isHidden = !isLinkedToGlobal
            cell.globalIndicator.toolTip = isGlobalRoot ? "Global part" : "Child of global part"
            if let unavailableArea = unavailableChildArea(for: item) {
                cell.unavailableDropZoneLabel.stringValue = unavailableArea.label
                cell.unavailableDropZoneLabel.isHidden = false
                cell.warningIndicator.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle.fill",
                    accessibilityDescription: unavailableArea.label
                )
                cell.warningIndicator.isHidden = false
                cell.warningIndicator.toolTip = "This content is preserved but is not rendered because its parent no longer declares this child area."
            } else {
                cell.unavailableDropZoneLabel.stringValue = ""
                cell.unavailableDropZoneLabel.isHidden = true
                cell.warningIndicator.image = nil
                cell.warningIndicator.isHidden = true
                cell.warningIndicator.toolTip = nil
            }
            return cell
        }

        private func partIcon(for part: PartNode) -> NSImage? {
            if let iconURL = part.type.definition.package?.iconURL,
               let icon = NSImage(contentsOf: iconURL) {
                return icon
            }
            return NSImage(
                systemSymbolName: part.type.systemImage,
                accessibilityDescription: part.name
            )
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            menu.autoenablesItems = false
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
            menu.autoenablesItems = false
            let selectionCount = parent.selectedPartIDs.count
            let isSingleSelection = selectionCount == 1
            let selectedGlobalContext = isSingleSelection ? globalContext(for: item) : nil
            menu.addItem(contextMenuHeader(for: item, selectionCount: selectionCount))
            menu.addItem(.separator())
            let rename = menuItem("Rename", action: #selector(renameFromContextMenu(_:)), item: item, key: "\r", modifiers: [])
            rename.isEnabled = isSingleSelection
            menu.addItem(rename)
            if let recoveryMenu = unavailableChildAreaRecoveryMenu(for: item) {
                menu.addItem(recoveryMenu)
            }
            menu.addItem(.separator())

            if let globalContext = selectedGlobalContext {
                menu.addItem(menuItem(
                    globalContext.isLinked ? "Make Local Override" : "Relink to Global",
                    action: globalContext.isLinked
                        ? #selector(makeLocalOverrideFromContextMenu(_:))
                        : #selector(relinkGlobalFromContextMenu(_:)),
                    item: globalContext.target
                ))
                menu.addItem(.separator())
            }

            let duplicate = menuItem("Duplicate", action: #selector(duplicateFromContextMenu(_:)), item: item, key: "d")
            duplicate.isEnabled = canDuplicateSelection
            menu.addItem(duplicate)
            menu.addItem(menuItem("Copy", action: #selector(copyFromContextMenu(_:)), item: item, key: "c"))
            let pasteItem = menuItem("Paste", action: #selector(pasteFromContextMenu(_:)), item: item, key: "v")
            pasteItem.isEnabled = parent.canPastePart
            menu.addItem(pasteItem)
            menu.addItem(.separator())
            let canSaveAsPart = isSingleSelection && selectedGlobalContext?.isLinked != true
            let saveReusable = menuItem("Save as Template…", action: #selector(saveReusableFromContextMenu(_:)), item: item)
            let saveGlobal = menuItem("Save as Global Part…", action: #selector(saveGlobalFromContextMenu(_:)), item: item)
            saveReusable.isEnabled = canSaveAsPart
            saveGlobal.isEnabled = canSaveAsPart
            menu.addItem(saveReusable)
            menu.addItem(saveGlobal)
            menu.addItem(.separator())
            let movement = movementAvailability(for: item, isSingleSelection: isSingleSelection)
            let moveUp = menuItem("Move Up", action: #selector(moveUpFromContextMenu(_:)), item: item, key: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), modifiers: [.command, .option])
            let moveDown = menuItem("Move Down", action: #selector(moveDownFromContextMenu(_:)), item: item, key: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), modifiers: [.command, .option])
            let outdent = menuItem("Move Out of Container", action: #selector(outdentFromContextMenu(_:)), item: item, key: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), modifiers: [.command, .option])
            moveUp.isEnabled = movement.canMoveUp
            moveDown.isEnabled = movement.canMoveDown
            outdent.isEnabled = movement.canOutdent
            menu.addItem(moveUp)
            menu.addItem(moveDown)
            menu.addItem(outdent)
            menu.addItem(.separator())
            let delete = menuItem("Delete", action: #selector(deleteFromContextMenu(_:)), item: item, key: String(Character(UnicodeScalar(NSDeleteCharacter)!)), modifiers: [])
            delete.isEnabled = canDeleteSelection
            menu.addItem(delete)
            return menu
        }

        private var canDuplicateSelection: Bool {
            guard let id = parent.primarySelectedPartID,
                  parent.selectedPartIDs.count == 1,
                  let source = parent.parts.node(withID: id) else { return false }
            return parent.parts.accepts(source, at: .after(id))
        }

        private var canDeleteSelection: Bool {
            var candidate = parent.parts
            for id in parent.selectedPartIDs {
                guard candidate.permitsRemoving(id) else { return false }
                _ = candidate.extractNode(withID: id)
            }
            return !parent.selectedPartIDs.isEmpty
        }

        private struct MovementAvailability {
            let canMoveUp: Bool
            let canMoveDown: Bool
            let canOutdent: Bool
        }

        private func movementAvailability(
            for item: Item,
            isSingleSelection: Bool
        ) -> MovementAvailability {
            guard isSingleSelection else {
                return MovementAvailability(canMoveUp: false, canMoveDown: false, canOutdent: false)
            }
            let siblings = item.parent?.children ?? roots
            guard let index = siblings.firstIndex(where: { $0.id == item.id }) else {
                return MovementAvailability(canMoveUp: false, canMoveDown: false, canOutdent: false)
            }
            let canMoveUp = index > 0
                && parent.canMoveParts([item.id], .before(siblings[index - 1].id))
            let canMoveDown = index < siblings.count - 1
                && parent.canMoveParts([item.id], .after(siblings[index + 1].id))
            let canOutdent = item.parent.map {
                parent.canMoveParts([item.id], .after($0.id))
            } ?? false
            return MovementAvailability(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                canOutdent: canOutdent
            )
        }

        private func contextMenuHeader(for item: Item, selectionCount: Int) -> NSMenuItem {
            let title = selectionCount > 1 ? "\(selectionCount) Parts" : item.part.type.displayName
            let package = item.part.type.definition.package
            let author = package?.manifest.author ?? "Foundry"
            let version = package?.manifest.version ?? ""
            let subtitle = version.isEmpty ? author : "\(author)  v\(version)"
            let icon = NSImageView(image: partIcon(for: item.part) ?? NSImage())
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 36 * 0.16
            icon.layer?.masksToBounds = true
            icon.setAccessibilityLabel(title)
            icon.translatesAutoresizingMaskIntoConstraints = false

            let titleField = NSTextField(labelWithString: title)
            titleField.font = .systemFont(ofSize: 15, weight: .semibold)
            titleField.lineBreakMode = .byTruncatingTail
            let subtitleField = NSTextField(labelWithString: subtitle)
            subtitleField.font = .systemFont(ofSize: 12)
            subtitleField.textColor = .secondaryLabelColor
            subtitleField.lineBreakMode = .byTruncatingTail
            let labels = NSStackView(views: [titleField, subtitleField])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 2
            let content = NSStackView(views: [icon, labels])
            content.orientation = .horizontal
            content.alignment = .centerY
            content.spacing = 12
            content.edgeInsets = .init(top: 9, left: 10, bottom: 9, right: 10)
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 36),
                icon.heightAnchor.constraint(equalToConstant: 36),
                content.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
                content.heightAnchor.constraint(equalToConstant: 58)
            ])
            let menuItem = NSMenuItem()
            menuItem.view = content
            return menuItem
        }

        private func globalContext(for item: Item) -> (target: Item, isLinked: Bool)? {
            var current: Item? = item
            var overrideOwner: Item?
            while let candidate = current {
                if overrideOwner == nil, candidate.part.overridesGlobalDefinition == true {
                    overrideOwner = candidate
                }
                if candidate.part.reusableDefinitionID != nil {
                    return (overrideOwner ?? candidate, overrideOwner == nil)
                }
                current = candidate.parent
            }
            return nil
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
                case "d" where canDuplicateSelection: parent.duplicatePart(); return true
                case "c": parent.copyPart(); return true
                case "v" where parent.canPastePart: parent.pastePart(); return true
                default: break
                }
            }

            if modifiers == [.command, .option] {
                let selectedItem = singleSelectedItem(in: outlineView)
                let movement = selectedItem.map {
                    movementAvailability(for: $0, isSingleSelection: true)
                }
                switch event.keyCode {
                case 126:
                    if movement?.canMoveUp == true { parent.movePart(-1) }
                    return true
                case 125:
                    if movement?.canMoveDown == true { parent.movePart(1) }
                    return true
                case 123:
                    if movement?.canOutdent == true { parent.outdentPart() }
                    return true
                default: break
                }
            }

            switch event.keyCode {
            case 36, 76:
                if outlineView.selectedRowIndexes.count == 1 {
                    beginRenamingSelectedRow()
                }
                return true
            case 51, 117:
                if canDeleteSelection { parent.deletePart() }
                return true
            default:
                return false
            }
        }

        private func singleSelectedItem(in outlineView: NSOutlineView) -> Item? {
            guard outlineView.selectedRowIndexes.count == 1,
                  outlineView.selectedRow >= 0 else { return nil }
            return outlineView.item(atRow: outlineView.selectedRow) as? Item
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
            perform(sender, action: parent.duplicatePart)
        }

        @objc private func copyFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.copyPart)
        }

        @objc private func pasteFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.pastePart)
        }

        @objc private func saveReusableFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender) else { return }
            selectForContextAction(item)
            parent.saveAsReusablePart(item.part.name)
        }

        @objc private func saveGlobalFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender) else { return }
            selectForContextAction(item)
            parent.saveAsGlobalPart(item.part.name)
        }

        @objc private func makeLocalOverrideFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender) else { return }
            parent.setGlobalPartLinked(item.id, false)
        }

        @objc private func relinkGlobalFromContextMenu(_ sender: NSMenuItem) {
            guard let item = contextItem(from: sender) else { return }
            parent.setGlobalPartLinked(item.id, true)
        }

        @objc private func moveUpFromContextMenu(_ sender: NSMenuItem) {
            perform(sender) { parent.movePart(-1) }
        }

        @objc private func moveDownFromContextMenu(_ sender: NSMenuItem) {
            perform(sender) { parent.movePart(1) }
        }

        @objc private func outdentFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.outdentPart)
        }

        @objc private func deleteFromContextMenu(_ sender: NSMenuItem) {
            perform(sender, action: parent.deletePart)
        }

        @objc private func moveToAvailableDropZone(_ sender: NSMenuItem) {
            guard let destination = sender.representedObject as? DropZoneRecoveryDestination else { return }
            _ = parent.moveParts(
                [destination.partID],
                .insideSlot(destination.parentID, destination.slotID)
            )
        }

        private func unavailableChildAreaRecoveryMenu(for item: Item) -> NSMenuItem? {
            guard unavailableChildArea(for: item) != nil,
                  let parentItem = item.parent,
                  let package = parentItem.part.type.definition.package else { return nil }
            let submenu = NSMenu(title: "Move to Child Area")
            for name in package.dropZoneNames {
                let slotID = package.dropZoneSlotID(for: name)
                guard parent.parts.accepts(item.part, at: .insideSlot(parentItem.id, slotID)) else { continue }
                let menuItem = NSMenuItem(
                    title: "Drop zone: \(name)",
                    action: #selector(moveToAvailableDropZone(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = DropZoneRecoveryDestination(
                    partID: item.id,
                    parentID: parentItem.id,
                    slotID: slotID
                )
                submenu.addItem(menuItem)
            }
            for slot in package.manifest.slots {
                guard parent.parts.accepts(item.part, at: .insideSlot(parentItem.id, slot.id)) else { continue }
                let menuItem = NSMenuItem(
                    title: "Child picker: \(slot.title)",
                    action: #selector(moveToAvailableDropZone(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = DropZoneRecoveryDestination(
                    partID: item.id,
                    parentID: parentItem.id,
                    slotID: slot.id
                )
                submenu.addItem(menuItem)
            }
            guard !submenu.items.isEmpty else { return nil }
            let rootItem = NSMenuItem(title: "Move to Child Area", action: nil, keyEquivalent: "")
            rootItem.submenu = submenu
            return rootItem
        }

        private func perform(_ sender: NSMenuItem, action: () -> Void) {
            guard let item = contextItem(from: sender) else { return }
            selectForContextAction(item)
            action()
        }

        private func contextItem(from sender: NSMenuItem) -> Item? {
            guard let partID = sender.representedObject as? UUID else { return nil }
            return itemsByID[partID]
        }

        private func selectForContextAction(_ item: Item) {
            guard let outlineView else { return }
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            if parent.selectedPartIDs.contains(item.id) {
                parent.primarySelectedPartID = item.id
                return
            }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            parent.selectedPartIDs = [item.id]
            parent.primarySelectedPartID = item.id
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField,
                  let identifier = textField.identifier?.rawValue,
                  let partID = UUID(uuidString: identifier),
                  let item = itemsByID[partID] else { return }
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                textField.stringValue = item.part.name
                return
            }
            guard name != item.part.name else { return }
            parent.renamePart(partID, name)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRestoringSelection, let outlineView else { return }
            let selectedIDs = Set(outlineView.selectedRowIndexes.compactMap { row in
                (outlineView.item(atRow: row) as? Item)?.id
            })
            parent.selectedPartIDs = selectedIDs
            let primaryRow = outlineView.selectedRow
            parent.primarySelectedPartID = primaryRow >= 0
                ? (outlineView.item(atRow: primaryRow) as? Item)?.id
                : nil
            lastRequestedSelectedIDs = selectedIDs
            lastRequestedPrimaryID = parent.primarySelectedPartID
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            synchronizeExpansionState()
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            synchronizeExpansionState()
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let item = item as? Item else { return nil }
            let pasteboardItem = NSPasteboardItem()
            let selectedIDs = canonicalDraggedIDs(including: item.id)
            let payload: PartDragPayload = selectedIDs.count > 1
                ? .nodes(selectedIDs)
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
            guard let payload = payload(from: info),
                  let proposal = dropProposal(
                    in: outlineView,
                    info: info,
                    proposedItem: item as? Item,
                    proposedChildIndex: index
                  ) else {
                describeRejectedDrop("That part cannot contain other parts.")
                return []
            }
            guard canApply(payload, to: proposal.placement) else {
                describeRejectedDrop("Parts cannot be moved into themselves or their descendants.")
                return []
            }
            outlineView.setDropItem(proposal.parentItem, dropChildIndex: proposal.childIndex)
            describeAcceptedDrop()
            return payload.isNode ? .move : .copy
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let payload = payload(from: info),
                  let placement = placement(parent: item as? Item, childIndex: index) else { return false }
            let accepted: Bool
            switch payload {
            case .library(let type):
                accepted = parent.insertPart(type, placement)
            case .reusable(let id):
                accepted = parent.insertReusablePart(id, placement)
            case .global(let id):
                accepted = parent.insertGlobalPart(id, placement)
            case .node(let id):
                accepted = parent.moveParts([id], placement)
            case .nodes(let ids):
                accepted = parent.moveParts(ids, placement)
            }
            if accepted {
                expandDestination(for: placement)
            }
            return accepted
        }

        private struct DropProposal {
            let parentItem: Item?
            let childIndex: Int
            let placement: PartPlacement
        }

        private func dropProposal(
            in outlineView: NSOutlineView,
            info: any NSDraggingInfo,
            proposedItem item: Item?,
            proposedChildIndex index: Int
        ) -> DropProposal? {
            guard index == NSOutlineViewDropOnItemIndex, let item else {
                guard let placement = placement(parent: item, childIndex: index) else { return nil }
                return DropProposal(parentItem: item, childIndex: index, placement: placement)
            }

            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return nil }
            let rowFrame = outlineView.rect(ofRow: row)
            let location = outlineView.convert(info.draggingLocation, from: nil)
            let position = rowFrame.height > 0 ? (location.y - rowFrame.minY) / rowFrame.height : 0.5

            if item.part.type.definition.allowsChildren {
                return DropProposal(
                    parentItem: item,
                    childIndex: NSOutlineViewDropOnItemIndex,
                    placement: insidePlacement(for: item)
                )
            }

            let parentItem = outlineView.parent(forItem: item) as? Item
            let itemIndex = outlineView.childIndex(forItem: item)
            guard itemIndex >= 0 else { return nil }
            let childIndex = position < 0.5 ? itemIndex : itemIndex + 1
            guard let placement = placement(parent: parentItem, childIndex: childIndex) else { return nil }
            return DropProposal(parentItem: parentItem, childIndex: childIndex, placement: placement)
        }

        private func insidePlacement(for item: Item) -> PartPlacement {
            if !item.children.isEmpty {
                return item.children.map(\.part).endPlacement(in: item.id)
            }
            if let package = item.part.type.definition.package,
               let slotID = package.dropZoneNames.first.map(package.dropZoneSlotID(for:))
                    ?? package.manifest.slots.first?.id {
                return .insideSlot(item.id, slotID)
            }
            return .inside(item.id)
        }

        private func expandDestination(for placement: PartPlacement) {
            let destinationID: UUID
            switch placement {
            case .inside(let id), .insideSlot(let id, _): destinationID = id
            case .before, .after, .end: return
            }
            parent.expandedItemIDs.insert(destinationID)
            if let item = itemsByID[destinationID] {
                outlineView?.expandItem(item)
            }
        }

        private func canonicalDraggedIDs(including clickedID: UUID) -> [UUID] {
            let requestedIDs = parent.selectedPartIDs.contains(clickedID)
                ? parent.selectedPartIDs
                : [clickedID]
            let flattenedIDs = flattenedItems(roots).map(\.id)
            return flattenedIDs.filter { id in
                guard requestedIDs.contains(id) else { return false }
                return (ancestorPath(of: id, in: roots) ?? [])
                    .allSatisfy { !requestedIDs.contains($0.id) }
            }
        }

        private func flattenedItems(_ items: [Item]) -> [Item] {
            items.flatMap { [$0] + flattenedItems($0.children) }
        }

        private func canApply(_ payload: PartDragPayload, to placement: PartPlacement) -> Bool {
            switch payload {
            case .node(let id): return parent.canMoveParts([id], placement)
            case .nodes(let nodeIDs): return parent.canMoveParts(nodeIDs, placement)
            case .library, .reusable, .global: return true
            }
        }

        private func describeRejectedDrop(_ reason: String) {
            outlineView?.toolTip = reason
            outlineView?.setAccessibilityHelp(reason)
        }

        private func describeAcceptedDrop() {
            outlineView?.toolTip = StructureOutlineView.dropGuidance
            outlineView?.setAccessibilityHelp(StructureOutlineView.dropGuidance)
        }

        private func placement(parent item: Item?, childIndex index: Int) -> PartPlacement? {
            let siblings = item?.children ?? roots
            if index == NSOutlineViewDropOnItemIndex {
                guard let item, item.part.type.definition.allowsChildren else { return nil }
                return .inside(item.id)
            }
            if siblings.indices.contains(index) {
                return .before(siblings[index].id)
            }
            if let item {
                return siblings.map(\.part).endPlacement(in: item.id)
            }
            return .end
        }

        private func payload(from info: any NSDraggingInfo) -> PartDragPayload? {
            guard let value = info.draggingPasteboard.string(forType: .string) else { return nil }
            return PartDragPayload(value)
        }

        private func children(of item: Any?) -> [Item] {
            (item as? Item)?.children ?? roots
        }

        private func makeItem(_ part: PartNode, parent: Item? = nil) -> Item {
            let item = Item(part: part, parent: parent)
            itemsByID[item.id] = item
            item.children = part.children.map { makeItem($0, parent: item) }
            return item
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> StructureOutlineCell {
            let cell = StructureOutlineCell()
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
            cell.globalIndicator.symbolConfiguration = .init(pointSize: 11, weight: .regular)
            cell.globalIndicator.imageScaling = .scaleProportionallyUpOrDown
            cell.globalIndicator.translatesAutoresizingMaskIntoConstraints = false
            cell.warningIndicator.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            cell.warningIndicator.contentTintColor = .systemOrange
            cell.warningIndicator.imageScaling = .scaleProportionallyUpOrDown
            cell.warningIndicator.translatesAutoresizingMaskIntoConstraints = false
            cell.unavailableDropZoneLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.unavailableDropZoneLabel.textColor = .systemOrange
            cell.unavailableDropZoneLabel.lineBreakMode = .byTruncatingTail
            cell.unavailableDropZoneLabel.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.addSubview(cell.unavailableDropZoneLabel)
            cell.addSubview(cell.warningIndicator)
            cell.addSubview(cell.globalIndicator)
            cell.imageView = imageView
            cell.textField = textField
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.unavailableDropZoneLabel.leadingAnchor, constant: -5),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cell.unavailableDropZoneLabel.trailingAnchor.constraint(equalTo: cell.warningIndicator.leadingAnchor, constant: -4),
                cell.unavailableDropZoneLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cell.warningIndicator.trailingAnchor.constraint(equalTo: cell.globalIndicator.leadingAnchor, constant: -5),
                cell.warningIndicator.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cell.warningIndicator.widthAnchor.constraint(equalToConstant: 14),
                cell.globalIndicator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                cell.globalIndicator.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cell.globalIndicator.widthAnchor.constraint(equalToConstant: 14)
            ])
            return cell
        }

        private func expandedItemIDs() -> Set<UUID> {
            guard let outlineView else { return [] }
            return Set(itemsByID.values.compactMap { outlineView.isItemExpanded($0) ? $0.id : nil })
        }

        private func restoreExpansion(in items: [Item], expandedIDs: Set<UUID>) {
            for item in items {
                if expandedIDs.contains(item.id) {
                    outlineView?.expandItem(item)
                }
                restoreExpansion(in: item.children, expandedIDs: expandedIDs)
            }
        }

        private func synchronizeExpansionState() {
            guard !isRestoringExpansion else { return }
            parent.expandedItemIDs = expandedItemIDs()
        }

        private func restoreSelection(_ selectedIDs: Set<UUID>, reveal: Bool) {
            guard let outlineView else { return }
            isRestoringSelection = true
            isRestoringExpansion = true
            defer {
                isRestoringSelection = false
                isRestoringExpansion = false
            }
            if reveal {
                for id in selectedIDs {
                    for ancestor in ancestorPath(of: id, in: roots) ?? [] {
                        outlineView.expandItem(ancestor)
                    }
                }
            }
            let rows = IndexSet(selectedIDs.compactMap { id in
                guard let item = itemsByID[id] else { return nil }
                let row = outlineView.row(forItem: item)
                return row >= 0 ? row : nil
            })
            if outlineView.selectedRowIndexes != rows {
                outlineView.selectRowIndexes(rows, byExtendingSelection: false)
            }
            if reveal,
               let primaryID = parent.primarySelectedPartID,
               let primaryItem = itemsByID[primaryID] {
                let row = outlineView.row(forItem: primaryItem)
                if row >= 0 {
                    outlineView.scrollRowToVisible(row)
                }
            }
        }

        private func ancestorPath(of id: UUID, in items: [Item]) -> [Item]? {
            for item in items {
                if item.id == id { return [] }
                if let descendantPath = ancestorPath(of: id, in: item.children) {
                    return [item] + descendantPath
                }
            }
            return nil
        }

        private func displayName(for part: PartNode) -> String {
            part.reusableDefinitionID.flatMap { parent.globalPartNames[$0] } ?? part.name
        }

        private struct UnavailableChildArea {
            let label: String
        }

        private func unavailableChildArea(for item: Item) -> UnavailableChildArea? {
            guard let slotID = item.part.slotID,
                  let parentPackage = item.parent?.part.type.definition.package else { return nil }
            if let name = LoadedPartPackage.dropZoneName(forSlotID: slotID) {
                return parentPackage.isDropZoneSlotID(slotID)
                    ? nil
                    : UnavailableChildArea(label: "Unavailable drop zone: \(name)")
            }
            return parentPackage.manifest.slots.contains(where: { $0.id == slotID })
                ? nil
                : UnavailableChildArea(label: "Unavailable child picker: \(slotID)")
        }

        private func flattenedSignature(_ parts: [PartNode], parentID: UUID?) -> [String] {
            parts.flatMap {
                [
                    "\($0.id.uuidString):\(parentID?.uuidString ?? "root"):\($0.slotID ?? "default"):\(displayName(for: $0)):\($0.type.rawValue):\($0.type.systemImage):\($0.type.definition.package?.iconURL.path ?? "system"):\($0.type.definition.package?.dropZoneNames.joined(separator: ",") ?? "none"):\($0.reusableDefinitionID?.uuidString ?? "local"):\($0.overridesGlobalDefinition == true)"
                ] + flattenedSignature($0.children, parentID: $0.id)
            }
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

/// Keeps the outline's drop surface at least as tall as the visible panel.
/// Without this, the apparent empty area below the final row belongs only to
/// the clip view, so AppKit continues targeting the final row during a drag.
private final class StructureScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let outlineView = documentView as? NSOutlineView else { return }

        let rowsHeight: CGFloat
        if outlineView.numberOfRows > 0 {
            rowsHeight = outlineView.rect(ofRow: outlineView.numberOfRows - 1).maxY
        } else {
            rowsHeight = 0
        }
        let desiredSize = NSSize(
            width: contentView.bounds.width,
            height: max(contentView.bounds.height, rowsHeight)
        )
        if outlineView.frame.size != desiredSize {
            outlineView.setFrameSize(desiredSize)
        }
    }
}

private final class Item: NSObject {
    let part: PartNode
    weak var parent: Item?
    var children: [Item] = []
    var id: UUID { part.id }

    init(part: PartNode, parent: Item?) {
        self.part = part
        self.parent = parent
    }
}

private final class StructureOutlineCell: NSTableCellView {
    let globalIndicator = NSImageView()
    let warningIndicator = NSImageView()
    let unavailableDropZoneLabel = NSTextField(labelWithString: "")
}

private final class DropZoneRecoveryDestination: NSObject {
    let partID: UUID
    let parentID: UUID
    let slotID: String

    init(partID: UUID, parentID: UUID, slotID: String) {
        self.partID = partID
        self.parentID = parentID
        self.slotID = slotID
    }
}

private extension PartDragPayload {
    var isNode: Bool {
        switch self {
        case .node, .nodes: true
        case .library, .reusable, .global: false
        }
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let partColumn = NSUserInterfaceItemIdentifier("StructurePartColumn")
    static let partCell = NSUserInterfaceItemIdentifier("StructurePartCell")
}
