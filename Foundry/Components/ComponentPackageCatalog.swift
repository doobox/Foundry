import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ComponentPackageCatalog {
    static let shared = ComponentPackageCatalog()

    enum Phase: Equatable {
        case initialLoading
        case ready
        case reloading
    }

    private(set) var revision = 0
    private(set) var diagnostics: [URL: [ComponentPackageDiagnostic]] = [:]
    private(set) var packages: [String: LoadedComponentPackage] = [:]
    private var developmentWatchers: [URL: FoundryDevelopmentPackWatcher] = [:]
    private var dirtyDevelopmentRoots: Set<URL> = []
    private var applicationActiveObserver: NSObjectProtocol?
    private var loadingTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private var reloadGenerations: [URL: UInt64] = [:]
    private(set) var phase = Phase.initialLoading

    var isInitialLoading: Bool { phase == .initialLoading }

    var isLoading: Bool { phase != .ready }

    private init() {
        reloadCompleteCatalog(initial: true)
        applicationActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadDirtyDevelopmentPacks() }
        }
    }

    private func reloadCompleteCatalog(initial: Bool = false) {
        loadGeneration &+= 1
        let generation = loadGeneration
        reloadGenerations.removeAll()
        loadingTask?.cancel()
        phase = initial ? .initialLoading : .reloading
        loadingTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                await ComponentCatalogSnapshot.load()
            }.value
            guard !Task.isCancelled, let self, generation == loadGeneration else { return }
            publish(snapshot)
        }
    }

    private func publish(_ snapshot: ComponentCatalogSnapshot) {
        packages = snapshot.packages
        diagnostics = snapshot.diagnostics
        ComponentRegistry.replacePackages(Array(snapshot.packages.values))
        Task { await ComponentIconLoader.shared.removeAll() }
        configureDevelopmentWatchers(snapshot.developmentRoots, installedRoot: snapshot.installedRoot)
        phase = .ready
        revision += 1
    }

    private func reloadComponentPacks(under rootURL: URL, allowsReplacement: Bool = false) {
        let rootURL = rootURL.standardizedFileURL
        let initialLoadTask = phase == .initialLoading ? loadingTask : nil
        if phase == .reloading {
            loadingTask?.cancel()
            loadGeneration &+= 1
            phase = .ready
        }
        let generation = (reloadGenerations[rootURL] ?? 0) &+ 1
        reloadGenerations[rootURL] = generation
        Task { [weak self] in
            _ = await initialLoadTask?.value
            let result = await Task.detached(priority: .utility) {
                let urls = FoundryPackLoader.packURLs(in: rootURL, includingRoot: true)
                    .map(\.standardizedFileURL)
                return (urls, await ComponentCatalogSnapshot.loadOutcomes(urls))
            }.value
            guard !Task.isCancelled,
                  let self,
                  reloadGenerations[rootURL] == generation else { return }
            for outcome in result.1 {
                apply(outcome, allowsReplacement: allowsReplacement)
            }
            reconcileRegisteredPackages(under: rootURL, discoveredAt: result.0)
        }
    }

    private func apply(_ outcome: ComponentPackageLoadOutcome, allowsReplacement: Bool) {
        let url = outcome.url
        Task {
            await ComponentIconLoader.shared.removeIcon(
                at: url.appending(path: "Contents/Resources/icon.svg")
            )
        }
        if let package = outcome.package {
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
            let replacedIdentifiers = packages.compactMap { identifier, existingPackage in
                existingPackage.rootURL.standardizedFileURL == url ? identifier : nil
            }
            for identifier in replacedIdentifiers {
                packages.removeValue(forKey: identifier)
            }
            packages[package.manifest.identifier] = package
            diagnostics[url] = ComponentPackageValidator.validate(
                package.manifest,
                rootURL: package.resourceRootURL
            )
            ComponentRegistry.replacePackage(package, removing: replacedIdentifiers)
            revision += 1
        } else if !outcome.diagnostics.isEmpty {
            diagnostics[url] = outcome.diagnostics
            revision += 1
        } else if diagnostics.removeValue(forKey: url) != nil {
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
        reloadCompleteCatalog()
    }

    func reloadAllPacks() {
        reloadCompleteCatalog()
    }

    func waitUntilLoaded() async {
        await loadingTask?.value
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
        watchDevelopmentPack(at: rootURL)
    }

    private func watchDevelopmentPack(at rootURL: URL) {
        guard developmentWatchers[rootURL] == nil else { return }
        developmentWatchers[rootURL] = FoundryDevelopmentPackWatcher(rootURL: rootURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.dirtyDevelopmentRoots.insert(rootURL)
            }
        }
    }

    private func configureDevelopmentWatchers(_ roots: Set<URL>, installedRoot: URL?) {
        if let installedRoot {
            removeMissingDevelopmentWatchers(under: installedRoot, discoveredRoots: roots)
        }
        for root in roots {
            watchDevelopmentPack(at: root)
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
        reloadComponentPacks(under: rootURL, allowsReplacement: true)
    }
}

