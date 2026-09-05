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
        let packageURLs = FoundryPackLoader.packURLs(in: containerURL, includingRoot: true)
        for url in packageURLs {
            loadComponentPack(at: url)
        }
        reconcileRegisteredPackages(under: containerURL, discoveredAt: packageURLs)
    }

    private func loadInstalledComponents() {
        guard let root = try? FoundryPackLoader.installedPacksURL() else { return }
        let installedURLs = FoundryPackLoader.packURLs(in: root)
        var discoveredURLs = Set(installedURLs.map(\.standardizedFileURL))
        var developmentRoots = Set<URL>()
        for url in installedURLs {
            if url.pathExtension.lowercased() == "foundrydevpack" {
                let rootURL = url.standardizedFileURL
                developmentRoots.insert(rootURL)
                discoveredURLs.formUnion(
                    FoundryPackLoader.packURLs(in: rootURL, includingRoot: true).map(\.standardizedFileURL)
                )
                openDevelopmentPack(at: url)
                continue
            }
            loadComponentPack(at: url)
        }
        reconcileRegisteredPackages(under: root, discoveredAt: Array(discoveredURLs))
        removeMissingDevelopmentWatchers(under: root, discoveredRoots: developmentRoots)
    }

    private func loadComponentPack(at url: URL, allowsReplacement: Bool = false) {
        do {
            let pack = try FoundryPackLoader.load(from: url)
            guard !pack.isCollection else {
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
                        location: "Info.plist:id",
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

    private func reconcileRegisteredPackages(under rootURL: URL, discoveredAt urls: [URL]) {
        let rootURL = rootURL.standardizedFileURL
        let discoveredURLs = Set(urls.map(\.standardizedFileURL))
        let removedIdentifiers = packages.compactMap { identifier, package in
            let packageURL = package.rootURL.standardizedFileURL
            return packageURL.isContained(in: rootURL) && !discoveredURLs.contains(packageURL)
                ? identifier
                : nil
        }
        guard !removedIdentifiers.isEmpty else { return }
        for identifier in removedIdentifiers {
            packages.removeValue(forKey: identifier)
            ComponentRegistry.unregisterPackage(identifier: identifier)
        }
        diagnostics = diagnostics.filter { url, _ in
            !url.isContained(in: rootURL) || discoveredURLs.contains(url)
        }
        revision += 1
    }

    private func removeMissingDevelopmentWatchers(under rootURL: URL, discoveredRoots: Set<URL>) {
        let rootURL = rootURL.standardizedFileURL
        let removedRoots = developmentWatchers.keys.filter {
            $0.isContained(in: rootURL) && !discoveredRoots.contains($0)
        }
        for removedRoot in removedRoots {
            developmentWatchers.removeValue(forKey: removedRoot)
            dirtyDevelopmentRoots.remove(removedRoot)
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

    func conversionRootURL(for package: LoadedComponentPackage) -> URL {
        guard let installedRoot = try? FoundryPackLoader.installedPacksURL() else {
            return package.developmentPackRootURL ?? package.rootURL
        }

        let standardizedInstalledRoot = installedRoot.standardizedFileURL
        var candidate = package.rootURL.standardizedFileURL
        var conversionRoot = package.developmentPackRootURL ?? package.rootURL

        while candidate.isContained(in: standardizedInstalledRoot), candidate != standardizedInstalledRoot {
            if FoundryPackLoader.isPackURL(candidate) {
                conversionRoot = candidate
            }
            candidate.deleteLastPathComponent()
        }
        return conversionRoot
    }

    func convertPack(at sourceURL: URL, toExtension destinationExtension: String) throws -> URL {
        let sourceURL = sourceURL.standardizedFileURL
        let destinationURL = sourceURL
            .deletingPathExtension()
            .appendingPathExtension(destinationExtension)
            .standardizedFileURL
        let fileManager = FileManager.default

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }

        unregisterPackages(under: sourceURL)
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            reloadAllPacks()
            throw error
        }

        reloadAllPacks()
        return destinationURL
    }

    private func unregisterPackages(under rootURL: URL) {
        let rootURL = rootURL.standardizedFileURL
        let identifiers = packages.compactMap { identifier, package in
            package.rootURL.standardizedFileURL.isContained(in: rootURL) ? identifier : nil
        }
        for identifier in identifiers {
            packages.removeValue(forKey: identifier)
            ComponentRegistry.unregisterPackage(identifier: identifier)
        }
        diagnostics = diagnostics.filter { url, _ in
            !url.standardizedFileURL.isContained(in: rootURL)
        }
        developmentWatchers.removeValue(forKey: rootURL)
        dirtyDevelopmentRoots.remove(rootURL)
        revision += 1
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

private extension URL {
    func isContained(in directoryURL: URL) -> Bool {
        let directoryPath = directoryURL.standardizedFileURL.path
        let candidatePath = standardizedFileURL.path
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
    }
}
