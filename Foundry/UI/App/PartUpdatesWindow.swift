import SwiftUI

struct PartUpdatesWindow: View {
    @State private var catalog = PartPackageCatalog.shared
    @State private var selection: PartUpdatesSection

    init() {
        _selection = State(
            initialValue: PartUpdatePublisherConfiguration.hasSavedSettings
                ? .releases
                : .publishing
        )
    }

    var body: some View {
        let _ = catalog.revision
        NavigationSplitView {
            List(PartUpdatesSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Part Updates")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            switch selection {
            case .publishing:
                PartUpdatePublishingSettingsView()
            case .releases:
                DeveloperReleasesView(developmentPacks: developmentPacks)
            }
        }
        .background(WindowGeometryPersistence(key: "partUpdates.windowFrame"))
    }

    private var developmentPacks: [URL] {
        Set(catalog.packages.values.compactMap(\.developmentPackRootURL))
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

private enum PartUpdatesSection: String, CaseIterable, Identifiable {
    case publishing
    case releases

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var systemImage: String { self == .publishing ? "server.rack" : PartDefinition.genericSystemImage }
}

private struct PartUpdatePublishingSettingsView: View {
    @AppStorage("partUpdates.method") private var method = PublishingDestinationKind.sftp.rawValue
    @AppStorage("partUpdates.host") private var host = ""
    @AppStorage("partUpdates.port") private var port = 22
    @AppStorage("partUpdates.username") private var username = ""
    @AppStorage("partUpdates.remotePath") private var remotePath = ""
    @AppStorage("partUpdates.publicURL") private var publicURL = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var status: String?

    var body: some View {
        Form {
            Section("Server Connection") {
                Picker("Method", selection: $method) {
                    ForEach([PublishingDestinationKind.sftp, .ftp, .ftps], id: \.rawValue) { kind in
                        Text(kind.title).tag(kind.rawValue)
                    }
                }
                TextField("Server", text: $host)
                TextField("Port", value: $port, format: .number)
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
            }
            Section("Part Updates") {
                TextField("Website Base URL", text: $publicURL, prompt: Text("https://example.com"))
                TextField("Website Upload Root", text: $remotePath, prompt: Text("/public_html"))

                LabeledContent("Foundry uploads to") {
                    Text(PartUpdatePublisherConfiguration.updatesRemotePath(from: remotePath))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Updates are available at") {
                    Text(PartUpdatePublisherConfiguration.updatesPublicURL(
                        from: publicURL,
                        uploadRoot: remotePath
                    ))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text("Foundry creates and manages the foundry-updates folder inside these locations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Save and Test Connection", systemImage: "network") { saveAndTest() }
                    .disabled(!isComplete || isTesting)
                if isTesting { ProgressView("Testing…") }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Publishing Settings")
        .onAppear {
            migrateLegacyUpdateLocations()
            password = PublishingCredentialStore.credential(site: configuredSite)
        }
        .onChange(of: method) { _, value in
            port = PublishingDestinationKind(rawValue: value)?.defaultPort ?? 22
        }
    }

    private var configuredSite: Site { PartUpdatePublisherConfiguration.site }
    private var isComplete: Bool {
        !host.isEmpty && !username.isEmpty && !remotePath.isEmpty && URL(string: publicURL)?.scheme == "https"
    }

    private func saveAndTest() {
        let site = configuredSite
        var connectionTestSite = site
        connectionTestSite.publishingRemotePath = remotePath
        PublishingCredentialStore.setCredential(password, site: site)
        isTesting = true
        status = nil
        Task {
            do {
                let result = try await SitePublisher().testConnection(site: connectionTestSite, credential: password)
                status = result.message
            } catch { status = error.localizedDescription }
            isTesting = false
        }
    }

    private func migrateLegacyUpdateLocations() {
        remotePath = PartUpdatePublisherConfiguration.removingManagedDirectory(from: remotePath)
        publicURL = PartUpdatePublisherConfiguration.removingManagedDirectory(from: publicURL)
    }
}

@MainActor
enum PartUpdatePublisherConfiguration {
    static let siteID = UUID(uuidString: "F0A6EA31-47DF-42D8-B496-74E087307E6B")!
    private static let managedDirectory = "foundry-updates"

    static var hasSavedSettings: Bool {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: "partUpdates.host")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = defaults.string(forKey: "partUpdates.username")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let remotePath = defaults.string(forKey: "partUpdates.remotePath")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicURL = defaults.string(forKey: "partUpdates.publicURL")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !host.isEmpty
            && !username.isEmpty
            && !remotePath.isEmpty
            && URL(string: publicURL)?.scheme?.lowercased() == "https"
    }

    static var site: Site {
        let defaults = UserDefaults.standard
        let method = PublishingDestinationKind(rawValue: defaults.string(forKey: "partUpdates.method") ?? "sftp") ?? .sftp
        let uploadRoot = defaults.string(forKey: "partUpdates.remotePath") ?? ""
        return Site(
            id: siteID,
            name: "Part Updates",
            publicURL: updatesPublicURL(
                from: defaults.string(forKey: "partUpdates.publicURL") ?? "",
                uploadRoot: uploadRoot
            ),
            publishingDestination: method,
            publishingHost: defaults.string(forKey: "partUpdates.host") ?? "",
            publishingPort: defaults.integer(forKey: "partUpdates.port"),
            publishingUsername: defaults.string(forKey: "partUpdates.username") ?? "",
            publishingRemotePath: updatesRemotePath(from: uploadRoot),
            pages: [],
            assetLibrary: []
        )
    }

    static func updatesRemotePath(from uploadRoot: String) -> String {
        appendingManagedDirectory(to: uploadRoot)
    }

    static func updatesPublicURL(from websiteURL: String, uploadRoot: String) -> String {
        let rootParts = removingManagedDirectory(from: uploadRoot)
            .split(separator: "/")
            .map(String.init)
        let publicSubdirectory: ArraySlice<String>
        if let webRootIndex = rootParts.firstIndex(where: {
            ["public_html", "www", "htdocs"].contains($0.lowercased())
        }) {
            publicSubdirectory = rootParts.suffix(from: rootParts.index(after: webRootIndex))
        } else {
            publicSubdirectory = []
        }

        var result = removingManagedDirectory(from: websiteURL)
        for part in publicSubdirectory {
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + part
        }
        return appendingManagedDirectory(to: result)
    }

    static func removingManagedDirectory(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = "/\(managedDirectory)"
        guard trimmed.lowercased().hasSuffix(suffix) else { return trimmed }
        return String(trimmed.dropLast(suffix.count))
    }

    private static func appendingManagedDirectory(to value: String) -> String {
        let base = removingManagedDirectory(from: value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { return managedDirectory }

        if value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
            return "/\(base)/\(managedDirectory)"
        }
        return "\(base)/\(managedDirectory)"
    }
}

nonisolated enum PartUpdatePublisher {
    static func publish(
        directory: URL,
        packID: String,
        site: Site,
        credential: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let files = try files(in: directory, packID: packID)
        let releaseMetadata = files.filter { $0.path.hasSuffix("/release.json") }
        let releaseAssets = files.filter { !$0.path.hasSuffix("/release.json") }
        guard releaseMetadata.count == 1 else {
            throw FoundryPackUpdateError.invalidMetadata("The release must contain exactly one release.json file.")
        }
        if !releaseAssets.isEmpty {
            _ = try await SitePublisher().publish(
                bundle: SiteExportBundle(files: releaseAssets),
                site: site,
                localDirectory: nil,
                credential: credential,
                forceAllFiles: true,
                progress: { progress(0.9 * $0.fractionCompleted) }
            )
        }
        try Task.checkCancellation()
        _ = try await SitePublisher().publish(
            bundle: SiteExportBundle(files: releaseMetadata),
            site: site,
            localDirectory: nil,
            credential: credential,
            forceAllFiles: true,
            progress: { progress(0.9 + (0.1 * $0.fractionCompleted)) }
        )
        progress(1)
    }

    private static func files(in directory: URL, packID: String) throws -> [SiteExportFile] {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try fileURLs.compactMap { fileURL in
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return nil
            }
            return .init(
                path: "\(packID)/\(directory.lastPathComponent)/\(fileURL.lastPathComponent)",
                data: try Data(contentsOf: fileURL)
            )
        }
    }

    static func publishSetup(
        directory: URL,
        packID: String,
        site: Site,
        credential: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let appcast = directory.appending(path: "appcast.php")
        let bundle = SiteExportBundle(files: [
            .init(path: "\(packID)/appcast.php", data: try Data(contentsOf: appcast))
        ])
        _ = try await SitePublisher().publish(
            bundle: bundle,
            site: site,
            localDirectory: nil,
            credential: credential,
            forceAllFiles: true,
            progress: { progress($0.fractionCompleted) }
        )
        progress(1)
    }
}
