import Foundation

nonisolated enum FoundryPackType: String, Codable, Sendable {
    case component
    case theme
    case collection
}

nonisolated struct FoundryPackHeader: Codable, Sendable {
    let type: FoundryPackType
    let identifier: String

    enum CodingKeys: String, CodingKey {
        case type
        case identifier = "CFBundleIdentifier"
    }
}

nonisolated struct FoundryPack: Sendable {
    let type: FoundryPackType
    let identifier: String
    let rootURL: URL
}

nonisolated enum FoundryPackLoadingError: Error, LocalizedError {
    case wrongExtension
    case missingManifest
    case invalidManifest(Error)

    var errorDescription: String? {
        switch self {
        case .wrongExtension:
            "Foundry extensions must use the .foundrypack extension."
        case .missingManifest:
            "The pack does not contain Contents/Info.plist."
        case .invalidManifest(let error):
            "The pack's Info.plist is invalid: \(error.localizedDescription)"
        }
    }
}

nonisolated enum FoundryPackLoader {
    static func load(from rootURL: URL) throws -> FoundryPack {
        guard rootURL.pathExtension.lowercased() == "foundrypack" else {
            throw FoundryPackLoadingError.wrongExtension
        }
        let manifestURL = rootURL.appending(path: "Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw FoundryPackLoadingError.missingManifest
        }
        do {
            let header = try PropertyListDecoder().decode(
                FoundryPackHeader.self,
                from: Data(contentsOf: manifestURL)
            )
            guard !header.identifier.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return FoundryPack(type: header.type, identifier: header.identifier, rootURL: rootURL)
        } catch {
            throw FoundryPackLoadingError.invalidManifest(error)
        }
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

    static func packURLs(in rootURL: URL, includingRoot: Bool = false) -> [URL] {
        var results: [URL] = []
        var visited: Set<URL> = []

        func visit(_ url: URL, isRoot: Bool) {
            let standardizedURL = url.standardizedFileURL
            guard visited.insert(standardizedURL).inserted else { return }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { return }

            if url.pathExtension.lowercased() == "foundrypack", (!isRoot || includingRoot) {
                results.append(url)
            }
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for child in children {
                visit(child, isRoot: false)
            }
        }

        visit(rootURL, isRoot: true)
        return results.sorted {
            $0.standardizedFileURL.path < $1.standardizedFileURL.path
        }
    }
}
