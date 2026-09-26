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
        digest: String? = nil,
        cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "Foundry/ImageRenditions-v2", directoryHint: .isDirectory)
    ) -> Result? {
        let dimension = min(max(maximumDimension, 1), canonicalMaximumDimension)
        let metadata = PartImageMetadata.inspect(data: data, filename: filename, mimeType: mimeType)
        guard let width = metadata.width, let height = metadata.height, max(width, height) > dimension else { return nil }
        // Include processing version and output-affecting inputs. No project
        // paths or asset IDs: identical sources can share a cached variant.
        // When a persisted digest is available, key on that instead of
        // re-hashing the source bytes on every request.
        var hash = SHA256()
        if let digest {
            hash.update(data: Data("\u{0}v2\u{0}\(digest)\u{0}\(dimension)\u{0}\(filename)\u{0}\(mimeType)".utf8))
        } else {
            hash.update(data: data)
            hash.update(data: Data("\u{0}v2\u{0}\(dimension)\u{0}\(filename)\u{0}\(mimeType)".utf8))
        }
        let key = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let cachedURL = cacheDirectory?.appending(path: key)
        if let cachedURL,
           let cached = try? Data(contentsOf: cachedURL, options: .mappedIfSafe),
           let source = CGImageSourceCreateWithData(cached as CFData, nil),
           CGImageSourceCreateImageAtIndex(source, 0, nil) != nil {
            let ext = renditionFileExtension(mimeType: mimeType, fallback: (filename as NSString).pathExtension)
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

    /// Byte-free variant: decides purely from the declared MIME type, which
    /// is safe because `mediaType` is always derived from real bytes at import.
    static func renditionFileExtension(mimeType: String, fallback: String) -> String {
        guard let type = UTType(mimeType: mimeType),
              !(CGImageDestinationCopyTypeIdentifiers() as NSArray).contains(type.identifier as CFString) else {
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
        let dimensions = imageDimensions(from: CGImageSourceCreateWithData(data as CFData, nil))
        return PartImageMetadata(
            width: dimensions?.width,
            height: dimensions?.height,
            mimeType: mimeType,
            byteCount: data.count,
            filename: filename
        )
    }

    /// Metadata-only inspection when the source already has a stable on-disk
    /// location — ImageIO reads just the header, never the full file.
    static func inspect(
        url: URL,
        byteCount: Int,
        filename: String,
        mimeType: String
    ) -> PartImageMetadata {
        let dimensions = imageDimensions(from: CGImageSourceCreateWithURL(url as CFURL, nil))
        return PartImageMetadata(
            width: dimensions?.width,
            height: dimensions?.height,
            mimeType: mimeType,
            byteCount: byteCount,
            filename: filename
        )
    }

    private static func imageDimensions(from source: CGImageSource?) -> (width: Int, height: Int)? {
        guard let source,
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

nonisolated enum PartVideoTemplateValues {
    struct PlaybackOptions: Equatable, Sendable {
        static let standard = Self(
            autoplay: "never",
            muted: false,
            showsControls: true,
            loops: false,
            startAt: 0
        )

        let autoplay: String
        let muted: Bool
        let showsControls: Bool
        let loops: Bool
        let startAt: Double
    }

    static func posterPropertyKey(for propertyID: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_video_poster_" + propertyID)
    }

    static func autoplayPropertyKey(for propertyID: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_video_autoplay_" + propertyID)
    }

    static func mutedPropertyKey(for propertyID: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_video_muted_" + propertyID)
    }

    static func controlsPropertyKey(for propertyID: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_video_controls_" + propertyID)
    }

    static func loopPropertyKey(for propertyID: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_video_loop_" + propertyID)
    }

    static func startAtPropertyKey(for propertyID: String) -> PartProperty.Key {
        .init(rawValue: "__foundry_video_start_at_" + propertyID)
    }

    static func playbackOptions(propertyID: String, node: PartNode) -> PlaybackOptions {
        let autoplay = node.property(autoplayPropertyKey(for: propertyID))
        return .init(
            autoplay: autoplay == "onLoad" ? autoplay : PlaybackOptions.standard.autoplay,
            muted: node.propertyValue(mutedPropertyKey(for: propertyID)).booleanValue ?? PlaybackOptions.standard.muted,
            showsControls: node.propertyValue(controlsPropertyKey(for: propertyID)).booleanValue ?? PlaybackOptions.standard.showsControls,
            loops: node.propertyValue(loopPropertyKey(for: propertyID)).booleanValue ?? PlaybackOptions.standard.loops,
            startAt: max(node.propertyValue(startAtPropertyKey(for: propertyID)).numberValue ?? 0, 0)
        )
    }

    static func insert(
        propertyID: String,
        href: String,
        poster: String,
        asset: ProjectAsset?,
        playback: PlaybackOptions = .standard,
        enablesEditorMarkup: Bool = false,
        hasSelection: Bool = false,
        into values: inout [String: PartPackageValue]
    ) {
        values[propertyID + ".element"] = .string(element(
            propertyID: propertyID,
            href: href,
            poster: poster,
            playback: playback,
            enablesEditorMarkup: enablesEditorMarkup,
            hasSelection: hasSelection
        ))
        values[propertyID + ".href"] = .string(href)
        values[propertyID + ".poster"] = .string(poster)
        values[propertyID + ".autoplay"] = .string(playback.autoplay)
        values[propertyID + ".muted"] = .boolean(playback.muted)
        values[propertyID + ".controls"] = .boolean(playback.showsControls)
        values[propertyID + ".loop"] = .boolean(playback.loops)
        values[propertyID + ".startAt"] = .number(playback.startAt)
        values[propertyID + ".filename"] = .string(asset?.filename ?? "")
        values[propertyID + ".extension"] = .string(
            asset.map { ($0.filename as NSString).pathExtension.lowercased() } ?? ""
        )
        values[propertyID + ".mimeType"] = .string(asset?.mediaType ?? "")
        values[propertyID + ".byteCount"] = asset.map { .number(Double($0.byteCount)) } ?? .string("")
        values[propertyID + ".width"] = asset?.pixelWidth.map { .number(Double($0)) } ?? .string("")
        values[propertyID + ".height"] = asset?.pixelHeight.map { .number(Double($0)) } ?? .string("")
        if let width = asset?.pixelWidth, let height = asset?.pixelHeight, height > 0 {
            values[propertyID + ".aspectRatio"] = .number(Double(width) / Double(height))
        } else {
            values[propertyID + ".aspectRatio"] = .string("")
        }
        values[propertyID + ".duration"] = asset?.videoMetadata.map { .number($0.duration) } ?? .string("")
    }

    private static func element(
        propertyID: String,
        href: String,
        poster: String,
        playback: PlaybackOptions,
        enablesEditorMarkup: Bool,
        hasSelection: Bool = false
    ) -> String {
        if enablesEditorMarkup && !hasSelection && href.isEmpty && poster.isEmpty {
            // An unfilled video control renders as an explicit drop well on
            // the canvas, mirroring the image control's empty state.
            return "<span class=\"foundry-video-drop-zone\" data-foundry-video-drop-zone data-foundry-video-property=\"\(escapeAttribute(propertyID))\"><span class=\"foundry-drop-label\">\(FoundryDropZoneGlyphs.video)</span></span>"
        }
        guard !href.isEmpty || !poster.isEmpty || (enablesEditorMarkup && hasSelection) else { return "" }
        let source = source(href: href, startAt: playback.startAt)
        let sourceAttribute = source.isEmpty ? "" : " src=\"\(escapeAttribute(source))\""
        let posterAttribute = poster.isEmpty ? "" : " poster=\"\(escapeAttribute(poster))\""
        let autoplayAttribute = playback.autoplay == "onLoad" ? " autoplay" : ""
        let mutedAttribute = playback.muted ? " muted" : ""
        let controlsAttribute = playback.showsControls ? " controls" : ""
        let loopAttribute = playback.loops ? " loop" : ""
        // On the canvas the video element is a double drop target: an image
        // file replaces the poster (via the image pipeline against the poster
        // companion key) and a movie file replaces the video itself.
        let editorAttributes = enablesEditorMarkup
            ? " data-foundry-image-drop-zone data-foundry-image-property=\"\(escapeAttribute(posterPropertyKey(for: propertyID).rawValue))\""
              + " data-foundry-video-drop-zone data-foundry-video-property=\"\(escapeAttribute(propertyID))\""
            : ""
        return "<video class=\"fd-video\"\(sourceAttribute)\(posterAttribute)\(autoplayAttribute)\(mutedAttribute)\(controlsAttribute)\(loopAttribute)\(editorAttributes) playsinline></video>"
    }

    private static func source(href: String, startAt: Double) -> String {
        guard !href.isEmpty, startAt > 0 else { return href }
        let time = startAt.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3))
        )
        return href + "#t=" + time
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

nonisolated struct ProjectVideoMetadata: Codable, Equatable, Sendable {
    let duration: Double
    let posterJPEG: Data

    var posterDataURL: String {
        "data:image/jpeg;base64," + posterJPEG.base64EncodedString()
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
    /// Lowercase SHA-256 hex digest of the asset's bytes, computed once at import.
    var contentDigest: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var videoMetadata: ProjectVideoMetadata?
    var exportDirectory: ExportDirectory?
    var exportOrder: Int

    init(
        id: UUID = UUID(),
        filename: String,
        mediaType: String,
        byteCount: Int,
        contentDigest: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        videoMetadata: ProjectVideoMetadata? = nil,
        exportDirectory: ExportDirectory? = nil,
        exportOrder: Int = 0
    ) {
        self.id = id
        self.filename = filename
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.contentDigest = contentDigest
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.videoMetadata = videoMetadata
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
        if !value.isEmpty { return value }
        // Extensionless filenames export with the extension their media type
        // implies; "bin" is the last resort for genuinely unknown bytes.
        if let inferred = UTType(mimeType: mediaType)?.preferredFilenameExtension {
            return inferred
        }
        return "bin"
    }

    private enum CodingKeys: String, CodingKey {
        case id, filename, mediaType, byteCount, contentDigest, pixelWidth, pixelHeight, videoMetadata, exportDirectory, exportOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        contentDigest = try container.decode(String.self, forKey: .contentDigest)
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight)
        videoMetadata = try container.decodeIfPresent(ProjectVideoMetadata.self, forKey: .videoMetadata)
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
    let digest: String?

    init(asset: ProjectAsset, data: Data, digest: String? = nil) {
        self.asset = asset
        self.data = data
        self.digest = digest ?? asset.contentDigest
    }
}

nonisolated extension String {
    var foundryAssetID: UUID? {
        guard hasPrefix("foundry-asset:") else { return nil }
        return UUID(uuidString: String(dropFirst("foundry-asset:".count)))
    }
}
