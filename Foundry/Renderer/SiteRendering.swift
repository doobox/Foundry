import Foundation
import CryptoKit
import Darwin

/// An immutable preview generation. In-flight requests retain it while a newer
/// generation is published, so PHP and static files never see a partial refresh.
nonisolated final class PreviewDiskSnapshot: @unchecked Sendable {
    let root: URL
    let fingerprints: [String: String]
    var index: SiteExportBundle {
        SiteExportBundle(files: fingerprints.keys.map { SiteExportFile(path: $0, data: Data()) })
    }

    private init(root: URL, fingerprints: [String: String]) {
        self.root = root
        self.fingerprints = fingerprints
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    static func build(previous: PreviewDiskSnapshot? = nil, generate: ((SiteExportFile) throws -> Void) throws -> Void) throws -> PreviewDiskSnapshot {
        let root = FileManager.default.temporaryDirectory.appending(path: "FoundryPreview-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var fingerprints: [String: String] = [:]
        let canReusePrevious = previous?.fingerprints.keys.contains(where: { $0.lowercased().hasSuffix(".php") }) == false
        do {
            try generate { file in
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
                        try file.data.write(to: target, options: .atomic)
                    }
                } else {
                    try file.data.write(to: target, options: .atomic)
                }
                fingerprints[file.path] = fingerprint
            }
            try Task.checkCancellation()
            return PreviewDiskSnapshot(root: root, fingerprints: fingerprints)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
}

nonisolated struct SiteExportFile: Equatable, Sendable {
    let path: String
    let data: Data
    let contentFingerprint: String?

    init(path: String, contents: String) {
        self.path = path
        data = Data(contents.utf8)
        contentFingerprint = nil
    }

    init(path: String, data: Data, contentFingerprint: String? = nil) {
        self.path = path
        self.data = data
        self.contentFingerprint = contentFingerprint
    }

    var contents: String { String(decoding: data, as: UTF8.self) }
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
    func render(site: Site, assets: [UUID: ProjectAssetContent]) -> SiteExportBundle
}
