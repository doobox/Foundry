import Foundation

nonisolated struct PageColourAdjustment: Codable, Equatable, Sendable {
    var variant: String = "normal"
    var opacity: Double = 100
}
