import Foundation

nonisolated enum FoundryPackType: String, Codable, Sendable {
    case component
    case theme
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

    static func packURLs(in rootURL: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "foundrypack" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
