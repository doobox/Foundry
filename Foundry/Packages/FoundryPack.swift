import Foundation

nonisolated struct FoundryPack: Sendable {
    let identifier: String
    let rootURL: URL
    let metadata: FoundryPackMetadata
    let partURLs: [URL]
    let templateURLs: [URL]
    let frameworkURLs: [URL]
    let assetCollectionURLs: [URL]
    /// Typed items that are not a directory containing Info.plist and
    /// Resources — typically a part folder mid-creation in a development
    /// pack. Loading skips them so the rest of the pack stays usable;
    /// installation and release authoring reject packs that carry any.
    let invalidItemPaths: [String]
}

nonisolated enum FoundryPackItemKind: String, CaseIterable, Sendable {
    case part = "Parts"
    case template = "Templates"
    case framework = "Frameworks"
    case assetCollection = "Assets"
}

nonisolated enum FoundryPackLoadingError: Error, LocalizedError {
    case wrongExtension
    case missingManifest
    case invalidManifest(Error)
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
    private static let allowedTopLevelNames = Set(
        ["Info.plist", "Resources"] + FoundryPackItemKind.allCases.map(\.rawValue)
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
        let identifier = metadata.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { throw FoundryPackLoadingError.missingIdentifier }

        // Hidden files are tolerated so development packs can live inside a
        // git checkout (.git, .gitignore) without being rejected.
        let children = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        if let unknown = children.first(where: { !allowedTopLevelNames.contains($0.lastPathComponent) }) {
            throw FoundryPackLoadingError.unknownTopLevelItem(unknown.lastPathComponent)
        }

        var invalidItemPaths: [String] = []
        let partURLs = try itemURLs(in: rootURL, kind: .part, invalidPaths: &invalidItemPaths)
        let templateURLs = try itemURLs(in: rootURL, kind: .template, invalidPaths: &invalidItemPaths)
        let frameworkURLs = try itemURLs(in: rootURL, kind: .framework, invalidPaths: &invalidItemPaths)
        let assetCollectionURLs = try itemURLs(in: rootURL, kind: .assetCollection, invalidPaths: &invalidItemPaths)
        return FoundryPack(
            identifier: identifier,
            rootURL: rootURL,
            metadata: metadata,
            partURLs: partURLs,
            templateURLs: templateURLs,
            frameworkURLs: frameworkURLs,
            assetCollectionURLs: assetCollectionURLs,
            invalidItemPaths: invalidItemPaths.sorted()
        )
    }

    /// The pack of built-in content shipped inside the app bundle.
    static func builtInPackURL() -> URL? {
        guard let bundleURL = Bundle.main.url(forResource: "BuiltInParts", withExtension: "bundle"),
              let partBundle = Bundle(url: bundleURL) else { return nil }
        let containerURL = partBundle.url(forResource: "BuiltInParts", withExtension: "foundrypack")
            ?? partBundle.resourceURL?.appending(path: "BuiltInParts.foundrypack", directoryHint: .isDirectory)
        return containerURL?.standardizedFileURL
    }

    static func installedPacksURL(fileManager: FileManager = .default) throws -> URL {
        try FoundryLibraryLocation.directoryURL(named: "Packs", fileManager: fileManager)
    }

    static func personalDevelopmentPackURL(fileManager: FileManager = .default) throws -> URL {
        let url = try installedPacksURL(fileManager: fileManager)
            .appending(path: "My Library.foundrydevpack", directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let manifest: [String: Any] = [
                "id": "local.foundry.my-library",
                "title": "My Library",
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

    private static func itemURLs(
        in rootURL: URL,
        kind: FoundryPackItemKind,
        invalidPaths: inout [String]
    ) throws -> [URL] {
        let directoryURL = rootURL.appending(path: kind.rawValue, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        // Templates organize into plain directories — a child without an
        // Info.plist is a folder, recursed for the bundles inside.
        if kind == .template {
            var valid: [URL] = []
            try collectTemplateItems(
                in: directoryURL,
                relativePath: kind.rawValue,
                valid: &valid,
                invalidPaths: &invalidPaths
            )
            return valid.sorted { $0.path < $1.path }
        }
        let children = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var valid: [URL] = []
        for url in children {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isPlainDirectory = values.isDirectory == true && values.isSymbolicLink != true
            // Asset collections are hand-authorable: any folder of files is a
            // collection, and its Info.plist is optional licence metadata.
            // The other kinds are structured items Foundry generates.
            let isValidItem: Bool
            if kind == .assetCollection {
                isValidItem = isPlainDirectory
            } else {
                let hasManifest = FileManager.default.fileExists(atPath: url.appending(path: "Info.plist").path)
                let hasResources = FileManager.default.fileExists(atPath: url.appending(path: "Resources").path)
                isValidItem = isPlainDirectory && hasManifest && hasResources
            }
            if isValidItem {
                valid.append(url.standardizedFileURL)
            } else {
                invalidPaths.append("\(kind.rawValue)/\(url.lastPathComponent)")
            }
        }
        return valid.sorted { $0.path < $1.path }
    }

    private static func collectTemplateItems(
        in directoryURL: URL,
        relativePath: String,
        valid: inout [URL],
        invalidPaths: inout [String]
    ) throws {
        let children = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        for url in children {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let path = "\(relativePath)/\(url.lastPathComponent)"
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                invalidPaths.append(path)
                continue
            }
            if FileManager.default.fileExists(atPath: url.appending(path: "Info.plist").path) {
                if FileManager.default.fileExists(atPath: url.appending(path: "Resources").path) {
                    valid.append(url.standardizedFileURL)
                } else {
                    invalidPaths.append(path)
                }
            } else {
                try collectTemplateItems(
                    in: url,
                    relativePath: path,
                    valid: &valid,
                    invalidPaths: &invalidPaths
                )
            }
        }
    }
}
