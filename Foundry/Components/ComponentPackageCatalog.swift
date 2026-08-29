import Foundation
import Observation

@MainActor
@Observable
final class ComponentPackageCatalog {
    static let shared = ComponentPackageCatalog()

    private(set) var revision = 0
    private(set) var diagnostics: [URL: [ComponentPackageDiagnostic]] = [:]
    private(set) var packages: [String: LoadedComponentPackage] = [:]
    private(set) var developmentPackageURLs: [URL] = []

    @ObservationIgnored private var fingerprints: [URL: String] = [:]
    @ObservationIgnored private var securityScopedURLs: Set<URL> = []
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    private init() {
        loadBundledComponents()
        loadPackComponents()
    }

    deinit {
        watchTask?.cancel()
    }

    func addDevelopmentPackage(at url: URL) {
        guard !developmentPackageURLs.contains(url) else { return }
        if url.startAccessingSecurityScopedResource() {
            securityScopedURLs.insert(url)
        }
        developmentPackageURLs.append(url)
        reload(url)
        startWatching()
    }

    func removeDevelopmentPackage(at url: URL) {
        developmentPackageURLs.removeAll(where: { $0 == url })
        fingerprints.removeValue(forKey: url)
        diagnostics.removeValue(forKey: url)
        if securityScopedURLs.remove(url) != nil {
            url.stopAccessingSecurityScopedResource()
        }
        if let package = packages.values.first(where: { $0.rootURL == url }) {
            packages.removeValue(forKey: package.manifest.identifier)
            ComponentRegistry.unregisterPackage(identifier: package.manifest.identifier)
            revision += 1
        }
    }

    func startWatching() {
        guard watchTask == nil else { return }
        watchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.reloadChangedDevelopmentPackages()
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    private func loadBundledComponents() {
        guard let containerURL = Bundle.main.url(
            forResource: "BuiltInComponents",
            withExtension: "bundle"
        ), let urls = try? FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls where url.pathExtension == "foundrycomponent" {
            reload(url)
        }
    }

    private func loadPackComponents() {
        var roots: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL)
        }
        if let installedURL = try? FoundryPackLoader.installedPacksURL() {
            roots.append(installedURL)
        }
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            let packURLs = enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension == "foundrypack" }
            for packURL in packURLs {
                guard let pack = try? FoundryPackLoader.load(from: packURL) else { continue }
                for componentURL in pack.componentURLs {
                    reload(componentURL)
                }
            }
        }
    }

    private func reloadChangedDevelopmentPackages() {
        for url in developmentPackageURLs {
            let nextFingerprint = fingerprint(for: url)
            if fingerprints[url] != nextFingerprint {
                reload(url)
            }
        }
    }

    private func reload(_ url: URL) {
        let nextFingerprint = fingerprint(for: url)
        fingerprints[url] = nextFingerprint
        do {
            let package = try ComponentPackageLoader.load(from: url)
            if let previous = packages[package.manifest.identifier], previous.rootURL != url {
                diagnostics[url] = [
                    .init(
                        severity: .error,
                        location: "Info.plist:CFBundleIdentifier",
                        message: "Another installed package already uses '\(package.manifest.identifier)'."
                    )
                ]
                return
            }
            packages[package.manifest.identifier] = package
            diagnostics[url] = ComponentPackageValidator.validate(
                package.manifest,
                rootURL: package.resourceRootURL
            )
            ComponentRegistry.register(package)
            revision += 1
        } catch ComponentPackageLoadingError.invalid(let packageDiagnostics) {
            diagnostics[url] = packageDiagnostics
            revision += 1
        } catch {
            diagnostics[url] = [
                .init(severity: .error, location: url.lastPathComponent, message: error.localizedDescription)
            ]
            revision += 1
        }
    }

    private func fingerprint(for rootURL: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return "missing" }
        return enumerator.compactMap { item -> String? in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return "\(url.path):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.fileSize ?? 0)"
        }.sorted().joined(separator: "|")
    }
}
