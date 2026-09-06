import Foundation
import UniformTypeIdentifiers

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
    let instancePHP: String
    let pagePHP: String
    let editorCSS: String
    let updateSourceURL: URL?
    let imageMetadata: [String: ComponentImageMetadata]

    var lock: ComponentPackageLock {
        .init(identifier: manifest.identifier)
    }

    var iconURL: URL {
        resourceRootURL.appending(path: "icon.svg")
    }

    var isDevelopmentPack: Bool {
        rootURL.pathComponents.contains {
            ($0 as NSString).pathExtension.caseInsensitiveCompare("foundrydevpack") == .orderedSame
        }
    }

    var isBuiltIn: Bool {
        guard let bundleURL = Bundle.main.url(forResource: "BuiltInComponents", withExtension: "bundle") else {
            return false
        }
        let bundlePath = bundleURL.standardizedFileURL.path
        let packagePath = rootURL.standardizedFileURL.path
        return packagePath == bundlePath || packagePath.hasPrefix(bundlePath + "/")
    }

    var developmentPackRootURL: URL? {
        var candidate = rootURL.standardizedFileURL
        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("foundrydevpack") == .orderedSame {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    var resourceRootURL: URL {
        rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
    }

    var repeatMaximums: [String: Int] {
        Dictionary(uniqueKeysWithValues: manifest.properties.compactMap { property in
            guard property.control.type == .number || property.control.type == .slider,
                  let maximum = property.control.maximum,
                  maximum.isFinite,
                  maximum >= 0,
                  maximum <= Double(ComponentTemplateRepeater.maximumIterationCount) else { return nil }
            return (property.id, Int(maximum.rounded(.down)))
        })
    }

    func declaresJavaScript(in scopes: ComponentPackageTemplateFile.Scope...) -> Bool {
        manifest.render.files.contains { file in
            scopes.contains { $0.rawValue == file.scope.rawValue }
                && file.path.lowercased().hasSuffix(".js")
        }
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

nonisolated struct ComponentPackageLoadResult: Sendable {
    let package: LoadedComponentPackage
    let diagnostics: [ComponentPackageDiagnostic]
    let timings: ComponentPackageLoadTimings
}

nonisolated struct ComponentPackageLoadTimings: Sendable {
    var manifestRead: Duration = .zero
    var schemaValidation: Duration = .zero
    var manifestDecoding: Duration = .zero
    var semanticValidation: Duration = .zero
    var resourceLoading: Duration = .zero

    var validation: Duration { schemaValidation + semanticValidation }

    var total: Duration {
        manifestRead + schemaValidation + manifestDecoding + semanticValidation + resourceLoading
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        .init(
            manifestRead: lhs.manifestRead + rhs.manifestRead,
            schemaValidation: lhs.schemaValidation + rhs.schemaValidation,
            manifestDecoding: lhs.manifestDecoding + rhs.manifestDecoding,
            semanticValidation: lhs.semanticValidation + rhs.semanticValidation,
            resourceLoading: lhs.resourceLoading + rhs.resourceLoading
        )
    }
}

nonisolated enum ComponentPackageLoader {
    static func load(from rootURL: URL) throws -> LoadedComponentPackage {
        try loadWithDiagnostics(from: rootURL).package
    }

    static func loadWithDiagnostics(from rootURL: URL) throws -> ComponentPackageLoadResult {
        try loadWithDiagnostics(from: rootURL, validates: true)
    }

    static func loadWithDiagnostics(
        from rootURL: URL,
        validates: Bool
    ) throws -> ComponentPackageLoadResult {
        let clock = ContinuousClock()
        var timings = ComponentPackageLoadTimings()
        let manifestURL = rootURL.appending(path: "Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ComponentPackageLoadingError.missingManifest
        }

        let manifest: ComponentPackageManifest
        let schemaDiagnostics: [ComponentPackageDiagnostic]
        do {
            let readStart = clock.now
            let data = try Data(contentsOf: manifestURL)
            timings.manifestRead = readStart.duration(to: clock.now)
            if validates {
                let schemaStart = clock.now
                schemaDiagnostics = try ComponentPackageManifestSchema.diagnostics(for: data)
                timings.schemaValidation = schemaStart.duration(to: clock.now)
                guard !schemaDiagnostics.contains(where: { $0.severity == .error }) else {
                    throw ComponentPackageLoadingError.invalid(schemaDiagnostics)
                }
            } else {
                schemaDiagnostics = []
            }
            let decodingStart = clock.now
            manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: data)
            timings.manifestDecoding = decodingStart.duration(to: clock.now)
        } catch let error as ComponentPackageLoadingError {
            throw error
        } catch {
            throw ComponentPackageLoadingError.unreadableManifest(error)
        }

        let resourceRootURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let semanticDiagnostics: [ComponentPackageDiagnostic]
        if validates {
            let validationStart = clock.now
            semanticDiagnostics = ComponentPackageValidator.validate(manifest, rootURL: resourceRootURL)
            timings.semanticValidation = validationStart.duration(to: clock.now)
        } else {
            semanticDiagnostics = []
        }
        let diagnostics = schemaDiagnostics + semanticDiagnostics
        let errors = diagnostics.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw ComponentPackageLoadingError.invalid(diagnostics)
        }
        let resourceLoadingStart = clock.now
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
                        ? "document.getElementById('{{ id }}')"
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
        let package = LoadedComponentPackage(
                manifest: manifest,
                rootURL: rootURL,
                htmlTemplate: try read(manifest.render.html, from: resourceRootURL),
                css: instanceCSS.joined(separator: "\n"),
                pageCSS: pageCSS.joined(separator: "\n"),
                siteCSS: siteCSS.joined(separator: "\n"),
                placedHTML: placedHTML,
                instanceJavaScript: try javascript(scope: .instance),
                pageJavaScript: try javascript(scope: .page),
                instancePHP: try php(scope: .instance),
                pagePHP: try php(scope: .page),
                editorCSS: try readIfPresent(manifest.render.editorCSS, from: resourceRootURL),
                updateSourceURL: updateSourceURL(containing: rootURL),
                imageMetadata: imageMetadata(for: manifest, resourceRootURL: resourceRootURL)
            )
        timings.resourceLoading = resourceLoadingStart.duration(to: clock.now)
        return ComponentPackageLoadResult(
            package: package,
            diagnostics: diagnostics,
            timings: timings
        )
    }

    private static func imageMetadata(
        for manifest: ComponentPackageManifest,
        resourceRootURL: URL
    ) -> [String: ComponentImageMetadata] {
        manifest.properties.reduce(into: [:]) { result, property in
            guard property.control.type == .image else { return }
            let path = property.defaultValue.stringValue
            guard !path.isEmpty else { return }
            let url = resourceRootURL.appending(path: path)
            guard let data = try? Data(contentsOf: url) else { return }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            result[path] = ComponentImageMetadata.inspect(
                data: data,
                filename: url.lastPathComponent,
                mimeType: mimeType
            )
        }
    }

    private static func readIfPresent(_ path: String?, from rootURL: URL) throws -> String {
        guard let path else { return "" }
        return try read(path, from: rootURL)
    }

    private static func updateSourceURL(containing componentURL: URL) -> URL? {
        guard componentURL.pathComponents.allSatisfy({
            ($0 as NSString).pathExtension.caseInsensitiveCompare("foundrydevpack") != .orderedSame
        }) else { return nil }
        var candidate = componentURL.standardizedFileURL
        var result: URL?
        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("foundrypack") == .orderedSame,
               let pack = try? FoundryPackLoader.load(from: candidate),
               pack.metadata.updates != nil {
                result = candidate
            }
            candidate.deleteLastPathComponent()
        }
        return result
    }

    private static func read(_ path: String, from rootURL: URL) throws -> String {
        do {
            return try String(contentsOf: rootURL.appending(path: path), encoding: .utf8)
        } catch {
            throw ComponentPackageLoadingError.unreadableResource(path, error)
        }
    }
}
