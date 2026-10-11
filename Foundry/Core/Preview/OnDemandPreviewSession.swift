import Foundation
import OSLog

/// One immutable project revision with lazily materialized page/resource caches.
/// Old requests retain their session when the server publishes a newer revision.
actor OnDemandPreviewSession {
    enum PreparationError: Error { case requiresFullSnapshot }
    let identity: PreviewBuildIdentity
    private let site: Site
    private let assets: ProjectAssetContents
    private let resources: [String: SiteExportFile]
    private let routes: [String: UUID]
    private var pages: [UUID: PreviewDiskSnapshot]
    private var resourceSnapshots: [String: PreviewDiskSnapshot]
    private var pageTasks: [UUID: Task<PreviewDiskSnapshot, any Error>] = [:]
    private var resourceTasks: [String: Task<PreviewDiskSnapshot, any Error>] = [:]
    private var timings: [String: Duration] = [:]
    private static let logger = Logger(subsystem: "uk.co.garysimpson.Foundry", category: "PreviewPerformance")

    private init(site: Site, assets: ProjectAssetContents, identity: PreviewBuildIdentity,
                 resources: [String: SiteExportFile], pages: [UUID: PreviewDiskSnapshot],
                 resourceSnapshots: [String: PreviewDiskSnapshot]) {
        self.site = site
        self.assets = assets
        self.identity = identity
        self.resources = resources
        self.pages = pages
        self.resourceSnapshots = resourceSnapshots
        routes = Dictionary(site.pages.map { (StaticSiteRenderer.outputPath(for: $0, in: site), $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    static func prepare(site: Site, assets: ProjectAssetContents, identity: PreviewBuildIdentity,
                        invalidation: PreviewInvalidation, selectedPageID: UUID?,
                        previous: OnDemandPreviewSession?) async throws -> OnDemandPreviewSession {
        try Task.checkCancellation()
        guard !site.pages.contains(where: { StaticSiteRenderer.fileExtension(for: $0) == "php" }) else {
            throw PreparationError.requiresFullSnapshot
        }
        if let previous, await previous.matches(identity) {
            if let selected = selectedPageID ?? site.pages.first?.id { _ = try await previous.pageSnapshot(selected) }
            try Task.checkCancellation()
            return previous
        }
        let start = ContinuousClock.now
        let resourceTask = Task.detached(priority: .userInitiated) {
            var files: [String: SiteExportFile] = [:]
            var timings: [String: Duration] = [:]
            try StaticSiteRenderer(environment: .preview).generate(site: site, assets: assets, pageIDs: [],
                stageTiming: { timings[$0] = $1 }) { file in
                if file.path.lowercased().hasSuffix(".php") { throw PreparationError.requiresFullSnapshot }
                if let existing = files[file.path], existing != file {
                    throw SiteExportBundleError.invalid(["Conflicting preview resource: \(file.path)"])
                }
                files[file.path] = file
            }
            return (files, timings)
        }
        let (resources, timings) = try await withTaskCancellationHandler {
            try await resourceTask.value
        } onCancel: { resourceTask.cancel() }
        try Task.checkCancellation()
        let resourceTime = start.duration(to: .now)
        var pages: [UUID: PreviewDiskSnapshot] = [:]
        var resourceSnapshots: [String: PreviewDiskSnapshot] = [:]
        if let previous {
            (pages, resourceSnapshots) = await previous.reusableCaches(for: identity, invalidation: invalidation, resources: resources)
        }
        let currentIDs = Set(site.pages.map(\.id))
        pages = pages.filter { currentIDs.contains($0.key) }
        let session = OnDemandPreviewSession(site: site, assets: assets, identity: identity,
            resources: resources, pages: pages, resourceSnapshots: resourceSnapshots)
        let pageStarted = ContinuousClock.now
        if let selected = selectedPageID ?? site.pages.first?.id {
            _ = try await session.pageSnapshot(selected)
        }
        try Task.checkCancellation()
        await session.setTimings(timings.merging(["selectedPage": pageStarted.duration(to: .now), "total": start.duration(to: .now)]) { _, new in new })
        logger.debug("On-demand preview preparation: \(String(describing: start.duration(to: .now)), privacy: .public); shared resource planning: \(String(describing: resourceTime), privacy: .public)")
        return session
    }

    private func reusableCaches(for next: PreviewBuildIdentity, invalidation: PreviewInvalidation,
                                resources nextResources: [String: SiteExportFile]) -> ([UUID: PreviewDiskSnapshot], [String: PreviewDiskSnapshot]) {
        guard identity.siteID == next.siteID, identity.documentRevision <= next.documentRevision else { return ([:], [:]) }
        let sameDependencies = identity.packageRevision == next.packageRevision && identity.assetRevision == next.assetRevision
        let cleanPages: [UUID: PreviewDiskSnapshot]
        if sameDependencies, let dirty = invalidation.dirtyPages(since: identity.documentRevision) {
            cleanPages = pages.filter { !dirty.contains($0.key) }
        } else { cleanPages = [:] }
        let cleanResources = resourceSnapshots.filter { nextResources[$0.key] != nil && nextResources[$0.key] == resources[$0.key] }
        return (cleanPages, cleanResources)
    }

    func cachedPageIDs() -> Set<UUID> { Set(pages.keys) }
    private func matches(_ value: PreviewBuildIdentity) -> Bool { identity == value }
    func cachedResourcePaths() -> Set<String> { Set(resourceSnapshots.keys) }
    func preparationTimings() -> [String: Duration] { timings }
    private func setTimings(_ values: [String: Duration]) { timings = values }

    func resolve(_ target: String) async throws -> (snapshot: PreviewDiskSnapshot, path: String)? {
        guard let path = PreviewHTTPRouter.safeBundlePath(target) else { return nil }
        if let file = resources[path] { return (try await resourceSnapshot(file), path) }
        let pageID = routes[path] ?? routes.sorted { $0.key.count > $1.key.count }.first { route in
            let directory = (route.key as NSString).deletingLastPathComponent
            let prefix = directory.isEmpty ? "files/" : directory + "/files/"
            return path.hasPrefix(prefix)
        }?.value
        guard let pageID else { return nil }
        let snapshot = try await pageSnapshot(pageID)
        guard snapshot.fingerprints[path] != nil else { return nil }
        return (snapshot, path)
    }

    private func pageSnapshot(_ id: UUID) async throws -> PreviewDiskSnapshot {
        if let cached = pages[id] { return cached }
        if let task = pageTasks[id] { return try await task.value }
        let site = site
        let assets = assets
        let task = Task.detached(priority: .userInitiated) {
            try PreviewDiskSnapshot.build { emit in
                try StaticSiteRenderer(environment: .preview).generate(site: site, assets: assets,
                    pageIDs: [id], includeSharedFiles: false, emit: emit)
            }
        }
        pageTasks[id] = task
        defer { pageTasks[id] = nil }
        let snapshot = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        pages[id] = snapshot
        return snapshot
    }

    private func resourceSnapshot(_ file: SiteExportFile) async throws -> PreviewDiskSnapshot {
        if let cached = resourceSnapshots[file.path] { return cached }
        if let task = resourceTasks[file.path] { return try await task.value }
        let task = Task.detached(priority: .userInitiated) {
            try PreviewDiskSnapshot.build { try $0(file) }
        }
        resourceTasks[file.path] = task
        defer { resourceTasks[file.path] = nil }
        let snapshot = try await task.value
        resourceSnapshots[file.path] = snapshot
        return snapshot
    }
}
