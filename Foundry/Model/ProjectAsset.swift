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
    var exportPath: String { "assets/images/" + storageFilename }
    var reference: String { "foundry-asset:" + id.uuidString }

    private var fileExtension: String {
        let value = (filename as NSString).pathExtension.lowercased()
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
