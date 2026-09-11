import Foundation
import Synchronization
import UniformTypeIdentifiers

nonisolated struct ComponentPackagePayloadFailure: Error, Equatable, Sendable {
    let location: String
    let message: String
}

extension Notification.Name {
    nonisolated static let componentPackagePayloadDidFail = Notification.Name("componentPackagePayloadDidFail")
}

nonisolated struct LoadedComponentPackage: Sendable {
    static let dropZoneSlotPrefix = "__foundry_drop_zone:"

    let manifest: ComponentPackageManifest
    let rootURL: URL
    let updateSourceURL: URL?
    let preparedPrimitives: ComponentPreparedPrimitives
    private let payloadStorage: ComponentPackagePayloadStorage

    var htmlTemplate: String { payloadStorage.payload.htmlTemplate }
    var css: String { payloadStorage.payload.css }
    var pageCSS: String { payloadStorage.payload.pageCSS }
    var siteCSS: String { payloadStorage.payload.siteCSS }
    var placedHTML: [LoadedPlacedHTMLTemplate] { payloadStorage.payload.placedHTML }
    var instanceJavaScript: String { payloadStorage.payload.instanceJavaScript }
    var pageJavaScript: String { payloadStorage.payload.pageJavaScript }
    var instancePHP: String { payloadStorage.payload.instancePHP }
    var pagePHP: String { payloadStorage.payload.pagePHP }
    var editorCSS: String { payloadStorage.payload.editorCSS }
    var imageMetadata: [String: ComponentImageMetadata] { payloadStorage.payload.imageMetadata }
    var isPayloadLoaded: Bool { payloadStorage.isLoaded }
    var payloadFailure: ComponentPackagePayloadFailure? { payloadStorage.failure }
    var dropZoneNames: [String] { preparedPrimitives.dropZoneNames ?? [] }
    var hasDropZone: Bool { !dropZoneNames.isEmpty }

    func dropZoneSlotID(for name: String) -> String {
        Self.dropZoneSlotPrefix + name
    }

    func isDropZoneSlotID(_ id: String) -> Bool {
        dropZoneNames.contains { dropZoneSlotID(for: $0) == id }
    }

    static func dropZoneName(forSlotID id: String) -> String? {
        guard id.hasPrefix(dropZoneSlotPrefix) else { return nil }
        let name = String(id.dropFirst(dropZoneSlotPrefix.count))
        return name.isEmpty ? nil : name
    }

    func preparePayload() throws {
        try payloadStorage.prepare()
    }

    init(
        manifest: ComponentPackageManifest,
        rootURL: URL,
        htmlTemplate: String,
        css: String,
        pageCSS: String,
        siteCSS: String,
        placedHTML: [LoadedPlacedHTMLTemplate],
        instanceJavaScript: String,
        pageJavaScript: String,
        instancePHP: String,
        pagePHP: String,
        editorCSS: String,
        updateSourceURL: URL?,
        imageMetadata: [String: ComponentImageMetadata]
    ) {
        self.manifest = manifest
        self.rootURL = rootURL
        self.updateSourceURL = updateSourceURL
        preparedPrimitives = ComponentPreparedPrimitives(template: htmlTemplate, loopMaximums: Self.loopMaximums(for: manifest))
        payloadStorage = .init(payload: .init(
            htmlTemplate: htmlTemplate,
            css: css,
            pageCSS: pageCSS,
            siteCSS: siteCSS,
            placedHTML: placedHTML,
            instanceJavaScript: instanceJavaScript,
            pageJavaScript: pageJavaScript,
            instancePHP: instancePHP,
            pagePHP: pagePHP,
            editorCSS: editorCSS,
            imageMetadata: imageMetadata
        ))
    }

    init(
        manifest: ComponentPackageManifest,
        rootURL: URL,
        updateSourceURL: URL?,
        preparedPrimitives: ComponentPreparedPrimitives
    ) {
        self.manifest = manifest
        self.rootURL = rootURL
        self.updateSourceURL = updateSourceURL
        self.preparedPrimitives = preparedPrimitives
        payloadStorage = .init(manifest: manifest, rootURL: rootURL)
    }

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

    var loopMaximums: [String: Int] {
        Self.loopMaximums(for: manifest)
    }

    private static func loopMaximums(for manifest: ComponentPackageManifest) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: manifest.properties.compactMap { property in
            guard property.control.type == .number || property.control.type == .slider,
                  let maximum = property.control.maximum,
                  maximum.isFinite,
                  maximum >= 0,
                  maximum <= Double(ComponentTemplateLoop.maximumIterationCount) else { return nil }
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

nonisolated struct ComponentPreparedPrimitives: Codable, Equatable, Sendable {
    let text: [ComponentTextPrimitive]
    let html: [ComponentHTMLPrimitive]
    let images: [ComponentImagePrimitive]
    let dropZoneNames: [String]?

    init(
        text: [ComponentTextPrimitive],
        html: [ComponentHTMLPrimitive],
        images: [ComponentImagePrimitive],
        dropZoneNames: [String]? = nil
    ) {
        self.text = text
        self.html = html
        self.images = images
        self.dropZoneNames = dropZoneNames
    }

    init(template: String, loopMaximums: [String: Int]) {
        text = ComponentTemplateRenderer.textPrimitives(in: template, loopMaximums: loopMaximums)
        html = ComponentTemplateRenderer.htmlPrimitives(in: template, loopMaximums: loopMaximums)
        images = ComponentTemplateRenderer.imagePrimitives(in: template)
        dropZoneNames = ComponentTemplateRenderer.dropZoneNames(in: template)
    }
}

nonisolated fileprivate struct ComponentPackagePayload: Sendable {
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
    let imageMetadata: [String: ComponentImageMetadata]

    static let empty = ComponentPackagePayload(
        htmlTemplate: "", css: "", pageCSS: "", siteCSS: "", placedHTML: [],
        instanceJavaScript: "", pageJavaScript: "", instancePHP: "", pagePHP: "",
        editorCSS: "", imageMetadata: [:]
    )
}

nonisolated private final class ComponentPackagePayloadStorage: Sendable {
    private struct State: Sendable {
        var payload: ComponentPackagePayload?
        var failure: ComponentPackagePayloadFailure?
        var reportedFailure = false
    }

    private let manifest: ComponentPackageManifest?
    private let rootURL: URL?
    private let state: Mutex<State>

    init(payload: ComponentPackagePayload) {
        manifest = nil
        rootURL = nil
        state = Mutex(.init(payload: payload, failure: nil))
    }

    init(manifest: ComponentPackageManifest, rootURL: URL) {
        self.manifest = manifest
        self.rootURL = rootURL
        state = Mutex(.init(payload: nil, failure: nil))
    }

    var payload: ComponentPackagePayload {
        do {
            try prepare()
            return state.withLock { $0.payload ?? .empty }
        } catch {
            reportFailureIfNeeded()
            return .empty
        }
    }

    var isLoaded: Bool {
        state.withLock { $0.payload != nil }
    }

    var failure: ComponentPackagePayloadFailure? {
        state.withLock { $0.failure }
    }

    func prepare() throws {
        if let result: Result<ComponentPackagePayload, ComponentPackagePayloadFailure> = state.withLock({ state in
            if let payload = state.payload { return .success(payload) }
            if let failure = state.failure { return .failure(failure) }
            return nil
        }) {
            _ = try result.get()
            return
        }
        guard let manifest, let rootURL else { return }
        do {
            let payload = try ComponentPackageLoader.loadPayload(manifest: manifest, rootURL: rootURL)
            state.withLock {
                $0.payload = payload
                $0.failure = nil
                $0.reportedFailure = false
            }
        } catch {
            let failure = Self.failure(from: error)
            state.withLock { $0.failure = failure }
            reportFailureIfNeeded()
            throw failure
        }
    }

    private func reportFailureIfNeeded() {
        guard let rootURL else { return }
        let failure: ComponentPackagePayloadFailure? = state.withLock { state in
            guard !state.reportedFailure, let failure = state.failure else { return nil }
            state.reportedFailure = true
            return failure
        }
        guard let failure else { return }
        NotificationCenter.default.post(
            name: .componentPackagePayloadDidFail,
            object: nil,
            userInfo: ["url": rootURL, "failure": failure]
        )
    }

    private static func failure(from error: Error) -> ComponentPackagePayloadFailure {
        if case ComponentPackageLoadingError.unreadableResource(let path, let underlying) = error {
            return .init(location: "Contents/Resources/\(path)", message: underlying.localizedDescription)
        }
        return .init(location: "Contents/Resources", message: error.localizedDescription)
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

    static func loadForCatalog(
        from rootURL: URL,
        validates: Bool
    ) throws -> ComponentPackageLoadResult {
        if !validates, let cached = ComponentPackagePreparedIndex.entry(for: rootURL) {
            return .init(
                package: .init(
                    manifest: cached.manifest,
                    rootURL: rootURL,
                    updateSourceURL: updateSourceURL(containing: rootURL),
                    preparedPrimitives: cached.primitives
                ),
                diagnostics: [],
                timings: .init()
            )
        }

        let clock = ContinuousClock()
        var timings = ComponentPackageLoadTimings()
        let manifestURL = rootURL.appending(path: "Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ComponentPackageLoadingError.missingManifest
        }

        let data: Data
        let manifest: ComponentPackageManifest
        let schemaDiagnostics: [ComponentPackageDiagnostic]
        do {
            let readStart = clock.now
            data = try Data(contentsOf: manifestURL)
            timings.manifestRead = readStart.duration(to: clock.now)
            if validates {
                let validationStart = clock.now
                schemaDiagnostics = try ComponentPackageManifestSchema.diagnostics(for: data)
                timings.schemaValidation = validationStart.duration(to: clock.now)
                guard !schemaDiagnostics.contains(where: { $0.severity == .error }) else {
                    throw ComponentPackageLoadingError.invalid(schemaDiagnostics)
                }
            } else {
                schemaDiagnostics = []
            }
            let decodeStart = clock.now
            manifest = try PropertyListDecoder().decode(ComponentPackageManifest.self, from: data)
            timings.manifestDecoding = decodeStart.duration(to: clock.now)
        } catch let error as ComponentPackageLoadingError {
            throw error
        } catch {
            throw ComponentPackageLoadingError.unreadableManifest(error)
        }

        let resourceRootURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let validationFingerprint = validates ? ComponentPackageValidationCache.fingerprint(
            manifestData: data,
            manifest: manifest,
            rootURL: resourceRootURL
        ) : nil
        let semanticDiagnostics: [ComponentPackageDiagnostic]
        if let validationFingerprint,
           ComponentPackageValidationCache.contains(validationFingerprint, for: rootURL) {
            semanticDiagnostics = []
        } else if validates {
            let validationStart = clock.now
            semanticDiagnostics = ComponentPackageValidator.validate(manifest, rootURL: resourceRootURL)
            timings.semanticValidation = validationStart.duration(to: clock.now)
        } else {
            semanticDiagnostics = []
        }
        let diagnostics = schemaDiagnostics + semanticDiagnostics
        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            throw ComponentPackageLoadingError.invalid(diagnostics)
        }
        if diagnostics.isEmpty,
           let validationFingerprint,
           ComponentPackageValidationCache.fingerprint(
               manifestData: data,
               manifest: manifest,
               rootURL: resourceRootURL
           ) == validationFingerprint {
            ComponentPackageValidationCache.storeSuccessful(validationFingerprint, for: rootURL)
        }

        let preparationStart = clock.now
        let template = try read(manifest.render.html, from: resourceRootURL)
        let maximums = LoadedComponentPackage(
            manifest: manifest,
            rootURL: rootURL,
            updateSourceURL: nil,
            preparedPrimitives: .init(text: [], html: [], images: [])
        ).loopMaximums
        let primitives = ComponentPreparedPrimitives(template: template, loopMaximums: maximums)
        timings.resourceLoading = preparationStart.duration(to: clock.now)
        ComponentPackagePreparedIndex.store(manifest: manifest, primitives: primitives, rootURL: rootURL)
        return .init(
            package: .init(
                manifest: manifest,
                rootURL: rootURL,
                updateSourceURL: updateSourceURL(containing: rootURL),
                preparedPrimitives: primitives
            ),
            diagnostics: diagnostics,
            timings: timings
        )
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

        let data: Data
        let manifest: ComponentPackageManifest
        let schemaDiagnostics: [ComponentPackageDiagnostic]
        do {
            let readStart = clock.now
            data = try Data(contentsOf: manifestURL)
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
        let validationFingerprint = validates ? ComponentPackageValidationCache.fingerprint(
            manifestData: data,
            manifest: manifest,
            rootURL: resourceRootURL
        ) : nil
        let semanticDiagnostics: [ComponentPackageDiagnostic]
        if let validationFingerprint,
           ComponentPackageValidationCache.contains(validationFingerprint, for: rootURL) {
            semanticDiagnostics = []
        } else if validates {
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
        if diagnostics.isEmpty,
           let validationFingerprint,
           ComponentPackageValidationCache.fingerprint(
               manifestData: data,
               manifest: manifest,
               rootURL: resourceRootURL
           ) == validationFingerprint {
            ComponentPackageValidationCache.storeSuccessful(validationFingerprint, for: rootURL)
        }
        let resourceLoadingStart = clock.now
        let payload = try loadPayload(manifest: manifest, rootURL: rootURL)
        let package = LoadedComponentPackage(
            manifest: manifest,
            rootURL: rootURL,
            htmlTemplate: payload.htmlTemplate,
            css: payload.css,
            pageCSS: payload.pageCSS,
            siteCSS: payload.siteCSS,
            placedHTML: payload.placedHTML,
            instanceJavaScript: payload.instanceJavaScript,
            pageJavaScript: payload.pageJavaScript,
            instancePHP: payload.instancePHP,
            pagePHP: payload.pagePHP,
            editorCSS: payload.editorCSS,
            updateSourceURL: updateSourceURL(containing: rootURL),
            imageMetadata: payload.imageMetadata
        )
        timings.resourceLoading = resourceLoadingStart.duration(to: clock.now)
        return ComponentPackageLoadResult(
            package: package,
            diagnostics: diagnostics,
            timings: timings
        )
    }

    fileprivate static func loadPayload(
        manifest: ComponentPackageManifest,
        rootURL: URL
    ) throws -> ComponentPackagePayload {
        let resourceRootURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
        let instanceHierarchyHelper = """
            const foundryMatchesPackage = (element, packageIdentifier) =>
                !packageIdentifier || element.dataset.foundryPackage === packageIdentifier;
            const foundryParent = () =>
                component?.parentElement?.closest("[data-foundry-component]") || null;
            const foundryDescendants = (packageIdentifier) =>
                component
                    ? Array.from(component.querySelectorAll("[data-foundry-component]"))
                        .filter((element) => foundryMatchesPackage(element, packageIdentifier))
                    : [];
            const foundryChildren = (packageIdentifier) =>
                foundryDescendants(packageIdentifier).filter((element) =>
                    element.parentElement?.closest("[data-foundry-component]") === component
                );
            const foundryAncestors = (packageIdentifier) => {
                const result = [];
                let ancestor = foundryParent();
                while (ancestor) {
                    if (foundryMatchesPackage(ancestor, packageIdentifier)) result.push(ancestor);
                    ancestor = ancestor.parentElement?.closest("[data-foundry-component]") || null;
                }
                return result;
            };
            const foundry = Object.freeze({
                children: foundryChildren,
                descendants: foundryDescendants,
                parent: foundryParent,
                ancestors: foundryAncestors,
                closest: (packageIdentifier) => foundryAncestors(packageIdentifier)[0] || null
            });
        """
        func javascript(scope: ComponentPackageTemplateFile.Scope) throws -> String {
            try manifest.render.files
                .filter { $0.scope == scope && $0.path.lowercased().hasSuffix(".js") }
                .map { file in
                    let source = try read(file.path, from: resourceRootURL)
                    guard file.closure else { return source }
                    let parameter = scope == .instance ? "component" : "page"
                    let argument = scope == .instance
                        ? "document.querySelector('[data-foundry-id=\\\"{{ instance.id }}\\\"]')"
                        : "document"
                    return """
                    (function (\(parameter)) {
                        "use strict";
                    \(scope == .instance ? instanceHierarchyHelper : "")
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
        return ComponentPackagePayload(
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
            imageMetadata: imageMetadata(for: manifest, resourceRootURL: resourceRootURL)
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
