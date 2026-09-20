import Foundation
import Synchronization

nonisolated struct PartPackagePreparedIndexEntry: Codable, Sendable {
    let manifest: PartPackageManifest
    let fingerprint: PartPackagePreparedIndex.Fingerprint
    let primitives: PartPreparedPrimitives
}

nonisolated enum PartPackagePreparedIndex {
    struct Fingerprint: Codable, Equatable, Sendable {
        let manifestSize: Int64
        let manifestModificationTime: TimeInterval
        let templateSize: Int64
        let templateModificationTime: TimeInterval
    }

    private struct Document: Codable, Sendable {
        let formatVersion: Int
        let applicationBuild: String
        var entries: [String: PartPackagePreparedIndexEntry]
    }

    private struct State: Sendable {
        var document: Document?
        var isDirty = false
    }

    // 6: theme→framework rename of control kinds and manifest keys.
    private static let formatVersion = 8
    private static let state = Mutex(State())

    static func entry(for rootURL: URL) -> PartPackagePreparedIndexEntry? {
        let key = rootURL.standardizedFileURL.path
        return state.withLock { state in
            loadIfNeeded(state: &state)
            guard let entry = state.document?.entries[key],
                  fingerprint(for: rootURL, manifest: entry.manifest) == entry.fingerprint else {
                if state.document?.entries.removeValue(forKey: key) != nil {
                    state.isDirty = true
                }
                return nil
            }
            return entry
        }
    }

    static func store(
        manifest: PartPackageManifest,
        primitives: PartPreparedPrimitives,
        rootURL: URL
    ) {
        guard let fingerprint = fingerprint(for: rootURL, manifest: manifest) else { return }
        let key = rootURL.standardizedFileURL.path
        state.withLock { state in
            loadIfNeeded(state: &state)
            state.document?.entries[key] = .init(
                manifest: manifest,
                fingerprint: fingerprint,
                primitives: primitives
            )
            state.isDirty = true
        }
    }

    static func flush(retaining rootURLs: [URL]? = nil) {
        let data: Data? = state.withLock { state in
            loadIfNeeded(state: &state)
            if let rootURLs {
                let retained = Set(rootURLs.map { $0.standardizedFileURL.path })
                if var document = state.document {
                    document.entries = document.entries.filter { retained.contains($0.key) }
                    state.document = document
                }
                state.isDirty = true
            }
            guard state.isDirty, let document = state.document else { return nil }
            state.isDirty = false
            return try? PropertyListEncoder().encode(document)
        }
        guard let data, let cacheURL = try? cacheURL() else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // A cache write failure must never prevent part loading.
        }
    }

    private static func loadIfNeeded(state: inout State) {
        guard state.document == nil else { return }
        let currentBuild = applicationBuild
        if let url = try? cacheURL(),
           let data = try? Data(contentsOf: url),
           let decoded = try? PropertyListDecoder().decode(Document.self, from: data),
           decoded.formatVersion == formatVersion,
           decoded.applicationBuild == currentBuild {
            state.document = decoded
        } else {
            state.document = .init(
                formatVersion: formatVersion,
                applicationBuild: currentBuild,
                entries: [:]
            )
            state.isDirty = true
        }
    }

    private static func fingerprint(
        for rootURL: URL,
        manifest: PartPackageManifest
    ) -> Fingerprint? {
        let manifestURL = rootURL.appending(path: "Contents/Info.plist")
        let templateURL = rootURL.appending(path: "Contents/Resources/\(manifest.render.html)")
        guard let manifestValues = try? manifestURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let templateValues = try? templateURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let manifestSize = manifestValues.fileSize,
              let manifestDate = manifestValues.contentModificationDate,
              let templateSize = templateValues.fileSize,
              let templateDate = templateValues.contentModificationDate else { return nil }
        return .init(
            manifestSize: Int64(manifestSize),
            manifestModificationTime: manifestDate.timeIntervalSinceReferenceDate,
            templateSize: Int64(templateSize),
            templateModificationTime: templateDate.timeIntervalSinceReferenceDate
        )
    }

    private static var applicationBuild: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version)-\(build)"
    }

    private static func cacheURL() throws -> URL {
        let root = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return root
            .appending(path: Bundle.main.bundleIdentifier ?? "uk.co.garysimpson.Foundry", directoryHint: .isDirectory)
            .appending(path: "PartCatalog", directoryHint: .isDirectory)
            .appending(path: "PreparedIndex-v\(formatVersion).plist")
    }
}