private struct ComponentCatalogSnapshot: Sendable {
    let packages: [String: LoadedComponentPackage]
    let diagnostics: [URL: [ComponentPackageDiagnostic]]
    let developmentRoots: Set<URL>
    let installedRoot: URL?

    nonisolated static func load() async -> ComponentCatalogSnapshot {
        var urls: [URL] = []
        if let bundleURL = Bundle.main.url(forResource: "BuiltInComponents", withExtension: "bundle"),
           let componentBundle = Bundle(url: bundleURL),
           let resourcesURL = componentBundle.resourceURL {
            let containerURL = componentBundle.url(
                forResource: "BuiltInComponents",
                withExtension: "foundrypack"
            ) ?? resourcesURL.appending(
                path: "BuiltInComponents.foundrypack",
                directoryHint: .isDirectory
            )
            urls.append(contentsOf: FoundryPackLoader.packURLs(in: containerURL, includingRoot: true))
        }

        let installedRoot = try? FoundryPackLoader.installedPacksURL()
        let installedURLs = installedRoot.map { FoundryPackLoader.packURLs(in: $0) } ?? []
        urls.append(contentsOf: installedURLs)
        let developmentRoots = Set(installedURLs.compactMap { url in
            url.pathExtension.lowercased() == "foundrydevpack" ? url.standardizedFileURL : nil
        })

        let outcomes = await loadOutcomes(urls.map(\.standardizedFileURL))
        var packages: [String: LoadedComponentPackage] = [:]
        var diagnostics: [URL: [ComponentPackageDiagnostic]] = [:]
        for outcome in outcomes {
            let url = outcome.url.standardizedFileURL
            guard let package = outcome.package else {
                if !outcome.diagnostics.isEmpty {
                    diagnostics[url] = outcome.diagnostics
                }
                continue
            }
            let identifier = package.manifest.identifier
            if let previous = packages[identifier], previous.rootURL.standardizedFileURL != url {
                diagnostics[url] = [.init(
                    severity: .error,
                    location: "Info.plist:id",
                    message: "Another installed package already uses '\(identifier)'."
                )]
                continue
            }
            packages[identifier] = package
            diagnostics[url] = ComponentPackageValidator.validate(
                package.manifest,
                rootURL: package.resourceRootURL
            )
        }
        return ComponentCatalogSnapshot(
            packages: packages,
            diagnostics: diagnostics,
            developmentRoots: developmentRoots,
            installedRoot: installedRoot
        )
    }

    fileprivate nonisolated static func loadOutcomes(_ urls: [URL]) async -> [ComponentPackageLoadOutcome] {
        guard !urls.isEmpty else { return [] }
        var results = Array<ComponentPackageLoadOutcome?>(repeating: nil, count: urls.count)
        await withTaskGroup(of: (Int, ComponentPackageLoadOutcome).self) { group in
            let concurrentLoadCount = min(4, urls.count)
            for index in 0..<concurrentLoadCount {
                group.addTask { (index, ComponentPackageLoadOutcome.load(from: urls[index])) }
            }
            var nextIndex = concurrentLoadCount
            for await (index, outcome) in group {
                results[index] = outcome
                if nextIndex < urls.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask { (index, ComponentPackageLoadOutcome.load(from: urls[index])) }
                }
            }
        }
        return results.compactMap { $0 }
    }
}

private struct ComponentPackageLoadOutcome: Sendable {
    let url: URL
    let package: LoadedComponentPackage?
    let diagnostics: [ComponentPackageDiagnostic]

    nonisolated static func load(from url: URL) -> ComponentPackageLoadOutcome {
        do {
            let pack = try FoundryPackLoader.load(from: url)
            guard !pack.isCollection else {
                return .init(url: url, package: nil, diagnostics: [])
            }
            return .init(url: url, package: try ComponentPackageLoader.load(from: url), diagnostics: [])
        } catch ComponentPackageLoadingError.invalid(let diagnostics) {
            return .init(url: url, package: nil, diagnostics: diagnostics)
        } catch {
            return .init(
                url: url,
                package: nil,
                diagnostics: [.init(
                    severity: .error,
                    location: url.lastPathComponent,
                    message: error.localizedDescription
                )]
            )
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
