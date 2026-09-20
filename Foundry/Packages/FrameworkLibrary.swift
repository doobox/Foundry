import Foundation
import ImageIO
import UniformTypeIdentifiers
import Observation

nonisolated struct FrameworkBundleMetadata: Codable, Equatable, Sendable {
    static let currentFormatVersion = 5

    let id: UUID
    var name: String
    let previewFilename: String
    let formatVersion: Int
    let createdAt: Date
    var modifiedAt: Date
    var resources: [FrameworkBundleResource]
}

nonisolated struct FrameworkBundleResource: Codable, Equatable, Sendable {
    let asset: ProjectAsset
    let storageFilename: String
}

nonisolated struct SavedFramework: Equatable, Identifiable, Sendable {
    let metadata: FrameworkBundleMetadata
    let framework: Framework
    let bundleURL: URL
    let resources: [ProjectAssetContent]
    let isBuiltIn: Bool

    var id: UUID { metadata.id }
    func hasModifiedSettings(in projectFramework: Framework) -> Bool {
        projectFramework.savedSettings != framework.savedSettings
    }

    var previewURL: URL {
        bundleURL.appending(path: "Contents/Resources/\(metadata.previewFilename)")
    }
}

nonisolated struct FrameworkPreviewImage: Equatable, Sendable {
    static let pixelWidth = 1200
    static let pixelHeight = 600

    let data: Data
    let filename: String
}

nonisolated enum FrameworkBundleError: Error, LocalizedError {
    case wrongExtension
    case missingContents
    case unsupportedVersion(Int)
    case invalidName
    case missingPreview
    case unsupportedPreviewType
    case previewTypeMismatch
    case invalidPreviewDimensions(width: Int, height: Int)

    var errorDescription: String? {
        switch self {
        case .wrongExtension:
            "Frameworks must use the .foundryframework extension."
        case .missingContents:
            "The framework bundle is missing its metadata or framework data."
        case .unsupportedVersion(let version):
            "This framework uses unsupported format version \(version)."
        case .invalidName:
            "Enter a name for the framework."
        case .missingPreview:
            "Choose a preview image for the framework."
        case .unsupportedPreviewType:
            "Framework previews must be PNG, JPEG, or WebP images."
        case .previewTypeMismatch:
            "The preview image’s file extension does not match its contents."
        case .invalidPreviewDimensions(let width, let height):
            "The preview image has invalid dimensions (\(width) × \(height) px)."
        }
    }
}

