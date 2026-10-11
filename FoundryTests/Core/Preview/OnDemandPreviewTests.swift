import Foundation
import Testing
@testable import Foundry

@MainActor
@Suite(.serialized)
struct OnDemandPreviewTests {
    private func makeSite(pages count: Int) -> Site {
        _ = PartPackageCatalog.shared
        return Site(name: "Preview probe", pages: (0..<count).map { index in
            Page(title: "Page \(index)", slug: index == 0 ? "index" : "page-\(index)",
                 parts: (0..<10).map { _ in PartNode.make(.button) })
        })
    }

    private func prepare(_ site: Site, assets: ProjectAssetContents = [:], revision: UInt64 = 0,
                         invalidation: PreviewInvalidation = .init(), previous: OnDemandPreviewSession? = nil) async throws -> OnDemandPreviewSession {
        try await OnDemandPreviewSession.prepare(site: site, assets: assets,
            identity: .init(siteID: site.id, documentRevision: revision, packageRevision: 1),
            invalidation: invalidation, selectedPageID: site.pages.first?.id, previous: previous)
    }

    @Test func onlyRequestedPagesAreRenderedAndMatchFullOutput() async throws {
        let site = makeSite(pages: 3)
        let session = try await prepare(site)
        #expect(await session.cachedPageIDs() == [site.pages[0].id])
        let full = StaticSiteRenderer(environment: .preview).render(site: site)
        try full.validate()
        for file in full.files {
            let resolved = try #require(try await session.resolve("/" + file.path))
            #expect(try Data(contentsOf: resolved.snapshot.root.appending(path: resolved.path)) == file.resolvedData())
        }
        #expect(await session.cachedPageIDs().count == 3)
        #expect(try await session.resolve("/../private") == nil)
        #expect(try await session.resolve("/missing/") == nil)
    }

    @Test func cachedPagesInvalidateAfterEditsAndRoutesDisappear() async throws {
        var site = makeSite(pages: 3)
        let first = try await prepare(site)
        let old = try #require(try await first.resolve("/page-1/"))
        _ = try await first.resolve("/page-2/")
        let partID = site.pages[1].parts[0].id
        site.updatePart(id: partID) { $0.setProperty(.init(rawValue: "variant"), value: "btn-outline") }
        var dirty = PreviewInvalidation()
        dirty.record(.partProperty(partID: partID, propertyKey: .init(rawValue: "variant")), in: site, revision: 1)
        let second = try await prepare(site, revision: 1, invalidation: dirty, previous: first)
        #expect(await second.cachedPageIDs() == [site.pages[0].id, site.pages[2].id])
        let updated = try #require(try await second.resolve("/page-1/"))
        #expect(updated.snapshot.root != old.snapshot.root)
        let full = StaticSiteRenderer(environment: .preview).render(site: site)
        #expect(try Data(contentsOf: updated.snapshot.root.appending(path: updated.path)) == full.file(at: updated.path)?.data)
        site.pages.removeLast()
        site.pages[1].slug = "renamed"
        dirty.record(.page, in: site, revision: 2)
        let third = try await prepare(site, revision: 2, invalidation: dirty, previous: second)
        #expect(try await third.resolve("/page-1/") == nil)
        #expect(try await third.resolve("/page-2/") == nil)
        #expect(try await third.resolve("/renamed/") != nil)
    }

    @Test func concurrentRequestsShareOnePageBuild() async throws {
        let site = makeSite(pages: 3)
        let session = try await prepare(site)
        async let first = session.resolve("/page-1/")
        async let second = session.resolve("/page-1/files/page.css")
        let (html, css) = try await (first, second)
        #expect(try #require(html).snapshot.root == #require(css).snapshot.root)
        #expect(await session.cachedPageIDs().count == 2)
    }

    @Test func customFilenamesResolvePageResources() async throws {
        var site = makeSite(pages: 2)
        site.pages[1].filenameOverride = "details.html"
        let session = try await prepare(site)
        let path = StaticSiteRenderer.outputPath(for: site.pages[1], in: site)
        let directory = (path as NSString).deletingLastPathComponent
        let css = try #require(try await session.resolve("/" + directory + "/files/page.css"))
        let html = try #require(try await session.resolve("/" + path))
        #expect(css.snapshot.root == html.snapshot.root)
    }

