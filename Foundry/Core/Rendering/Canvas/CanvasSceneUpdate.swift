import Foundation

nonisolated struct CanvasSceneUpdate: Equatable, Sendable {
    let html: [String: String]
    let styles: [String: String]
    let removed: [String]
    let roots: [String]?
    /// Repositioning instructions for instance stylesheets, as `[id, anchorID]`
    /// pairs applied in this order. An empty anchor means the shared-styles
    /// boundary. Only stylesheets whose position actually changed appear, so
    /// adding one instance costs one instruction on a page of any size.
    var styleMoves: [[String]] = []
    /// Child placements per parent, as `[childID, "before"|"after", siblingID]`
    /// triples applied in this order. A parent that only gained, lost or
    /// reordered children is re-seated through these instead of republishing
    /// its markup — republishing would rebuild the parent element and drag
    /// every sibling in the page through the DOM with it.
    var childMoves: [String: [[String]]] = [:]
}
