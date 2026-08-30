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
    let file: String
    let fileIndex: Int
    let fileCount: Int
    let uploadedBytes: Int64
    let totalBytes: Int64

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
    let unchangedFileCount: Int
    let nextManifest: PublishingManifest

    static func make(
        bundle: SiteExportBundle,
        previous: PublishingManifest?,
        removesObsoleteFiles: Bool
    ) -> PublishingPlan {
        let current = Dictionary(uniqueKeysWithValues: bundle.files.map { ($0.path, hash($0.data)) })
        let previousFiles = previous?.files ?? [:]
        let uploads = bundle.files.filter { previousFiles[$0.path] != current[$0.path] }
        let obsolete = previousFiles.keys.filter { current[$0] == nil }.sorted()
        let retained = removesObsoleteFiles ? current : previousFiles.merging(current) { _, new in new }
        return PublishingPlan(
            uploads: uploads,
            removals: removesObsoleteFiles ? obsolete : [],
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
            let currentHash = hash(file.data)
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
    let baseBytes: Int64
    let totalBytes: Int64
    let file: String
    let fileIndex: Int
    let fileCount: Int
    let handler: @Sendable (PublishingProgress) -> Void

    init(
        baseBytes: Int64,
        totalBytes: Int64,
        file: String,
        fileIndex: Int,
        fileCount: Int,
        handler: @escaping @Sendable (PublishingProgress) -> Void
    ) {
        self.baseBytes = baseBytes
        self.totalBytes = totalBytes
        self.file = file
        self.fileIndex = fileIndex
        self.fileCount = fileCount
        self.handler = handler
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func update(uploadedBytes: Int64) -> Int32 {
        let isCancelled = lock.withLock { cancelled }
        if isCancelled { return 1 }
        handler(PublishingProgress(
            file: file,
            fileIndex: fileIndex,
            fileCount: fileCount,
            uploadedBytes: baseBytes + uploadedBytes,
            totalBytes: totalBytes
        ))
        return 0
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
        progress: @escaping @Sendable (PublishingProgress) -> Void
    ) async throws -> PublishingResult {
        if site.publishingDestination == .local {
            guard let localDirectory else { throw PublishingError.missingLocalDestination }
            try await Task.detached {
                try SiteExportWriter().write(
                    bundle,
                    to: localDirectory,
                    cleaningObsoleteFiles: site.cleansObsoleteExportFiles
                )
            }.value
            let manifest = PublishingPlan.make(
                bundle: bundle,
                previous: nil,
                removesObsoleteFiles: true
            ).nextManifest
            try PublishingManifestStore().save(manifest, for: site, localDirectory: localDirectory)
            return PublishingResult(
                uploadedFileCount: bundle.files.count,
                unchangedFileCount: 0,
                removedFileCount: 0
            )
        }

        try validate(site: site, credential: credential)
        let manifestStore = PublishingManifestStore()
        let plan = PublishingPlan.make(
            bundle: bundle,
            previous: manifestStore.load(for: site, localDirectory: localDirectory),
            removesObsoleteFiles: site.cleansObsoleteExportFiles
        )
        let totalBytes = plan.uploads.reduce(Int64(0)) { $0 + Int64($1.data.count) }
        var completedBytes: Int64 = 0
        for (offset, file) in plan.uploads.enumerated() {
            try Task.checkCancellation()
            let context = CurlProgressContext(
                baseBytes: completedBytes,
                totalBytes: totalBytes,
                file: file.path,
                fileIndex: offset + 1,
                fileCount: plan.uploads.count,
                handler: progress
            )
            try await perform(
                site: site,
                relativePath: file.path,
                credential: credential,
                operation: .upload(file.data),
                context: context
            )
            completedBytes += Int64(file.data.count)
        }
        for path in plan.removals {
            try Task.checkCancellation()
            try await perform(
                site: site,
                relativePath: path,
                credential: credential,
                operation: .delete,
                context: CurlProgressContext(
                    baseBytes: totalBytes,
                    totalBytes: totalBytes,
                    file: path,
                    fileIndex: plan.uploads.count,
                    fileCount: plan.uploads.count,
                    handler: progress
                )
            )
        }
        try manifestStore.save(plan.nextManifest, for: site, localDirectory: localDirectory)
        return PublishingResult(
            uploadedFileCount: plan.uploads.count,
            unchangedFileCount: plan.unchangedFileCount,
            removedFileCount: plan.removals.count
        )
    }

    func testConnection(site: Site, credential: String) async throws {
        guard site.publishingDestination != .local else { return }
        try validate(site: site, credential: credential)
        let context = CurlProgressContext(
            baseBytes: 0,
            totalBytes: 0,
            file: "",
            fileIndex: 0,
            fileCount: 0,
            handler: { _ in }
        )
        try await perform(
            site: site,
            relativePath: "",
            credential: credential,
            operation: .test,
            context: context
        )
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
        case delete
        case test

        var isDelete: Bool {
            if case .delete = self { true } else { false }
        }

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
        case .delete, .test: data = Data()
        }
        try await withTaskCancellationHandler {
            try await Task.detached {
                try data.withUnsafeBytes { bytes in
                    let requestPath = operation.isDelete && site.publishingDestination != .amazonS3
                        ? ""
                        : relativePath
                    let url = PublishingRemoteURLBuilder.url(
                        site: site,
                        relativePath: requestPath,
                        testOnly: operation.isTest || operation.isDelete
                    ) as NSString
                    let username = site.publishingUsername as NSString
                    let password = credential as NSString
                    let caPath = certificatePath as NSString?
                    let knownHosts = knownHostsPath as NSString?
                    let awsSignature = site.publishingDestination == .amazonS3
                        ? "aws:amz:\(site.publishingS3Region):s3" as NSString
                        : nil
                    let deleteCommand = operation.isDelete
                        ? PublishingRemoteURLBuilder.deleteCommand(site: site, relativePath: relativePath)
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
                        deleteOnly: operation.isDelete ? 1 : 0,
                        deleteCommand: deleteCommand?.utf8String,
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

    static func deleteCommand(site: Site, relativePath: String) -> NSString {
        let root = trimmedPath(site.publishingRemotePath)
        let path = [root, relativePath].filter { !$0.isEmpty }.joined(separator: "/")
        switch site.publishingDestination {
        case .sftp:
            return "rm \(site.publishingRemotePath.hasPrefix("/") ? "/" : "")\(path)" as NSString
        case .ftp, .ftps:
            return "DELE \(site.publishingRemotePath.hasPrefix("/") ? "/" : "")\(path)" as NSString
        case .local, .amazonS3:
            return "" as NSString
        }
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
