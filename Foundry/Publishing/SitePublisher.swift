import Foundation
import CryptoKit
import Security

nonisolated enum PublishingError: LocalizedError {
    case missingLocalDestination
    case incompleteRemoteConfiguration
    case missingCredential
    case missingKnownHosts
    case missingCertificateBundle
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingLocalDestination:
            "Choose a local publishing folder first."
        case .incompleteRemoteConfiguration:
            "Complete the publishing destination settings before publishing."
        case .missingCredential:
            "Enter the password or secret access key before publishing."
        case .missingKnownHosts:
            "This SFTP host is not trusted yet. Connect to it once with SSH to add it to ~/.ssh/known_hosts."
        case .missingCertificateBundle:
            "Foundry’s certificate bundle is unavailable. Reinstall Foundry before using a secure publishing method."
        case .transferFailed(let message):
            message
        }
    }
}

nonisolated struct PublishingProgress: Sendable, Equatable {
    let fileCount: Int
    let completedFileCount: Int
    let uploadedBytes: Int64
    let totalBytes: Int64
    let transfers: [PublishingFileProgress]

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(uploadedBytes) / Double(totalBytes))
    }
}

nonisolated struct PublishingFileProgress: Sendable, Equatable, Identifiable {
    let file: String
    let fileIndex: Int
    let uploadedBytes: Int64
    let totalBytes: Int64

    var id: String { file }
    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(uploadedBytes) / Double(totalBytes))
    }
}

nonisolated struct PublishingResult: Sendable, Equatable {
    let uploadedFileCount: Int
    let unchangedFileCount: Int
    let removedFileCount: Int
}

nonisolated struct PublishingManifest: Codable, Sendable, Equatable {
    var files: [String: String]
}

nonisolated enum PublishingChange: String, Sendable, Equatable {
    case new
    case modified

    var title: String {
        switch self {
        case .new: "New"
        case .modified: "Modified"
        }
    }
}

nonisolated struct PublishingPlan: Sendable, Equatable {
    let uploads: [SiteExportFile]
    let removals: [String]
    let removalHashes: [String: String]
    let unchangedFileCount: Int
    let nextManifest: PublishingManifest

    static func make(
        bundle: SiteExportBundle,
        previous: PublishingManifest?,
        removesObsoleteFiles: Bool,
        removesManagedSiteAssets: Bool = false
    ) -> PublishingPlan {
        let current = Dictionary(uniqueKeysWithValues: bundle.files.map {
            ($0.path, $0.contentFingerprint ?? hash($0.data))
        })
        let previousFiles = previous?.files ?? [:]
        let uploads = bundle.files.filter { previousFiles[$0.path] != current[$0.path] }
        let obsolete = previousFiles.keys.filter { current[$0] == nil }.sorted()
        let removals = removesObsoleteFiles
            ? obsolete
            : removesManagedSiteAssets ? obsolete.filter(ManagedSiteAssetStorage.isManagedExportPath) : []
        var retained = removesObsoleteFiles ? current : previousFiles.merging(current) { _, new in new }
        removals.forEach { retained[$0] = nil }
        return PublishingPlan(
            uploads: uploads,
            removals: removals,
            removalHashes: Dictionary(uniqueKeysWithValues: removals.compactMap { path in
                    previousFiles[path].map { (path, $0) }
                }),
            unchangedFileCount: bundle.files.count - uploads.count,
            nextManifest: PublishingManifest(files: retained)
        )
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func changes(
        bundle: SiteExportBundle,
        previous: PublishingManifest?
    ) -> [String: PublishingChange] {
        Dictionary(uniqueKeysWithValues: bundle.files.compactMap { file in
            let currentHash = file.contentFingerprint ?? hash(file.data)
            guard previous?.files[file.path] != currentHash else { return nil }
            return (file.path, previous?.files[file.path] == nil ? .new : .modified)
        })
    }
}

nonisolated struct PublishingManifestStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Foundry/Publishing Manifests", directoryHint: .isDirectory)
    }

    func load(for site: Site, localDirectory: URL? = nil) -> PublishingManifest? {
        try? JSONDecoder().decode(
            PublishingManifest.self,
            from: Data(contentsOf: url(for: site, localDirectory: localDirectory))
        )
    }

    func save(_ manifest: PublishingManifest, for site: Site, localDirectory: URL? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url(for: site, localDirectory: localDirectory), options: .atomic)
    }

    func remove(for site: Site, localDirectory: URL? = nil) throws {
        let manifestURL = url(for: site, localDirectory: localDirectory)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        try FileManager.default.removeItem(at: manifestURL)
    }

    private func url(for site: Site, localDirectory: URL?) -> URL {
        let identity = [
            site.id.uuidString,
            site.publishingDestination.rawValue,
            site.publishingHost,
            String(site.publishingPort),
            site.publishingUsername,
            site.publishingRemotePath,
            site.publishingS3Bucket,
            site.publishingS3Region,
            localDirectory?.standardizedFileURL.path ?? ""
        ].joined(separator: "\u{1f}")
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(key).json")
    }
}

