import Foundation

nonisolated struct ThemePackageManifest: Codable, Equatable, Sendable {
    let type: FoundryPackType
    let identifier: String
    let version: String
    let minimumFoundryVersion: String?
    let name: String
    let description: String
    let author: String?
    let category: String
    let tags: [String]
    let icon: String
    let properties: [ComponentPackageProperty]
    let theme: Theme
    let assets: [String]
    let helpURL: URL?

    enum CodingKeys: String, CodingKey {
        case type
        case identifier = "CFBundleIdentifier"
        case version
        case minimumFoundryVersion
        case name
        case description
        case author
        case category
        case tags
        case icon
        case properties
        case theme
        case assets
        case helpURL
    }
}

nonisolated struct ThemePackageLock: Codable, Equatable, Hashable, Sendable {
    let identifier: String
    let version: String
}

nonisolated struct LoadedThemePackage: Sendable {
    let manifest: ThemePackageManifest
    let rootURL: URL

    var iconURL: URL {
        rootURL.appending(path: "Contents/Resources").appending(path: manifest.icon)
    }
    var lock: ThemePackageLock {
        .init(identifier: manifest.identifier, version: manifest.version)
    }
}

nonisolated enum ThemePackageLoader {
    static func load(from rootURL: URL) throws -> LoadedThemePackage {
        let manifestURL = rootURL.appending(path: "Contents/Info.plist")
        let manifest = try PropertyListDecoder().decode(
            ThemePackageManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.type == .theme,
              !manifest.identifier.isEmpty,
              !manifest.version.isEmpty,
              !manifest.name.isEmpty,
              FileManager.default.fileExists(
                atPath: rootURL.appending(path: "Contents/Resources").appending(path: manifest.icon).path
              ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return LoadedThemePackage(manifest: manifest, rootURL: rootURL)
    }
}
