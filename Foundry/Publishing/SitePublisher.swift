import Foundation
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
    ) async throws {
        if site.publishingDestination == .local {
            guard let localDirectory else { throw PublishingError.missingLocalDestination }
            try await Task.detached {
                try SiteExportWriter().write(
                    bundle,
                    to: localDirectory,
                    cleaningObsoleteFiles: site.cleansObsoleteExportFiles
                )
            }.value
            return
        }

        try validate(site: site, credential: credential)
        let totalBytes = bundle.files.reduce(Int64(0)) { $0 + Int64($1.data.count) }
        var completedBytes: Int64 = 0
        for (offset, file) in bundle.files.enumerated() {
            try Task.checkCancellation()
            let context = CurlProgressContext(
                baseBytes: completedBytes,
                totalBytes: totalBytes,
                file: file.path,
                fileIndex: offset + 1,
                fileCount: bundle.files.count,
                handler: progress
            )
            try await perform(
                site: site,
                relativePath: file.path,
                data: file.data,
                credential: credential,
                testOnly: false,
                context: context
            )
            completedBytes += Int64(file.data.count)
        }
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
            data: Data(),
            credential: credential,
            testOnly: true,
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

    private func perform(
        site: Site,
        relativePath: String,
        data: Data,
        credential: String,
        testOnly: Bool,
        context: CurlProgressContext
    ) async throws {
        try await withTaskCancellationHandler {
            try await Task.detached {
                try data.withUnsafeBytes { bytes in
                    let url = PublishingRemoteURLBuilder.url(
                        site: site,
                        relativePath: relativePath,
                        testOnly: testOnly
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
                        testOnly: testOnly ? 1 : 0,
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
