import Foundation
import CoreText

nonisolated struct FoundryWebIcon: Identifiable, Hashable, Sendable {
    let name: String
    let glyph: String

    var id: String { name }
    var cssClass: String { "bi-\(name)" }
    var displayName: String {
        name
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

nonisolated enum FoundryWebLibraryRegistry {
    static let iconsIdentifier = "bootstrapIcons"
    static let iconsMajorVersion = 1
    static let nativeIconFontName = "bootstrap-icons"

    static let iconRequirement = PartPackageLibraryRequirement(
        identifier: iconsIdentifier,
        majorVersion: iconsMajorVersion
    )

    static let icons: [FoundryWebIcon] = {
        guard let css = resourceString(at: "bootstrap-icons.css"),
              let expression = try? NSRegularExpression(
                pattern: #"(?m)^\.bi-([a-z0-9-]+)::before\s*\{\s*content:\s*"\\([0-9a-fA-F]+)";\s*\}"#
              ) else { return [] }

        let range = NSRange(css.startIndex..<css.endIndex, in: css)
        return expression.matches(in: css, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: css),
                  let codePointRange = Range(match.range(at: 2), in: css),
                  let codePoint = UInt32(css[codePointRange], radix: 16),
                  let scalar = UnicodeScalar(codePoint) else { return nil }
            return FoundryWebIcon(name: String(css[nameRange]), glyph: String(Character(scalar)))
        }
    }()

    private static let iconsByName = Dictionary(uniqueKeysWithValues: icons.map { ($0.name, $0) })

    static func icon(named name: String) -> FoundryWebIcon? {
        iconsByName[normalizedIconName(name)]
    }

    static func normalizedIconName(_ name: String) -> String {
        name.hasPrefix("bi-") ? String(name.dropFirst(3)) : name
    }

    @discardableResult
    static func prepareNativeIconFont() -> Bool {
        nativeIconFontRegistration
    }

    private static let nativeIconFontRegistration: Bool = {
        guard let url = resourceURL(at: "bootstrap-icons.woff2") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            || CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) != nil
    }()

    static func supports(_ requirement: PartPackageLibraryRequirement) -> Bool {
        requirement == iconRequirement
    }

    static func uniqueRequirements(
        in packages: [LoadedPartPackage]
    ) -> [PartPackageLibraryRequirement] {
        var seen = Set<PartPackageLibraryRequirement>()
        return packages.flatMap { package in
            var requirements = package.manifest.libraries
            if package.manifest.properties.contains(where: { $0.control.type == .icon }) {
                requirements.append(iconRequirement)
            }
            return requirements
        }
        .filter { seen.insert($0).inserted }
    }

    static func canvasCSS(for packages: [LoadedPartPackage]) -> String {
        guard uniqueRequirements(in: packages).contains(iconRequirement),
              let css = resourceString(at: "bootstrap-icons.css"),
              let font = resourceData(at: "bootstrap-icons.woff2") else { return "" }
        let dataURL = "data:font/woff2;base64,\(font.base64EncodedString())"
        return rewrittenIconCSS(css, fontURL: dataURL)
    }

    static func exportCSS(for packages: [LoadedPartPackage]) -> String {
        guard uniqueRequirements(in: packages).contains(iconRequirement),
              let css = resourceString(at: "bootstrap-icons.css") else { return "" }
        return rewrittenIconCSS(
            css,
            fontURL: #"./libraries/bootstrapIcons/bootstrap-icons.woff2"#
        )
    }

    static func exportFiles(for packages: [LoadedPartPackage]) -> [SiteExportFile] {
        guard uniqueRequirements(in: packages).contains(iconRequirement),
              let font = resourceData(at: "bootstrap-icons.woff2") else { return [] }
        return [SiteExportFile(
            path: "files/libraries/bootstrapIcons/bootstrap-icons.woff2",
            data: font
        )]
    }

    private static func resourceString(at path: String) -> String? {
        resourceData(at: path).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func rewrittenIconCSS(_ css: String, fontURL: String) -> String {
        css
            .replacingOccurrences(
                of: #"\./fonts/bootstrap-icons\.woff2(?:\?[^\"]*)?"#,
                with: fontURL,
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #",\s*\nurl\(\"\./fonts/bootstrap-icons\.woff(?:\?[^\"]*)?\"\) format\(\"woff\"\)"#,
                with: "",
                options: .regularExpression
            )
    }

    private static func resourceData(at path: String) -> Data? {
        guard let url = resourceURL(at: path) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func resourceURL(at path: String) -> URL? {
        guard let bundleURL = Bundle.main.url(forResource: "BuiltInLibraries", withExtension: "bundle"),
              let bundle = Bundle(url: bundleURL),
              let resourcesURL = bundle.resourceURL else { return nil }
        return resourcesURL.appending(path: path)
    }
}
