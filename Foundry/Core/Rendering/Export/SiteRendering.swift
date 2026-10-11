import Foundation
import CryptoKit
import Darwin
import OSLog

/// An immutable preview generation. In-flight requests retain it while a newer
/// generation is published, so PHP and static files never see a partial refresh.
nonisolated final class PreviewDiskSnapshot: @unchecked Sendable {
    let root: URL
    let fingerprints: [String: String]
    let buildIdentity: PreviewBuildIdentity?
    let pagePaths: [UUID: [String]]
    let reusedPageIDs: Set<UUID>
    private let containsPHP: Bool
    private static let logger = Logger(subsystem: "uk.co.garysimpson.Foundry", category: "PreviewPerformance")
    var index: SiteExportBundle {
        SiteExportBundle(files: fingerprints.keys.map { SiteExportFile(path: $0, data: Data()) })
    }

    private init(root: URL, fingerprints: [String: String], buildIdentity: PreviewBuildIdentity?, pagePaths: [UUID: [String]], reusedPageIDs: Set<UUID>) {
        self.root = root
        self.fingerprints = fingerprints
        self.buildIdentity = buildIdentity
        self.pagePaths = pagePaths
        self.reusedPageIDs = reusedPageIDs
        containsPHP = fingerprints.keys.contains { $0.lowercased().hasSuffix(".php") }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    static func build(previous: PreviewDiskSnapshot? = nil, identity: PreviewBuildIdentity? = nil,
                      pagePaths: () -> [UUID: [String]] = { [:] }, reusedPageIDs: Set<UUID> = [],
                      generate: ((SiteExportFile) throws -> Void) throws -> Void) throws -> PreviewDiskSnapshot {
        try Task.checkCancellation()
        // PHP may modify its document root, so it must always get a fresh
        // generation. Callers without a complete identity also always build.
        if let identity, let previous, previous.buildIdentity == identity, !previous.containsPHP {
            logger.debug("Reusing unchanged preview; no rendering or file generation")
            return previous
        }
        let started = ContinuousClock.now
        var outputDuration = Duration.zero
        let root = FileManager.default.temporaryDirectory.appending(path: "FoundryPreview-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var fingerprints: [String: String] = [:]
        let canReusePrevious = previous?.containsPHP == false
        do {
            try generate { file in
                let outputStarted = ContinuousClock.now
                defer { outputDuration += outputStarted.duration(to: .now) }
                try Task.checkCancellation()
                guard !file.path.hasPrefix("/"), !file.path.contains("\\"),
                      !file.path.contains("\0"), !file.path.split(separator: "/").contains(".."),
                      !file.path.split(separator: "/").contains("."),
                      file.path == file.path.split(separator: "/").joined(separator: "/"),
                      !file.path.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
                let fingerprint = file.contentFingerprint ?? SHA256.hash(data: file.data).map { String(format: "%02x", $0) }.joined()
                if let existing = fingerprints[file.path] {
                    guard existing == fingerprint else {
                        throw SiteExportBundleError.invalid(["Two assets publish to '\(file.path)' with different contents."])
                    }
                    return
                }
                let target = root.appending(path: file.path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if canReusePrevious, let previous, previous.fingerprints[file.path] == fingerprint {
                    // Copy-on-write clones on APFS avoid rewriting unchanged assets;
                    // unlike hard links, PHP cannot modify another generation's file.
                    let source = previous.root.appending(path: file.path)
                    if clonefile(source.path, target.path, 0) != 0 {
                        try file.resolvedData().write(to: target, options: .atomic)
                    }
                } else {
                    try file.resolvedData().write(to: target, options: .atomic)
                }
                fingerprints[file.path] = fingerprint
            }
            try Task.checkCancellation()
            let elapsed = started.duration(to: .now)
            logger.debug("Preview generation: \(String(describing: elapsed), privacy: .public); output/hash/assets: \(String(describing: outputDuration), privacy: .public); files: \(fingerprints.count); reused pages: \(reusedPageIDs.count)")
            return PreviewDiskSnapshot(root: root, fingerprints: fingerprints, buildIdentity: identity,
                                       pagePaths: pagePaths(), reusedPageIDs: reusedPageIDs)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    /// Preserve only page-owned output; shared CSS/assets are always re-planned.
    /// Lazy payloads keep the source generation alive until cloning completes.
    func reusablePages(for identity: PreviewBuildIdentity, invalidation: PreviewInvalidation) -> [UUID: [SiteExportFile]] {
        guard !containsPHP, let old = buildIdentity,
              old.siteID == identity.siteID, old.packageRevision == identity.packageRevision,
              old.documentRevision <= identity.documentRevision,
              old.assetRevision == identity.assetRevision,
              let dirty = invalidation.dirtyPages(since: old.documentRevision) else { return [:] }
        return pagePaths.filter { !dirty.contains($0.key) }.mapValues { paths in
            paths.map { path in
                SiteExportFile(path: path, fingerprint: fingerprints[path]) {
                    try? Data(contentsOf: self.root.appending(path: path))
                }
            }
        }
    }
}

nonisolated struct SiteExportFile: Equatable, Sendable {
    let path: String
    let contentFingerprint: String?

    private enum Payload: Sendable {
        case inline(Data)
        case resolved(@Sendable () -> Data?)
    }
    private let payload: Payload

    init(path: String, contents: String) {
        self.path = path
        payload = .inline(Data(contents.utf8))
        contentFingerprint = nil
    }

    init(path: String, data: Data, contentFingerprint: String? = nil) {
        self.path = path
        payload = .inline(data)
        self.contentFingerprint = contentFingerprint
    }

    /// A payload resolved on demand rather than held in memory up front.
    /// `fingerprint` stands in for the bytes wherever identity/change
    /// detection only needs to compare content, not read it.
    init(path: String, fingerprint: String?, resolve: @escaping @Sendable () -> Data?) {
        self.path = path
        payload = .resolved(resolve)
        contentFingerprint = fingerprint
    }

    /// Best-effort accessor kept for existing call sites that only ever see
    /// inline payloads; a lazy payload that fails to resolve reads as empty.
    /// Prefer `resolvedData()` wherever a resolution failure should be
    /// surfaced instead of silently treated as an empty file.
    var data: Data {
        switch payload {
        case .inline(let data): data
        case .resolved(let resolve): resolve() ?? Data()
        }
    }

    /// Throws when a lazy payload cannot be resolved (e.g. the document
    /// closed or the source asset moved) instead of silently producing an
    /// empty file.
    func resolvedData() throws -> Data {
        switch payload {
        case .inline(let data):
            return data
        case .resolved(let resolve):
            guard let data = resolve() else {
                throw SiteExportFileError.unavailable(path)
            }
            return data
        }
    }

    var contents: String { String(decoding: data, as: UTF8.self) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.path == rhs.path else { return false }
        switch (lhs.payload, rhs.payload) {
        case (.inline(let lhsData), .inline(let rhsData)):
            return lhsData == rhsData && lhs.contentFingerprint == rhs.contentFingerprint
        default:
            // At least one side is lazily resolved: fingerprints are already
            // the identity that publish/export diffing treats as authoritative.
            return lhs.contentFingerprint == rhs.contentFingerprint
        }
    }
}

nonisolated enum SiteExportFileError: LocalizedError, Equatable {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let path):
            "The contents of '\(path)' are no longer available."
        }
    }
}

nonisolated struct SiteExportBundle: Equatable, Sendable {
    let files: [SiteExportFile]
    let errors: [String]

    init(files: [SiteExportFile], errors: [String] = []) {
        self.files = files
        self.errors = errors
    }

    func file(at path: String) -> SiteExportFile? {
        files.first(where: { $0.path == path })
    }

    func validate() throws {
        if !errors.isEmpty { throw SiteExportBundleError.invalid(errors) }
    }
}

nonisolated enum SiteExportBundleError: LocalizedError, Equatable {
    case invalid([String])

    var errorDescription: String? {
        switch self {
        case .invalid(let errors):
            errors.joined(separator: "\n")
        }
    }
}

nonisolated protocol SiteRendering: Sendable {
    func render(site: Site, assets: ProjectAssetContents) -> SiteExportBundle
}
