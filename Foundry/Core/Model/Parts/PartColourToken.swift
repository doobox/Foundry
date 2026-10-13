import Foundation

/// Single theme paint tokens, distinct from complete component themes.
nonisolated struct PartColourToken: Identifiable {
    let id: String
    var selection: String { "token:" + id }
    var expression: String { "var(--bs-\(id))" }

    static let groups: [(String, [String])] = [
        ("Black & White", ["black", "white"]),
        ("Surfaces", BootstrapColourCatalogue.tokens(for: "background")),
        ("Foregrounds", BootstrapColourCatalogue.tokens(for: "foreground") + ["fg-bg"]),
        ("Borders", BootstrapColourCatalogue.tokens(for: "border")),
        ("Links", ["link-color", "link-hover-color"]),
        ("Shadow", ["shadow-color"]),
        ("Palettes", BootstrapColourCatalogue.hues.flatMap { hue in
            ColourShade.allCases.map { hue + "-" + $0.bootstrapLabel }
        })
    ]
    static let all: [Self] = groups.flatMap { $0.1 }.map { Self(id: $0) }
    private static let nativeSelections = Dictionary(uniqueKeysWithValues: all.map { ($0.selection, $0) })
    static let sectionIDs = ["blackWhite", "surfaces", "foregrounds", "borders", "links", "shadow", "palettes"]
    static let pickerSectionIDs = ["themes"] + sectionIDs
    static func groups(for sections: [String]) -> [(String, [String])] {
        var seen = Set<String>()
        return sections.compactMap { section in
            guard seen.insert(section).inserted,
                  let index = sectionIDs.firstIndex(of: section) else { return nil }
            return groups[index]
        }
    }
    static func parse(_ selection: String) -> Self? {
        if let native = nativeSelections[selection] { return native }
        guard selection.range(of: #"^token:custom-(?:[0-9a-f]{2})+-(bg-(body|[1-4])|fg-(body|[1-4])|border-(body|subtle|muted|emphasized)|link-(color|hover-color))$"#, options: .regularExpression) != nil else { return nil }
        return Self(id: String(selection.dropFirst(6)))
    }

    static func groups(for sections: [String], palettes: [ColourPalette], linksOnly: Bool = false) -> [(String, [String])] {
        groups(for: sections).map { title, native in
            let normalLinksOnly = linksOnly && title == "Links"
            let section = sectionIDs[groups.firstIndex { $0.0 == title }!]
            let custom = palettes.filter { $0.origin == .custom && $0.colourKind.section == section }
                .flatMap { normalLinksOnly ? Array($0.colourTokens.prefix(1)) : $0.colourTokens }
            return (title, (normalLinksOnly ? Array(native.prefix(1)) : native) + custom)
        }
    }

    static func label(_ token: String, palettes: [ColourPalette], linksOnly: Bool = false) -> String {
        if let hue = BootstrapColourCatalogue.hues.first(where: { token.hasPrefix($0 + "-") }),
           nativeSelections["token:" + token] != nil {
            return hue.capitalized + " " + token.dropFirst(hue.count + 1)
        }
        guard let palette = palettes.first(where: { $0.origin == .custom && $0.colourTokens.contains(token) }) else {
            return linksOnly && token == "link-color" ? "Default links" : token
        }
        let source = palette.colourKind.sourceTokens.first { palette.colourToken($0) == token }
        return source.flatMap { palette.publicUtilityClass(for: $0) } ?? palette.name
    }
}
