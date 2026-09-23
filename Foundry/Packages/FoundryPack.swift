import Foundation

nonisolated struct FoundryPack: Sendable {
    let identifier: String
    let rootURL: URL
    let metadata: FoundryPackMetadata
    let partURLs: [URL]
    let templateURLs: [URL]
    let frameworkURLs: [URL]
}

nonisolated enum FoundryPackItemKind: String, CaseIterable, Sendable {
    case part = "Parts"
    case template = "Templates"
    case framework = "Frameworks"
}

nonisolated enum FoundryPackLoadingError: Error, LocalizedError {
    case wrongExtension
    case missingManifest
    case invalidManifest(Error)
    case unsupportedFormatVersion(Int)
    case missingIdentifier
    case unknownTopLevelItem(String)
    case invalidItem(String)

    var errorDescription: String? {
        switch self {
        case .wrongExtension:
            "Foundry packs must use .foundrypack or .foundrydevpack."
        case .missingManifest:
            "The pack does not contain Info.plist."
        case .invalidManifest(let error):
            "The pack's Info.plist is invalid: \(error.localizedDescription)"
        case .unsupportedFormatVersion(let version):
            "The pack uses unsupported format version \(version)."
        case .missingIdentifier:
            "The pack's Info.plist must contain a non-empty id."
        case .unknownTopLevelItem(let name):
            "The pack contains an unsupported top-level item named '\(name)'."
        case .invalidItem(let path):
            "The pack item at '\(path)' must be a directory containing Info.plist and Resources."
        }
    }
}

nonisolated enum FoundryPackLoader {
    static let currentFormatVersion = 2
    private static let allowedTopLevelNames = Set(
        ["Info.plist", "Resources", ".DS_Store"] + FoundryPackItemKind.allCases.map(\.rawValue)
    )

    static func load(from rootURL: URL) throws -> FoundryPack {
        guard isPackURL(rootURL) else { throw FoundryPackLoadingError.wrongExtension }
        let manifestURL = rootURL.appending(path: "Info.plist")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw FoundryPackLoadingError.missingManifest
        }

        let metadata: FoundryPackMetadata
        do {
            metadata = try PropertyListDecoder().decode(
                FoundryPackMetadata.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw FoundryPackLoadingError.invalidManifest(error)
        }
        guard metadata.formatVersion == currentFormatVersion else {
            throw FoundryPackLoadingError.unsupportedFormatVersion(metadata.formatVersion)
        }
        let identifier = metadata.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { throw FoundryPackLoadingError.missingIdentifier }

        let children = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        if let unknown = children.first(where: { !allowedTopLevelNames.contains($0.lastPathComponent) }) {
            throw FoundryPackLoadingError.unknownTopLevelItem(unknown.lastPathComponent)
        }

        return FoundryPack(
            identifier: identifier,
            rootURL: rootURL,
            metadata: metadata,
            partURLs: try itemURLs(in: rootURL, kind: .part),
            templateURLs: try itemURLs(in: rootURL, kind: .template),
            frameworkURLs: try itemURLs(in: rootURL, kind: .framework)
        )
    }

    static func installedPacksURL(fileManager: FileManager = .default) throws -> URL {
        try FoundryLibraryLocation.directoryURL(named: "Packs", fileManager: fileManager)
    }

    static func personalDevelopmentPackURL(fileManager: FileManager = .default) throws -> URL {
        let url = try installedPacksURL(fileManager: fileManager)
            .appending(path: "My Foundry Content.foundrydevpack", directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let manifest: [String: Any] = [
                "formatVersion": currentFormatVersion,
                "id": "local.foundry.personal-content",
                "title": "My Foundry Content",
                "version": "1.0.0",
                "minimumAPIVersion": 1
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: manifest,
                format: .xml,
                options: 0
            )
            try data.write(to: url.appending(path: "Info.plist"), options: .atomic)
        }
        return url
    }

    /// Returns outer packs only. A pack is a boundary and is never searched recursively.
    static func packURLs(in rootURL: URL, includingRoot: Bool = false) -> [URL] {
        if isPackURL(rootURL) {
            return includingRoot ? [rootURL.standardizedFileURL] : []
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap { url in
            guard isPackURL(url),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { return nil }
            return url.standardizedFileURL
        }.sorted { $0.path < $1.path }
    }

    static func isPackURL(_ url: URL) -> Bool {
        ["foundrypack", "foundrydevpack"].contains(url.pathExtension.lowercased())
    }

    static func exportFramework(_ framework: SavedFramework, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        do {
            let manifest: [String: Any] = [
                "formatVersion": currentFormatVersion,
                "id": "framework.\(framework.id.uuidString.lowercased())",
                "title": framework.metadata.name,
                "version": "1.0.0",
                "minimumAPIVersion": 1
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: manifest,
                format: .xml,
                options: 0
            )
            try data.write(to: destinationURL.appending(path: "Info.plist"), options: .atomic)
            let frameworksURL = destinationURL.appending(
                path: FoundryPackItemKind.framework.rawValue,
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(at: frameworksURL, withIntermediateDirectories: true)
            try fileManager.copyItem(
                at: framework.bundleURL,
                to: frameworksURL.appending(path: framework.id.uuidString, directoryHint: .isDirectory)
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func itemURLs(in rootURL: URL, kind: FoundryPackItemKind) throws -> [URL] {
        let directoryURL = rootURL.appending(path: kind.rawValue, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let children = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return try children.map { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let hasManifest = FileManager.default.fileExists(atPath: url.appending(path: "Info.plist").path)
            let hasResources = FileManager.default.fileExists(atPath: url.appending(path: "Resources").path)
            guard values.isDirectory == true, values.isSymbolicLink != true, hasManifest, hasResources else {
                throw FoundryPackLoadingError.invalidItem(
                    "\(kind.rawValue)/\(url.lastPathComponent)"
                )
            }
            return url.standardizedFileURL
        }.sorted { $0.path < $1.path }
    }
}
