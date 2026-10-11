import Foundation

/// All mutable inputs to a document's browser preview. Never persisted: a
/// newly opened document starts with a fresh preview server and snapshot.
nonisolated struct PreviewBuildIdentity: Equatable, Sendable {
    let siteID: UUID
    let documentRevision: UInt64
    let packageRevision: Int
    var assetRevision: UInt64 = 0
}
