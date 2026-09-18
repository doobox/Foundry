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
    func publishingPlanReusesTrustedAssetFingerprints() {
        let originalData = Data(repeating: 0x11, count: 1_000_000)
        let replacementData = Data(repeating: 0x22, count: 1_000_000)
        let fingerprint = "known-document-digest"
        let original = SiteExportBundle(files: [
            .init(path: "assets/image.bin", data: originalData, contentFingerprint: fingerprint)
        ])
        let manifest = PublishingPlan.make(
            bundle: original,
            previous: nil,
            removesObsoleteFiles: true
        ).nextManifest
        let current = SiteExportBundle(files: [
            .init(path: "assets/image.bin", data: replacementData, contentFingerprint: fingerprint)
        ])

        let plan = PublishingPlan.make(bundle: current, previous: manifest, removesObsoleteFiles: true)

        #expect(plan.uploads.isEmpty)
        #expect(plan.unchangedFileCount == 1)
        #expect(plan.nextManifest.files["assets/image.bin"] == fingerprint)
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
    func publishingPlanCanRemoveObsoleteManagedWebIconsIndependently() {
        let iconPath = "assets/web-icons/favicon.ico"
        let previous = PublishingManifest(files: [
            "index.html": "old-page",
            iconPath: "old-icon"
        ])
        let bundle = SiteExportBundle(files: [.init(path: "index.html", contents: "new")])

        let plan = PublishingPlan.make(
            bundle: bundle,
            previous: previous,
            removesObsoleteFiles: false,
            removesManagedSiteAssets: true
        )

        #expect(plan.removals == [iconPath])
        #expect(plan.removalHashes == [iconPath: "old-icon"])
        #expect(plan.nextManifest.files[iconPath] == nil)
        #expect(plan.nextManifest.files["index.html"] != nil)
    }

    @Test
    func publishingPlanCanRemoveAnObsoleteManagedSiteLogoIndependently() {
        let logoPath = "assets/site-logo/site-logo.png"
        let previous = PublishingManifest(files: [
            "index.html": "old-page",
            logoPath: "old-logo"
        ])
        let bundle = SiteExportBundle(files: [.init(path: "index.html", contents: "new")])

        let plan = PublishingPlan.make(
            bundle: bundle,
            previous: previous,
            removesObsoleteFiles: false,
            removesManagedSiteAssets: true
        )

        #expect(plan.removals == [logoPath])
        #expect(plan.removalHashes == [logoPath: "old-logo"])
        #expect(plan.nextManifest.files[logoPath] == nil)
        #expect(plan.nextManifest.files["index.html"] != nil)
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
    func publishingManifestCanBeRemovedToMarkEverythingChanged() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PublishingManifestStore(directory: directory)
        let site = Site.starter()

        try store.save(PublishingManifest(files: ["index.html": "hash"]), for: site)
        try store.remove(for: site)

        #expect(store.load(for: site) == nil)
    }

    @Test
    func localPublishingHonorsChangedAndUnchangedManifestState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        var site = Site.starter()
        site.publishingDestination = .local
        let store = PublishingManifestStore()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? store.remove(for: site, localDirectory: directory)
        }
        let bundle = SiteExportBundle(files: [
            .init(path: "index.html", contents: "published")
        ])
        let publisher = SitePublisher()

        let firstResult = try await publisher.publish(
            bundle: bundle,
            site: site,
            localDirectory: directory,
            credential: "",
            progress: { _ in }
        )
        let outputURL = directory.appending(path: "index.html")
        try Data("locally edited".utf8).write(to: outputURL)

        let unchangedResult = try await publisher.publish(
            bundle: bundle,
            site: site,
            localDirectory: directory,
            credential: "",
            progress: { _ in }
        )
        let skippedContents = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)

        try store.remove(for: site, localDirectory: directory)
        let changedResult = try await publisher.publish(
            bundle: bundle,
            site: site,
            localDirectory: directory,
            credential: "",
            progress: { _ in }
        )
        let republishedContents = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)

        #expect(firstResult.uploadedFileCount == 1)
        #expect(unchangedResult.uploadedFileCount == 0)
        #expect(unchangedResult.unchangedFileCount == 1)
        #expect(skippedContents == "locally edited")
        #expect(changedResult.uploadedFileCount == 1)
        #expect(republishedContents == "published")
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
    func publishingChangesNeverResolveAssetBytesWhenAFingerprintIsPresent() {
        let counter = ResolveCounter()
        let file = SiteExportFile(
            path: "assets/example.png",
            fingerprint: "digest-abc",
            resolve: {
                counter.increment()
                return Data("should not be read".utf8)
            }
        )
        let bundle = SiteExportBundle(files: [file])

        let changes = PublishingPlan.changes(bundle: bundle, previous: nil)

        #expect(changes["assets/example.png"] == .new)
        #expect(counter.count == 0, "Diffing by fingerprint must never resolve the file's bytes.")
    }

    @Test
    func publishingPlanMakeNeverResolvesUnchangedAssetBytes() {
        let counter = ResolveCounter()
        let file = SiteExportFile(
            path: "assets/example.png",
            fingerprint: "digest-abc",
            resolve: {
                counter.increment()
                return Data("should not be read".utf8)
            }
        )
        let bundle = SiteExportBundle(files: [file])
        let previous = PublishingManifest(files: ["assets/example.png": "digest-abc"])

        let plan = PublishingPlan.make(bundle: bundle, previous: previous, removesObsoleteFiles: true)

        #expect(plan.uploads.isEmpty)
        #expect(plan.unchangedFileCount == 1)
        #expect(counter.count == 0, "An unchanged file's bytes should never be resolved while planning a publish.")
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

private final class ResolveCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}
