import AppKit
import AVFoundation

nonisolated enum VideoPosterGenerator {
    struct Result: Sendable {
        let metadata: ProjectVideoMetadata
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// Convenience for bytes with no on-disk home yet (e.g. a fresh import
    /// still staged in memory). Stages to a temp file only for this call,
    /// then delegates to the URL-based entry point below.
    static func metadata(for data: Data, filename: String) async -> Result? {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "foundry-video-poster-\(UUID().uuidString)", directoryHint: .isDirectory)
        let videoURL = temporaryDirectory.appending(path: filename)
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try data.write(to: videoURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            return nil
        }
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        return await metadata(for: videoURL)
    }

    /// Preferred entry point when the video already has a stable on-disk
    /// location — avoids a redundant full copy of the source bytes.
    static func metadata(for url: URL) async -> Result? {
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 720)
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity

            let result = try await generator.image(
                at: CMTime(seconds: 0.1, preferredTimescale: 600)
            )
            guard !Task.isCancelled else { return nil }
            let bitmap = NSBitmapImageRep(cgImage: result.image)
            guard let jpeg = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.78]
            ) else { return nil }
            return Result(
                metadata: ProjectVideoMetadata(
                    duration: duration.isFinite ? max(duration, 0) : 0,
                    posterJPEG: jpeg
                ),
                pixelWidth: result.image.width,
                pixelHeight: result.image.height
            )
        } catch {
            return nil
        }
    }
}
