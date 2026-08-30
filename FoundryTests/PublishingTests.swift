import Foundation
import Testing
@testable import Foundry

@Suite("Publishing")
struct PublishingTests {
    @Test
    func embeddedTransportIncludesSecurePublishingBackends() {
        let version = SitePublisher.transportVersion

        #expect(version.contains("libcurl/8.16.0"))
        #expect(version.contains("libssh2/1.11.1"))
        #expect(version.contains("mbedTLS/3.6.4"))
    }

    @Test
    func sftpRelativePathsResolveFromTheAccountHomeDirectory() {
        var site = Site.starter()
        site.publishingDestination = .sftp
        site.publishingHost = "ftp.example.com"
        site.publishingPort = 722
        site.publishingRemotePath = "public_html/test-site"

        let url = PublishingRemoteURLBuilder.url(site: site, relativePath: "index.html", testOnly: false)

        #expect(url == "sftp://ftp.example.com:722/~/public_html/test-site/index.html")
    }

    @Test
    func explicitLeadingSlashProducesAnAbsoluteSFTPPath() {
        var site = Site.starter()
        site.publishingDestination = .sftp
        site.publishingHost = "ftp.example.com"
        site.publishingRemotePath = "/srv/www"

        let url = PublishingRemoteURLBuilder.url(site: site, relativePath: "index.html", testOnly: false)

        #expect(url == "sftp://ftp.example.com:22/srv/www/index.html")
    }

    @Test
    func publishingPlanUploadsOnlyNewAndChangedFiles() {
        let previous = PublishingManifest(files: [
            "index.html": PublishingPlan.make(
                bundle: SiteExportBundle(files: [.init(path: "index.html", contents: "same")]),
                previous: nil,
                removesObsoleteFiles: false
            ).nextManifest.files["index.html"]!,
            "old.html": "old-hash"
        ])
        let bundle = SiteExportBundle(files: [
            .init(path: "index.html", contents: "same"),
            .init(path: "about.html", contents: "new")
        ])

        let plan = PublishingPlan.make(bundle: bundle, previous: previous, removesObsoleteFiles: false)

        #expect(plan.uploads.map(\.path) == ["about.html"])
        #expect(plan.unchangedFileCount == 1)
        #expect(plan.removals.isEmpty)
        #expect(plan.nextManifest.files["old.html"] == "old-hash")
    }

    @Test
    func publishingPlanRemovesOnlyPreviouslyManagedObsoleteFiles() {
        let previous = PublishingManifest(files: ["index.html": "changed", "old.html": "old-hash"])
        let bundle = SiteExportBundle(files: [.init(path: "index.html", contents: "new")])

        let plan = PublishingPlan.make(bundle: bundle, previous: previous, removesObsoleteFiles: true)

        #expect(plan.uploads.map(\.path) == ["index.html"])
        #expect(plan.removals == ["old.html"])
        #expect(plan.nextManifest.files.keys.sorted() == ["index.html"])
    }

    @Test
    func publishingManifestRoundTripsForDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PublishingManifestStore(directory: directory)
        var site = Site.starter()
        site.publishingDestination = .sftp
        site.publishingHost = "example.com"
        let manifest = PublishingManifest(files: ["index.html": "hash"])

        try store.save(manifest, for: site)

        #expect(store.load(for: site) == manifest)
    }

    @Test
    func publishingChangesDistinguishNewModifiedAndUnchangedFiles() {
        let original = SiteExportBundle(files: [
            .init(path: "unchanged.html", contents: "same"),
            .init(path: "modified.html", contents: "old")
        ])
        let manifest = PublishingPlan.make(
            bundle: original,
            previous: nil,
            removesObsoleteFiles: true
        ).nextManifest
        let current = SiteExportBundle(files: [
            .init(path: "unchanged.html", contents: "same"),
            .init(path: "modified.html", contents: "new"),
            .init(path: "new.html", contents: "new")
        ])

        let changes = PublishingPlan.changes(bundle: current, previous: manifest)

        #expect(changes["unchanged.html"] == nil)
        #expect(changes["modified.html"] == .modified)
        #expect(changes["new.html"] == .new)
    }

    @Test
    func localPublishingDestinationsKeepSeparateManifests() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PublishingManifestStore(directory: directory)
        var site = Site.starter()
        site.publishingDestination = .local
        let firstDestination = URL(filePath: "/tmp/first")
        let secondDestination = URL(filePath: "/tmp/second")
        let manifest = PublishingManifest(files: ["index.html": "hash"])

        try store.save(manifest, for: site, localDirectory: firstDestination)

        #expect(store.load(for: site, localDirectory: firstDestination) == manifest)
        #expect(store.load(for: site, localDirectory: secondDestination) == nil)
    }
}