    @Test func explicitPHPFilenameRequiresFullSnapshot() async throws {
        var site = makeSite(pages: 2)
        site.pages[1].filenameOverride = "details.php"
        await #expect(throws: OnDemandPreviewSession.PreparationError.self) {
            _ = try await prepare(site)
        }
    }

    @Test(.timeLimit(.minutes(2))) func manualEditHandoffBenchmark() async throws {
        var site = makeSite(pages: 10)
        var session = try await prepare(site)
        let server = PreviewServer()
        do {
            let url = try await server.publish(.onDemand(session), notifyingClients: false)
            let sessionID = UUID()
            let initialURL = try #require(URL(string: "?__foundry_session=\(sessionID.uuidString)", relativeTo: url))
            let probe = PreviewBrowserProbe()
            _ = try await probe.load(initialURL)
            var invalidation = PreviewInvalidation()
            for revision in 1...5 {
                // Wait for the actual connection, outside the measured edit.
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while await server.hasPreviewConnection(sessionID: sessionID) == false, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                #expect(await server.hasPreviewConnection(sessionID: sessionID))
                let partID = site.pages[0].parts[0].id
                site.updatePart(id: partID) { $0.setProperty(.init(rawValue: "variant"), value: revision.isMultiple(of: 2) ? "btn-solid" : "btn-outline") }
                invalidation.record(.partProperty(partID: partID, propertyKey: .init(rawValue: "variant")), in: site, revision: UInt64(revision))
                let start = ContinuousClock.now
                session = try await prepare(site, revision: UInt64(revision), invalidation: invalidation, previous: session)
                let generation = start.duration(to: .now)
                _ = try await server.publish(.onDemand(session), notifyingClients: false)
                let published = start.duration(to: .now)
                let loaded = try await probe.navigate(server: server, sessionID: sessionID, target: "/?__foundry_session=\(sessionID.uuidString)")
                print("MANUAL PREVIEW sample=\(revision) generation=\(generation) published=\(published) handoffThroughLoad=\(loaded) total=\(start.duration(to: .now))")
            }
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(2))) func stageAndBrowserBenchmarks() async throws {
        for (pageCount, assetCount) in [(1, 0), (10, 0), (30, 32)] {
            var site = makeSite(pages: pageCount)
            var contents: [UUID: ProjectAssetContent] = [:]
            // 64 MiB of binary project assets: exercises staging, not image decoding.
            let payload = Data(repeating: 0x5A, count: 2 * 1024 * 1024)
            for index in 0..<assetCount {
                let asset = ProjectAsset(filename: "payload-\(index).bin", mediaType: "application/octet-stream",
                    byteCount: payload.count, contentDigest: FoundryDocumentSnapshot.digest(for: payload))
                site.assetLibrary.append(.asset(asset))
                contents[asset.id] = ProjectAssetContent(asset: asset, data: payload)
            }
            let assets = ProjectAssetContents(contents)
            var stages: [String: Duration] = [:]
            let started = ContinuousClock.now
            let full = try PreviewDiskSnapshot.build {
                try StaticSiteRenderer(environment: .preview).generate(site: site, assets: assets,
                    stageTiming: { stages[$0] = $1 }, emit: $0)
            }
            let fullTime = started.duration(to: .now)
            let session = try await prepare(site, assets: assets)
            #expect(await session.cachedPageIDs().count == 1)
            #expect(await session.cachedResourcePaths().isEmpty)
            let timings = await session.preparationTimings()
            print("PREVIEW PROFILE pages=\(pageCount) assetMiB=\(assetCount * 2) full=\(fullTime) fullStages=\(stages) onDemand=\(timings)")
            let server = PreviewServer()
            do {
                let serverStart = ContinuousClock.now
                let url = try await server.publish(.onDemand(session), notifyingClients: false)
                let serverTime = serverStart.duration(to: .now)
                let probe = PreviewBrowserProbe()
                let sessionID = UUID()
                let initialURL = try #require(URL(string: "?__foundry_session=\(sessionID.uuidString)", relativeTo: url))
                let loadTime = try await probe.load(initialURL)
                let nextURL = pageCount > 1 ? url.appending(path: "page-1/") : initialURL
                let reloadTime = try await probe.load(nextURL)
                print("PREVIEW BROWSER pages=\(pageCount) startServer=\(serverTime) firstWebKitLoad=\(loadTime) navigateAndLoad=\(reloadTime)")
                if let asset = site.assets.first {
                    let path = site.publishedPath(for: asset)
                    #expect(await session.cachedResourcePaths().contains(path) == false)
                    let (data, response) = try await URLSession.shared.data(from: url.appending(path: path))
                    #expect((response as? HTTPURLResponse)?.statusCode == 200)
                    #expect(data == payload)
                    #expect(await session.cachedResourcePaths().contains(path))
                }
                #expect(full.fingerprints.isEmpty == false)
                await server.stop()
            } catch {
                await server.stop()
                throw error
            }
        }
    }
}
