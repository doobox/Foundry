import AppKit
import Foundation
import Synchronization

nonisolated struct LoadedComponentIcon: @unchecked Sendable {
    let image: NSImage
}

actor ComponentIconLoader {
    static let shared = ComponentIconLoader()

    private nonisolated static let cache = Mutex<[URL: LoadedComponentIcon]>([:])

    nonisolated static func cachedIcon(at sourceURL: URL) -> LoadedComponentIcon? {
        let url = sourceURL.standardizedFileURL
        return cache.withLock { $0[url] }
    }

    func icon(at sourceURL: URL) -> LoadedComponentIcon? {
        let url = sourceURL.standardizedFileURL
        if let cached = Self.cachedIcon(at: url) { return cached }
        guard let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              byteCount <= ComponentPackageValidator.maximumIconByteCount,
              let image = NSImage(contentsOf: url) else { return nil }
        let loaded = LoadedComponentIcon(image: image)
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
