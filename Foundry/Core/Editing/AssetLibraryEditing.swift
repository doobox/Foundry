import Foundation

nonisolated extension Array where Element == ProjectAssetNode {
    var resourcesOnly: [ProjectAssetNode] {
        compactMap { node in
            switch node {
            case .asset(let asset):
                return asset.exportDirectory == nil ? node : nil
            case .folder(var folder):
                folder.children = folder.children.resourcesOnly
                return .folder(folder)
            }
        }
    }

    func node(withID id: UUID) -> ProjectAssetNode? {
        for node in self {
            if node.id == id { return node }
            if case .folder(let folder) = node,
               let match = folder.children.node(withID: id) {
                return match
            }
        }
        return nil
    }

    mutating func insert(_ node: ProjectAssetNode, at placement: AssetPlacement) -> Bool {
        switch placement {
        case .end:
            append(node)
            return true
        case .inside(let folderID):
            return mutateFolder(id: folderID) { $0.children.append(node) }
        case .before(let nodeID):
            return insert(node, adjacentTo: nodeID, offset: 0)
        case .after(let nodeID):
            return insert(node, adjacentTo: nodeID, offset: 1)
        }
    }

    mutating func move(id: UUID, to placement: AssetPlacement) -> Bool {
        guard !placement.targets(id),
              let node = node(withID: id),
              !node.containsTargetFolder(for: placement) else { return false }
        var copy = self
        guard let removed = copy.removeNode(id: id), copy.insert(removed, at: placement) else { return false }
        self = copy
        return true
    }

    @discardableResult
    mutating func removeNode(id: UUID) -> ProjectAssetNode? {
        if let index = firstIndex(where: { $0.id == id }) {
            return remove(at: index)
        }
        for index in indices {
            guard case .folder(var folder) = self[index],
                  let removed = folder.children.removeNode(id: id) else { continue }
            self[index] = .folder(folder)
            return removed
        }
        return nil
    }

    mutating func renameFolder(id: UUID, to name: String) -> Bool {
        mutateFolder(id: id) { $0.name = name }
    }

    mutating func renameAsset(id: UUID, to filename: String) -> Bool {
        for index in indices {
            switch self[index] {
            case .asset(var asset) where asset.id == id:
                asset.filename = filename
                self[index] = .asset(asset)
                return true
            case .folder(var folder):
                if folder.children.renameAsset(id: id, to: filename) {
                    self[index] = .folder(folder)
                    return true
                }
            case .asset:
                continue
            }
        }
        return false
    }

    mutating func setVideoMetadata(
        id: UUID,
        metadata: ProjectVideoMetadata,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> Bool {
        for index in indices {
            switch self[index] {
            case .asset(var asset) where asset.id == id:
                asset.videoMetadata = metadata
                asset.pixelWidth = pixelWidth
                asset.pixelHeight = pixelHeight
                self[index] = .asset(asset)
                return true
            case .folder(var folder):
                if folder.children.setVideoMetadata(
                    id: id,
                    metadata: metadata,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight
                ) {
                    self[index] = .folder(folder)
                    return true
                }
            case .asset:
                continue
            }
        }
        return false
    }

    mutating func clearExportDirectory(forAssetID id: UUID) -> Bool {
        for index in indices {
            switch self[index] {
            case .asset(var asset) where asset.id == id:
                asset.exportDirectory = nil
                asset.exportOrder = 0
                self[index] = .asset(asset)
                return true
            case .folder(var folder):
                if folder.children.clearExportDirectory(forAssetID: id) {
                    self[index] = .folder(folder)
                    return true
                }
            case .asset:
                continue
            }
        }
        return false
    }

    private mutating func insert(_ node: ProjectAssetNode, adjacentTo targetID: UUID, offset: Int) -> Bool {
        if let index = firstIndex(where: { $0.id == targetID }) {
            insert(node, at: index + offset)
            return true
        }
        for index in indices {
            guard case .folder(var folder) = self[index],
                  folder.children.insert(node, adjacentTo: targetID, offset: offset) else { continue }
            self[index] = .folder(folder)
            return true
        }
        return false
    }

    private mutating func mutateFolder(id: UUID, mutation: (inout ProjectAssetFolder) -> Void) -> Bool {
        for index in indices {
            switch self[index] {
            case .asset:
                continue
            case .folder(var folder):
                if folder.id == id {
                    mutation(&folder)
                    self[index] = .folder(folder)
                    return true
                }
                if folder.children.mutateFolder(id: id, mutation: mutation) {
                    self[index] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }
}

nonisolated private extension ProjectAssetNode {
    func containsTargetFolder(for placement: AssetPlacement) -> Bool {
        guard case .folder(let folder) = self,
              case .inside(let targetID) = placement else { return false }
        return folder.id == targetID || folder.children.node(withID: targetID) != nil
    }
}

nonisolated private extension AssetPlacement {
    func targets(_ id: UUID) -> Bool {
        switch self {
        case .end: false
        case .inside(let folderID): folderID == id
        case .before(let nodeID), .after(let nodeID): nodeID == id
        }
    }
}
