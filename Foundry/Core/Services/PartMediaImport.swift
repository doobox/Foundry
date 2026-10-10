import Foundation
import UniformTypeIdentifiers

nonisolated enum PartMediaImport {
    /// Finder and WebKit may describe an SVG as generic XML or binary data.
    /// Prefer a recognised media MIME type, otherwise inspect the filename.
    static func contentType(filename: String, mediaType: String) -> UTType? {
        let reported = UTType(mimeType: mediaType)
        if let reported, reported.conforms(to: .image) || reported.conforms(to: .movie) {
            return reported
        }
        return UTType(filenameExtension: (filename as NSString).pathExtension) ?? reported
    }
}
