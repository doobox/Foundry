import Foundation

nonisolated enum GoogleFontFileSize {
    // A fixed modern browser profile keeps comparisons between selections consistent.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    static func fontURLs(in css: String) throws -> [URL] {
        let expression = try NSRegularExpression(pattern: #"url\(\s*['"]?(https://fonts\.gstatic\.com/[^\s)'"]+)['"]?\s*\)"#)
        let urls = expression.matches(in: css, range: NSRange(css.startIndex..., in: css)).compactMap { match -> URL? in
            guard let range = Range(match.range(at: 1), in: css) else { return nil }
            return URL(string: String(css[range]))
        }
        return Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
    }

    static func measure(stylesheetURL: URL) async throws -> Int64 {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: stylesheetURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let css = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        let urls = try fontURLs(in: css)
        guard !urls.isEmpty else { throw URLError(.cannotParseResponse) }
        var total: Int64 = 0
        for url in urls {
            try Task.checkCancellation()
            let (file, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: file) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size else { throw URLError(.cannotDecodeContentData) }
            total += Int64(size)
        }
        try Task.checkCancellation()
        return total
    }
}
