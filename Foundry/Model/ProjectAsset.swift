import Foundation

nonisolated struct ProjectAsset: Codable, Equatable, Identifiable, Sendable {
    enum ExportDirectory: Codable, Equatable, Sendable {
        case root
        case folder(UUID)
    }

    let id: UUID
    var filename: String
    var mediaType: String
    var byteCount: Int
    var exportDirectory: ExportDirectory?
    var exportOrder: Int

    init(
        id: UUID = UUID(),
        filename: String,
        mediaType: String,
        byteCount: Int,
        exportDirectory: ExportDirectory? = nil,
        exportOrder: Int = 0
    ) {
        self.id = id
        self.filename = filename
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.exportDirectory = exportDirectory
        self.exportOrder = exportOrder
    }

    var storageFilename: String { id.uuidString + "." + fileExtension }
    var exportPath: String { "assets/" + storageFilename }
    var reference: String { "foundry-asset:" + id.uuidString }

    var readableExportFilename: String {
        let lastComponent = (filename as NSString).lastPathComponent
        let stem = (lastComponent as NSString).deletingPathExtension
        let readableStem = stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "file" : Page.slugify(stem)
        return readableStem + "." + fileExtension
    }

    private var fileExtension: String {
        let value = (filename as NSString).pathExtension.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return value.isEmpty ? "bin" : value
    }

    private enum CodingKeys: String, CodingKey {
        case id, filename, mediaType, byteCount, exportDirectory, exportOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        exportDirectory = try container.decodeIfPresent(ExportDirectory.self, forKey: .exportDirectory)
        exportOrder = try container.decodeIfPresent(Int.self, forKey: .exportOrder) ?? 0
    }
}

nonisolated struct ProjectAssetFolder: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var children: [ProjectAssetNode]

    init(id: UUID = UUID(), name: String, children: [ProjectAssetNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

nonisolated indirect enum ProjectAssetNode: Codable, Equatable, Identifiable, Sendable {
    case folder(ProjectAssetFolder)
    case asset(ProjectAsset)

    var id: UUID {
        switch self {
        case .folder(let folder): folder.id
        case .asset(let asset): asset.id
        }
    }
}

nonisolated extension Array where Element == ProjectAssetNode {
    func managedExportPath(for asset: ProjectAsset) -> String {
        managedExportPaths()[asset.id] ?? asset.exportPath
    }

    func managedExportPaths() -> [UUID: String] {
        var paths: [UUID: String] = [:]

        func collect(_ nodes: [ProjectAssetNode], under components: [String]) {
            let assets = nodes.compactMap { node -> ProjectAsset? in
                guard case .asset(let asset) = node else { return nil }
                return asset
            }
            let folders = nodes.compactMap { node -> ProjectAssetFolder? in
                guard case .folder(let folder) = node else { return nil }
                return folder
            }
            let filenameCounts = Dictionary(grouping: assets) {
                $0.readableExportFilename.lowercased()
            }.mapValues(\.count)
            let folderNameCounts = Dictionary(grouping: folders) {
                Page.slugify($0.name).lowercased()
            }.mapValues(\.count)

            for asset in assets {
                var filename = asset.readableExportFilename
                if filenameCounts[filename.lowercased(), default: 0] > 1 {
                    let base = (filename as NSString).deletingPathExtension
                    let ext = (filename as NSString).pathExtension
                    let suffix = asset.id.uuidString.lowercased().prefix(8)
                    filename = "\(base)--\(suffix).\(ext)"
                }
                paths[asset.id] = (components + [filename]).joined(separator: "/")
            }

            for folder in folders {
                let readableName = Page.slugify(folder.name)
                let exportName = folderNameCounts[readableName.lowercased(), default: 0] > 1
                    ? "\(readableName)--\(folder.id.uuidString.lowercased().prefix(8))"
                    : readableName
                collect(folder.children, under: components + [exportName])
            }
        }

        collect(self, under: ["assets"])
        return paths
    }
}

nonisolated enum AssetPlacement: Equatable, Sendable {
    case end
    case inside(folderID: UUID)
    case before(nodeID: UUID)
    case after(nodeID: UUID)
}

nonisolated struct ProjectAssetContent: Equatable, Sendable {
    let asset: ProjectAsset
    let data: Data
}

nonisolated extension String {
    var foundryAssetID: UUID? {
        guard hasPrefix("foundry-asset:") else { return nil }
        return UUID(uuidString: String(dropFirst("foundry-asset:".count)))
    }
}
