import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

nonisolated struct ThemeBundleMetadata: Codable, Equatable, Sendable {
    static let currentFormatVersion = 3

    let id: UUID
    var name: String
    let previewFilename: String
    let formatVersion: Int
    let createdAt: Date
    var modifiedAt: Date
    var resources: [ThemeBundleResource]
}

nonisolated struct ThemeBundleResource: Codable, Equatable, Sendable {
    let asset: ProjectAsset
    let storageFilename: String
}

nonisolated struct SavedTheme: Equatable, Identifiable, Sendable {
    let metadata: ThemeBundleMetadata
    let theme: Theme
    let bundleURL: URL
    let resources: [ProjectAssetContent]
    let isBuiltIn: Bool

    var id: UUID { metadata.id }
    var previewURL: URL {
        bundleURL.appending(path: "Contents/Resources/\(metadata.previewFilename)")
    }
}

nonisolated struct ThemePreviewImage: Equatable, Sendable {
    static let pixelWidth = 1000
    static let pixelHeight = 1600

    let data: Data
    let filename: String
}

nonisolated enum ThemeBundleError: Error, LocalizedError {
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
            "Themes must use the .foundrytheme extension."
        case .missingContents:
            "The theme bundle is missing its metadata or theme data."
        case .unsupportedVersion(let version):
            "This theme uses unsupported format version \(version)."
        case .invalidName:
            "Enter a name for the theme."
        case .missingPreview:
            "Choose a preview image for the theme."
        case .unsupportedPreviewType:
            "Theme previews must be PNG, JPEG, or WebP images."
        case .previewTypeMismatch:
            "The preview image’s file extension does not match its contents."
        case .invalidPreviewDimensions(let width, let height):
            "The preview image is \(width) × \(height) px. Choose an image that is exactly \(ThemePreviewImage.pixelWidth) × \(ThemePreviewImage.pixelHeight) px."
        }
    }
}

