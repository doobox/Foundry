import Foundation

/// Resolved inputs of one part. Children contain identity/placement only;
/// changing a grandchild cannot invalidate an ancestor's rendering.
nonisolated struct CanvasSceneInput: Equatable, Sendable {
    let node: PartNode
    let globalID: UUID?
    let parentID: UUID?
    let slot: PartPackageSlot?
    let dropZone: String?
}
