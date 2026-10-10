import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum WebIconGenerator {
    static let exportDirectory = "assets/web-icons"
    static let faviconPNGSizes = [16, 32, 48]
    static let appleTouchSizes = [57, 76, 114, 120, 152, 167, 180]
    static let icoSizes = [16, 32, 48, 64, 96, 128, 256]

    static func sourceValidationError(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return "Choose a valid raster image."
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            swap(&width, &height)
        }
        guard width == height else { return "The web icon source must be square." }
        guard width >= 256 else { return "The web icon source must be at least 256 × 256 pixels." }
        return nil
    }

    static func exportPlan(
        storedAssets: [ProjectAsset],
        contents: ProjectAssetContents
    ) -> WebIconExportPlan {
        let files = generatedFilenames.compactMap { filename -> SiteExportFile? in
            guard let asset = storedAssets.first(where: { $0.filename == filename }),
                  contents.hasContent(asset.id) else { return nil }
            return SiteExportFile(
                path: exportDirectory + "/" + filename,
                fingerprint: contents.digest(asset.id),
                resolve: { contents[asset.id]?.data }
            )
        }
        return WebIconExportPlan(files: files)
    }

    static func isManagedExportPath(_ path: String) -> Bool {
        path == exportDirectory || path.hasPrefix(exportDirectory + "/")
    }

    static var generatedFilenames: [String] {
        ["favicon.ico"]
            + faviconPNGSizes.map { "favicon-\($0)x\($0).png" }
            + appleTouchSizes.map { "apple-touch-icon-\($0)x\($0).png" }
    }

    static func generateFiles(from sourceData: Data) -> [SiteExportFile] {
        guard sourceValidationError(for: sourceData) == nil else { return [] }

        var files: [SiteExportFile] = []
        let icoImages = icoSizes.compactMap { size in
            pngData(from: sourceData, size: size).map { (size, $0) }
        }
        if let ico = icoData(images: icoImages) {
            files.append(.init(path: exportDirectory + "/favicon.ico", data: ico))
        }
        for size in faviconPNGSizes {
            guard let data = pngData(from: sourceData, size: size) else { continue }
            files.append(.init(
                path: exportDirectory + "/favicon-\(size)x\(size).png",
                data: data
            ))
        }
        for size in appleTouchSizes {
            guard let data = pngData(from: sourceData, size: size) else { continue }
            files.append(.init(
                path: exportDirectory + "/apple-touch-icon-\(size)x\(size).png",
                data: data
            ))
        }
        return files
    }

    private static func pngData(from sourceData: Data, size: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size
              ] as CFDictionary),
              let context = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func icoData(images: [(size: Int, data: Data)]) -> Data? {
        guard !images.isEmpty else { return nil }
        var result = Data()
        appendUInt16(0, to: &result)
        appendUInt16(1, to: &result)
        appendUInt16(UInt16(images.count), to: &result)

        var offset = 6 + images.count * 16
        for image in images {
            result.append(UInt8(image.size == 256 ? 0 : image.size))
            result.append(UInt8(image.size == 256 ? 0 : image.size))
            result.append(0)
            result.append(0)
            appendUInt16(1, to: &result)
            appendUInt16(32, to: &result)
            appendUInt32(UInt32(image.data.count), to: &result)
            appendUInt32(UInt32(offset), to: &result)
            offset += image.data.count
        }
        images.forEach { result.append($0.data) }
        return result
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

nonisolated struct WebIconExportPlan: Sendable {
    let files: [SiteExportFile]

    func markup(rootPrefix: String) -> [String] {
        let paths = Set(files.map(\.path))
        var lines: [String] = []
        let icoPath = WebIconGenerator.exportDirectory + "/favicon.ico"
        if paths.contains(icoPath) {
            lines.append(
                "<link rel=\"shortcut icon\" href=\"\(rootPrefix)\(icoPath)\" type=\"image/x-icon\">"
            )
        }
        for size in WebIconGenerator.faviconPNGSizes {
            let path = WebIconGenerator.exportDirectory + "/favicon-\(size)x\(size).png"
            guard paths.contains(path) else { continue }
            lines.append(
                "<link rel=\"icon\" type=\"image/png\" sizes=\"\(size)x\(size)\" href=\"\(rootPrefix)\(path)\">"
            )
        }
        for size in WebIconGenerator.appleTouchSizes {
            let path = WebIconGenerator.exportDirectory + "/apple-touch-icon-\(size)x\(size).png"
            guard paths.contains(path) else { continue }
            lines.append(
                "<link rel=\"apple-touch-icon\" sizes=\"\(size)x\(size)\" href=\"\(rootPrefix)\(path)\">"
            )
        }
        return lines
    }
}
