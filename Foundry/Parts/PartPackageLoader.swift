import Foundation
import Synchronization
import UniformTypeIdentifiers

nonisolated struct PartPackagePayloadFailure: Error, Equatable, Sendable {
    let location: String
    let message: String
}

extension Notification.Name {
    nonisolated static let partPackagePayloadDidFail = Notification.Name("partPackagePayloadDidFail")
}

nonisolated struct LoadedPartPackage: Sendable {
    static let dropZoneSlotPrefix = "__foundry_drop_zone:"

    let manifest: PartPackageManifest
    let rootURL: URL
    let updateSourceURL: URL?
    let preparedPrimitives: PartPreparedPrimitives
    private let payloadStorage: PartPackagePayloadStorage

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
    var imageMetadata: [String: PartImageMetadata] { payloadStorage.payload.imageMetadata }
    var isPayloadLoaded: Bool { payloadStorage.isLoaded }
    var payloadFailure: PartPackagePayloadFailure? { payloadStorage.failure }
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
        manifest: PartPackageManifest,
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
        imageMetadata: [String: PartImageMetadata]
    ) {
        self.manifest = manifest
        self.rootURL = rootURL
        self.updateSourceURL = updateSourceURL
        preparedPrimitives = PartPreparedPrimitives(template: htmlTemplate, loopMaximums: Self.loopMaximums(for: manifest))
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
        manifest: PartPackageManifest,
        rootURL: URL,
        updateSourceURL: URL?,
        preparedPrimitives: PartPreparedPrimitives
    ) {
        self.manifest = manifest
        self.rootURL = rootURL
        self.updateSourceURL = updateSourceURL
        self.preparedPrimitives = preparedPrimitives
        payloadStorage = .init(manifest: manifest, rootURL: rootURL)
    }

    var lock: PartPackageLock {
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
        guard let bundleURL = Bundle.main.url(forResource: "BuiltInParts", withExtension: "bundle") else {
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

    private static func loopMaximums(for manifest: PartPackageManifest) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: manifest.resolvedProperties.compactMap { property in
            guard property.control.type == .number || property.control.type == .slider,
                  let maximum = property.control.maximum,
                  maximum.isFinite,
                  maximum >= 0,
                  maximum <= Double(PartTemplateLoop.maximumIterationCount) else { return nil }
            return (property.id, Int(maximum.rounded(.down)))
        })
    }

    func declaresJavaScript(in scopes: PartPackageTemplateFile.Scope...) -> Bool {
        manifest.render.files.contains { file in
            scopes.contains { $0.rawValue == file.scope.rawValue }
                && file.path.lowercased().hasSuffix(".js")
        }
    }
}

nonisolated struct PartPreparedPrimitives: Codable, Equatable, Sendable {
    let text: [PartTextPrimitive]
    let html: [PartHTMLPrimitive]
    let images: [PartImagePrimitive]
    let dropZoneNames: [String]?

    init(
        text: [PartTextPrimitive],
        html: [PartHTMLPrimitive],
        images: [PartImagePrimitive],
        dropZoneNames: [String]? = nil
    ) {
        self.text = text
        self.html = html
        self.images = images
        self.dropZoneNames = dropZoneNames
    }

    init(template: String, loopMaximums: [String: Int]) {
        text = PartTemplateRenderer.textPrimitives(in: template, loopMaximums: loopMaximums)
        html = PartTemplateRenderer.htmlPrimitives(in: template, loopMaximums: loopMaximums)
        images = PartTemplateRenderer.imagePrimitives(in: template)
        dropZoneNames = PartTemplateRenderer.dropZoneNames(in: template)
    }
}

nonisolated fileprivate struct PartPackagePayload: Sendable {
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
    let imageMetadata: [String: PartImageMetadata]

    static let empty = PartPackagePayload(
        htmlTemplate: "", css: "", pageCSS: "", siteCSS: "", placedHTML: [],
        instanceJavaScript: "", pageJavaScript: "", instancePHP: "", pagePHP: "",
        editorCSS: "", imageMetadata: [:]
    )
}

