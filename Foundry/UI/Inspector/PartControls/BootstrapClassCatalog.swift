import Foundation

/// Exact class tokens found in Foundry's bundled Bootstrap stylesheet.
struct BootstrapClassCatalog {
    private struct Resource: Decodable {
        let classes: [Entry]
    }

    private struct Entry: Decodable {
        let name: String
    }

    static let shared = BootstrapClassCatalog()
    let sortedNames: [String]

    private init() {
        let data = FoundryWebLibraryRegistry.resourceData(at: "bootstrap-class-catalog.json")
        let resource = data.flatMap { try? JSONDecoder().decode(Resource.self, from: $0) }
        let entries = resource?.classes ?? []
        sortedNames = entries.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
