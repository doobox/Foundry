import Foundation

nonisolated protocol SiteExportWriting: Sendable {
    func write(_ bundle: SiteExportBundle, to directory: URL) throws
}

nonisolated enum SiteExportWriterError: LocalizedError {
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            "Foundry refused to write an unsafe export path: \(path)"
        }
    }
}

nonisolated struct SiteExportWriter: SiteExportWriting {
    func write(_ bundle: SiteExportBundle, to directory: URL) throws {
        try write(bundle, to: directory, cleaningObsoleteFiles: true)
    }

    func write(_ bundle: SiteExportBundle, to directory: URL, cleaningObsoleteFiles: Bool) throws {
        try bundle.validate()
        let fileManager = FileManager.default
        let root = try Self.preparedRoot(directory, fileManager: fileManager)
        let previous = Self.loadOwnershipManifest(from: root, fileManager: fileManager)
        let current = Dictionary(uniqueKeysWithValues: bundle.files.map {
            ($0.path, PublishingPlan.hash($0.data))
        })
        let obsolete = previous.files.keys.filter { current[$0] == nil }.sorted()

        if cleaningObsoleteFiles {
            _ = try Self.removeOwnedFiles(
                obsolete,
                expectedHashes: previous.files,
                from: root,
                fileManager: fileManager
            )
        }

        for file in bundle.files {
            try Self.write(file, to: root, fileManager: fileManager)
        }

        let retained = cleaningObsoleteFiles
            ? current
            : previous.files.merging(current) { _, new in new }
        try Self.writeOwnershipManifest(.init(files: retained), to: root, fileManager: fileManager)
    }

    @discardableResult
    func apply(
        _ plan: PublishingPlan,
        bundle: SiteExportBundle,
        to directory: URL
    ) throws -> Int {
        try bundle.validate()
        let fileManager = FileManager.default
        let root = try Self.preparedRoot(directory, fileManager: fileManager)
        let removedCount = try Self.removeOwnedFiles(
            plan.removals,
            expectedHashes: plan.removalHashes,
            from: root,
            fileManager: fileManager
        )
        for file in plan.uploads {
            try Self.write(file, to: root, fileManager: fileManager)
        }
        try Self.writeOwnershipManifest(
            .init(files: plan.nextManifest.files),
            to: root,
            fileManager: fileManager
        )
        return removedCount
    }

    private struct ExportOwnershipManifest: Codable {
        let version: Int
        let files: [String: String]

        init(files: [String: String]) {
            version = 1
            self.files = files
        }
    }

    private static let manifestFilename = ".foundry-export-manifest.json"

    private static func preparedRoot(_ directory: URL, fileManager: FileManager) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func write(
        _ file: SiteExportFile,
        to root: URL,
        fileManager: FileManager
    ) throws {
        let url = try safeURL(for: file.path, under: root, fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try safeURL(for: file.path, under: root, fileManager: fileManager)
        try file.data.write(to: url, options: .atomic)
    }

    private static func removeOwnedFiles(
        _ paths: [String],
        expectedHashes: [String: String],
        from root: URL,
        fileManager: FileManager
    ) throws -> Int {
        var removedURLs: [URL] = []
        for path in paths {
            guard let expectedHash = expectedHashes[path] else { continue }
            let url = try safeURL(for: path, under: root, fileManager: fileManager)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            let existingData = try Data(contentsOf: url)
            guard PublishingPlan.hash(existingData) == expectedHash else { continue }
            try fileManager.removeItem(at: url)
            removedURLs.append(url)
        }
        pruneEmptyParentDirectories(of: removedURLs, under: root, fileManager: fileManager)
        return removedURLs.count
    }

    private static func pruneEmptyParentDirectories(
        of removedURLs: [URL],
        under root: URL,
        fileManager: FileManager
    ) {
        var candidates = Set<URL>()
        for removedURL in removedURLs {
            var candidate = removedURL.deletingLastPathComponent()
            while candidate != root && isDescendant(candidate, of: root) {
                candidates.insert(candidate)
                candidate.deleteLastPathComponent()
            }
        }
        for directory in candidates.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
                  contents.isEmpty else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    private static func loadOwnershipManifest(
        from root: URL,
        fileManager: FileManager
    ) -> ExportOwnershipManifest {
        guard let manifestURL = try? safeURL(
            for: manifestFilename,
            under: root,
            fileManager: fileManager
        ), let data = try? Data(contentsOf: manifestURL) else {
            return .init(files: [:])
        }
        if let manifest = try? JSONDecoder().decode(ExportOwnershipManifest.self, from: data) {
            return manifest
        }

        // A legacy path-only manifest cannot prove that its files still match Foundry's output.
        // Leave those files untouched rather than risking deletion of a user's local edits.
        return .init(files: [:])
    }

    private static func writeOwnershipManifest(
        _ manifest: ExportOwnershipManifest,
        to root: URL,
        fileManager: FileManager
    ) throws {
        let data = try JSONEncoder().encode(manifest)
        let url = try safeURL(for: manifestFilename, under: root, fileManager: fileManager)
        try data.write(to: url, options: .atomic)
    }

    private static func safeURL(
        for path: String,
        under root: URL,
        fileManager: FileManager
    ) throws -> URL {
        guard isSafeRelativePath(path) else { throw SiteExportWriterError.unsafePath(path) }
        var candidate = root
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            candidate.append(path: String(component))
            if let attributes = try? fileManager.attributesOfItem(atPath: candidate.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw SiteExportWriterError.unsafePath(path)
            }
        }
        candidate = candidate.standardizedFileURL
        guard isDescendant(candidate, of: root) else {
            throw SiteExportWriterError.unsafePath(path)
        }
        return candidate
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        candidate.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty
            && !path.hasPrefix("/")
            && !components.contains("")
            && !components.contains(".")
            && !components.contains("..")
    }
}
