import AppKit
import SwiftUI

struct AssetsOutlineView: NSViewRepresentable {
    let nodes: [ProjectAssetNode]
    let assetContents: [UUID: ProjectAssetContent]
    @Binding var selectedNodeID: UUID?
    let moveNode: (UUID, AssetPlacement) -> Bool
    let importURLs: ([URL], AssetPlacement) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let column = NSTableColumn(identifier: .assetColumn)
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
        outlineView.registerForDraggedTypes([.assetNode, .fileURL])
        outlineView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
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
        var parent: AssetsOutlineView
        weak var outlineView: NSOutlineView?
        private var roots: [AssetOutlineItem] = []
        private var itemsByID: [UUID: AssetOutlineItem] = [:]
        private var displayedSignature: [String] = []
        private var isRestoringSelection = false
        private var dragTemporaryDirectories: [URL] = []

        init(parent: AssetsOutlineView) { self.parent = parent }

        func reload(nodes: [ProjectAssetNode], selectedNodeID: UUID?) {
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
            (item as? AssetOutlineItem)?.isFolder == true
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? AssetOutlineItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier.assetCell
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                ?? makeCell(identifier: identifier)
            cell.textField?.stringValue = item.title
            cell.imageView?.image = NSImage(
                systemSymbolName: item.systemImage,
                accessibilityDescription: item.title
            )
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRestoringSelection, let outlineView else { return }
            let row = outlineView.selectedRow
            parent.selectedNodeID = row >= 0
                ? (outlineView.item(atRow: row) as? AssetOutlineItem)?.id
                : nil
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let item = item as? AssetOutlineItem else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString("foundry-asset-node:\(item.id.uuidString)", forType: .assetNode)
            if case .asset(let asset) = item.node {
                let isImage = asset.mediaType.hasPrefix("image/")
                let prefix = isImage ? "foundry-image-asset:" : "foundry-asset:"
                pasteboardItem.setString(prefix + asset.id.uuidString, forType: .string)
                if isImage {
                    pasteboardItem.setString(asset.id.uuidString, forType: .imageAsset)
                    if let content = parent.assetContents[asset.id],
                       let fileURL = temporaryDragFile(for: content) {
                        pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)
                    }
                }
            }
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            for directory in dragTemporaryDirectories {
                try? FileManager.default.removeItem(at: directory)
            }
            dragTemporaryDirectories.removeAll(keepingCapacity: true)
        }

        private func temporaryDragFile(for content: ProjectAssetContent) -> URL? {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "FoundryAssetDrag-\(UUID().uuidString)", directoryHint: .isDirectory)
            let originalName = (content.asset.filename as NSString).lastPathComponent
            guard !originalName.isEmpty else { return nil }
            let filename = "foundry-image-asset-\(content.asset.id.uuidString)--\(originalName)"
            let fileURL = directory.appending(path: filename)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try content.data.write(to: fileURL, options: .atomic)
                dragTemporaryDirectories.append(directory)
                return fileURL
            } catch {
                try? FileManager.default.removeItem(at: directory)
                return nil
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard internalNodeID(from: info) != nil || !fileURLs(from: info).isEmpty else { return [] }
            if index == NSOutlineViewDropOnItemIndex,
               (item as? AssetOutlineItem)?.isFolder != true {
                return []
            }
            return internalNodeID(from: info) == nil ? .copy : .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let placement = placement(parent: item as? AssetOutlineItem, childIndex: index) else {
                return false
            }
            if let nodeID = internalNodeID(from: info) {
                return parent.moveNode(nodeID, placement)
            }
            let urls = fileURLs(from: info)
            guard !urls.isEmpty else { return false }
            parent.importURLs(urls, placement)
            return true
        }

        private func placement(parent item: AssetOutlineItem?, childIndex index: Int) -> AssetPlacement? {
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
            guard let value = info.draggingPasteboard.string(forType: .assetNode),
                  value.hasPrefix("foundry-asset-node:") else { return nil }
            return UUID(uuidString: String(value.dropFirst("foundry-asset-node:".count)))
        }

        private func fileURLs(from info: any NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        }

        private func children(of item: Any?) -> [AssetOutlineItem] {
            (item as? AssetOutlineItem)?.children ?? roots
        }

        private func makeItem(_ node: ProjectAssetNode) -> AssetOutlineItem {
            let item = AssetOutlineItem(node: node)
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
                ? (outlineView.item(atRow: outlineView.selectedRow) as? AssetOutlineItem)?.id
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
        private func expandAncestors(of id: UUID, in items: [AssetOutlineItem]) -> Bool {
            for item in items {
                if item.id == id { return true }
                if expandAncestors(of: id, in: item.children) {
                    outlineView?.expandItem(item)
                    return true
                }
            }
            return false
        }

        private func flattenedSignature(_ nodes: [ProjectAssetNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node {
                case .asset(let asset):
                    return ["a:\(asset.id):\(asset.filename):\(asset.mediaType):\(asset.byteCount)"]
                case .folder(let folder):
                    return ["f:\(folder.id):\(folder.name)"] + flattenedSignature(folder.children)
                }
            }
        }
    }
}

private final class AssetOutlineItem: NSObject {
    let node: ProjectAssetNode
    var children: [AssetOutlineItem] = []
    var id: UUID { node.id }
    var isFolder: Bool { if case .folder = node { return true }; return false }
    var title: String {
        switch node {
        case .asset(let asset): asset.filename
        case .folder(let folder): folder.name
        }
    }
    var systemImage: String {
        switch node {
        case .folder: "folder"
        case .asset(let asset):
            asset.mediaType.hasPrefix("image/") ? "photo" : "doc"
        }
    }

    init(node: ProjectAssetNode) { self.node = node }
}

extension NSPasteboard.PasteboardType {
    static let assetNode = NSPasteboard.PasteboardType("uk.co.garysimpson.foundry.asset-node")
    static let imageAsset = NSPasteboard.PasteboardType("uk.co.garysimpson.foundry.image-asset")
}


private extension NSUserInterfaceItemIdentifier {
    static let assetColumn = NSUserInterfaceItemIdentifier("AssetsColumn")
    static let assetCell = NSUserInterfaceItemIdentifier("AssetsCell")
}
