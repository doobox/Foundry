import AVFoundation
import Foundation
import UniformTypeIdentifiers

nonisolated enum RemoteVideoImport {
    static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The caller owns the returned temporary directory and must remove it.
    static func download(_ url: URL, fetch: @Sendable (URLRequest) async throws -> (URL, URLResponse) = {
        try await URLSession.shared.download(for: $0)
    }) async throws -> URL {
        guard webURL(url.absoluteString) != nil else { throw URLError(.badURL) }
        let (download, response) = try await fetch(URLRequest(url: url, timeoutInterval: 120))
        defer { try? FileManager.default.removeItem(at: download) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.mimeType?.lowercased() != "text/html",
              response.mimeType?.lowercased() != "application/xhtml+xml",
              let size = try download.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 100_000_000 else { throw URLError(.cannotDecodeContentData) }
        try Task.checkCancellation()
        let type = PartMediaImport.contentType(filename: response.url?.lastPathComponent ?? url.lastPathComponent,
                                               mediaType: response.mimeType ?? "")
        guard let type, type.conforms(to: .movie), let ext = type.preferredFilenameExtension else {
            throw URLError(.cannotDecodeContentData)
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "foundry-web-video-\(UUID().uuidString)")
        let file = directory.appending(path: "video." + ext)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: download, to: file)
            let tracks = try await AVURLAsset(url: file).loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else { throw URLError(.cannotDecodeContentData) }
            try Task.checkCancellation()
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
