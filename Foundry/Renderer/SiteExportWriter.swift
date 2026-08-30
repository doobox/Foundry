import Foundation

nonisolated protocol SiteExportWriting: Sendable {
    func write(_ bundle: SiteExportBundle, to directory: URL) throws
}

nonisolated struct SiteExportWriter: SiteExportWriting {
    func write(_ bundle: SiteExportBundle, to directory: URL) throws {
        try write(bundle, to: directory, cleaningObsoleteFiles: false)
    }

    func write(_ bundle: SiteExportBundle, to directory: URL, cleaningObsoleteFiles: Bool) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if cleaningObsoleteFiles,
           let data = try? Data(contentsOf: directory.appending(path: Self.manifestFilename)),
           let previousPaths = try? JSONDecoder().decode([String].self, from: data) {
            let currentPaths = Set(bundle.files.map(\.path))
            for path in previousPaths where !currentPaths.contains(path) && Self.isSafeRelativePath(path) {
                let url = directory.appending(path: path)
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
        }
        for file in bundle.files {
            let url = directory.appending(path: file.path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url, options: .atomic)
        }
        let manifest = try JSONEncoder().encode(bundle.files.map(\.path).sorted())
        try manifest.write(to: directory.appending(path: Self.manifestFilename), options: .atomic)
    }

    private static let manifestFilename = ".foundry-export-manifest.json"

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}
