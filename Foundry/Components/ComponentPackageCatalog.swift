import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ComponentPackageCatalog {
    static let shared = ComponentPackageCatalog()

    private(set) var revision = 0
    private(set) var diagnostics: [URL: [ComponentPackageDiagnostic]] = [:]
    private(set) var packages: [String: LoadedComponentPackage] = [:]
    private var developmentWatchers: [URL: FoundryDevelopmentPackWatcher] = [:]
    private var dirtyDevelopmentRoots: Set<URL> = []
    private var applicationActiveObserver: NSObjectProtocol?

    private init() {
        loadBundledComponents()
        loadInstalledComponents()
        applicationActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadDirtyDevelopmentPacks() }
        }
    }

    private func loadBundledComponents() {
        guard let bundleURL = Bundle.main.url(forResource: "BuiltInComponents", withExtension: "bundle"),
              let componentBundle = Bundle(url: bundleURL),
              let resourcesURL = componentBundle.resourceURL else { return }
        let containerURL = componentBundle.url(
            forResource: "BuiltInComponents",
            withExtension: "foundrypack"
        ) ?? resourcesURL.appending(
            path: "BuiltInComponents.foundrypack",
            directoryHint: .isDirectory
        )
        for url in FoundryPackLoader.packURLs(in: containerURL, includingRoot: true) {
            loadComponentPack(at: url)
        }
    }

    private func loadInstalledComponents() {
        guard let root = try? FoundryPackLoader.installedPacksURL() else { return }
        for url in FoundryPackLoader.packURLs(in: root) {
            if url.pathExtension.lowercased() == "foundrydevpack" {
                openDevelopmentPack(at: url)
                continue
            }
            loadComponentPack(at: url)
        }
    }

    private func loadComponentPack(at url: URL, allowsReplacement: Bool = false) {
        do {
            let pack = try FoundryPackLoader.load(from: url)
            guard pack.type == .component else {
                if diagnostics.removeValue(forKey: url.standardizedFileURL) != nil {
                    revision += 1
                }
                return
            }
            reload(url, allowsReplacement: allowsReplacement)
        } catch {
            removeRegisteredPackages(at: url)
            diagnostics[url.standardizedFileURL] = [
                .init(
                    severity: .error,
                    location: "Info.plist",
                    message: error.localizedDescription
                )
            ]
            revision += 1
        }
    }

    private func reload(_ url: URL, allowsReplacement: Bool = false) {
        let url = url.standardizedFileURL
        do {
            let package = try ComponentPackageLoader.load(from: url)
            if !allowsReplacement,
               let previous = packages[package.manifest.identifier],
               previous.rootURL.standardizedFileURL != url {
                removeRegisteredPackages(at: url)
                diagnostics[url] = [
                    .init(
                        severity: .error,
                        location: "Info.plist:CFBundleIdentifier",
                        message: "Another installed package already uses '\(package.manifest.identifier)'."
                    )
                ]
                revision += 1
                return
            }
            removeRegisteredPackages(at: url)
            packages[package.manifest.identifier] = package
            diagnostics[url] = ComponentPackageValidator.validate(
                package.manifest,
                rootURL: package.resourceRootURL
            )
            ComponentRegistry.register(package)
            revision += 1
        } catch ComponentPackageLoadingError.invalid(let packageDiagnostics) {
            removeRegisteredPackages(at: url)
            diagnostics[url] = packageDiagnostics
            revision += 1
        } catch {
            removeRegisteredPackages(at: url)
            diagnostics[url] = [
                .init(severity: .error, location: url.lastPathComponent, message: error.localizedDescription)
            ]
            revision += 1
        }
    }

    private func removeRegisteredPackages(at url: URL) {
        let url = url.standardizedFileURL
        let identifiers = packages.compactMap { identifier, package in
            package.rootURL.standardizedFileURL == url ? identifier : nil
        }
        for identifier in identifiers {
            packages.removeValue(forKey: identifier)
            ComponentRegistry.unregisterPackage(identifier: identifier)
        }
    }

    func reloadInstalledPacks() {
        loadInstalledComponents()
    }

    func reloadAllPacks() {
        loadBundledComponents()
        loadInstalledComponents()
        for rootURL in Array(developmentWatchers.keys) {
            reloadDevelopmentPack(at: rootURL)
        }
    }

    func openDevelopmentPack(at rootURL: URL) {
        let rootURL = rootURL.standardizedFileURL
        reloadDevelopmentPack(at: rootURL)
        guard developmentWatchers[rootURL] == nil else { return }
        developmentWatchers[rootURL] = FoundryDevelopmentPackWatcher(rootURL: rootURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.dirtyDevelopmentRoots.insert(rootURL)
            }
        }
    }

    private func reloadDirtyDevelopmentPacks() {
        let roots = dirtyDevelopmentRoots
        dirtyDevelopmentRoots.removeAll()
        guard !roots.isEmpty else { return }
        for rootURL in roots {
            reloadDevelopmentPack(at: rootURL)
        }
    }

    private func reloadDevelopmentPack(at rootURL: URL) {
        for url in FoundryPackLoader.packURLs(in: rootURL, includingRoot: true) {
            loadComponentPack(at: url, allowsReplacement: true)
        }
    }
}
