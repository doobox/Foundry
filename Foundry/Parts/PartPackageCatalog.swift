import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PartPackageCatalog {
    static let shared = PartPackageCatalog()

    nonisolated enum LoadingStage: Equatable, Sendable {
        case finding
        case loading
        case savingIndex
        case preparing
        case publishing
        case ready
    }

    enum Phase: Equatable {
        case initialLoading
        case ready
        case reloading
    }

    private(set) var revision = 0
    private(set) var diagnostics: [URL: [PartPackageDiagnostic]] = [:]
    private(set) var packages: [String: LoadedPartPackage] = [:]
    private var developmentWatchers: [URL: FoundryDevelopmentPackWatcher] = [:]
    private var dirtyDevelopmentRoots: Set<URL> = []
    private var applicationActiveObserver: NSObjectProtocol?
    private var payloadFailureObserver: NSObjectProtocol?
    private var loadingTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private var reloadGenerations: [URL: UInt64] = [:]
    private(set) var phase = Phase.initialLoading
    private(set) var loadingStage = LoadingStage.finding
    private(set) var completedPackageCount = 0
    private(set) var totalPackageCount = 0

    var isInitialLoading: Bool { phase == .initialLoading }

    var isLoading: Bool { phase != .ready }

    var loadingProgress: Double {
        guard totalPackageCount > 0 else { return 0 }
        let packageProgress = Double(completedPackageCount) / Double(totalPackageCount)
        switch loadingStage {
        case .finding:
            return 0
        case .loading:
            return packageProgress * 0.88
        case .savingIndex:
            return 0.88
        case .preparing:
            return 0.88 + (packageProgress * 0.11)
        case .publishing:
            return 0.99
        case .ready:
            return 1
        }
    }

    private init() {
        reloadCompleteCatalog(initial: true)
        applicationActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadDirtyDevelopmentPacks() }
        }
        payloadFailureObserver = NotificationCenter.default.addObserver(
            forName: .partPackagePayloadDidFail,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?["url"] as? URL,
                  let failure = notification.userInfo?["failure"] as? PartPackagePayloadFailure else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let diagnostic = PartPackageDiagnostic(
                    severity: .error,
                    location: failure.location,
                    message: "Runtime files could not be loaded: \(failure.message)"
                )
                if self.diagnostics[url.standardizedFileURL]?.contains(diagnostic) != true {
                    self.diagnostics[url.standardizedFileURL, default: []].append(diagnostic)
                    self.revision += 1
                }
            }
        }
    }

    private func reloadCompleteCatalog(initial: Bool = false) {
        loadGeneration &+= 1
        let generation = loadGeneration
        reloadGenerations.removeAll()
        loadingTask?.cancel()
        phase = initial ? .initialLoading : .reloading
        loadingStage = .finding
        completedPackageCount = 0
        totalPackageCount = 0
        loadingTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) { [weak self] in
                await PartCatalogSnapshot.load { [weak self] stage, completed, total in
                    guard let self, generation == loadGeneration else { return }
                    loadingStage = stage
                    completedPackageCount = completed
                    totalPackageCount = total
                }
            }.value
            guard !Task.isCancelled, let self, generation == loadGeneration else { return }
            loadingStage = .publishing
            publish(snapshot)
        }
    }

    private func publish(_ snapshot: PartCatalogSnapshot) {
        packages = snapshot.packages
        diagnostics = snapshot.diagnostics
        PartRegistry.replaceDefinitions(snapshot.definitions)
        Task { await PartIconLoader.shared.removeAll() }
        configureDevelopmentWatchers(snapshot.developmentRoots, installedRoot: snapshot.installedRoot)
        loadingStage = .ready
        phase = .ready
        revision += 1
    }

    private func reloadPartPacks(under rootURL: URL, allowsReplacement: Bool = false) {
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
                let urls = (try? FoundryPackLoader.load(from: rootURL).partURLs) ?? []
                let outcomes = await PartCatalogSnapshot.loadOutcomes(urls)
                PartPackagePreparedIndex.flush()
                PartPackageValidationCache.flush()
                return (urls, outcomes)
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

    private func apply(_ outcome: PartPackageLoadOutcome, allowsReplacement: Bool) {
        let url = outcome.url
        Task {
            await PartIconLoader.shared.removeIcon(
                at: url.appending(path: "Resources/icon.svg")
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
            diagnostics[url] = outcome.diagnostics
            PartRegistry.replacePackage(package, removing: replacedIdentifiers)
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
            PartRegistry.unregisterPackage(identifier: identifier)
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
            PartRegistry.unregisterPackage(identifier: identifier)
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
        ReusablePartLibrary.shared.refresh()
        FrameworkLibrary.shared.reload()
        AssetCollectionLibrary.shared.refresh()
        SiteKitLibrary.shared.refreshIfScanned()
    }

    func reloadAllPacks() {
        reloadCompleteCatalog()
        ReusablePartLibrary.shared.refresh()
        FrameworkLibrary.shared.reload()
        AssetCollectionLibrary.shared.refresh()
        SiteKitLibrary.shared.refreshIfScanned()
    }

    func waitUntilLoaded() async {
        await loadingTask?.value
    }

    func conversionRootURL(for package: LoadedPartPackage) -> URL {
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
            PartRegistry.unregisterPackage(identifier: identifier)
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
        ReusablePartLibrary.shared.openDevelopmentPack(at: rootURL)
        FrameworkLibrary.shared.openDevelopmentPack(at: rootURL)
        AssetCollectionLibrary.shared.openDevelopmentPack(at: rootURL)
        SiteKitLibrary.shared.openDevelopmentPack(at: rootURL)
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
        reloadPartPacks(under: rootURL, allowsReplacement: true)
        ReusablePartLibrary.shared.refresh()
        FrameworkLibrary.shared.reload()
        AssetCollectionLibrary.shared.refresh()
        SiteKitLibrary.shared.refreshIfScanned()
    }
}

private struct PartCatalogSnapshot: Sendable {
    let packages: [String: LoadedPartPackage]
    let definitions: [PartType: PartDefinition]
    let diagnostics: [URL: [PartPackageDiagnostic]]
    let developmentRoots: Set<URL>
    let installedRoot: URL?

    nonisolated static func load(
        progress: @escaping @MainActor @Sendable (
            _ stage: PartPackageCatalog.LoadingStage,
            _ completed: Int,
            _ total: Int
        ) -> Void
    ) async -> PartCatalogSnapshot {
        var urls: [URL] = []
        if let bundleURL = Bundle.main.url(forResource: "BuiltInParts", withExtension: "bundle"),
           let partBundle = Bundle(url: bundleURL),
           let resourcesURL = partBundle.resourceURL {
            let containerURL = partBundle.url(
                forResource: "BuiltInParts",
                withExtension: "foundrypack"
            ) ?? resourcesURL.appending(
                path: "BuiltInParts.foundrypack",
                directoryHint: .isDirectory
            )
            if let pack = try? FoundryPackLoader.load(from: containerURL) {
                urls.append(contentsOf: pack.partURLs)
            }
        }

        let installedRoot = try? FoundryPackLoader.installedPacksURL()
        let installedPackURLs = installedRoot.map { FoundryPackLoader.packURLs(in: $0) } ?? []
        let installedPacks = installedPackURLs.compactMap { try? FoundryPackLoader.load(from: $0) }
        urls.append(contentsOf: installedPacks.flatMap(\.partURLs))
        let developmentRoots = Set(installedPackURLs.compactMap { url in
            url.pathExtension.lowercased() == "foundrydevpack" ? url.standardizedFileURL : nil
        })

        let standardizedURLs = urls.map(\.standardizedFileURL)
        await progress(.loading, 0, standardizedURLs.count)
        let progressUpdateInterval = max(1, standardizedURLs.count / 100)
        let outcomes = await loadOutcomes(
            standardizedURLs,
            validationMode: PartValidationPreference.mode
        ) { completed in
            if completed == standardizedURLs.count || completed.isMultiple(of: progressUpdateInterval) {
                await progress(.loading, completed, standardizedURLs.count)
            }
        }
        await progress(.savingIndex, standardizedURLs.count, standardizedURLs.count)
        PartPackagePreparedIndex.flush(retaining: standardizedURLs)
        PartPackageValidationCache.flush(retaining: standardizedURLs)
        var packages: [String: LoadedPartPackage] = [:]
        var definitions: [PartType: PartDefinition] = [:]
        var diagnostics: [URL: [PartPackageDiagnostic]] = [:]
        await progress(.preparing, 0, outcomes.count)
        for (index, outcome) in outcomes.enumerated() {
            let url = outcome.url.standardizedFileURL
            if let package = outcome.package {
                let identifier = package.manifest.identifier
                if let previous = packages[identifier], previous.rootURL.standardizedFileURL != url {
                    diagnostics[url] = [.init(
                        severity: .error,
                        location: "Info.plist:id",
                        message: "Another installed package already uses '\(identifier)'."
                    )]
                } else {
                    packages[identifier] = package
                    let definition = PartPackageAdapter.definition(from: package)
                    definitions[definition.type] = definition
                    diagnostics[url] = outcome.diagnostics
                }
            } else if !outcome.diagnostics.isEmpty {
                diagnostics[url] = outcome.diagnostics
            }
            let completed = index + 1
            if completed == outcomes.count || completed.isMultiple(of: progressUpdateInterval) {
                await progress(.preparing, completed, outcomes.count)
            }
        }
        return PartCatalogSnapshot(
            packages: packages,
            definitions: definitions,
            diagnostics: diagnostics,
            developmentRoots: developmentRoots,
            installedRoot: installedRoot
        )
    }

    fileprivate nonisolated static func loadOutcomes(
        _ urls: [URL],
        validationMode: PartValidationMode = PartValidationPreference.mode,
        progress: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async -> [PartPackageLoadOutcome] {
        guard !urls.isEmpty else { return [] }
        var results = Array<PartPackageLoadOutcome?>(repeating: nil, count: urls.count)
        await withTaskGroup(of: (Int, PartPackageLoadOutcome).self) { group in
            let concurrentLoadCount = min(4, urls.count)
            for index in 0..<concurrentLoadCount {
                group.addTask {
                    let url = urls[index]
                    return (index, PartPackageLoadOutcome.load(from: url, validates: validationMode.validates(url)))
                }
            }
            var nextIndex = concurrentLoadCount
            var completedCount = 0
            for await (index, outcome) in group {
                results[index] = outcome
                completedCount += 1
                await progress(completedCount)
                if nextIndex < urls.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        let url = urls[index]
                        return (index, PartPackageLoadOutcome.load(from: url, validates: validationMode.validates(url)))
                    }
                }
            }
        }
        return results.compactMap { $0 }
    }
}

private struct PartPackageLoadOutcome: Sendable {
    let url: URL
    let package: LoadedPartPackage?
    let diagnostics: [PartPackageDiagnostic]

    nonisolated static func load(from url: URL, validates: Bool) -> PartPackageLoadOutcome {
        do {
            let result = try PartPackageLoader.loadForCatalog(from: url, validates: validates)
            if result.package.isDevelopmentPack {
                try result.package.preparePayload()
            }
            return .init(url: url, package: result.package, diagnostics: result.diagnostics)
        } catch let failure as PartPackagePayloadFailure {
            return .init(
                url: url,
                package: nil,
                diagnostics: [.init(
                    severity: .error,
                    location: failure.location,
                    message: "Runtime files could not be loaded: \(failure.message)"
                )]
            )
        } catch PartPackageLoadingError.invalid(let diagnostics) {
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
