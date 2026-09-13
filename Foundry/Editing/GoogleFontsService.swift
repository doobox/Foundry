import Foundation

nonisolated struct GoogleFontFamily: Identifiable, Sendable {
    let family: String
    let category: String
    let styleCount: Int
    var faces: [GoogleFontFace] = []

    var id: String { family }
}

nonisolated enum GoogleFontCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case sansSerif = "Sans Serif"
    case serif = "Serif"
    case display = "Display"
    case handwriting = "Handwriting"
    case monospace = "Monospace"

    var id: String { rawValue }
    var title: String { self == .all ? "All fonts" : rawValue }

    func includes(_ value: String) -> Bool {
        self == .all || value.caseInsensitiveCompare(rawValue) == .orderedSame
    }
}

actor GoogleFontsService {
    static let shared = GoogleFontsService()

    static let fallback = [
        GoogleFontFamily(family: "ABeeZee", category: "Sans Serif", styleCount: 2,
                         faces: [.init(italic: false, minimum: 400, maximum: 400), .init(italic: true, minimum: 400, maximum: 400)]),
        GoogleFontFamily(family: "ADLaM Display", category: "Display", styleCount: 1),
        GoogleFontFamily(family: "AR One Sans", category: "Sans Serif", styleCount: 4),
        GoogleFontFamily(family: "Abel", category: "Sans Serif", styleCount: 1),
        GoogleFontFamily(family: "Abhaya Libre", category: "Serif", styleCount: 5)
    ]

    private var cachedFamilies: [GoogleFontFamily]?

    func families() async throws -> [GoogleFontFamily] {
        if let cachedFamilies { return cachedFamilies }
        let url = URL(string: "https://fonts.google.com/metadata/fonts")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let families = try Self.decodeFamilies(from: data)
        guard !families.isEmpty else { throw URLError(.cannotParseResponse) }
        cachedFamilies = families
        return families
    }

    nonisolated static func decodeFamilies(from data: Data) throws -> [GoogleFontFamily] {
        let prefix = Data(")]}'".utf8)
        let jsonData = data.starts(with: prefix) ? data.dropFirst(prefix.count) : data[...]
        guard let root = try JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any],
              let entries = root["familyMetadataList"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return entries.compactMap { entry in
            guard let family = entry["family"] as? String else { return nil }
            let category = (entry["category"] as? String ?? "Sans Serif")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            let fonts = entry["fonts"] as? [String: Any] ?? [:]
            let axes = entry["axes"] as? [[String: Any]] ?? []
            let weightAxis = axes.first { $0["tag"] as? String == "wght" }
            let minimum = (weightAxis?["min"] as? NSNumber)?.doubleValue
            let maximum = (weightAxis?["max"] as? NSNumber)?.doubleValue
            let staticFaces = fonts.keys.compactMap { key -> GoogleFontFace? in
                let italic = key.hasSuffix("i")
                guard let weight = Int(italic ? String(key.dropLast()) : key), (1...1000).contains(weight) else { return nil }
                return GoogleFontFace(italic: italic, minimum: weight, maximum: weight)
            }
            let faces: [GoogleFontFace]
            if let minimum, let maximum, minimum.isFinite, maximum.isFinite,
               minimum >= 1, maximum <= 1000, minimum < maximum {
                faces = Set(staticFaces.map(\.italic)).map {
                    GoogleFontFace(italic: $0, minimum: Int(ceil(minimum)), maximum: Int(floor(maximum)))
                }
            } else { faces = staticFaces }
            return GoogleFontFamily(family: family, category: category, styleCount: fonts.count,
                                    faces: faces.sorted { ($0.italic ? 1 : 0, $0.minimum) < ($1.italic ? 1 : 0, $1.minimum) })
        }
        .sorted { $0.family.localizedStandardCompare($1.family) == .orderedAscending }
    }
}
