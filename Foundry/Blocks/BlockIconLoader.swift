import AppKit
import Foundation
import Synchronization

nonisolated struct LoadedBlockIcon: @unchecked Sendable {
    let image: NSImage
}

actor BlockIconLoader {
    static let shared = BlockIconLoader()

    private nonisolated static let cache = Mutex<[URL: LoadedBlockIcon]>([:])

    nonisolated static func cachedIcon(at sourceURL: URL) -> LoadedBlockIcon? {
        let url = sourceURL.standardizedFileURL
        return cache.withLock { $0[url] }
    }

    func icon(at sourceURL: URL) -> LoadedBlockIcon? {
        let url = sourceURL.standardizedFileURL
        if let cached = Self.cachedIcon(at: url) { return cached }
        guard let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              byteCount <= BlockPackageValidator.maximumIconByteCount,
              let image = NSImage(contentsOf: url) else { return nil }
        let loaded = LoadedBlockIcon(image: image)
        return Self.cache.withLock { cache in
            if let cached = cache[url] { return cached }
            cache[url] = loaded
            return loaded
        }
    }

    func removeIcon(at sourceURL: URL) {
        _ = Self.cache.withLock { cache in
            cache.removeValue(forKey: sourceURL.standardizedFileURL)
        }
    }

    func removeAll() {
        Self.cache.withLock { $0.removeAll() }
    }
}
