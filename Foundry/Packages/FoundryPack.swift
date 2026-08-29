import Foundation

nonisolated struct FoundryPackManifest: Codable, Equatable, Sendable {
    static let supportedAPIVersion = 1

    let apiVersion: Int
    let identifier: String
    let version: String
    let name: String
    let description: String
    let author: String?

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case identifier = "id"
        case version
        case name
        case description
        case author
    }
}

nonisolated struct FoundryPackageMetadata: Codable, Equatable, Sendable {
    let apiVersion: Int
    let identifier: String
    let version: String
    let minimumFoundryVersion: String?
    let name: String
    let description: String
    let author: String?
    let category: String
    let tags: [String]
    let icon: String
    let assets: [String]
    let helpURL: URL?

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case identifier = "id"
        case version
        case minimumFoundryVersion
        case name
        case description
        case author
        case category
        case tags
        case icon
        case assets
        case helpURL
    }
}

nonisolated struct FoundryPack: Sendable {
    let manifest: FoundryPackManifest
    let rootURL: URL
    let componentURLs: [URL]
    let themeURLs: [URL]
}

nonisolated enum FoundryPackLoader {
    static func load(from rootURL: URL) throws -> FoundryPack {
        let manifestURL = rootURL.appending(path: "pack.json")
        let manifest = try JSONDecoder().decode(
            FoundryPackManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.apiVersion == FoundryPackManifest.supportedAPIVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let children = try FileManager.default.subpathsOfDirectory(atPath: rootURL.path)
            .map { rootURL.appending(path: $0) }
        return FoundryPack(
            manifest: manifest,
            rootURL: rootURL,
            componentURLs: packageRoots(in: children, extension: "foundrycomponent"),
            themeURLs: packageRoots(in: children, extension: "foundrytheme")
        )
    }

    static func installedPacksURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = applicationSupport
            .appending(path: "Foundry", directoryHint: .isDirectory)
            .appending(path: "Packs", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func packageRoots(in urls: [URL], extension pathExtension: String) -> [URL] {
        let matches = urls.filter { $0.pathExtension == pathExtension }
        return matches.filter { candidate in
            !matches.contains { other in
                other != candidate && candidate.path.hasPrefix(other.path + "/")
            }
        }.sorted { $0.path < $1.path }
    }
}
