import Foundation

nonisolated struct ComponentLink: Codable, Equatable, Sendable {
    enum Destination: Codable, Equatable, Sendable {
        case none
        case url(String)
        case plainText(String)
        case page(UUID)
        case resource(UUID)
    }

    var destination: Destination = .none
    var anchor = ""
    var opensInNewWindow = false
    var attributes: [Attribute] = []

    struct Attribute: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        var name: String
        var value: String

        init(id: UUID = UUID(), name: String = "", value: String = "") {
            self.id = id
            self.name = name
            self.value = value
        }
    }
}
