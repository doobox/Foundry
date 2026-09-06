import AppKit
import Foundation

nonisolated struct LoadedComponentIcon: @unchecked Sendable {
    let image: NSImage
}

actor ComponentIconLoader {
    static let shared = ComponentIconLoader()

    private var cache: [URL: LoadedComponentIcon] = [:]

    func icon(at sourceURL: URL) -> LoadedComponentIcon? {
        let url = sourceURL.standardizedFileURL
        if let cached = cache[url] { return cached }
        guard let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              byteCount <= ComponentPackageValidator.maximumIconByteCount,
              let image = NSImage(contentsOf: url) else { return nil }
        let loaded = LoadedComponentIcon(image: image)
        cache[url] = loaded
        return loaded
    }

    func removeIcon(at sourceURL: URL) {
        cache.removeValue(forKey: sourceURL.standardizedFileURL)
    }
}