nonisolated private final class CurlProgressContext: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let file: String
    let tracker: PublishingProgressTracker?

    init(file: String, tracker: PublishingProgressTracker? = nil) {
        self.file = file
        self.tracker = tracker
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func update(uploadedBytes: Int64) -> Int32 {
        let isCancelled = lock.withLock { cancelled }
        if isCancelled { return 1 }
        tracker?.update(file: file, uploadedBytes: uploadedBytes)
        return 0
    }
}

nonisolated private final class PublishingProgressTracker: @unchecked Sendable {
    private struct ActiveTransfer {
        let index: Int
        let totalBytes: Int64
        var uploadedBytes: Int64
    }

    private let lock = NSLock()
    private let totalBytes: Int64
    private let fileCount: Int
    private let handler: @Sendable (PublishingProgress) -> Void
    private var active: [String: ActiveTransfer] = [:]
    private var completedBytes: Int64 = 0
    private var completedFileCount = 0

    init(files: [SiteExportFile], handler: @escaping @Sendable (PublishingProgress) -> Void) {
        totalBytes = files.reduce(0) { $0 + Int64($1.data.count) }
        fileCount = files.count
        self.handler = handler
    }

    func start(file: SiteExportFile, index: Int) {
        emit(lock.withLock {
            active[file.path] = ActiveTransfer(
                index: index,
                totalBytes: Int64(file.data.count),
                uploadedBytes: 0
            )
            return snapshot()
        })
    }

    func update(file: String, uploadedBytes: Int64) {
        let progress = lock.withLock { () -> PublishingProgress in
            guard var transfer = active[file] else { return snapshot() }
            transfer.uploadedBytes = min(transfer.totalBytes, max(0, uploadedBytes))
            active[file] = transfer
            return snapshot()
        }
        emit(progress)
    }

    func finish(file: SiteExportFile) {
        emit(lock.withLock {
            active.removeValue(forKey: file.path)
            completedBytes += Int64(file.data.count)
            completedFileCount += 1
            return snapshot()
        })
    }

    private func snapshot() -> PublishingProgress {
        let transfers = active.map { file, transfer in
            PublishingFileProgress(
                file: file,
                fileIndex: transfer.index,
                uploadedBytes: transfer.uploadedBytes,
                totalBytes: transfer.totalBytes
            )
        }.sorted { $0.fileIndex < $1.fileIndex }
        return PublishingProgress(
            fileCount: fileCount,
            completedFileCount: completedFileCount,
            uploadedBytes: completedBytes + transfers.reduce(0) { $0 + $1.uploadedBytes },
            totalBytes: totalBytes,
            transfers: transfers
        )
    }

    private func emit(_ progress: PublishingProgress) {
        handler(progress)
    }
}

nonisolated private let foundryCurlProgress: FoundryCurlProgressCallback = { uploaded, _, pointer in
    guard let pointer else { return 0 }
    return Unmanaged<CurlProgressContext>.fromOpaque(pointer).takeUnretainedValue()
        .update(uploadedBytes: uploaded)
}

