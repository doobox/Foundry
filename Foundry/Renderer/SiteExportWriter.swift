import Foundation

nonisolated protocol SiteExportWriting: Sendable {
    func write(_ bundle: SiteExportBundle, to directory: URL) throws
}

nonisolated struct SiteExportWriter: SiteExportWriting {
    func write(_ bundle: SiteExportBundle, to directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in bundle.files {
            let url = directory.appending(path: file.path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url, options: .atomic)
        }
    }
}
