import Foundation

nonisolated struct LoadedComponentPackage: Sendable {
    let manifest: ComponentPackageManifest
    let rootURL: URL
    let htmlTemplate: String
    let css: String
    let editorCSS: String
    let runtimeJavaScript: String?

    var lock: ComponentPackageLock {
        .init(identifier: manifest.identifier)
    }

    var iconURL: URL {
        resourceRootURL.appending(path: manifest.icon)
    }

    var resourceRootURL: URL {
        rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
    }
}

nonisolated enum ComponentPackageLoadingError: Error, LocalizedError {
    case missingManifest
    case unreadableManifest(Error)
    case invalid([ComponentPackageDiagnostic])
    case unreadableResource(String, Error)
    case unapprovedCapabilities(Set<ComponentPackageRuntime.Capability>)

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
        case .unapprovedCapabilities(let capabilities):
            "The package requests capabilities that have not been approved: \(capabilities.map(\.rawValue).sorted().joined(separator: ", "))."
        }
    }
}

nonisolated enum ComponentPackageLoader {
    static func load(
        from rootURL: URL,
        approvedCapabilities: Set<ComponentPackageRuntime.Capability> = [.dom, .timers]
    ) throws -> LoadedComponentPackage {
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

        let resourceRootURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let diagnostics = ComponentPackageValidator.validate(manifest, rootURL: resourceRootURL)
        let errors = diagnostics.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw ComponentPackageLoadingError.invalid(diagnostics)
        }
        let requestedCapabilities = Set(manifest.runtime?.capabilities ?? [])
        let unapprovedCapabilities = requestedCapabilities.subtracting(approvedCapabilities)
        guard unapprovedCapabilities.isEmpty else {
            throw ComponentPackageLoadingError.unapprovedCapabilities(unapprovedCapabilities)
        }

        return LoadedComponentPackage(
            manifest: manifest,
            rootURL: rootURL,
            htmlTemplate: try read(manifest.render.html, from: resourceRootURL),
            css: try readIfPresent(manifest.render.css, from: resourceRootURL),
            editorCSS: try readIfPresent(manifest.render.editorCSS, from: resourceRootURL),
            runtimeJavaScript: try manifest.runtime.map { try read($0.entry, from: resourceRootURL) }
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
