import Foundation

nonisolated struct LoadedComponentPackage: Sendable {
    let manifest: ComponentPackageManifest
    let rootURL: URL
    let htmlTemplate: String
    let css: String
    let pageCSS: String
    let siteCSS: String
    let placedHTML: [LoadedPlacedHTMLTemplate]
    let instanceJavaScript: String
    let pageJavaScript: String
    let siteJavaScript: String
    let instancePHP: String
    let pagePHP: String
    let sitePHP: String
    let editorCSS: String

    var lock: ComponentPackageLock {
        .init(identifier: manifest.identifier)
    }

    var iconURL: URL {
        resourceRootURL.appending(path: "icon.svg")
    }

    var resourceRootURL: URL {
        rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
    }
}

nonisolated struct LoadedPlacedHTMLTemplate: Sendable {
    let placement: ComponentPackageTemplateFile.Placement
    let contents: String
}

nonisolated enum ComponentPackageLoadingError: Error, LocalizedError {
    case missingManifest
    case unreadableManifest(Error)
    case invalid([ComponentPackageDiagnostic])
    case unreadableResource(String, Error)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            "The component bundle does not contain Contents/Info.plist."
        case .unreadableManifest(let error):
            "Info.plist could not be decoded: \(error.localizedDescription)"
        case .invalid(let diagnostics):
            diagnostics.map { "\($0.location): \($0.message)" }.joined(separator: "\n")
        case .unreadableResource(let path, let error):
            "\(path) could not be read: \(error.localizedDescription)"
        }
    }
}

nonisolated enum ComponentPackageLoader {
    static func load(from rootURL: URL) throws -> LoadedComponentPackage {
        let manifestURL = rootURL.appending(path: "Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ComponentPackageLoadingError.missingManifest
        }

        let manifest: ComponentPackageManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: data)
        } catch {
            throw ComponentPackageLoadingError.unreadableManifest(error)
        }

        guard manifest.type == .component else {
            throw ComponentPackageLoadingError.unreadableManifest(CocoaError(.fileReadCorruptFile))
        }

        let resourceRootURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let diagnostics = ComponentPackageValidator.validate(manifest, rootURL: resourceRootURL)
        let errors = diagnostics.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw ComponentPackageLoadingError.invalid(diagnostics)
        }
        let instanceCSS = try manifest.render.files
            .filter { $0.scope == .instance && $0.path.lowercased().hasSuffix(".css") }
            .map { try read($0.path, from: resourceRootURL) }
        let pageCSS = try manifest.render.files
            .filter { $0.scope == .page && $0.path.lowercased().hasSuffix(".css") }
            .map { try read($0.path, from: resourceRootURL) }
        let siteCSS = try manifest.render.files
            .filter { $0.scope == .site && $0.path.lowercased().hasSuffix(".css") }
            .map { try read($0.path, from: resourceRootURL) }
        let placedHTML = try manifest.render.files.compactMap { file -> LoadedPlacedHTMLTemplate? in
            guard file.path.lowercased().hasSuffix(".html"), let placement = file.placement else { return nil }
            return LoadedPlacedHTMLTemplate(placement: placement, contents: try read(file.path, from: resourceRootURL))
        }
        func javascript(scope: ComponentPackageTemplateFile.Scope) throws -> String {
            try manifest.render.files
                .filter { $0.scope == scope && $0.path.lowercased().hasSuffix(".js") }
                .map { file in
                    let source = try read(file.path, from: resourceRootURL)
                    guard file.closure else { return source }
                    let parameter = scope == .instance ? "component" : "page"
                    let argument = scope == .instance
                        ? "document.getElementById(\"{{ id }}\")"
                        : "document"
                    return """
                    (function (\(parameter)) {
                        "use strict";
                    \(source)
                    })(\(argument));
                    """
                }
                .joined(separator: "\n")
        }
        func php(scope: ComponentPackageTemplateFile.Scope) throws -> String {
            try manifest.render.files
                .filter { $0.scope == scope && $0.path.lowercased().hasSuffix(".php") }
                .map { try read($0.path, from: resourceRootURL) }
                .joined(separator: "\n")
        }
        return LoadedComponentPackage(
            manifest: manifest,
            rootURL: rootURL,
            htmlTemplate: try read(manifest.render.html, from: resourceRootURL),
            css: instanceCSS.joined(separator: "\n"),
            pageCSS: pageCSS.joined(separator: "\n"),
            siteCSS: siteCSS.joined(separator: "\n"),
            placedHTML: placedHTML,
            instanceJavaScript: try javascript(scope: .instance),
            pageJavaScript: try javascript(scope: .page),
            siteJavaScript: try javascript(scope: .site),
            instancePHP: try php(scope: .instance),
            pagePHP: try php(scope: .page),
            sitePHP: try php(scope: .site),
            editorCSS: try readIfPresent(manifest.render.editorCSS, from: resourceRootURL),
        )
    }

    private static func readIfPresent(_ path: String?, from rootURL: URL) throws -> String {
        guard let path else { return "" }
        return try read(path, from: rootURL)
    }

    private static func read(_ path: String, from rootURL: URL) throws -> String {
        do {
            return try String(contentsOf: rootURL.appending(path: path), encoding: .utf8)
        } catch {
            throw ComponentPackageLoadingError.unreadableResource(path, error)
        }
    }
}