nonisolated struct SitePublisher: Sendable {
    static var transportVersion: String {
        String(cString: FoundryCurlVersion())
    }

    func publish(
        bundle: SiteExportBundle,
        site: Site,
        localDirectory: URL?,
        credential: String,
        forceAllFiles: Bool = false,
        progress: @escaping @Sendable (PublishingProgress) -> Void
    ) async throws -> PublishingResult {
        try bundle.validate()
        if site.publishingDestination == .local {
            guard let localDirectory else { throw PublishingError.missingLocalDestination }
            let manifestStore = PublishingManifestStore()
            let plan = PublishingPlan.make(
                bundle: bundle,
                previous: forceAllFiles ? nil : manifestStore.load(for: site, localDirectory: localDirectory),
                removesObsoleteFiles: site.cleansObsoleteExportFiles,
                removesManagedSiteAssets: true
            )
            let removedFileCount = try await Task.detached {
                try SiteExportWriter().apply(plan, bundle: bundle, to: localDirectory)
            }.value
            try manifestStore.save(plan.nextManifest, for: site, localDirectory: localDirectory)
            return PublishingResult(
                uploadedFileCount: plan.uploads.count,
                unchangedFileCount: plan.unchangedFileCount,
                removedFileCount: removedFileCount
            )
        }

        try validate(site: site, credential: credential)
        let manifestStore = PublishingManifestStore()
        let plan = PublishingPlan.make(
            bundle: bundle,
            previous: forceAllFiles ? nil : manifestStore.load(for: site, localDirectory: localDirectory),
            removesObsoleteFiles: false
        )
        let tracker = PublishingProgressTracker(files: plan.uploads, handler: progress)
        try await uploadConcurrently(
            plan.uploads,
            site: site,
            credential: credential,
            tracker: tracker
        )
        try manifestStore.save(plan.nextManifest, for: site, localDirectory: localDirectory)
        return PublishingResult(
            uploadedFileCount: plan.uploads.count,
            unchangedFileCount: plan.unchangedFileCount,
            removedFileCount: 0
        )
    }

    func testConnection(site: Site, credential: String) async throws {
        guard site.publishingDestination != .local else { return }
        try validate(site: site, credential: credential)
        let context = CurlProgressContext(file: "")
        try await perform(
            site: site,
            relativePath: "",
            credential: credential,
            operation: .test,
            context: context
        )
    }

    private func uploadConcurrently(
        _ files: [SiteExportFile],
        site: Site,
        credential: String,
        tracker: PublishingProgressTracker
    ) async throws {
        let maximumConcurrentUploads = 4
        try await withThrowingTaskGroup(of: Void.self) { group in
            var nextIndex = 0
            let initialCount = min(maximumConcurrentUploads, files.count)
            for _ in 0..<initialCount {
                addUpload(files[nextIndex], index: nextIndex, to: &group, site: site, credential: credential, tracker: tracker)
                nextIndex += 1
            }
            while try await group.next() != nil {
                if nextIndex < files.count {
                    addUpload(files[nextIndex], index: nextIndex, to: &group, site: site, credential: credential, tracker: tracker)
                    nextIndex += 1
                }
            }
        }
    }

    private func addUpload(
        _ file: SiteExportFile,
        index: Int,
        to group: inout ThrowingTaskGroup<Void, any Error>,
        site: Site,
        credential: String,
        tracker: PublishingProgressTracker
    ) {
        group.addTask {
            try Task.checkCancellation()
            tracker.start(file: file, index: index + 1)
            let context = CurlProgressContext(file: file.path, tracker: tracker)
            try await perform(
                site: site,
                relativePath: file.path,
                credential: credential,
                operation: .upload(file.data),
                context: context
            )
            tracker.finish(file: file)
        }
    }

    private func validate(site: Site, credential: String) throws {
        switch site.publishingDestination {
        case .local:
            return
        case .ftp, .ftps, .sftp:
            guard !site.publishingHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !site.publishingUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !site.publishingRemotePath.contains("\n") else {
                throw PublishingError.incompleteRemoteConfiguration
            }
            if site.publishingDestination != .sftp && credential.isEmpty {
                throw PublishingError.missingCredential
            }
            if site.publishingDestination == .sftp && knownHostsPath == nil {
                throw PublishingError.missingKnownHosts
            }
        case .amazonS3:
            guard !site.publishingS3Bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !site.publishingS3Region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !site.publishingUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PublishingError.incompleteRemoteConfiguration
            }
            guard !credential.isEmpty else { throw PublishingError.missingCredential }
        }
        if site.publishingDestination.usesTLS && certificatePath == nil {
            throw PublishingError.missingCertificateBundle
        }
    }

    private enum Operation {
        case upload(Data)
        case test

        var isTest: Bool {
            if case .test = self { true } else { false }
        }
    }

    private func perform(
        site: Site,
        relativePath: String,
        credential: String,
        operation: Operation,
        context: CurlProgressContext
    ) async throws {
        let data: Data
        switch operation {
        case .upload(let contents): data = contents
        case .test: data = Data()
        }
        try await withTaskCancellationHandler {
            try await Task.detached {
                try data.withUnsafeBytes { bytes in
                    let url = PublishingRemoteURLBuilder.url(
                        site: site,
                        relativePath: relativePath,
                        testOnly: operation.isTest
                    ) as NSString
                    let username = site.publishingUsername as NSString
                    let password = credential as NSString
                    let caPath = certificatePath as NSString?
                    let knownHosts = knownHostsPath as NSString?
                    let awsSignature = site.publishingDestination == .amazonS3
                        ? "aws:amz:\(site.publishingS3Region):s3" as NSString
                        : nil
                    var request = FoundryCurlRequest(
                        url: url.utf8String,
                        username: username.utf8String,
                        password: password.length == 0 ? nil : password.utf8String,
                        caCertificatePath: caPath?.utf8String,
                        knownHostsPath: site.publishingDestination == .sftp ? knownHosts?.utf8String : nil,
                        awsSignature: awsSignature?.utf8String,
                        data: bytes.bindMemory(to: UInt8.self).baseAddress,
                        dataLength: bytes.count,
                        testOnly: operation.isTest ? 1 : 0,
                        createRemoteDirectories: 1,
                        requireExplicitFTPSTLS: site.publishingDestination == .ftps ? 1 : 0
                    )
                    var error = [CChar](repeating: 0, count: 512)
                    let retained = Unmanaged.passRetained(context)
                    defer { retained.release() }
                    let result = FoundryCurlPerform(
                        &request,
                        foundryCurlProgress,
                        retained.toOpaque(),
                        &error,
                        error.count
                    )
                    guard result == 0 else {
                        if result == 42 { throw CancellationError() }
                        throw PublishingError.transferFailed(String(cString: error))
                    }
                }
            }.value
        } onCancel: {
            context.cancel()
        }
    }

    private var certificatePath: String? {
        Bundle.main.url(forResource: "cacert", withExtension: "pem")?.path
    }

    private var knownHostsPath: String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh/known_hosts")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
}

