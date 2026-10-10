import SwiftUI
import ImageIO

/// Framework-authored artwork, decoded at thumbnail size rather than its original resolution.
struct FrameworkArtworkPreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    // Empty only while the validated artwork is being decoded.
                    Color.clear
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: url) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 960
                  ] as CFDictionary) else { return }
            image = NSImage(cgImage: thumbnail, size: .zero)
        }
    }
}