nonisolated enum ThemeBundleStore {
    static let pathExtension = "foundrytheme"
    static let systemThemeID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    static func isThemeURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == pathExtension
    }

    static func load(from bundleURL: URL, isBuiltIn: Bool = false) throws -> SavedTheme {
        guard isThemeURL(bundleURL) else { throw ThemeBundleError.wrongExtension }
        let metadataURL = bundleURL.appending(path: "Contents/Info.plist")
        let themeURL = bundleURL.appending(path: "Contents/Resources/theme.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              FileManager.default.fileExists(atPath: themeURL.path) else {
            throw ThemeBundleError.missingContents
        }
        let metadata = try PropertyListDecoder().decode(
            ThemeBundleMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard metadata.formatVersion == ThemeBundleMetadata.currentFormatVersion else {
            throw ThemeBundleError.unsupportedVersion(metadata.formatVersion)
        }
        let previewURL = bundleURL.appending(path: "Contents/Resources/\(metadata.previewFilename)")
        guard FileManager.default.fileExists(atPath: previewURL.path) else { throw ThemeBundleError.missingPreview }
        _ = try preview(from: previewURL)
        let theme = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: themeURL))
        let resourcesURL = bundleURL.appending(path: "Contents/Resources/Assets", directoryHint: .isDirectory)
        let resources = metadata.resources.compactMap { resource -> ProjectAssetContent? in
            guard let data = try? Data(contentsOf: resourcesURL.appending(path: resource.storageFilename)) else {
                return nil
            }
            return ProjectAssetContent(asset: resource.asset, data: data)
        }
        return SavedTheme(
            metadata: metadata,
            theme: theme,
            bundleURL: bundleURL,
            resources: resources,
            isBuiltIn: isBuiltIn
        )
    }

    static func write(
        theme: Theme,
        name: String,
        preview: ThemePreviewImage,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        assetContents: [UUID: ProjectAssetContent] = [:],
        to bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> SavedTheme {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ThemeBundleError.invalidName }
        let contentsURL = bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        let resourcesURL = contentsURL.appending(path: "Resources", directoryHint: .isDirectory)
        let assetsURL = resourcesURL.appending(path: "Assets", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let referencedAssetIDs = theme.bundledFontAssetIDs
        let bundledResources = referencedAssetIDs.compactMap { assetContents[$0] }
        if !bundledResources.isEmpty {
            try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        }
        let resources = bundledResources.map {
            ThemeBundleResource(asset: $0.asset, storageFilename: $0.asset.storageFilename)
        }
        let metadata = ThemeBundleMetadata(
            id: id,
            name: trimmedName,
            previewFilename: preview.filename,
            formatVersion: ThemeBundleMetadata.currentFormatVersion,
            createdAt: createdAt,
            modifiedAt: Date(),
            resources: resources
        )
        let plistEncoder = PropertyListEncoder()
        plistEncoder.outputFormat = .xml
        try plistEncoder.encode(metadata).write(to: contentsURL.appending(path: "Info.plist"), options: .atomic)
        let themeEncoder = JSONEncoder()
        themeEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try themeEncoder.encode(theme).write(to: resourcesURL.appending(path: "theme.json"), options: .atomic)
        try preview.data.write(to: resourcesURL.appending(path: preview.filename), options: .atomic)
        for content in bundledResources {
            try content.data.write(to: assetsURL.appending(path: content.asset.storageFilename), options: .atomic)
        }
        return SavedTheme(
            metadata: metadata,
            theme: theme,
            bundleURL: bundleURL,
            resources: bundledResources,
            isBuiltIn: false
        )
    }

    static func libraryURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = applicationSupport
            .appending(path: "Foundry", directoryHint: .isDirectory)
            .appending(path: "Themes", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func filename(for name: String, id: UUID) -> String {
        let invalid = CharacterSet.alphanumerics.union(.whitespaces).inverted
        let cleaned = name.components(separatedBy: invalid).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        let stem = cleaned.isEmpty ? "Theme" : cleaned
        return "\(stem)-\(id.uuidString.prefix(8)).\(pathExtension)"
    }

    static func preview(from url: URL) throws -> ThemePreviewImage {
        guard let declaredType = UTType(filenameExtension: url.pathExtension.lowercased()),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceTypeIdentifier = CGImageSourceGetType(source),
              let detectedType = UTType(sourceTypeIdentifier as String) else {
            throw ThemeBundleError.unsupportedPreviewType
        }
        let acceptedTypes: [UTType] = [.png, .jpeg, .webP]
        guard acceptedTypes.contains(where: { detectedType.conforms(to: $0) }) else {
            throw ThemeBundleError.unsupportedPreviewType
        }
        guard detectedType.conforms(to: declaredType) || declaredType.conforms(to: detectedType) else {
            throw ThemeBundleError.previewTypeMismatch
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ThemeBundleError.unsupportedPreviewType
        }
        guard width == ThemePreviewImage.pixelWidth, height == ThemePreviewImage.pixelHeight else {
            throw ThemeBundleError.invalidPreviewDimensions(width: width, height: height)
        }
        let pathExtension = detectedType == .png ? "png" : detectedType == .webP ? "webp" : "jpg"
        return ThemePreviewImage(data: data, filename: "preview.\(pathExtension)")
    }

    static func themeURLs(in rootURL: URL, fileManager: FileManager = .default) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter(isThemeURL)
    }

    static func builtInThemes(bundle: Bundle = .main) -> [SavedTheme] {
        guard let bundleURL = bundle.url(forResource: "BuiltInThemes", withExtension: "bundle"),
              let themeBundle = Bundle(url: bundleURL),
              let resourcesURL = themeBundle.resourceURL else {
            preconditionFailure("The built-in theme bundle is missing.")
        }
        return themeURLs(in: resourcesURL).map { url in
            do {
                return try load(from: url, isBuiltIn: true)
            } catch {
                preconditionFailure("Invalid built-in theme at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    static var systemTheme: Theme {
        guard let theme = builtInThemes().first(where: { $0.metadata.id == systemThemeID })?.theme else {
            preconditionFailure("The System UI theme is missing.")
        }
        return theme
    }
}

@MainActor
@Observable
final class ThemeLibrary {
    static let shared = ThemeLibrary()

    private(set) var themes: [SavedTheme] = []
    private(set) var errorMessage: String?

    private init() {
        reload()
    }

    func reload() {
        do {
            let rootURL = try ThemeBundleStore.libraryURL()
            let urls = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter(ThemeBundleStore.isThemeURL)
            let builtInThemes = ThemeBundleStore.builtInThemes()
            let builtInIDs = Set(builtInThemes.map(\.id))
            let userThemes = try urls.map { try ThemeBundleStore.load(from: $0) }
                .filter { !builtInIDs.contains($0.id) }
            themes = (builtInThemes + userThemes)
                .sorted { $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            themes = []
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(
        name: String,
        from theme: Theme,
        preview: ThemePreviewImage,
        assetContents: [UUID: ProjectAssetContent] = [:]
    ) throws -> SavedTheme {
        let id = UUID()
        let rootURL = try ThemeBundleStore.libraryURL()
        let destination = rootURL.appending(
            path: ThemeBundleStore.filename(for: name, id: id),
            directoryHint: .isDirectory
        )
        let saved = try ThemeBundleStore.write(
            theme: theme,
            name: name,
            preview: preview,
            id: id,
            assetContents: assetContents,
            to: destination
        )
        reload()
        return saved
    }

    @discardableResult
    func install(from sourceURL: URL) throws -> SavedTheme {
        let source = try ThemeBundleStore.load(from: sourceURL)
        let rootURL = try ThemeBundleStore.libraryURL()
        let destination = rootURL.appending(
            path: ThemeBundleStore.filename(for: source.metadata.name, id: source.id),
            directoryHint: .isDirectory
        )
        if destination.standardizedFileURL != sourceURL.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
        reload()
        return try ThemeBundleStore.load(from: destination)
    }

    @discardableResult
    func update(
        _ savedTheme: SavedTheme,
        from theme: Theme,
        assetContents: [UUID: ProjectAssetContent] = [:]
    ) throws -> SavedTheme {
        guard !savedTheme.isBuiltIn else { return savedTheme }
        let preview = try ThemeBundleStore.preview(from: savedTheme.previewURL)
        let updated = try ThemeBundleStore.write(
            theme: theme,
            name: savedTheme.metadata.name,
            preview: preview,
            id: savedTheme.id,
            createdAt: savedTheme.metadata.createdAt,
            assetContents: assetContents,
            to: savedTheme.bundleURL
        )
        reload()
        return updated
    }

    func remove(_ savedTheme: SavedTheme) throws {
        guard !savedTheme.isBuiltIn else { return }
        try FileManager.default.removeItem(at: savedTheme.bundleURL)
        reload()
    }
}

nonisolated extension Theme {
    var bundledFontAssetIDs: [UUID] {
        typography.allFonts.flatMap { font -> [UUID] in
            guard case .bundled(let files) = font.source else { return [] }
            return files.compactMap(\.foundryAssetID)
        }
    }

    func remappingBundledFontAssets(_ mapping: [UUID: UUID]) -> Theme {
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

nonisolated private extension ThemeFontDefinition {
    mutating func remapBundledFontAssets(_ mapping: [UUID: UUID]) {
        guard case .bundled(let files) = source else { return }
        source = .bundled(files: files.map { reference in
            guard let oldID = reference.foundryAssetID, let newID = mapping[oldID] else { return reference }
            return "foundry-asset:\(newID.uuidString)"
        })
    }
}
