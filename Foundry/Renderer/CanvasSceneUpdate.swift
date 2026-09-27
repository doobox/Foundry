import Foundation

nonisolated struct CanvasSceneUpdate: Equatable, Sendable {
    let html: [String: String]
    let styles: [String: String]
    let removed: [String]
    let roots: [String]?
    var styleOrder: [String] = []
}
