import Foundation

nonisolated struct GoogleFontFace: Codable, Equatable, Hashable, Identifiable, Sendable {
    var italic: Bool
    var minimum: Int
    var maximum: Int
    var id: String { "\(italic)-\(minimum)-\(maximum)" }
    var isVariable: Bool { minimum != maximum }
    var title: String { "\(minimum)\(isVariable ? "–\(maximum)" : "")\(italic ? " Italic" : "")" }
}

nonisolated struct GoogleFontConfiguration: Codable, Equatable, Sendable {
    var available: [GoogleFontFace]
    var included: [GoogleFontFace]

    var validIncluded: [GoogleFontFace] {
        Array(Set(included.filter { face in
            face.minimum >= 1 && face.maximum <= 1000 && face.minimum <= face.maximum &&
            available.contains { $0.italic == face.italic && $0.minimum <= face.minimum && $0.maximum >= face.maximum }
        })).sorted { ($0.italic ? 1 : 0, $0.minimum, $0.maximum) < ($1.italic ? 1 : 0, $1.minimum, $1.maximum) }
    }

    func stylesheetURL(family: String) -> URL? {
        let faces = validIncluded
        guard !faces.isEmpty else { return nil }
        let tuples = faces.map { "\($0.italic ? 1 : 0),\($0.minimum)\($0.isVariable ? "..\($0.maximum)" : "")" }.joined(separator: ";")
        var components = URLComponents(string: "https://fonts.googleapis.com/css2")!
        components.queryItems = [URLQueryItem(name: "family", value: "\(family):ital,wght@\(tuples)"), URLQueryItem(name: "display", value: "swap")]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}

extension ThemeFontDefinition {
    mutating func applyGoogleConfiguration(_ configuration: GoogleFontConfiguration) {
        guard let url = configuration.stylesheetURL(family: family) else { return }
        googleConfiguration = configuration
        source = .remote(stylesheetURL: url)
        fallbacks = []
        weights = Array(Set(configuration.validIncluded.flatMap { [$0.minimum, $0.maximum] })).sorted()
        styles = configuration.validIncluded.contains(where: \.italic)
            ? (configuration.validIncluded.contains { !$0.italic } ? [.normal, .italic] : [.italic]) : [.normal]
    }
}
