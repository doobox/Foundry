import CryptoKit
import Foundation
import Security

nonisolated struct FoundryPackUpdateConfiguration: Codable, Equatable, Sendable {
    let appcastURL: URL
    let publicKey: String

    private enum CodingKeys: String, CodingKey {
        case appcastURL
        case publicKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .appcastURL)
        guard let url = URL(string: value) else {
            throw DecodingError.dataCorruptedError(
                forKey: .appcastURL,
                in: container,
                debugDescription: "appcastURL is not a valid URL."
            )
        }
        appcastURL = url
        publicKey = try container.decode(String.self, forKey: .publicKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appcastURL.absoluteString, forKey: .appcastURL)
        try container.encode(publicKey, forKey: .publicKey)
    }
}

nonisolated struct FoundryPackMetadata: Codable, Equatable, Sendable {
    let collection: Bool
    let identifier: String?
    let title: String?
    let author: String?
    let version: String?
    let minimumAPIVersion: Int?
    let updates: FoundryPackUpdateConfiguration?

    enum CodingKeys: String, CodingKey {
        case collection
        case identifier = "id"
        case title
        case author
        case version
        case minimumAPIVersion
        case updates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collection = try container.decodeIfPresent(Bool.self, forKey: .collection) ?? false
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        minimumAPIVersion = try container.decodeIfPresent(Int.self, forKey: .minimumAPIVersion)
        updates = try container.decodeIfPresent(FoundryPackUpdateConfiguration.self, forKey: .updates)
    }
}

nonisolated struct FoundryPackAppcast: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let packID: String
    let releases: [Release]

    struct Release: Codable, Equatable, Sendable {
        let version: String
        let publishedAt: Date
        let minimumAPIVersion: Int
        let downloadURL: URL
        let releaseNotesURL: URL?
        let fileSize: Int64
        let sha256: String
        let signature: String
    }
}

nonisolated enum FoundryPackUpdateError: Error, LocalizedError {
    case invalidURL(String)
    case insecureURL(String)
    case invalidMetadata(String)
    case unsupportedAppcast(Int)
    case wrongPack(String)
    case noCompatibleRelease
    case invalidFileSize
    case invalidChecksum
    case invalidSignature
    case archiveFailed(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let field): "Enter a valid \(field) URL."
        case .insecureURL(let field): "\(field) must use HTTPS."
        case .invalidMetadata(let message): message
        case .unsupportedAppcast(let version): "This appcast uses unsupported format version \(version)."
        case .wrongPack(let identifier): "The update is for a different pack (\(identifier))."
        case .noCompatibleRelease: "No newer compatible release is available."
        case .invalidFileSize: "The downloaded update has an unexpected file size."
        case .invalidChecksum: "The downloaded update failed its SHA-256 integrity check."
        case .invalidSignature: "The downloaded update has an invalid publisher signature."
        case .archiveFailed(let message): "The release archive could not be created: \(message)"
        case .keychain(let status): "The signing identity could not be accessed in Keychain (\(status))."
        }
    }
}

nonisolated enum FoundryPackSigningIdentity {
    private static let service = "uk.co.garysimpson.Foundry.component-signing"
    private static let account = "default-publisher"

    static func privateKey() throws -> Curve25519.Signing.PrivateKey {
        var result: CFTypeRef?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        guard status == errSecItemNotFound else { throw FoundryPackUpdateError.keychain(status) }

        let key = Curve25519.Signing.PrivateKey()
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: key.rawRepresentation
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw FoundryPackUpdateError.keychain(addStatus) }
        return key
    }
}

