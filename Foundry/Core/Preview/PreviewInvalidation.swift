import Foundation

/// Revision stamps, not work queued during editing. A successful preview's
/// revision is its own checkpoint; publishing never consumes these stamps.
nonisolated struct PreviewInvalidation: Sendable {
    private var sharedRevision: UInt64 = 0
    private var pageRevisions: [UUID: UInt64] = [:]

    mutating func record(_ impact: ProjectMutationImpact, in site: Site, revision: UInt64) {
        guard let pages = impact.affectedPageIDs(in: site) else {
            sharedRevision = revision
            pageRevisions.removeAll(keepingCapacity: true)
            return
        }
        for id in pages { pageRevisions[id] = revision }
    }

    /// nil requests a full build. Later edits remain newer than the completed
    /// build's checkpoint, including when that build failed or was cancelled.
    func dirtyPages(since revision: UInt64) -> Set<UUID>? {
        guard sharedRevision <= revision else { return nil }
        return Set(pageRevisions.compactMap { $0.value > revision ? $0.key : nil })
    }
}