nonisolated enum PublishingRemoteURLBuilder {
    static func url(site: Site, relativePath: String, testOnly: Bool) -> String {
        if site.publishingDestination == .amazonS3 {
            let prefix = trimmedPath(site.publishingRemotePath)
            let key = [prefix, relativePath].filter { !$0.isEmpty }.joined(separator: "/")
            return "https://\(site.publishingS3Bucket).s3.\(site.publishingS3Region).amazonaws.com/\(encodedPath(key))"
        }

        let isAbsolute = site.publishingRemotePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("/")
        let root = trimmedPath(site.publishingRemotePath)
        let joined = [root, relativePath].filter { !$0.isEmpty }.joined(separator: "/")
        let encoded = encodedPath(joined)
        let base = "\(site.publishingDestination == .sftp ? "sftp" : "ftp")://\(site.publishingHost):\(effectivePort(site))"
        let path: String
        switch site.publishingDestination {
        case .sftp:
            path = isAbsolute ? "/\(encoded)" : "/~/\(encoded)"
        case .ftp, .ftps:
            path = isAbsolute ? "//\(encoded)" : "/\(encoded)"
        case .local, .amazonS3:
            path = "/\(encoded)"
        }
        let suffix = testOnly && !path.hasSuffix("/") ? "/" : ""
        return base + path + suffix
    }

    private static func effectivePort(_ site: Site) -> Int {
        site.publishingPort == 0 ? site.publishingDestination.defaultPort : site.publishingPort
    }

    private static func trimmedPath(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func encodedPath(_ path: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}

enum PublishingDestinationStore {
    static func url(for siteID: UUID) -> URL? {
        UserDefaults.standard.string(forKey: key(siteID)).map { URL(filePath: $0) }
    }

    static func setURL(_ url: URL, for siteID: UUID) {
        UserDefaults.standard.set(url.path, forKey: key(siteID))
    }

    private static func key(_ siteID: UUID) -> String {
        "publishing.localDestination.\(siteID.uuidString)"
    }
}

enum PublishingCredentialStore {
    static func credential(site: Site) -> String {
        var query = baseQuery(site: site)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func setCredential(_ credential: String, site: Site) {
        let query = baseQuery(site: site)
        SecItemDelete(query as CFDictionary)
        guard !credential.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(credential.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func baseQuery(site: Site) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "uk.co.garysimpson.Foundry.publishing",
            kSecAttrAccount as String: "\(site.id.uuidString)|\(site.publishingDestination.rawValue)|\(site.publishingHost)|\(site.publishingUsername)|\(site.publishingS3Bucket)"
        ]
    }
}
