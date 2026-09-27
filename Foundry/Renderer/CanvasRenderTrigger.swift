import Foundation

/// Acknowledgment wakes the latest requested render, coalescing edits while a
/// previous transaction is in flight instead of escalating them to full pages.
struct CanvasRenderTrigger: Hashable {
    let request: CanvasRenderRequestID?
    let acknowledgedRevision: UInt64
}
