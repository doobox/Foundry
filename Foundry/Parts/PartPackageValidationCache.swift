import CryptoKit
import Foundation
import Synchronization

nonisolated enum PartPackageValidationCache {
    private struct Document: Codable, Sendable {
        let formatVersion: Int
        let validatorVersion: Int
        let applicationBuild: String
        var successfulFingerprints: [String: String]
    }

    private struct State: Sendable {
        var document: Document?
        var isDirty = false
    }

    private static let formatVersion = 3
    // Increment whenever validation rules change without an application build change.
    private static let validatorVersion = 9
    private static let state = Mutex(State())

    static func fingerprint(
        manifestData: Data,
        manifest: PartPackageManifest,
        rootURL: URL
    ) -> String? {
        var hasher = SHA256()
        update(&hasher, with: "validator:\(validatorVersion)\n")
        hasher.update(data: manifestData)

        let contentPaths = Set(
            ([manifest.render.html, manifest.render.editorCSS].compactMap { $0 })
                + manifest.render.files.map(\.path)
        )
        let declaredPaths = Set((manifest.icon?.file.map { [$0] } ?? []) + Array(contentPaths) + manifest.assets.map(\.path))

        for path in declaredPaths.sorted() {
            update(&hasher, with: "\npath:\(path)\n")
            guard isSafeRelativePath(path) else {
                update(&hasher, with: "unsafe")
                continue
            }
            let url = rootURL.appending(path: path)
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]) else {
                update(&hasher, with: "missing")
                continue
            }
            update(
                &hasher,
                with: "exists:\(values.isRegularFile == true):\(values.fileSize ?? -1):\(values.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1)"
            )
            if contentPaths.contains(path) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func contains(_ fingerprint: String, for packageURL: URL) -> Bool {
        let key = packageURL.standardizedFileURL.path
        return state.withLock { state in
            loadIfNeeded(state: &state)
            return state.document?.successfulFingerprints[key] == fingerprint
        }
    }

    static func storeSuccessful(_ fingerprint: String, for packageURL: URL) {
        let key = packageURL.standardizedFileURL.path
        state.withLock { state in
            loadIfNeeded(state: &state)
            if state.document?.successfulFingerprints[key] != fingerprint {
                state.document?.successfulFingerprints[key] = fingerprint
                state.isDirty = true
            }
        }
    }

    static func flush(retaining packageURLs: [URL]? = nil) {
        let data: Data? = state.withLock { state in
            loadIfNeeded(state: &state)
            if let packageURLs {
                let retained = Set(packageURLs.map { $0.standardizedFileURL.path })
                if var document = state.document {
                    document.successfulFingerprints = document.successfulFingerprints.filter { retained.contains($0.key) }
                    state.document = document
                    state.isDirty = true
                }
            }
            guard state.isDirty, let document = state.document else { return nil }
            state.isDirty = false
            return try? JSONEncoder().encode(document)
        }
        guard let data, let cacheURL = try? cacheURL() else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Validation remains correct when its performance cache cannot be written.
        }
    }

    private static func loadIfNeeded(state: inout State) {
        guard state.document == nil else { return }
        let build = applicationBuild
        if let url = try? cacheURL(),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Document.self, from: data),
           decoded.formatVersion == formatVersion,
           decoded.validatorVersion == validatorVersion,
           decoded.applicationBuild == build {
            state.document = decoded
        } else {
            state.document = Document(
                formatVersion: formatVersion,
                validatorVersion: validatorVersion,
                applicationBuild: build,
                successfulFingerprints: [:]
            )
            state.isDirty = true
        }
    }

    private static func update(_ hasher: inout SHA256, with string: String) {
        hasher.update(data: Data(string.utf8))
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        let parts = NSString(string: path).pathComponents
        return !path.isEmpty
            && !NSString(string: path).isAbsolutePath
            && !parts.contains("..")
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
            .appending(path: "SuccessfulValidation-v\(formatVersion).json")
    }
}