nonisolated private final class PartPackagePayloadStorage: Sendable {
    private struct State: Sendable {
        var payload: PartPackagePayload?
        var failure: PartPackagePayloadFailure?
        var reportedFailure = false
    }

    private let manifest: PartPackageManifest?
    private let rootURL: URL?
    private let state: Mutex<State>

    init(payload: PartPackagePayload) {
        manifest = nil
        rootURL = nil
        state = Mutex(.init(payload: payload, failure: nil))
    }

    init(manifest: PartPackageManifest, rootURL: URL) {
        self.manifest = manifest
        self.rootURL = rootURL
        state = Mutex(.init(payload: nil, failure: nil))
    }

    var payload: PartPackagePayload {
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

    var failure: PartPackagePayloadFailure? {
        state.withLock { $0.failure }
    }

    func prepare() throws {
        if let result: Result<PartPackagePayload, PartPackagePayloadFailure> = state.withLock({ state in
            if let payload = state.payload { return .success(payload) }
            if let failure = state.failure { return .failure(failure) }
            return nil
        }) {
            _ = try result.get()
            return
        }
        guard let manifest, let rootURL else { return }
        do {
            let payload = try PartPackageLoader.loadPayload(manifest: manifest, rootURL: rootURL)
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
        let failure: PartPackagePayloadFailure? = state.withLock { state in
            guard !state.reportedFailure, let failure = state.failure else { return nil }
            state.reportedFailure = true
            return failure
        }
        guard let failure else { return }
        NotificationCenter.default.post(
            name: .partPackagePayloadDidFail,
            object: nil,
            userInfo: ["url": rootURL, "failure": failure]
        )
    }

    private static func failure(from error: Error) -> PartPackagePayloadFailure {
        if case PartPackageLoadingError.unreadableResource(let path, let underlying) = error {
            return .init(location: "Contents/Resources/\(path)", message: underlying.localizedDescription)
        }
        return .init(location: "Contents/Resources", message: error.localizedDescription)
    }
}

nonisolated struct LoadedPlacedHTMLTemplate: Sendable {
    let placement: PartPackageTemplateFile.Placement
    let contents: String
}

nonisolated enum PartPackageLoadingError: Error, LocalizedError {
    case missingManifest
    case unreadableManifest(Error)
    case invalid([PartPackageDiagnostic])
    case unreadableResource(String, Error)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            "The part bundle does not contain Contents/Info.plist."
        case .unreadableManifest(let error):
            "Info.plist could not be decoded: \(Self.decodingDetail(error))"
        case .invalid(let diagnostics):
            diagnostics.map { "\($0.location): \($0.message)" }.joined(separator: "\n")
        case .unreadableResource(let path, let error):
            "\(path) could not be read: \(error.localizedDescription)"
        }
    }

    /// DecodingError's localizedDescription is a generic "isn't in the correct
    /// format" — useless when a manifest breaks after an API rename. Surface the
    /// decoder's own explanation and where in the plist it happened instead.
    private static func decodingDetail(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        func location(_ context: DecodingError.Context) -> String {
            let path = context.codingPath.reduce(into: "") { partial, key in
                if let index = key.intValue {
                    partial += "[\(index)]"
                } else {
                    partial += partial.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
            return path.isEmpty ? "the manifest root" : path
        }
        switch decodingError {
        case .dataCorrupted(let context), .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(context.debugDescription) (at \(location(context)))"
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' (at \(location(context)))"
        @unknown default:
            return decodingError.localizedDescription
        }
    }
}

nonisolated struct PartPackageLoadResult: Sendable {
    let package: LoadedPartPackage
    let diagnostics: [PartPackageDiagnostic]
    let timings: PartPackageLoadTimings
}

nonisolated struct PartPackageLoadTimings: Sendable {
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

nonisolated enum PartPackageLoader {
    static func load(from rootURL: URL) throws -> LoadedPartPackage {
        try loadWithDiagnostics(from: rootURL).package
    }

    static func loadWithDiagnostics(from rootURL: URL) throws -> PartPackageLoadResult {
        try loadWithDiagnostics(from: rootURL, validates: true)
    }

    static func loadForCatalog(
        from rootURL: URL,
        validates: Bool
    ) throws -> PartPackageLoadResult {
        if !validates, let cached = PartPackagePreparedIndex.entry(for: rootURL) {
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
        var timings = PartPackageLoadTimings()
        let manifestURL = rootURL.appending(path: "Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PartPackageLoadingError.missingManifest
        }

        let data: Data
        let manifest: PartPackageManifest
        let schemaDiagnostics: [PartPackageDiagnostic]
        do {
            let readStart = clock.now
            data = try Data(contentsOf: manifestURL)
            timings.manifestRead = readStart.duration(to: clock.now)
            if validates {
                let validationStart = clock.now
                schemaDiagnostics = try PartPackageManifestSchema.diagnostics(for: data)
                timings.schemaValidation = validationStart.duration(to: clock.now)
                guard !schemaDiagnostics.contains(where: { $0.severity == .error }) else {
                    throw PartPackageLoadingError.invalid(schemaDiagnostics)
                }
            } else {
                schemaDiagnostics = []
            }
            let decodeStart = clock.now
            manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
            timings.manifestDecoding = decodeStart.duration(to: clock.now)
        } catch let error as PartPackageLoadingError {
            throw error
        } catch {
            throw PartPackageLoadingError.unreadableManifest(error)
        }

        let resourceRootURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let validationFingerprint = validates ? PartPackageValidationCache.fingerprint(
            manifestData: data,
            manifest: manifest,
            rootURL: resourceRootURL
        ) : nil
        let semanticDiagnostics: [PartPackageDiagnostic]
        if let validationFingerprint,
           PartPackageValidationCache.contains(validationFingerprint, for: rootURL) {
            semanticDiagnostics = []
        } else if validates {
            let validationStart = clock.now
            semanticDiagnostics = PartPackageValidator.validate(manifest, rootURL: resourceRootURL)
            timings.semanticValidation = validationStart.duration(to: clock.now)
        } else {
            semanticDiagnostics = []
        }
        let diagnostics = schemaDiagnostics + semanticDiagnostics
        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            throw PartPackageLoadingError.invalid(diagnostics)
        }
        if diagnostics.isEmpty,
           let validationFingerprint,
           PartPackageValidationCache.fingerprint(
               manifestData: data,
               manifest: manifest,
               rootURL: resourceRootURL
           ) == validationFingerprint {
            PartPackageValidationCache.storeSuccessful(validationFingerprint, for: rootURL)
        }

        let preparationStart = clock.now
        let template = try read(manifest.render.html, from: resourceRootURL)
        let maximums = LoadedPartPackage(
            manifest: manifest,
            rootURL: rootURL,
            updateSourceURL: nil,
            preparedPrimitives: .init(text: [], html: [], images: [])
        ).loopMaximums
        let primitives = PartPreparedPrimitives(template: template, loopMaximums: maximums)
        timings.resourceLoading = preparationStart.duration(to: clock.now)
        PartPackagePreparedIndex.store(manifest: manifest, primitives: primitives, rootURL: rootURL)
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
    ) throws -> PartPackageLoadResult {
        let clock = ContinuousClock()
        var timings = PartPackageLoadTimings()
        let manifestURL = rootURL.appending(path: "Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PartPackageLoadingError.missingManifest
        }

        let data: Data
        let manifest: PartPackageManifest
        let schemaDiagnostics: [PartPackageDiagnostic]
        do {
            let readStart = clock.now
            data = try Data(contentsOf: manifestURL)
            timings.manifestRead = readStart.duration(to: clock.now)
            if validates {
                let schemaStart = clock.now
                schemaDiagnostics = try PartPackageManifestSchema.diagnostics(for: data)
                timings.schemaValidation = schemaStart.duration(to: clock.now)
                guard !schemaDiagnostics.contains(where: { $0.severity == .error }) else {
                    throw PartPackageLoadingError.invalid(schemaDiagnostics)
                }
            } else {
                schemaDiagnostics = []
            }
            let decodingStart = clock.now
            manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
            timings.manifestDecoding = decodingStart.duration(to: clock.now)
        } catch let error as PartPackageLoadingError {
            throw error
        } catch {
            throw PartPackageLoadingError.unreadableManifest(error)
        }

        let resourceRootURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let validationFingerprint = validates ? PartPackageValidationCache.fingerprint(
            manifestData: data,
            manifest: manifest,
            rootURL: resourceRootURL
        ) : nil
        let semanticDiagnostics: [PartPackageDiagnostic]
        if let validationFingerprint,
           PartPackageValidationCache.contains(validationFingerprint, for: rootURL) {
            semanticDiagnostics = []
        } else if validates {
            let validationStart = clock.now
            semanticDiagnostics = PartPackageValidator.validate(manifest, rootURL: resourceRootURL)
            timings.semanticValidation = validationStart.duration(to: clock.now)
        } else {
            semanticDiagnostics = []
        }
        let diagnostics = schemaDiagnostics + semanticDiagnostics
        let errors = diagnostics.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw PartPackageLoadingError.invalid(diagnostics)
        }
        if diagnostics.isEmpty,
           let validationFingerprint,
           PartPackageValidationCache.fingerprint(
               manifestData: data,
               manifest: manifest,
               rootURL: resourceRootURL
           ) == validationFingerprint {
            PartPackageValidationCache.storeSuccessful(validationFingerprint, for: rootURL)
        }
        let resourceLoadingStart = clock.now
        let payload = try loadPayload(manifest: manifest, rootURL: rootURL)
        let package = LoadedPartPackage(
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
        return PartPackageLoadResult(
            package: package,
            diagnostics: diagnostics,
            timings: timings
        )
    }

    fileprivate static func loadPayload(
        manifest: PartPackageManifest,
        rootURL: URL
    ) throws -> PartPackagePayload {
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
                part?.parentElement?.closest("[data-foundry-part]") || null;
            const foundryDescendants = (packageIdentifier) =>
                part
                    ? Array.from(part.querySelectorAll("[data-foundry-part]"))
                        .filter((element) => foundryMatchesPackage(element, packageIdentifier))
                    : [];
            const foundryChildren = (packageIdentifier) =>
                foundryDescendants(packageIdentifier).filter((element) =>
                    element.parentElement?.closest("[data-foundry-part]") === part
                );
            const foundryAncestors = (packageIdentifier) => {
                const result = [];
                let ancestor = foundryParent();
                while (ancestor) {
                    if (foundryMatchesPackage(ancestor, packageIdentifier)) result.push(ancestor);
                    ancestor = ancestor.parentElement?.closest("[data-foundry-part]") || null;
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
        func javascript(scope: PartPackageTemplateFile.Scope) throws -> String {
            try manifest.render.files
                .filter { $0.scope == scope && $0.path.lowercased().hasSuffix(".js") }
                .map { file in
                    let source = try read(file.path, from: resourceRootURL)
                    guard file.closure else { return source }
                    let parameter = scope == .instance ? "part" : "page"
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
        func php(scope: PartPackageTemplateFile.Scope) throws -> String {
            try manifest.render.files
                .filter { $0.scope == scope && $0.path.lowercased().hasSuffix(".php") }
                .map { try read($0.path, from: resourceRootURL) }
                .joined(separator: "\n")
        }
        return PartPackagePayload(
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
        for manifest: PartPackageManifest,
        resourceRootURL: URL
    ) -> [String: PartImageMetadata] {
        manifest.resolvedProperties.reduce(into: [:]) { result, property in
            guard property.control.type == .image else { return }
            let path = property.defaultValue.stringValue
            guard !path.isEmpty else { return }
            let url = resourceRootURL.appending(path: path)
            guard let data = try? Data(contentsOf: url) else { return }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            result[path] = PartImageMetadata.inspect(
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

    private static func updateSourceURL(containing partURL: URL) -> URL? {
        guard partURL.pathComponents.allSatisfy({
            ($0 as NSString).pathExtension.caseInsensitiveCompare("foundrydevpack") != .orderedSame
        }) else { return nil }
        var candidate = partURL.standardizedFileURL
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
            throw PartPackageLoadingError.unreadableResource(path, error)
        }
    }
}
