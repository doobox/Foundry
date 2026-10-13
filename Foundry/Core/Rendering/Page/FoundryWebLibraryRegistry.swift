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

nonisolated struct FoundryWebScript: Equatable, Sendable {
    let path: String
    let isModule: Bool

    init(path: String, isModule: Bool = false) {
        self.path = path
        self.isModule = isModule
    }

    var htmlTag: String {
        "<script\(isModule ? " type=\"module\"" : "") src=\"\(path)\"></script>"
    }
}

nonisolated enum FoundryWebLibraryRegistry {
    enum ScriptPlacement {
        case beforePage
        case afterPage
    }

    static let iconsIdentifier = "bootstrapIcons"
    static let iconsMajorVersion = 1
    static let nativeIconFontName = "bootstrap-icons"
    static let bootstrapSourceCSS = resourceString(at: "bootstrap-6.0.0-alpha.1.min.css") ?? ""

    static let alpineRequirement = PartPackageLibraryRequirement(identifier: "alpine", majorVersion: 3)
    static let bootstrapRequirement = PartPackageLibraryRequirement(identifier: "bootstrap", majorVersion: 6)
    static let gsapRequirement = PartPackageLibraryRequirement(identifier: "gsap", majorVersion: 3)
    static let glightboxRequirement = PartPackageLibraryRequirement(identifier: "glightbox", majorVersion: 3)
    static let gsapScrollTriggerRequirement = PartPackageLibraryRequirement(
        identifier: "gsapScrollTrigger",
        majorVersion: 3
    )

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
        [alpineRequirement, gsapRequirement, glightboxRequirement, gsapScrollTriggerRequirement]
            .contains(requirement)
    }

    static func uniqueRequirements(
        in packages: [LoadedPartPackage]
    ) -> [PartPackageLibraryRequirement] {
        var seen: Set<PartPackageLibraryRequirement> = [bootstrapRequirement, iconRequirement]
        let requested = packages.flatMap { package in
            var requirements = package.manifest.libraries
            if package.manifest.controlGroups.contains(where: { $0.type == .reveal }) {
                requirements.append(gsapScrollTriggerRequirement)
            }
            return requirements
        }
        var resolved: [PartPackageLibraryRequirement] = [bootstrapRequirement, iconRequirement]
        for requirement in requested {
            if requirement == gsapScrollTriggerRequirement,
               seen.insert(gsapRequirement).inserted {
                resolved.append(gsapRequirement)
            }
            if seen.insert(requirement).inserted {
                resolved.append(requirement)
            }
        }
        return resolved
    }

    static func canvasCSS(for packages: [LoadedPartPackage]) -> String {
        let libraryCSS = uniqueRequirements(in: packages).compactMap { requirement in
            if requirement == iconRequirement,
               let css = resourceString(at: "bootstrap-icons.css"),
               let font = resourceData(at: "bootstrap-icons.woff2") {
                let dataURL = "data:font/woff2;base64,\(font.base64EncodedString())"
                return rewrittenIconCSS(css, fontURL: dataURL)
            }
            guard requirement == bootstrapRequirement,
                  let resource = stylesheetResource(for: requirement) else { return nil }
            return resourceString(at: resource)
        }.joined(separator: "\n")
        return libraryCSS + "\n" + sharedUtilityCSS
    }

    static let sharedUtilityPath = "files/libraries/foundry/foundry-utilities.css"
    private static let sharedUtilityCSS = BootstrapUtilityExtensionsCSS.sharedCSS
        + BootstrapEditorCSS.sharedCSS + BootstrapColorCSS.sharedCSS
    static let markdownCodeStylesheetPath = "files/libraries/foundry/foundry-markdown-code.css"

    static let markdownCodeScriptPath = "files/libraries/foundry/foundry-markdown-code.js"

    static let markdownCodeCSS = resourceString(at: "FOUNDRY-MARKDOWN-CODE.css") ?? ""

    private static let markdownCodeFiles: [SiteExportFile] = {
        [
            ("FOUNDRY-MARKDOWN-CODE.css", markdownCodeStylesheetPath),
            ("FOUNDRY-MARKDOWN-CODE.js", markdownCodeScriptPath)
        ].compactMap { source, destination in
            guard let data = resourceData(at: source) else { return nil }
            return SiteExportFile(path: destination, data: data)
        }
    }()

    static func markdownCodeExportFiles() -> [SiteExportFile] {
        markdownCodeFiles
    }
    static func themeOverridesCSS(for packages: [LoadedPartPackage]) -> String {
        uniqueRequirements(in: packages).contains(glightboxRequirement) ? glightboxThemeCSS : ""
    }

    static func exportStylesheets(for packages: [LoadedPartPackage], prefix: String) -> [String] {
        uniqueRequirements(in: packages).compactMap { requirement in
            guard let resource = stylesheetResource(for: requirement) else { return nil }
            return "\(prefix)/\(requirement.identifier)/\(resource)"
        } + ["\(prefix)/foundry/foundry-utilities.css"]
    }

    static func exportFiles(for packages: [LoadedPartPackage]) -> [SiteExportFile] {
        let requirements = uniqueRequirements(in: packages)
        var files: [SiteExportFile] = []
        files.append(contentsOf: requirements.compactMap { libraryStylesheets[$0] })
        files.append(SiteExportFile(path: sharedUtilityPath, contents: sharedUtilityCSS))
        if requirements.contains(iconRequirement),
           let font = resourceData(at: "bootstrap-icons.woff2") {
            files.append(SiteExportFile(
                path: "files/libraries/bootstrapIcons/bootstrap-icons.woff2",
                data: font
            ))
        }
        for requirement in requirements {
            guard let resource = scriptResource(for: requirement),
                  let data = resourceData(at: resource) else { continue }
            // Keep the bundled original intact, but don't advertise a map
            // that preview and published sites deliberately do not ship.
            let output = requirement == bootstrapRequirement
                ? Data(String(decoding: data, as: UTF8.self)
                    .replacingOccurrences(of: "//# sourceMappingURL=bootstrap.bundle.min.js.map", with: "").utf8)
                : data
            files.append(SiteExportFile(
                path: "files/libraries/\(requirement.identifier)/\(resource)",
                data: output
            ))
        }
        return files
    }

    static let bootstrapStylesheetPath = "files/libraries/bootstrap/bootstrap-6.0.0-alpha.1.min.css"

    // Immutable vendor CSS is prepared once, independently of site/theme edits.
    private static let libraryStylesheets: [PartPackageLibraryRequirement: SiteExportFile] = {
        Dictionary(uniqueKeysWithValues: [bootstrapRequirement, iconRequirement, glightboxRequirement].compactMap { requirement in
            guard let resource = stylesheetResource(for: requirement),
                  var css = resourceString(at: resource) else { return nil }
            if requirement == bootstrapRequirement {
                css = css.replacingOccurrences(of: "/*# sourceMappingURL=bootstrap.min.css.map */", with: "")
            } else if requirement == iconRequirement {
                css = rewrittenIconCSS(css, fontURL: "./bootstrap-icons.woff2")
            }
            return (requirement, SiteExportFile(
                path: "files/libraries/\(requirement.identifier)/\(resource)", contents: css
            ))
        })
    }()

    static func exportScripts(
        for packages: [LoadedPartPackage],
        prefix: String,
        placement: ScriptPlacement
    ) -> [FoundryWebScript] {
        uniqueRequirements(in: packages).compactMap { requirement in
            guard scriptPlacement(for: requirement) == placement,
                  let resource = scriptResource(for: requirement) else { return nil }
            return FoundryWebScript(
                path: "\(prefix)/\(requirement.identifier)/\(resource)",
                isModule: requirement == bootstrapRequirement
            )
        }
    }

    private static func scriptResource(for requirement: PartPackageLibraryRequirement) -> String? {
        switch requirement {
        case alpineRequirement: "alpine.min.js"
        case bootstrapRequirement: "bootstrap-6.0.0-alpha.1.bundle.min.js"
        case gsapRequirement: "gsap.min.js"
        case glightboxRequirement: "glightbox.min.js"
        case gsapScrollTriggerRequirement: "ScrollTrigger.min.js"
        default: nil
        }
    }

    private static func stylesheetResource(for requirement: PartPackageLibraryRequirement) -> String? {
        switch requirement {
        case bootstrapRequirement: "bootstrap-6.0.0-alpha.1.min.css"
        case iconRequirement: "bootstrap-icons.css"
        case glightboxRequirement: "glightbox.min.css"
        default: nil
        }
    }

    private static let glightboxThemeCSS = """
    .glightbox-clean .gslide-desc { color: #3f3f46; }
    """

    private static func scriptPlacement(for requirement: PartPackageLibraryRequirement) -> ScriptPlacement? {
        requirement == alpineRequirement ? .afterPage : scriptResource(for: requirement).map { _ in .beforePage }
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

    static func resourceData(at path: String) -> Data? {
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