nonisolated enum FoundryPackReleaseBuilder {
    struct Request: Sendable {
        let sourceURL: URL
        let outputDirectoryURL: URL
        let version: String
        let releaseNotes: [String]
    }

    struct Result: Sendable {
        let outputDirectoryURL: URL
        let archiveURL: URL
        let releaseMetadataURL: URL
    }

    private struct PublishedRelease: Codable {
        let formatVersion: Int
        let packID: String
        let release: FoundryPackAppcast.Release
    }

    static func prepareForUpdates(
        sourceURL: URL,
        publishingDirectoryURL: URL,
        outputDirectoryURL: URL
    ) throws -> URL {
        try requireHTTPS(publishingDirectoryURL, field: "Publishing Directory URL")
        guard publishingDirectoryURL.query == nil,
              publishingDirectoryURL.fragment == nil else {
            throw FoundryPackUpdateError.invalidURL("Publishing Directory")
        }
        _ = try FoundryPackSigningIdentity.privateKey()

        let directoryName = publishingDirectoryURL.lastPathComponent.isEmpty
            ? sourceURL.deletingPathExtension().lastPathComponent
            : publishingDirectoryURL.lastPathComponent
        let setupDirectoryURL = outputDirectoryURL.appending(
            path: directoryName,
            directoryHint: .isDirectory
        )
        let appcastFileURL = setupDirectoryURL.appending(path: "appcast.php")
        guard !FileManager.default.fileExists(atPath: appcastFileURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(
            at: setupDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data(appcastPHP.utf8).write(to: appcastFileURL, options: .atomic)
        return setupDirectoryURL
    }

    static func finalizeUpdatePreparation(sourceURL: URL, publishingDirectoryURL: URL) throws {
        try requireHTTPS(publishingDirectoryURL, field: "Publishing Directory URL")
        let key = try FoundryPackSigningIdentity.privateKey()
        try writeUpdateConfiguration(
            appcastURL: publishingDirectoryURL.appending(path: "appcast.php"),
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            manifestURL: sourceURL.appending(path: "Contents/Info.plist")
        )
    }

    static func create(_ request: Request) async throws -> Result {
        let releaseNotes = request.releaseNotes.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !releaseNotes.isEmpty, releaseNotes.allSatisfy({ !$0.isEmpty }) else {
            throw FoundryPackUpdateError.invalidMetadata("Add at least one release note.")
        }

        let pack = try FoundryPackLoader.load(from: request.sourceURL)
        let version = request.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let identifier = pack.identifier, !identifier.isEmpty,
              let sourceVersionString = pack.metadata.version,
              let sourceVersion = SemanticVersion(sourceVersionString),
              let releaseVersion = SemanticVersion(version),
              releaseVersion > sourceVersion else {
            throw FoundryPackUpdateError.invalidMetadata("The release version must be greater than the development pack version.")
        }

        guard let configuration = pack.metadata.updates else {
            throw FoundryPackUpdateError.invalidMetadata("Prepare this pack for updates before issuing a release.")
        }
        try requireHTTPS(configuration.appcastURL, field: "Appcast URL")

        let publishedReleases = try await existingReleases(at: configuration.appcastURL, packID: identifier)
        let publishedVersions = try publishedReleases.map { release -> SemanticVersion in
            guard let version = SemanticVersion(release.version) else {
                throw FoundryPackUpdateError.invalidMetadata("The published appcast contains an invalid semantic version.")
            }
            return version
        }
        guard publishedVersions.allSatisfy({ $0 < releaseVersion }) else {
            throw FoundryPackUpdateError.invalidMetadata("The release version must be greater than every published version.")
        }

        let key = try FoundryPackSigningIdentity.privateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        guard configuration.publicKey == publicKey else {
            throw FoundryPackUpdateError.invalidSignature
        }

        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory.appending(
            path: "Foundry-Release-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let releasePackURL = stagingRoot
            .appending(path: request.sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("foundrypack")
        try fileManager.copyItem(at: request.sourceURL, to: releasePackURL)
        try writePackVersion(version, manifestURL: releasePackURL.appending(path: "Contents/Info.plist"))

        let publishingDirectoryURL = configuration.appcastURL.deletingLastPathComponent()
        let releaseDirectoryName = "\(identifier) \(version)"
        let releaseDirectoryURL = request.outputDirectoryURL.appending(
            path: releaseDirectoryName,
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: releaseDirectoryURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fileManager.createDirectory(at: releaseDirectoryURL, withIntermediateDirectories: true)

        let archiveFilename = "\(identifier) \(version).foundrypack.zip"
        let archiveURL = releaseDirectoryURL.appending(path: archiveFilename)
        let hostedReleaseDirectoryURL = publishingDirectoryURL.appending(path: releaseDirectoryName)
        let downloadURL = hostedReleaseDirectoryURL.appending(path: archiveFilename)
        let releaseNotesURL = hostedReleaseDirectoryURL.appending(path: "release-notes.html")
        let publishedAt = Date()

        try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", releasePackURL.path, archiveURL.path])
        let archiveData = try Data(contentsOf: archiveURL)
        let signature = try key.signature(for: archiveData).base64EncodedString()
        let digest = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        let release = FoundryPackAppcast.Release(
            version: version,
            publishedAt: publishedAt,
            minimumAPIVersion: pack.metadata.minimumAPIVersion ?? FoundryComponentAPI.currentVersion,
            downloadURL: downloadURL,
            releaseNotesURL: releaseNotesURL,
            fileSize: Int64(archiveData.count),
            sha256: digest,
            signature: signature
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let releaseMetadataURL = releaseDirectoryURL.appending(path: "release.json")
        try encoder.encode(
            PublishedRelease(
                formatVersion: FoundryPackAppcast.currentFormatVersion,
                packID: identifier,
                release: release
            )
        ).write(to: releaseMetadataURL, options: .atomic)

        let latestNotesURL = publishedReleases.max { left, right in
            guard let leftVersion = SemanticVersion(left.version),
                  let rightVersion = SemanticVersion(right.version) else { return false }
            return leftVersion < rightVersion
        }?.releaseNotesURL
        let existingSections = if let latestNotesURL {
            try await existingReleaseNotes(at: latestNotesURL)
        } else {
            ""
        }
        let releaseNotesHTML = releaseNotesHTML(
            packTitle: pack.metadata.title ?? request.sourceURL.deletingPathExtension().lastPathComponent,
            version: version,
            publishedAt: publishedAt,
            notes: releaseNotes,
            existingSections: existingSections
        )
        try Data(releaseNotesHTML.utf8).write(
            to: releaseDirectoryURL.appending(path: "release-notes.html"),
            options: .atomic
        )

        return Result(
            outputDirectoryURL: releaseDirectoryURL,
            archiveURL: archiveURL,
            releaseMetadataURL: releaseMetadataURL
        )
    }

    private static let appcastPHP = #"""
    <?php
    declare(strict_types=1);

    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $packID = null;
    $releasesByVersion = [];

    foreach (glob(__DIR__ . '/*/release.json') ?: [] as $releaseFile) {
        $payload = json_decode((string) file_get_contents($releaseFile), true);
        if (!is_array($payload)
            || ($payload['formatVersion'] ?? null) !== 1
            || !is_string($payload['packID'] ?? null)
            || !is_array($payload['release'] ?? null)) {
            continue;
        }

        if ($packID === null) {
            $packID = $payload['packID'];
        }
        if ($payload['packID'] !== $packID) {
            continue;
        }
        $version = (string) ($payload['release']['version'] ?? '');
        if ($version === '' || isset($releasesByVersion[$version])) {
            continue;
        }
        $releasesByVersion[$version] = $payload['release'];
    }

    $releases = array_values($releasesByVersion);

    usort($releases, static function (array $left, array $right): int {
        return version_compare((string) ($right['version'] ?? ''), (string) ($left['version'] ?? ''));
    });

    echo json_encode([
        'formatVersion' => 1,
        'packID' => $packID ?? '',
        'releases' => $releases,
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    """#

    private static let releasesStartMarker = "<!-- FOUNDRY_RELEASES_START -->"
    private static let releasesEndMarker = "<!-- FOUNDRY_RELEASES_END -->"

    private static func releaseNotesURL(baseURL: URL, version: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.fragment = versionAnchor(version)
        return components?.url ?? baseURL
    }

    private static func existingReleaseNotes(at url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8),
              let start = html.range(of: releasesStartMarker),
              let end = html.range(of: releasesEndMarker),
              start.upperBound <= end.lowerBound else {
            throw FoundryPackUpdateError.invalidMetadata("The existing release notes could not be read safely.")
        }
        return String(html[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func releaseNotesHTML(
        packTitle: String,
        version: String,
        publishedAt: Date,
        notes: [String],
        existingSections: String
    ) -> String {
        let items = notes.map { "<li>\(escapeHTML($0))</li>" }.joined(separator: "\n                    ")
        let newSection = """
                <section class="release" id="\(versionAnchor(version))">
                    <div class="release-heading">
                        <h2>Version \(escapeHTML(version))</h2>
                        <time datetime="\(publishedAt.ISO8601Format())">\(String(publishedAt.ISO8601Format().prefix(10)))</time>
                    </div>
                    <ul>
                        \(items)
                    </ul>
                </section>
        """
        let sections = existingSections.isEmpty
            ? newSection
            : newSection + "\n" + existingSections

        return """
        <!doctype html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(escapeHTML(packTitle)) Release Notes</title>
            <style>
                :root { color-scheme: light dark; }
                body {
                    max-width: 760px;
                    margin: 0 auto;
                    padding: 48px 24px 72px;
                    color: CanvasText;
                    background: Canvas;
                    font: 16px/1.6 system-ui, -apple-system, sans-serif;
                }
                header { margin-bottom: 40px; }
                h1, h2 { line-height: 1.2; }
                h1 { margin: 0; font-size: clamp(2rem, 6vw, 3rem); }
                header p, time { color: color-mix(in srgb, CanvasText 62%, transparent); }
                .release { padding: 24px 0; border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); }
                .release-heading { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; }
                .release-heading h2 { margin: 0; }
                li + li { margin-top: 8px; }
                @media (max-width: 520px) {
                    .release-heading { display: block; }
                }
            </style>
        </head>
        <body>
            <header>
                <h1>\(escapeHTML(packTitle))</h1>
                <p>Release notes and update history</p>
            </header>
            <main>
                \(releasesStartMarker)
        \(sections)
                \(releasesEndMarker)
            </main>
        </body>
        </html>
        """
    }

    private static func versionAnchor(_ version: String) -> String {
        "version-" + version.map { character in
            character.isLetter || character.isNumber ? String(character).lowercased() : "-"
        }.joined()
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func existingReleases(at url: URL, packID: String) async throws -> [FoundryPackAppcast.Release] {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FoundryPackUpdateError.invalidMetadata("The existing appcast could not be reached.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let appcast = try decoder.decode(FoundryPackAppcast.self, from: data)
        guard appcast.formatVersion == FoundryPackAppcast.currentFormatVersion else {
            throw FoundryPackUpdateError.unsupportedAppcast(appcast.formatVersion)
        }
        guard appcast.packID.isEmpty || appcast.packID == packID else {
            throw FoundryPackUpdateError.wrongPack(appcast.packID)
        }
        return appcast.releases
    }

    private static func requireHTTPS(_ url: URL, field: String) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw FoundryPackUpdateError.insecureURL(field)
        }
    }

    private static func writeUpdateConfiguration(appcastURL: URL, publicKey: String, manifestURL: URL) throws {
        let data = try Data(contentsOf: manifestURL)
        guard var dictionary = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw FoundryPackUpdateError.invalidMetadata("The pack Info.plist is not a dictionary.")
        }
        dictionary["updates"] = ["appcastURL": appcastURL.absoluteString, "publicKey": publicKey]
        let output = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try output.write(to: manifestURL, options: .atomic)
    }

    private static func writePackVersion(_ version: String, manifestURL: URL) throws {
        let data = try Data(contentsOf: manifestURL)
        guard var dictionary = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw FoundryPackUpdateError.invalidMetadata("The pack Info.plist is not a dictionary.")
        }
        dictionary["version"] = version
        let output = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try output.write(to: manifestURL, options: .atomic)
    }

    private static func runDitto(arguments: [String]) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw FoundryPackUpdateError.archiveFailed(String(decoding: data, as: UTF8.self))
        }
    }
}

nonisolated enum FoundryPackUpdateVerifier {
    static func newestRelease(
        in appcast: FoundryPackAppcast,
        packID: String,
        currentVersion: String
    ) throws -> FoundryPackAppcast.Release {
        guard appcast.formatVersion == FoundryPackAppcast.currentFormatVersion else {
            throw FoundryPackUpdateError.unsupportedAppcast(appcast.formatVersion)
        }
        guard appcast.packID == packID else { throw FoundryPackUpdateError.wrongPack(appcast.packID) }
        guard let current = SemanticVersion(currentVersion) else {
            throw FoundryPackUpdateError.invalidMetadata("The installed pack version is not semantic.")
        }
        let compatible = appcast.releases.filter {
            $0.minimumAPIVersion <= FoundryComponentAPI.currentVersion
                && SemanticVersion($0.version).map { current < $0 } == true
        }
        guard let release = compatible.max(by: {
            guard let lhs = SemanticVersion($0.version), let rhs = SemanticVersion($1.version) else { return false }
            return lhs < rhs
        }) else { throw FoundryPackUpdateError.noCompatibleRelease }
        return release
    }

    static func verify(_ data: Data, release: FoundryPackAppcast.Release, publicKey: String) throws {
        guard data.count == release.fileSize else { throw FoundryPackUpdateError.invalidFileSize }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(release.sha256) == .orderedSame else {
            throw FoundryPackUpdateError.invalidChecksum
        }
        guard let keyData = Data(base64Encoded: publicKey),
              let signature = Data(base64Encoded: release.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(signature, for: data) else {
            throw FoundryPackUpdateError.invalidSignature
        }
    }
}

@MainActor
enum FoundryPackUpdater {
    nonisolated struct AvailableUpdate: Identifiable, Sendable {
        let sourceURL: URL
        let packID: String
        let title: String
        let currentVersion: String
        let release: FoundryPackAppcast.Release

        var id: String { "\(packID)|\(sourceURL.standardizedFileURL.path)" }
    }

    static func check(for sourceURL: URL) async throws -> AvailableUpdate {
        let installedPack = try await Task.detached(priority: .utility) {
            try FoundryPackLoader.load(from: sourceURL)
        }.value
        guard let packID = installedPack.identifier,
              let currentVersion = installedPack.metadata.version,
              let configuration = installedPack.metadata.updates else {
            throw FoundryPackUpdateError.invalidMetadata("This pack does not declare update information.")
        }
        guard configuration.appcastURL.scheme?.lowercased() == "https" else {
            throw FoundryPackUpdateError.insecureURL("Appcast URL")
        }
        let (appcastData, appcastResponse) = try await fetchFreshData(from: configuration.appcastURL)
        try requireSuccessfulHTTP(appcastResponse)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let appcast = try decoder.decode(FoundryPackAppcast.self, from: appcastData)
        let release = try FoundryPackUpdateVerifier.newestRelease(
            in: appcast,
            packID: packID,
            currentVersion: currentVersion
        )
        return AvailableUpdate(
            sourceURL: sourceURL,
            packID: packID,
            title: installedPack.metadata.title ?? sourceURL.deletingPathExtension().lastPathComponent,
            currentVersion: currentVersion,
            release: release
        )
    }

    static func checkAndInstallUpdate(
        for sourceURL: URL,
        progress: @MainActor (Double) -> Void = { _ in }
    ) async throws -> String {
        progress(0.05)
        let installedPack = try await Task.detached(priority: .utility) {
            try FoundryPackLoader.load(from: sourceURL)
        }.value
        guard let packID = installedPack.identifier,
              let currentVersion = installedPack.metadata.version,
              let configuration = installedPack.metadata.updates else {
            throw FoundryPackUpdateError.invalidMetadata("This pack does not declare update information.")
        }
        guard configuration.appcastURL.scheme?.lowercased() == "https" else {
            throw FoundryPackUpdateError.insecureURL("Appcast URL")
        }
        let (appcastData, appcastResponse) = try await fetchFreshData(from: configuration.appcastURL)
        progress(0.2)
        try requireSuccessfulHTTP(appcastResponse)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let appcast = try decoder.decode(FoundryPackAppcast.self, from: appcastData)
        let release = try FoundryPackUpdateVerifier.newestRelease(
            in: appcast,
            packID: packID,
            currentVersion: currentVersion
        )
        guard release.downloadURL.scheme?.lowercased() == "https" else {
            throw FoundryPackUpdateError.insecureURL("Download URL")
        }
        let (archiveData, archiveResponse) = try await fetchFreshData(from: release.downloadURL)
        progress(0.65)
        try requireSuccessfulHTTP(archiveResponse)
        try FoundryPackUpdateVerifier.verify(archiveData, release: release, publicKey: configuration.publicKey)
        progress(0.75)

        try await Task.detached(priority: .utility) {
            try installArchive(
                archiveData,
                sourceURL: sourceURL,
                packID: packID,
                release: release,
                publicKey: configuration.publicKey
            )
        }.value
        progress(1)
        return release.version
    }

    private nonisolated static func installArchive(
        _ archiveData: Data,
        sourceURL: URL,
        packID: String,
        release: FoundryPackAppcast.Release,
        publicKey: String
    ) throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: "Foundry-Update-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let archiveURL = temporaryRoot.appending(path: "update.zip")
        let extractionURL = temporaryRoot.appending(path: "Extracted", directoryHint: .isDirectory)
        try archiveData.write(to: archiveURL, options: .atomic)
        try FileManager.default.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        try extract(archiveURL, to: extractionURL)

        let candidates = FoundryPackLoader.packURLs(in: extractionURL)
            .filter { $0.pathExtension.lowercased() == "foundrypack" }
            .filter { candidate in
                !candidatesParentIsPack(candidate, inside: extractionURL)
            }
        guard candidates.count == 1, let candidate = candidates.first else {
            throw FoundryPackUpdateError.invalidMetadata("The update archive must contain exactly one top-level .foundrypack.")
        }
        let downloadedPack = try FoundryPackLoader.load(from: candidate)
        guard downloadedPack.identifier == packID else {
            throw FoundryPackUpdateError.wrongPack(downloadedPack.identifier ?? "unknown")
        }
        guard downloadedPack.metadata.version == release.version else {
            throw FoundryPackUpdateError.invalidMetadata("The downloaded pack version does not match the appcast release.")
        }
        guard downloadedPack.metadata.updates?.publicKey == publicKey else {
            throw FoundryPackUpdateError.invalidSignature
        }

        let installURL = extractionURL.appending(path: sourceURL.lastPathComponent, directoryHint: .isDirectory)
        if candidate != installURL {
            try FileManager.default.moveItem(at: candidate, to: installURL)
        }
        try FoundryPackInstaller.installFiles(from: installURL)
    }

    private static func fetchFreshData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return try await URLSession.shared.data(for: request)
    }

    private static func requireSuccessfulHTTP(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw FoundryPackUpdateError.invalidMetadata("The update server returned an unsuccessful response.")
        }
    }

    private nonisolated static func extract(_ archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw FoundryPackUpdateError.archiveFailed(String(decoding: data, as: UTF8.self))
        }
    }

    private nonisolated static func candidatesParentIsPack(_ url: URL, inside root: URL) -> Bool {
        var parent = url.deletingLastPathComponent()
        while parent.standardizedFileURL != root.standardizedFileURL && parent.path != "/" {
            if FoundryPackLoader.isPackURL(parent) { return true }
            parent.deleteLastPathComponent()
        }
        return false
    }
}
