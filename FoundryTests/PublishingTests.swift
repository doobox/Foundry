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
    func publishingManifestRoundTripsForDestination() {
        let archive = PublishingManifestArchive()
        var site = Site.starter()
        site.publishingDestination = .sftp
        site.publishingHost = "example.com"
        let manifest = PublishingManifest(files: ["index.html": "hash"])

        archive.setManifest(manifest, for: site, destinationID: nil)

        #expect(archive.manifest(for: site, destinationID: nil) == manifest)
    }

    @Test
    func remotePublishingManifestIgnoresAnUnrelatedLocalDirectory() {
        let archive = PublishingManifestArchive()
        var site = Site.starter()
        site.publishingDestination = .sftp
        site.publishingHost = "example.com"
        let destinationID = UUID()
        let manifest = PublishingManifest(files: ["index.html": "hash"])

        archive.setManifest(
            manifest,
            for: site,
            destinationID: destinationID,
            localDirectory: URL(filePath: "/tmp/unrelated")
        )

        #expect(archive.manifest(
            for: site,
            destinationID: destinationID,
            localDirectory: nil
        ) == manifest)
    }

    @Test
    func publishingStatusUsesDefaultDestinationIdentity() {
        let archive = PublishingManifestArchive()
        let destination = PublishingDestination(
            name: "Production",
            kind: .sftp,
            host: "example.com",
            port: 22,
            username: "publisher",
            remotePath: "/public"
        )
        var publishedSite = Site.starter()
        publishedSite.publishingDestinations = [destination]
        publishedSite.defaultPublishingDestinationID = destination.id
        publishedSite.synchronizeLegacyPublishingFields()
        let manifest = PublishingManifest(files: ["index.html": "hash"])
        archive.setManifest(manifest, for: publishedSite, destinationID: destination.id)

        var statusSite = publishedSite
        statusSite.publishingDestination = .local
        statusSite.publishingHost = "stale.example.com"
        #expect(archive.manifest(for: statusSite, destinationID: destination.id) == nil)

        statusSite.synchronizeLegacyPublishingFields()
        #expect(archive.manifest(for: statusSite, destinationID: destination.id) == manifest)
    }

    @Test
    func publishingManifestCanBeRemovedToMarkEverythingChanged() {
        let archive = PublishingManifestArchive()
        let site = Site.starter()

        archive.setManifest(PublishingManifest(files: ["index.html": "hash"]), for: site, destinationID: nil)
        archive.removeManifest(for: site, destinationID: nil)

        #expect(archive.manifest(for: site, destinationID: nil) == nil)
    }

    @Test
    func publishingManifestArchiveKeepsEveryDestinationSeparate() {
        let archive = PublishingManifestArchive()
        var site = Site.starter()
        let destinationIDs = (0..<200).map { _ in UUID() }

        for (index, destinationID) in destinationIDs.enumerated() {
            archive.setManifest(
                PublishingManifest(files: ["index.html": "hash-\(index)"]),
                for: site,
                destinationID: destinationID
            )
        }
        site.publishingHost = "new.example.com"
        let replacement = PublishingManifest(files: ["index.html": "replacement"])
        archive.setManifest(replacement, for: site, destinationID: destinationIDs[0])

        #expect(archive.fileContents.count == 200)
        #expect(archive.manifest(for: site, destinationID: destinationIDs[0]) == replacement)
        #expect(archive.manifest(for: site, destinationID: destinationIDs[199]) == nil)
    }

    @Test
    func publishingManifestsRoundTripThroughTheDocumentPackage() throws {
        var site = Site.starter()
        site.publishingDestination = .sftp
        site.publishingHost = "example.com"
        let destinationID = UUID()
        let manifest = PublishingManifest(files: ["index.html": "hash"])
        let snapshot = FoundryDocumentSnapshot(site: site)
        snapshot.publishingManifests.setManifest(manifest, for: site, destinationID: destinationID)

        let wrapper = try FoundryDocument.makeFileWrapper(snapshot: snapshot, existingFile: nil)
        let decoded = try FoundryDocument.decodeSnapshot(from: wrapper)

        #expect(decoded.publishingManifests.manifest(for: site, destinationID: destinationID) == manifest)
    }

    @Test
    func localPublishingHonorsChangedAndUnchangedManifestState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        var site = Site.starter()
        site.publishingDestination = .local
        let archive = PublishingManifestArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = SiteExportBundle(files: [
            .init(path: "index.html", contents: "published")
        ])
        let publisher = SitePublisher()

        let firstResult = try await publisher.publish(
            bundle: bundle,
            site: site,
            manifests: archive,
            localDirectory: directory,
            credential: "",
            progress: { _ in }
        )
        let outputURL = directory.appending(path: "index.html")
        try Data("locally edited".utf8).write(to: outputURL)

        let unchangedResult = try await publisher.publish(
            bundle: bundle,
            site: site,
            manifests: archive,
            localDirectory: directory,
            credential: "",
            progress: { _ in }
        )
        let skippedContents = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)

        archive.removeManifest(for: site, destinationID: nil)
        let changedResult = try await publisher.publish(
            bundle: bundle,
            site: site,
            manifests: archive,
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
    func localPublishingDestinationsKeepSeparateManifests() {
        let archive = PublishingManifestArchive()
        var site = Site.starter()
        site.publishingDestination = .local
        let firstDestinationID = UUID()
        let secondDestinationID = UUID()
        let firstDestination = URL(filePath: "/tmp/first")
        let secondDestination = URL(filePath: "/tmp/second")
        let manifest = PublishingManifest(files: ["index.html": "hash"])

        archive.setManifest(
            manifest,
            for: site,
            destinationID: firstDestinationID,
            localDirectory: firstDestination
        )

        #expect(archive.manifest(
            for: site,
            destinationID: firstDestinationID,
            localDirectory: firstDestination
        ) == manifest)
        #expect(archive.manifest(
            for: site,
            destinationID: secondDestinationID,
            localDirectory: secondDestination
        ) == nil)
    }
}

private final class ResolveCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}
