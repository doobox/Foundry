import Foundation
import Testing
@testable import Foundry

@MainActor
struct IncrementalPreviewTests {
    private func document() -> FoundryDocument {
        _ = PartPackageCatalog.shared
        let pages = (0..<3).map { index in
            var part = PartNode.make(.init(rawValue: "foundry.content.html"))
            part.setProperty(.init(rawValue: "content"), value: "<div>Page \(index)</div>")
            return Page(title: "Page \(index)", slug: index == 0 ? "index" : "page-\(index)", parts: [part])
        }
        return FoundryDocument(site: Site(name: "Incremental", pages: pages))
    }

    private func identity(_ document: FoundryDocument, package: Int = 1) -> PreviewBuildIdentity {
        .init(siteID: document.site.id, documentRevision: document.mutationEvent.revision,
              packageRevision: package, assetRevision: document.assetRevision)
    }

    private func build(_ document: FoundryDocument, previous: PreviewDiskSnapshot? = nil, package: Int = 1) throws -> PreviewDiskSnapshot {
        try StaticSiteRenderer(environment: .preview).previewSnapshot(
            site: document.site, assets: document.assetContents, identity: identity(document, package: package),
            invalidation: document.previewInvalidation, previous: previous)
    }

    private func edit(_ document: FoundryDocument, page index: Int, text: String) {
        var site = document.site
        let id = site.pages[index].parts[0].id
        site.updatePart(id: id) { $0.setProperty(.init(rawValue: "content"), value: "<div>\(text)</div>") }
        document.replaceSite(with: site, undoManager: nil, actionName: "Edit",
                             impact: .partProperty(partID: id, propertyKey: .init(rawValue: "content")))
    }

    @Test func localEditRebuildsOnlyItsPageAndMatchesFullOutput() throws {
        let document = document()
        let first = try build(document)
        #expect(first.reusedPageIDs.isEmpty)
        edit(document, page: 1, text: "Changed")
        let next = try build(document, previous: first)
        #expect(next.reusedPageIDs == Set([document.site.pages[0].id, document.site.pages[2].id]))
        let full = try build(document)
        #expect(next.fingerprints == full.fingerprints)
        #expect(try String(contentsOf: next.root.appending(path: "page-1/index.html"), encoding: .utf8).contains("Changed"))
    }

    @Test func editsAfterBuildCaptureRemainDirtyAndMultipleEditsAccumulate() throws {
        let document = document()
        let first = try build(document)
        edit(document, page: 0, text: "First edit")
        let capturedSite = document.site
        let capturedIdentity = identity(document)
        let capturedInvalidation = document.previewInvalidation
        edit(document, page: 1, text: "Later edit")
        edit(document, page: 2, text: "Another edit")
        let inFlight = try StaticSiteRenderer(environment: .preview).previewSnapshot(
            site: capturedSite, assets: document.assetContents, identity: capturedIdentity,
            invalidation: capturedInvalidation, previous: first)
        let next = try build(document, previous: inFlight)
        #expect(next.reusedPageIDs == [document.site.pages[0].id])
        #expect(next.fingerprints == (try build(document)).fingerprints)
        // A failed/cancelled build would retain the older checkpoint instead.
        #expect(try build(document, previous: first).reusedPageIDs.isEmpty)
    }

    @Test func pageDeletionAndRenameRemoveObsoleteFiles() throws {
        let document = document()
        let first = try build(document)
        var site = document.site
        site.pages.removeLast()
        site.pages[1].slug = "renamed"
        document.replaceSite(with: site, undoManager: nil, actionName: "Change pages", impact: .page)
        let next = try build(document, previous: first)
        #expect(next.reusedPageIDs.isEmpty)
        #expect(next.fingerprints.keys.contains { $0.hasPrefix("page-1/") || $0.hasPrefix("page-2/") } == false)
        #expect(next.fingerprints == (try build(document)).fingerprints)
    }

    @Test func undoMarksTheEditedPageDirtyAgain() throws {
        let document = document()
        let first = try build(document)
        let undo = UndoManager()
        let id = document.site.pages[1].parts[0].id
        var site = document.site
        site.updatePart(id: id) { $0.setProperty(.init(rawValue: "content"), value: "<div>Changed</div>") }
        undo.beginUndoGrouping()
        document.replaceSite(with: site, undoManager: undo, actionName: "Edit",
                             impact: .partProperty(partID: id, propertyKey: .init(rawValue: "content")))
        undo.endUndoGrouping()
        let edited = try build(document, previous: first)
        undo.undo()
        let restored = try build(document, previous: edited)
        #expect(restored.reusedPageIDs.count == 2)
        #expect(restored.fingerprints == first.fingerprints)
    }

    @Test func packageChangesInvalidateAllPages() throws {
        let document = document()
        let first = try build(document)
        #expect(try build(document, previous: first, package: 2).reusedPageIDs.isEmpty)
    }

    @Test func singlePageEditBenchmark() throws {
        _ = PartPackageCatalog.shared
        let pages = (0..<10).map { index in
            Page(title: "Page \(index)", slug: index == 0 ? "index" : "page-\(index)",
                 parts: (0..<10).map { _ in PartNode.make(.button) })
        }
        let document = FoundryDocument(site: Site(name: "Benchmark", pages: pages))
        let first = try build(document)
        var site = document.site
        let partID = site.pages[4].parts[0].id
        site.updatePart(id: partID) { $0.setProperty(.init(rawValue: "variant"), value: "btn-outline") }
        document.replaceSite(with: site, undoManager: nil, actionName: "Change button",
                             impact: .partProperty(partID: partID, propertyKey: .init(rawValue: "variant")))
        let fullStart = ContinuousClock.now
        let full = try PreviewDiskSnapshot.build(previous: first) {
            try StaticSiteRenderer(environment: .preview).generate(site: document.site, assets: document.assetContents, emit: $0)
        }
        let fullDuration = fullStart.duration(to: .now)
        let incrementalStart = ContinuousClock.now
        let incremental = try build(document, previous: first)
        let incrementalDuration = incrementalStart.duration(to: .now)
        #expect(incremental.reusedPageIDs.count == 9)
        #expect(incremental.fingerprints == full.fingerprints)
        print("Edited-page preview benchmark (10 pages, 100 buttons): full=\(fullDuration), incremental=\(incrementalDuration), reused=\(incremental.reusedPageIDs.count)")
    }

    @Test(arguments: [ProjectMutationImpact.theme, .assets, .page, .package])
    func sharedChangesInvalidateAllPages(_ impact: ProjectMutationImpact) {
        let document = document()
        var invalidation = PreviewInvalidation()
        invalidation.record(impact, in: document.site, revision: 2)
        #expect(invalidation.dirtyPages(since: 1) == nil)
        #expect(invalidation.dirtyPages(since: 2) == [])
    }
}
