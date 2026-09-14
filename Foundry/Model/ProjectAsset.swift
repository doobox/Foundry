import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PartImageProcessor {
    static let canonicalMaximumDimension = 3_840

    struct Result: Sendable {
        let data: Data
        let metadata: PartImageMetadata
    }

    static func canonicalize(data: Data, filename: String, mimeType: String) -> Result {
        resized(data: data, filename: filename, mimeType: mimeType, maximumDimension: canonicalMaximumDimension)
            ?? Result(data: data, metadata: .inspect(data: data, filename: filename, mimeType: mimeType))
    }

    static func rendition(
        data: Data, filename: String, mimeType: String, maximumDimension: Int,
        cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "Foundry/ImageRenditions-v1", directoryHint: .isDirectory)
    ) -> Result? {
        let dimension = min(max(maximumDimension, 1), canonicalMaximumDimension)
        let metadata = PartImageMetadata.inspect(data: data, filename: filename, mimeType: mimeType)
        guard let width = metadata.width, let height = metadata.height, max(width, height) > dimension else { return nil }
        // Include processing version, source bytes and output-affecting inputs. No
        // project paths or asset IDs: identical sources can share a cached variant.
        var hash = SHA256()
        hash.update(data: data)
        hash.update(data: Data("\u{0}v1\u{0}\(dimension)\u{0}\(filename)\u{0}\(mimeType)".utf8))
        let key = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let cachedURL = cacheDirectory?.appending(path: key)
        if let cachedURL,
           let cached = try? Data(contentsOf: cachedURL, options: .mappedIfSafe),
           let source = CGImageSourceCreateWithData(cached as CFData, nil),
           CGImageSourceCreateImageAtIndex(source, 0, nil) != nil {
            let ext = renditionFileExtension(data: data, fallback: (filename as NSString).pathExtension)
            let outputName = ext == (filename as NSString).pathExtension ? filename : (filename as NSString).deletingPathExtension + "." + ext
            let outputMIMEType = CGImageSourceGetType(source).flatMap { UTType($0 as String)?.preferredMIMEType } ?? mimeType
            let cachedMetadata = PartImageMetadata.inspect(data: cached, filename: outputName, mimeType: outputMIMEType)
            if max(cachedMetadata.width ?? 0, cachedMetadata.height ?? 0) == dimension {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cachedURL.path)
                return Result(data: cached, metadata: cachedMetadata)
            }
        }
        guard let result = resized(data: data, filename: filename, mimeType: mimeType, maximumDimension: dimension) else { return nil }
        if let cacheDirectory, let cachedURL {
            // Cache failures must never prevent preview or export. Atomic replacement
            // also allows concurrent renders to safely request the same variant.
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                try result.data.write(to: cachedURL, options: .atomic)
                trimRenditionCache(cacheDirectory)
            } catch { /* The generated result remains usable without a cache. */ }
        }
        return result
    }

    private static func trimRenditionCache(_ directory: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard url.lastPathComponent.count == 64,
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = entries.reduce(0) { $0 + $1.1 }
        for (url, bytes, _) in entries where size > 256 * 1_024 * 1_024 {
            if (try? FileManager.default.removeItem(at: url)) != nil { size -= bytes }
        }
    }

    static func renditionFileExtension(data: Data, fallback: String) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              !(CGImageDestinationCopyTypeIdentifiers() as NSArray).contains(sourceType) else {
            return fallback
        }
        return "png"
    }

    private static func resized(data: Data, filename: String, mimeType: String, maximumDimension: Int) -> Result? {
        guard mimeType.hasPrefix("image/"), mimeType != "image/svg+xml",
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let sourceType = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              max(width, height) > maximumDimension else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let canPreserveType = (CGImageDestinationCopyTypeIdentifiers() as NSArray).contains(sourceType)
        let destinationType = canPreserveType ? sourceType : UTType.png.identifier as CFString
        let outputFilename = canPreserveType
            ? filename
            : (filename as NSString).deletingPathExtension + ".png"
        let outputMIMEType = UTType(String(destinationType))?.preferredMIMEType
            ?? (canPreserveType ? mimeType : "image/png")
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, destinationType, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let processed = output as Data
        return Result(
            data: processed,
            metadata: .inspect(data: processed, filename: outputFilename, mimeType: outputMIMEType)
        )
    }
}

nonisolated struct PartImageMetadata: Equatable, Sendable {
    let width: Int?
    let height: Int?
    let mimeType: String
    let byteCount: Int
    let filename: String

    var fileExtension: String {
        (filename as NSString).pathExtension.lowercased()
    }

    var aspectRatio: Double? {
        guard let width, let height, height > 0 else { return nil }
        return Double(width) / Double(height)
    }

    static func inspect(
        data: Data,
        filename: String,
        mimeType: String
    ) -> PartImageMetadata {
        let dimensions = imageDimensions(in: data)
        return PartImageMetadata(
            width: dimensions?.width,
            height: dimensions?.height,
            mimeType: mimeType,
            byteCount: data.count,
            filename: filename
        )
    }

    private static func imageDimensions(in data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth > 0,
              rawHeight > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return [5, 6, 7, 8].contains(orientation)
            ? (rawHeight, rawWidth)
            : (rawWidth, rawHeight)
    }
}