nonisolated enum FrameworkBundleStore {
    static let pathExtension = "foundryframework"
    static let systemFrameworkID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    static func isFrameworkURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == pathExtension
    }

    static func load(from bundleURL: URL, isBuiltIn: Bool = false) throws -> SavedFramework {
        guard isFrameworkURL(bundleURL) else { throw FrameworkBundleError.wrongExtension }
        let metadataURL = bundleURL.appending(path: "Contents/Info.plist")
        let frameworkURL = bundleURL.appending(path: "Contents/Resources/framework.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              FileManager.default.fileExists(atPath: frameworkURL.path) else {
            throw FrameworkBundleError.missingContents
        }
        let metadata = try PropertyListDecoder().decode(
            FrameworkBundleMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard metadata.formatVersion == FrameworkBundleMetadata.currentFormatVersion else {
            throw FrameworkBundleError.unsupportedVersion(metadata.formatVersion)
        }
        let previewURL = bundleURL.appending(path: "Contents/Resources/\(metadata.previewFilename)")
        guard FileManager.default.fileExists(atPath: previewURL.path) else { throw FrameworkBundleError.missingPreview }
        _ = try preview(from: previewURL)
        var framework = try JSONDecoder().decode(Framework.self, from: Data(contentsOf: frameworkURL))
        framework.colourPalettes = framework.fixedFrameworkColourPalettes + ColourPaletteDefaults.standard
        let resourcesURL = bundleURL.appending(path: "Contents/Resources/Assets", directoryHint: .isDirectory)
        let resources = metadata.resources.compactMap { resource -> ProjectAssetContent? in
            guard let data = try? Data(contentsOf: resourcesURL.appending(path: resource.storageFilename)) else {
                return nil
            }
            return ProjectAssetContent(asset: resource.asset, data: data)
        }
        return SavedFramework(
            metadata: metadata,
            framework: framework,
            bundleURL: bundleURL,
            resources: resources,
            isBuiltIn: isBuiltIn
        )
    }

    static func write(
        framework: Framework,
        name: String,
        preview: FrameworkPreviewImage,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        assetContents: ProjectAssetContents = [:],
        to bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> SavedFramework {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw FrameworkBundleError.invalidName }
        var bundleFramework = framework.savedSettings
        let contentsURL = bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        let resourcesURL = contentsURL.appending(path: "Resources", directoryHint: .isDirectory)
        let assetsURL = resourcesURL.appending(path: "Assets", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let referencedAssetIDs = framework.bundledFontAssetIDs
        let bundledResources = referencedAssetIDs.compactMap { assetContents[$0] }
        if !bundledResources.isEmpty {
            try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        }
        let resources = bundledResources.map {
            FrameworkBundleResource(asset: $0.asset, storageFilename: $0.asset.storageFilename)
        }
        let metadata = FrameworkBundleMetadata(
            id: id,
            name: trimmedName,
            previewFilename: preview.filename,
            formatVersion: FrameworkBundleMetadata.currentFormatVersion,
            createdAt: createdAt,
            modifiedAt: Date(),
            resources: resources
        )
        let plistEncoder = PropertyListEncoder()
        plistEncoder.outputFormat = .xml
        try plistEncoder.encode(metadata).write(to: contentsURL.appending(path: "Info.plist"), options: .atomic)
        let frameworkEncoder = JSONEncoder()
        frameworkEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try frameworkEncoder.encode(bundleFramework).write(to: resourcesURL.appending(path: "framework.json"), options: .atomic)
        try preview.data.write(to: resourcesURL.appending(path: preview.filename), options: .atomic)
        for content in bundledResources {
            try content.data.write(to: assetsURL.appending(path: content.asset.storageFilename), options: .atomic)
        }
        // Standard palettes are supplied by Foundry, never by the framework bundle.
        bundleFramework.colourPalettes += ColourPaletteDefaults.standard
        return SavedFramework(
            metadata: metadata,
            framework: bundleFramework,
            bundleURL: bundleURL,
            resources: bundledResources,
            isBuiltIn: false
        )
    }

    /// New frameworks always start from the bundled template, never project edits.
    static func create(name: String, preview: FrameworkPreviewImage, id: UUID = UUID(), to destination: URL) throws -> SavedFramework {
        guard let template = builtInFrameworks().first(where: { $0.id == systemFrameworkID }) else {
            throw FrameworkBundleError.missingContents
        }
        return try write(
            framework: template.framework,
            name: name,
            preview: preview,
            id: id,
            assetContents: ProjectAssetContents(Dictionary(uniqueKeysWithValues: template.resources.map { ($0.asset.id, $0) })),
            to: destination
        )
    }

    static func libraryURL(fileManager: FileManager = .default) throws -> URL {
        try FoundryLibraryLocation.directoryURL(named: "Frameworks", fileManager: fileManager)
    }

    static func editArtwork(_ saved: SavedFramework, name: String, preview: FrameworkPreviewImage) throws -> SavedFramework {
        guard !saved.isBuiltIn else { return saved }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FrameworkBundleError.invalidName }
        let metadata = FrameworkBundleMetadata(
            id: saved.id, name: name, previewFilename: preview.filename,
            formatVersion: saved.metadata.formatVersion, createdAt: saved.metadata.createdAt,
            modifiedAt: Date(), resources: saved.metadata.resources
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(metadata)
        try preview.data.write(to: saved.bundleURL.appending(path: "Contents/Resources/\(preview.filename)"), options: .atomic)
        try data.write(to: saved.bundleURL.appending(path: "Contents/Info.plist"), options: .atomic)
        return try load(from: saved.bundleURL)
    }

    static func filename(for name: String, id: UUID) -> String {
        let invalid = CharacterSet.alphanumerics.union(.whitespaces).inverted
        let cleaned = name.components(separatedBy: invalid).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        let stem = cleaned.isEmpty ? "Framework" : cleaned
        return "\(stem)-\(id.uuidString.prefix(8)).\(pathExtension)"
    }

    static func preview(from url: URL) throws -> FrameworkPreviewImage {
        guard let declaredType = UTType(filenameExtension: url.pathExtension.lowercased()),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
              let sourceTypeIdentifier = CGImageSourceGetType(source),
              let detectedType = UTType(sourceTypeIdentifier as String) else {
            throw FrameworkBundleError.unsupportedPreviewType
        }
        let acceptedTypes: [UTType] = [.png, .jpeg, .webP]
        guard acceptedTypes.contains(where: { detectedType.conforms(to: $0) }) else {
            throw FrameworkBundleError.unsupportedPreviewType
        }
        guard detectedType.conforms(to: declaredType) || declaredType.conforms(to: detectedType) else {
            throw FrameworkBundleError.previewTypeMismatch
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw FrameworkBundleError.unsupportedPreviewType
        }
        guard width > 0, height > 0 else {
            throw FrameworkBundleError.invalidPreviewDimensions(width: width, height: height)
        }
        let pathExtension = detectedType == .png ? "png" : detectedType == .webP ? "webp" : "jpg"
        return FrameworkPreviewImage(data: data, filename: "preview.\(pathExtension)")
    }

    static func frameworkURLs(in rootURL: URL, fileManager: FileManager = .default) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter(isFrameworkURL)
    }

    static func builtInFrameworks(bundle: Bundle = .main) -> [SavedFramework] {
        guard let bundleURL = bundle.url(forResource: "BuiltInFrameworks", withExtension: "bundle"),
              let frameworkBundle = Bundle(url: bundleURL),
              let resourcesURL = frameworkBundle.resourceURL else {
            preconditionFailure("The built-in framework bundle is missing.")
        }
        return frameworkURLs(in: resourcesURL).map { url in
            do {
                return try load(from: url, isBuiltIn: true)
            } catch {
                preconditionFailure("Invalid built-in framework at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    static var systemFramework: Framework {
        guard let framework = builtInFrameworks().first(where: { $0.metadata.id == systemFrameworkID })?.framework else {
            preconditionFailure("The System UI framework is missing.")
        }
        return framework
    }
}

@MainActor
@Observable
final class FrameworkLibrary {
    static let shared = FrameworkLibrary()

    private(set) var frameworks: [SavedFramework] = []
    private(set) var errorMessage: String?

    private init() {
        reload()
    }

    func reload() {
        do {
            let rootURL = try FrameworkBundleStore.libraryURL()
            let urls = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter(FrameworkBundleStore.isFrameworkURL)
            let builtInFrameworks = FrameworkBundleStore.builtInFrameworks()
            let builtInIDs = Set(builtInFrameworks.map(\.id))
            var failures: [String] = []
            let userFrameworks = urls.compactMap { url -> SavedFramework? in
                do { return try FrameworkBundleStore.load(from: url) }
                catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }.filter { !builtInIDs.contains($0.id) }
            frameworks = (builtInFrameworks + userFrameworks)
                .sorted { $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending }
            errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        } catch {
            frameworks = []
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(
        name: String,
        preview: FrameworkPreviewImage
    ) throws -> SavedFramework {
        let id = UUID()
        let rootURL = try FrameworkBundleStore.libraryURL()
        let destination = rootURL.appending(
            path: FrameworkBundleStore.filename(for: name, id: id),
            directoryHint: .isDirectory
        )
        let saved = try FrameworkBundleStore.create(
            name: name,
            preview: preview,
            id: id,
            to: destination
        )
        reload()
        return saved
    }

    @discardableResult
    func install(from sourceURL: URL) throws -> SavedFramework {
        let source = try FrameworkBundleStore.load(from: sourceURL)
        let rootURL = try FrameworkBundleStore.libraryURL()
        let destination = rootURL.appending(
            path: FrameworkBundleStore.filename(for: source.metadata.name, id: source.id),
            directoryHint: .isDirectory
        )
        if destination.standardizedFileURL != sourceURL.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
        reload()
        return try FrameworkBundleStore.load(from: destination)
    }

    @discardableResult
    func update(
        _ savedFramework: SavedFramework,
        from framework: Framework,
        assetContents: ProjectAssetContents = [:]
    ) throws -> SavedFramework {
        guard !savedFramework.isBuiltIn else { return savedFramework }
        let preview = try FrameworkBundleStore.preview(from: savedFramework.previewURL)
        let updated = try FrameworkBundleStore.write(
            framework: framework,
            name: savedFramework.metadata.name,
            preview: preview,
            id: savedFramework.id,
            createdAt: savedFramework.metadata.createdAt,
            assetContents: assetContents,
            to: savedFramework.bundleURL
        )
        reload()
        return updated
    }

    func remove(_ savedFramework: SavedFramework) throws {
        guard !savedFramework.isBuiltIn else { return }
        try FileManager.default.removeItem(at: savedFramework.bundleURL)
        reload()
    }

    func edit(_ savedFramework: SavedFramework, name: String, preview: FrameworkPreviewImage) throws {
        guard !savedFramework.isBuiltIn else { return }
        _ = try FrameworkBundleStore.editArtwork(savedFramework, name: name, preview: preview)
        reload()
    }
}

nonisolated extension Framework {
    var bundledFontAssetIDs: [UUID] {
        typography.allFonts.flatMap { font -> [UUID] in
            guard case .bundled(let files) = font.source else { return [] }
            return files.compactMap(\.foundryAssetID)
        }
    }

    func remappingBundledFontAssets(_ mapping: [UUID: UUID]) -> Framework {
        var copy = self
        copy.typography.bodyFont.remapBundledFontAssets(mapping)
        copy.typography.headingFont.remapBundledFontAssets(mapping)
        copy.typography.monospacedFont.remapBundledFontAssets(mapping)
        for index in copy.typography.customFonts.indices {
            copy.typography.customFonts[index].font.remapBundledFontAssets(mapping)
        }
        return copy
    }
}

nonisolated private extension FrameworkFontDefinition {
    mutating func remapBundledFontAssets(_ mapping: [UUID: UUID]) {
        guard case .bundled(let files) = source else { return }
        source = .bundled(files: files.map { reference in
            guard let oldID = reference.foundryAssetID, let newID = mapping[oldID] else { return reference }
            return "foundry-asset:\(newID.uuidString)"
        })
    }
}
