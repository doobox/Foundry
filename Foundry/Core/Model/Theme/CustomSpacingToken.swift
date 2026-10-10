import Foundation

nonisolated struct CustomSpacingToken: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var value: Double
}
