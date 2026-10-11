import Foundation

/// PHP keeps a complete filesystem; static previews resolve pages on demand.
nonisolated enum PreviewOutput: Sendable {
    case disk(PreviewDiskSnapshot)
    case onDemand(OnDemandPreviewSession)
}
