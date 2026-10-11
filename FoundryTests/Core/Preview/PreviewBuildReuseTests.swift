import Foundation
import Testing
@testable import Foundry

struct PreviewBuildReuseTests {
    private let identity = PreviewBuildIdentity(siteID: UUID(), documentRevision: 1, packageRevision: 1)

    @Test func unchangedPreviewSkipsGeneratorAndKeepsFiles() throws {
        let first = try PreviewDiskSnapshot.build(identity: identity) {
            try $0(.init(path: "index.html", contents: "Original"))
        }
        var generated = false
        let second = try PreviewDiskSnapshot.build(previous: first, identity: identity) { _ in generated = true }
        #expect(generated == false)
        #expect(second === first)
        #expect(try String(contentsOf: second.root.appending(path: "index.html"), encoding: .utf8) == "Original")
    }

    @Test(arguments: [0, 1, 2, 3])
    func changedInputsRebuild(input: Int) throws {
        let first = try PreviewDiskSnapshot.build(identity: identity) {
            try $0(.init(path: "index.html", contents: "Before"))
        }
        let changed = PreviewBuildIdentity(
            siteID: input == 0 ? UUID() : identity.siteID,
            documentRevision: input == 1 ? 2 : 1,
            packageRevision: input == 2 ? 2 : 1,
            assetRevision: input == 3 ? 1 : 0
        )
        var generated = false
        let second = try PreviewDiskSnapshot.build(previous: first, identity: changed) {
            generated = true
            try $0(.init(path: "index.html", contents: "After"))
        }
        #expect(generated)
        #expect(second.root != first.root)
        #expect(try String(contentsOf: second.root.appending(path: "index.html"), encoding: .utf8) == "After")
    }

    @Test func missingIdentityAlwaysRebuilds() throws {
        let first = try PreviewDiskSnapshot.build { try $0(.init(path: "index.html", contents: "Before")) }
        var generated = false
        let second = try PreviewDiskSnapshot.build(previous: first) {
            generated = true
            try $0(.init(path: "index.html", contents: "After"))
        }
        #expect(generated)
        #expect(second.root != first.root)
    }

    @Test func phpNeverReusesPotentiallyModifiedSnapshot() throws {
        let first = try PreviewDiskSnapshot.build(identity: identity) {
            try $0(.init(path: "index.php", contents: "Original"))
        }
        try Data("Modified by PHP".utf8).write(to: first.root.appending(path: "index.php"))
        let second = try PreviewDiskSnapshot.build(previous: first, identity: identity) {
            try $0(.init(path: "index.php", contents: "Original"))
        }
        #expect(second.root != first.root)
        #expect(try String(contentsOf: second.root.appending(path: "index.php"), encoding: .utf8) == "Original")
    }

    @Test func cancelledRequestCannotReturnCachedPreview() async throws {
        let identity = identity
        let first = try PreviewDiskSnapshot.build(identity: identity) {
            try $0(.init(path: "index.html", contents: "Original"))
        }
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try PreviewDiskSnapshot.build(previous: first, identity: identity) { _ in
                Issue.record("Cancelled request must not render")
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled request must throw, even on a cache hit")
        } catch is CancellationError { }
    }

    @Test @MainActor func renderedSiteReuseBenchmark() throws {
        _ = PartPackageCatalog.shared
        let pages = (0..<10).map { index in
            Page(title: "Page \(index)", slug: index == 0 ? "index" : "page-\(index)",
                 parts: (0..<10).map { _ in PartNode.make(.button) })
        }
        let site = Site(name: "Preview benchmark", pages: pages)
        let started = ContinuousClock.now
        let first = try PreviewDiskSnapshot.build(identity: identity) {
            try StaticSiteRenderer(environment: .preview).generate(site: site, assets: [:], emit: $0)
        }
        let initialDuration = started.duration(to: .now)
        let rebuildStarted = ContinuousClock.now
        let rebuilt = try PreviewDiskSnapshot.build(previous: first) {
            try StaticSiteRenderer(environment: .preview).generate(site: site, assets: [:], emit: $0)
        }
        let rebuildDuration = rebuildStarted.duration(to: .now)
        let reuseStarted = ContinuousClock.now
        let reused = try PreviewDiskSnapshot.build(previous: first, identity: identity) { _ in
            Issue.record("Unchanged preview must not invoke the renderer")
        }
        let reuseDuration = reuseStarted.duration(to: .now)
        #expect(reused === first)
        #expect(rebuilt.fingerprints == first.fingerprints)
        #expect(first.fingerprints["index.html"] != nil)
        print("Preview benchmark (10 pages, 100 buttons): initial=\(initialDuration), unchanged old rebuild=\(rebuildDuration), reuse=\(reuseDuration)")
    }
}
