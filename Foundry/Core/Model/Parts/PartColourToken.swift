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
        ("Shadow", ["shadow-color"])
    ]
    static var all: [Self] { groups.flatMap { $0.1 }.map { Self(id: $0) } }
    static let sectionIDs = ["blackWhite", "surfaces", "foregrounds", "borders", "links", "shadow"]
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
        if let native = all.first(where: { $0.selection == selection }) { return native }
        guard selection.range(of: #"^token:custom-custom-[a-z0-9-]+-(bg-(body|[1-4])|fg-(body|[1-4])|border-(body|subtle|muted|emphasized)|link-(color|hover-color))$"#, options: .regularExpression) != nil else { return nil }
        return Self(id: String(selection.dropFirst(6)))
    }

    static func groups(for sections: [String], palettes: [ColourPalette], linksOnly: Bool = false) -> [(String, [String])] {
        groups(for: sections).map { title, native in
            let section = sectionIDs[groups.firstIndex { $0.0 == title }!]
            let custom = palettes.filter { $0.origin == .custom && $0.colourKind.section == section }
                .flatMap { linksOnly ? Array($0.colourTokens.prefix(1)) : $0.colourTokens }
            return (title, (linksOnly ? Array(native.prefix(1)) : native) + custom)
        }
    }

    static func label(_ token: String, palettes: [ColourPalette], linksOnly: Bool = false) -> String {
        guard let palette = palettes.first(where: { $0.origin == .custom && $0.colourTokens.contains(token) }) else {
            return linksOnly && token == "link-color" ? "Default links" : token
        }
        if linksOnly { return palette.name }
        let suffix = String(token.dropFirst(palette.customTokenPrefix.count))
        return palette.name + " · " + (suffix == "link-color" ? "Link" : suffix == "link-hover-color" ? "Link hover" : suffix)
    }
}