nonisolated enum PartImageTemplateValues {
    static func focalPoint(from value: PartProperty.Value) -> (x: Double, y: Double) {
        let values = value.arrayValue ?? []
        return (
            values.indices.contains(0) ? values[0].numberValue ?? 50 : 50,
            values.indices.contains(1) ? values[1].numberValue ?? 50 : 50
        )
    }

    static func insert(
        propertyID: String,
        href: String,
        alt: String,
        focalPointX: Double,
        focalPointY: Double,
        metadata: PartImageMetadata?,
        into values: inout [String: PartPackageValue]
    ) {
        values[propertyID + ".href"] = .string(href)
        values[propertyID + ".alt"] = .string(alt)
        values[propertyID + ".focalPointX"] = .number(focalPointX)
        values[propertyID + ".focalPointY"] = .number(focalPointY)
        values[propertyID + ".position"] = .string(
            "\(formattedPercentage(focalPointX))% \(formattedPercentage(focalPointY))%"
        )
        guard let metadata else {
            for suffix in ["width", "height", "mimeType", "byteCount", "filename", "extension", "aspectRatio"] {
                values[propertyID + "." + suffix] = .string("")
            }
            return
        }
        values[propertyID + ".width"] = metadata.width.map { .number(Double($0)) } ?? .string("")
        values[propertyID + ".height"] = metadata.height.map { .number(Double($0)) } ?? .string("")
        values[propertyID + ".mimeType"] = .string(metadata.mimeType)
        values[propertyID + ".byteCount"] = .number(Double(metadata.byteCount))
        values[propertyID + ".filename"] = .string(metadata.filename)
        values[propertyID + ".extension"] = .string(metadata.fileExtension)
        values[propertyID + ".aspectRatio"] = metadata.aspectRatio.map(PartPackageValue.number) ?? .string("")
    }

    private static func formattedPercentage(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(0...3))
        )
    }
}

nonisolated struct ProjectAsset: Codable, Equatable, Identifiable, Sendable {
    enum ExportDirectory: Codable, Equatable, Sendable {
        case root
        case folder(UUID)
    }

    let id: UUID
    var filename: String
    var mediaType: String
    var byteCount: Int
    var pixelWidth: Int?
    var pixelHeight: Int?
    var exportDirectory: ExportDirectory?
    var exportOrder: Int

    init(
        id: UUID = UUID(),
        filename: String,
        mediaType: String,
        byteCount: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        exportDirectory: ExportDirectory? = nil,
        exportOrder: Int = 0
    ) {
        self.id = id
        self.filename = filename
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.exportDirectory = exportDirectory
        self.exportOrder = exportOrder
    }

    var storageFilename: String { id.uuidString + "." + fileExtension }
    var exportPath: String { "assets/" + storageFilename }
    var reference: String { "foundry-asset:" + id.uuidString }

    var readableExportFilename: String {
        let lastPart = (filename as NSString).lastPathComponent
        let stem = (lastPart as NSString).deletingPathExtension
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
        case id, filename, mediaType, byteCount, pixelWidth, pixelHeight, exportDirectory, exportOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight)
        exportDirectory = try container.decodeIfPresent(ExportDirectory.self, forKey: .exportDirectory)
        exportOrder = try container.decodeIfPresent(Int.self, forKey: .exportOrder) ?? 0
    }

    var imageMetadata: PartImageMetadata {
        PartImageMetadata(
            width: pixelWidth,
            height: pixelHeight,
            mimeType: mediaType,
            byteCount: byteCount,
            filename: filename
        )
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
    mutating func hydrateImageMetadata(from dataByID: [UUID: Data]) {
        for index in indices {
            switch self[index] {
            case .asset(var asset):
                guard asset.mediaType.hasPrefix("image/"),
                      asset.pixelWidth == nil || asset.pixelHeight == nil,
                      let data = dataByID[asset.id] else { continue }
                let metadata = PartImageMetadata.inspect(
                    data: data,
                    filename: asset.filename,
                    mimeType: asset.mediaType
                )
                asset.pixelWidth = metadata.width
                asset.pixelHeight = metadata.height
                self[index] = .asset(asset)
            case .folder(var folder):
                folder.children.hydrateImageMetadata(from: dataByID)
                self[index] = .folder(folder)
            }
        }
    }

    func managedExportPath(for asset: ProjectAsset) -> String {
        managedExportPaths()[asset.id] ?? asset.exportPath
    }

    func managedExportPaths() -> [UUID: String] {
        var paths: [UUID: String] = [:]

        func collect(_ nodes: [ProjectAssetNode], under parts: [String]) {
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
                paths[asset.id] = (parts + [filename]).joined(separator: "/")
            }

            for folder in folders {
                let readableName = Page.slugify(folder.name)
                let exportName = folderNameCounts[readableName.lowercased(), default: 0] > 1
                    ? "\(readableName)--\(folder.id.uuidString.lowercased().prefix(8))"
                    : readableName
                collect(folder.children, under: parts + [exportName])
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
    let digest: Data?

    init(asset: ProjectAsset, data: Data, digest: Data? = nil) {
        self.asset = asset
        self.data = data
        self.digest = digest
    }
}

nonisolated extension String {
    var foundryAssetID: UUID? {
        guard hasPrefix("foundry-asset:") else { return nil }
        return UUID(uuidString: String(dropFirst("foundry-asset:".count)))
    }
}
