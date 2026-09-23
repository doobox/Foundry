import CoreGraphics
import Foundation
import ImageIO

/// Downsampled thumbnails for asset-collection files, decoded off the main
/// thread and sized for panel rows.
enum AssetCollectionThumbnailLoader {
    static func thumbnail(for url: URL) async -> CGImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}
