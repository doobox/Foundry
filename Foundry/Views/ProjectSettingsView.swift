import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum ProjectSettingsSection: Hashable, Identifiable, Sendable {
    case general
    case webIcons
    case identity
    case search
    case publishing
    case publishingDestination(UUID)
    case code

    var id: String {
        switch self {
        case .general: "general"
        case .webIcons: "webIcons"
        case .identity: "identity"
        case .search: "search"
        case .publishing: "publishing"
        case .publishingDestination(let id): "publishingDestination.\(id.uuidString)"
        case .code: "code"
        }
    }
}

@MainActor
@Observable
final class ProjectSettingsWindowSession {
    let document: FoundryDocument
    let editor: ProjectEditor
    var openPageMetadata: (UUID) -> Void
    var selection: ProjectSettingsSection?

    init(
        document: FoundryDocument,
        undoManager: UndoManager?,
        selection: ProjectSettingsSection,
        openPageMetadata: @escaping (UUID) -> Void
    ) {
        self.document = document
        editor = ProjectEditor(document: document, undoManager: undoManager)
        self.selection = selection
        self.openPageMetadata = openPageMetadata
    }
}

@MainActor
final class ProjectSettingsWindowRegistry {
    static let shared = ProjectSettingsWindowRegistry()

    private var sessions: [UUID: ProjectSettingsWindowSession] = [:]

    func register(
        id: UUID,
        document: FoundryDocument,
        undoManager: UndoManager?,
        selection: ProjectSettingsSection,
        openPageMetadata: @escaping (UUID) -> Void
    ) {
        if let session = sessions[id], session.document === document {
            session.selection = selection
            session.openPageMetadata = openPageMetadata
            return
        }
        sessions[id] = ProjectSettingsWindowSession(
            document: document,
            undoManager: undoManager,
            selection: selection,
            openPageMetadata: openPageMetadata
        )
    }

    func session(for id: UUID) -> ProjectSettingsWindowSession? {
        sessions[id]
    }

    func remove(id: UUID) {
        sessions.removeValue(forKey: id)
    }
}

struct ProjectSettingsWindowSceneContent: View {
    let presentationID: UUID?

    var body: some View {
        Group {
            if let presentationID,
               let session = ProjectSettingsWindowRegistry.shared.session(for: presentationID) {
                ProjectSettingsWindowContent(session: session)
            } else {
                ContentUnavailableView(
                    "Site Settings Unavailable",
                    systemImage: "gearshape",
                    description: Text("Open Site Settings from a project window.")
                )
            }
        }
        .background(WindowGeometryPersistence(key: "siteSettings.windowFrame"))
    }
}

private struct ProjectSettingsWindowContent: View {
    @Bindable var session: ProjectSettingsWindowSession
    @ObservedObject private var document: FoundryDocument

    init(session: ProjectSettingsWindowSession) {
        self.session = session
        document = session.document
    }

    var body: some View {
        ProjectSettingsView(
            selection: $session.selection,
            site: document.site,
            assetContents: document.assetContents,
            siteName: document.site.name,
            language: document.site.language,
            publicURL: document.site.publicURL,
            titleSuffix: document.site.titleSuffix,
            defaultDescription: document.site.defaultDescription,
            favicon: document.site.favicon,
            defaultSocialImage: document.site.defaultSocialImage,
            logo: document.site.logo,
            logoAlt: document.site.logoAlt,
            assets: document.site.assets,
            pages: document.site.pages,
            pageFolders: document.site.pageFolders,
            generatesCanonicalURLs: document.site.generatesCanonicalURLs,
            generatesSitemap: document.site.generatesSitemap,
            generatesRobotsTXT: document.site.generatesRobotsTXT,
            allowsSearchIndexing: document.site.allowsSearchIndexing,
            customCodeEnabled: document.site.customCodeEnabled,
            headCode: document.site.headCode,
            bodyStartCode: document.site.bodyStartCode,
            bodyEndCode: document.site.bodyEndCode,
            analyticsCode: document.site.analyticsCode,
            editor: session.editor,
            openPageMetadata: session.openPageMetadata
        )
        .navigationTitle("\(document.site.name) – Site Settings")
    }
}

struct ProjectSettingsView: View {
    @Binding var selection: ProjectSettingsSection?
    let site: Site
    let assetContents: [UUID: ProjectAssetContent]
    let siteName: String
    let language: String
    let publicURL: String
    let titleSuffix: String
    let defaultDescription: String
    let favicon: String
    let defaultSocialImage: String
    let logo: String
    let logoAlt: String
    let assets: [ProjectAsset]
    let pages: [Page]
    let pageFolders: [PageFolder]
    let generatesCanonicalURLs: Bool
    let generatesSitemap: Bool
    let generatesRobotsTXT: Bool
    let allowsSearchIndexing: Bool
    let customCodeEnabled: Bool
    let headCode: String
    let bodyStartCode: String
    let bodyEndCode: String
    let analyticsCode: String
    let editor: ProjectEditor
    let openPageMetadata: (UUID) -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(ProjectSettingsSection.general)
                Label("Web Icons", systemImage: "app.badge")
                    .tag(ProjectSettingsSection.webIcons)
                Label("Site Identity", systemImage: "globe")
                    .tag(ProjectSettingsSection.identity)
                Label("SEO & Search", systemImage: "magnifyingglass")
                    .tag(ProjectSettingsSection.search)
                Label("Publishing", systemImage: "arrow.up.circle")
                    .tag(ProjectSettingsSection.publishing)
                ForEach(site.publishingDestinations) { destination in
                    Label(destination.name, systemImage: destination.kind == .local ? "externaldrive" : "cloud")
                        .tag(ProjectSettingsSection.publishingDestination(destination.id))
                        .padding(.leading, 18)
                        .contextMenu {
                            Button("Set as Default") { editor.setDefaultPublishingDestination(id: destination.id) }
                            Button("Duplicate") { _ = editor.duplicatePublishingDestination(id: destination.id) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                editor.removePublishingDestination(id: destination.id)
                                selection = .publishing
                            }
                        }
                }
                Label("Code & Analytics", systemImage: "chevron.left.forwardslash.chevron.right")
                    .tag(ProjectSettingsSection.code)
            }
            .listStyle(.sidebar)
            .navigationTitle("Project Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralProjectSettingsView(
                    siteName: siteName,
                    language: language,
                    publicURL: publicURL,
                    logo: logo,
                    logoAlt: logoAlt,
                    allowsDarkMode: site.appearanceMode != .light,
                    assets: assets,
                    assetContents: assetContents,
                    editor: editor
                )
            case .webIcons:
                WebIconsProjectSettingsView(
                    favicon: favicon,
                    assets: assets,
                    assetContents: assetContents,
                    editor: editor
                )
            case .identity:
                SiteIdentityProjectSettingsView(
                    titleSuffix: titleSuffix,
                    defaultDescription: defaultDescription,
                    defaultSocialImage: defaultSocialImage,
                    assets: assets,
                    editor: editor
                )
            case .search:
                SearchProjectSettingsView(
                    publicURL: publicURL,
                    generatesCanonicalURLs: generatesCanonicalURLs,
                    generatesSitemap: generatesSitemap,
                    generatesRobotsTXT: generatesRobotsTXT,
                    allowsSearchIndexing: allowsSearchIndexing,
                    editor: editor
                )
            case .publishing:
                PublishingDestinationsOverview(selection: $selection, site: site, editor: editor)
            case .publishingDestination(let id):
                if let destination = site.publishingDestinations.first(where: { $0.id == id }) {
                    PublishingDestinationDetail(
                        site: site,
                        destination: destination,
                        isDefault: site.defaultPublishingDestinationID == id,
                        editor: editor
                    )
                    .id(destination.id)
                } else {
                    PublishingDestinationsOverview(selection: $selection, site: site, editor: editor)
                }
            case .code:
                CodeAndAnalyticsProjectSettingsView(
                    isEnabled: customCodeEnabled,
                    headCode: headCode,
                    bodyStartCode: bodyStartCode,
                    bodyEndCode: bodyEndCode,
                    analyticsCode: analyticsCode,
                    editor: editor
                )
            }
        }
        .frame(minWidth: 880, idealWidth: 1_000, minHeight: 560, idealHeight: 680)
    }
}

private struct PublishingDestinationsOverview: View {
    @Binding var selection: ProjectSettingsSection?
    let site: Site
    let editor: ProjectEditor

    @State private var name = ""
    @State private var kind = PublishingDestinationKind.local
    @State private var bookmarks: [PublishingDestinationBookmark] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Add a publishing destination")
                    .font(.title2.weight(.semibold))

                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                    ProjectSettingsGridRow("Name") {
                        TextField("Name", text: $name)
                            .labelsHidden()
                    }
                    ProjectSettingsGridRow("Publishing Method") {
                        Picker("Publishing Method", selection: $kind) {
                            ForEach(PublishingDestinationKind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                    }
                }

                HStack {
                    Button("Add Destination") {
                        let id = editor.addPublishingDestination(kind: kind, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                        name = ""
                        selection = .publishingDestination(id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !bookmarks.isEmpty {
                        Menu("Add From Bookmark") {
                            ForEach(bookmarks) { bookmark in
                                Button(bookmark.name) { add(bookmark) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Publishing")
        .onAppear { bookmarks = PublishingDestinationBookmarkStore.bookmarks() }
    }

    private func add(_ bookmark: PublishingDestinationBookmark) {
        let template = bookmark.destination
        let id = editor.addPublishingDestination(kind: template.kind, name: template.name)
        let destination = PublishingDestination(
            id: id,
            name: template.name,
            kind: template.kind,
            host: template.host,
            port: template.port,
            username: template.username,
            remotePath: template.remotePath,
            s3Bucket: template.s3Bucket,
            s3Region: template.s3Region,
            cleansObsoleteFiles: template.cleansObsoleteFiles
        )
        editor.updatePublishingDestination(destination)
        if let path = bookmark.localDirectoryPath {
            PublishingDestinationStore.setURL(URL(filePath: path), for: site.id, destinationID: id)
        }
        PublishingCredentialStore.setCredential(
            PublishingCredentialStore.credential(bookmarkID: bookmark.id),
            siteID: site.id,
            destinationID: id
        )
        selection = .publishingDestination(id)
    }
}

private struct PublishingDestinationDetail: View {
    let site: Site
    let destination: PublishingDestination
    let isDefault: Bool
    let editor: ProjectEditor

    @State private var credential: String
    @State private var statusMessage: String?
    @State private var statusSucceeded: Bool?
    @State private var bookmarkMessage: String?
    @State private var isTesting = false
    @State private var localDestination: URL?

    init(site: Site, destination: PublishingDestination, isDefault: Bool, editor: ProjectEditor) {
        self.site = site
        self.destination = destination
        self.isDefault = isDefault
        self.editor = editor
        _credential = State(initialValue: PublishingCredentialStore.credential(siteID: site.id, destinationID: destination.id))
        _localDestination = State(initialValue: PublishingDestinationStore.url(for: site.id, destinationID: destination.id))
    }

    var body: some View {
        Form {
            Section("Destination") {
                TextField("Name", text: binding(\.name))
                Picker("Publish To", selection: binding(\.kind)) {
                    ForEach(PublishingDestinationKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                if !isDefault {
                    Button("Make Default") { editor.setDefaultPublishingDestination(id: destination.id) }
                } else {
                    Label("Default destination", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section("Connection") {
                connectionFields
            }

            Section("Options") {
                Toggle("Remove obsolete files generated by Foundry", isOn: binding(\.cleansObsoleteFiles))
                Text("Cleanup uses Foundry’s export manifest and never removes unrelated files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if destination.kind == .local {
                        Button("Choose Folder…", action: chooseLocalDestination)
                        if localDestination != nil {
                            Button("Reveal Folder") {
                                if let url = localDestination {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                        }
                    } else {
                        Button("Test Connection", action: testConnection)
                            .buttonStyle(.borderedProminent)
                            .disabled(isTesting || !isConnectionConfigurationComplete)
                    }
                    if isTesting { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Save as Bookmark", action: saveBookmark)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusSucceeded == true ? .green : .red)
                }
                if let bookmarkMessage {
                    Text(bookmarkMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(destination.name)
    }

    @ViewBuilder
    private var connectionFields: some View {
        switch destination.kind {
        case .local:
            LabeledContent("Folder") {
                Text(localDestination?.path(percentEncoded: false) ?? "Not selected")
                    .foregroundStyle(.secondary)
            }
        case .amazonS3:
            TextField("Bucket", text: binding(\.s3Bucket))
            TextField("Region", text: binding(\.s3Region))
            TextField("Path Prefix", text: binding(\.remotePath))
            TextField("Access Key ID", text: binding(\.username))
            SecureField("Secret Access Key", text: credentialBinding)
        case .sftp, .ftp, .ftps:
            TextField("Host", text: binding(\.host))
            TextField("Port", value: binding(\.port), format: .number.grouping(.never))
            TextField("Username", text: binding(\.username))
            TextField("Remote Path", text: binding(\.remotePath))
            SecureField(destination.kind == .sftp ? "Password (Optional)" : "Password", text: credentialBinding)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PublishingDestination, Value>) -> Binding<Value> {
        Binding(
            get: { destination[keyPath: keyPath] },
            set: { value in
                var updated = destination
                updated[keyPath: keyPath] = value
                if keyPath == \PublishingDestination.kind, updated.port == destination.kind.defaultPort {
                    updated.port = updated.kind.defaultPort
                }
                editor.updatePublishingDestination(updated)
                statusMessage = nil
                statusSucceeded = nil
                bookmarkMessage = nil
            }
        )
    }

    private var credentialBinding: Binding<String> {
        Binding(
            get: { credential },
            set: { value in
                credential = value
                PublishingCredentialStore.setCredential(value, siteID: site.id, destinationID: destination.id)
                statusMessage = nil
                statusSucceeded = nil
                bookmarkMessage = nil
            }
        )
    }

    private func chooseLocalDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Publishing Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localDestination = url
        PublishingDestinationStore.setURL(url, for: site.id, destinationID: destination.id)
        editor.updatePublishingDestination(destination)
    }

    private func testConnection() {
        var configuredSite = site
        configuredSite.publishingDestination = destination.kind
        configuredSite.publishingHost = destination.host
        configuredSite.publishingPort = destination.port
        configuredSite.publishingUsername = destination.username
        configuredSite.publishingRemotePath = destination.remotePath
        configuredSite.publishingS3Bucket = destination.s3Bucket
        configuredSite.publishingS3Region = destination.s3Region
        isTesting = true
        statusMessage = nil
        statusSucceeded = nil
        Task {
            defer { isTesting = false }
            do {
                let result = try await SitePublisher().testConnection(site: configuredSite, credential: credential)
                statusMessage = result.message
                statusSucceeded = true
            } catch {
                statusMessage = error.localizedDescription
                statusSucceeded = false
            }
        }
    }

    private var isConnectionConfigurationComplete: Bool {
        let nonempty: (String) -> Bool = {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        switch destination.kind {
        case .local:
            return localDestination != nil
        case .sftp:
            return nonempty(destination.host) && nonempty(destination.username) && destination.port > 0
        case .ftp, .ftps:
            return nonempty(destination.host) && nonempty(destination.username) && nonempty(credential) && destination.port > 0
        case .amazonS3:
            return nonempty(destination.s3Bucket) && nonempty(destination.s3Region)
                && nonempty(destination.username) && nonempty(credential)
        }
    }

    private func saveBookmark() {
        PublishingDestinationBookmarkStore.save(
            destination: destination,
            localDirectory: localDestination,
            credential: credential
        )
        bookmarkMessage = "Bookmark saved. It is available to new and existing projects."
    }
}

private struct CodeAndAnalyticsProjectSettingsView: View {
    let isEnabled: Bool
    let headCode: String
    let bodyStartCode: String
    let bodyEndCode: String
    let analyticsCode: String
    let editor: ProjectEditor

    var body: some View {
        Form {
            Section("Custom Code") {
                Toggle(
                    "Enable custom code",
                    isOn: Binding(get: { isEnabled }, set: editor.setCustomCodeEnabled)
                )
                Text("Saved snippets are retained when disabled. Enabled code executes in canvas previews and exported pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Document Head") {
                codeEditor("Head Code", code: headCode, setter: editor.setSiteHeadCode)
                Text("Inserted inside <head> on every page. Use this for verification tags, preload links and site-wide styles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                validationMessage(for: headCode)
            }

            Section("Document Body") {
                codeEditor("After <body>", code: bodyStartCode, setter: editor.setSiteBodyStartCode)
                Text("Inserted immediately after the opening <body> tag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                validationMessage(for: bodyStartCode)

                codeEditor("Before </body>", code: bodyEndCode, setter: editor.setSiteBodyEndCode)
                Text("Inserted at the end of every page after Foundry’s part scripts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                validationMessage(for: bodyEndCode)
            }

            Section("Analytics") {
                codeEditor("Analytics Code", code: analyticsCode, setter: editor.setSiteAnalyticsCode)
                Text("Inserted near the end of <head>. Paste a complete analytics or tag-manager snippet supplied by your provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                validationMessage(for: analyticsCode)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Code & Analytics")
    }

    private func codeEditor(_ title: String, code: String, setter: @escaping (String) -> Void) -> some View {
        LabeledContent(title) {
            TextEditor(text: Binding(get: { code }, set: setter))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .padding(4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .disabled(!isEnabled)
        }
    }

    @ViewBuilder
    private func validationMessage(for code: String) -> some View {
        if let warning = markupWarning(for: code) {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func markupWarning(for code: String) -> String? {
        let lowercased = code.lowercased()
        if ["<html", "<head", "<body"].contains(where: lowercased.contains) {
            return "Paste only the contents for this location, without html, head or body wrapper tags."
        }
        if occurrenceCount(of: "<script", in: lowercased) != occurrenceCount(of: "</script>", in: lowercased) {
            return "This snippet appears to contain an unclosed script element."
        }
        if occurrenceCount(of: "<style", in: lowercased) != occurrenceCount(of: "</style>", in: lowercased) {
            return "This snippet appears to contain an unclosed style element."
        }
        return nil
    }

    private func occurrenceCount(of needle: String, in value: String) -> Int {
        value.components(separatedBy: needle).count - 1
    }
}

private struct SearchProjectSettingsView: View {
    let publicURL: String
    let generatesCanonicalURLs: Bool
    let generatesSitemap: Bool
    let generatesRobotsTXT: Bool
    let allowsSearchIndexing: Bool
    let editor: ProjectEditor

    var body: some View {
        ScrollView {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                ProjectSettingsGridRow("Search Options", alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Toggle(
                                "Allow search engines to index this site",
                                isOn: Binding(get: { allowsSearchIndexing }, set: editor.setAllowsSearchIndexing)
                            )
                            .toggleStyle(.checkbox)
                            Text(allowsSearchIndexing
                                 ? "Exported pages may be indexed by search engines."
                                 : "Exported pages include a noindex directive and robots.txt prevents crawling.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 20)
                        }

                        Toggle(
                            "Generate canonical URLs",
                            isOn: Binding(get: { generatesCanonicalURLs }, set: editor.setGeneratesCanonicalURLs)
                        )
                        .toggleStyle(.checkbox)
                        Toggle(
                            "Generate sitemap.xml",
                            isOn: Binding(get: { generatesSitemap }, set: editor.setGeneratesSitemap)
                        )
                        .toggleStyle(.checkbox)
                        Toggle(
                            "Generate robots.txt",
                            isOn: Binding(get: { generatesRobotsTXT }, set: editor.setGeneratesRobotsTXT)
                        )
                        .toggleStyle(.checkbox)

                        if needsPublicURL && !hasValidPublicURL {
                            Label("Set a valid Web Address in General to generate canonical URLs and a sitemap.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("SEO & Search")
    }

    private var needsPublicURL: Bool {
        generatesCanonicalURLs || generatesSitemap
    }

    private var hasValidPublicURL: Bool {
        guard let url = URL(string: publicURL),
              let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}

private struct PublishingProjectSettingsView: View {
    let site: Site
    let assetContents: [UUID: ProjectAssetContent]
    let publicURL: String
    let pages: [Page]
    let pageFolders: [PageFolder]
    let editor: ProjectEditor

    @State private var localDestination: URL?
    @State private var credential: String
    @State private var statusMessage: String?
    @State private var isTestingConnection = false
    @State private var connectionTask: Task<Void, Never>?

    init(
        site: Site,
        assetContents: [UUID: ProjectAssetContent],
        publicURL: String,
        pages: [Page],
        pageFolders: [PageFolder],
        editor: ProjectEditor
    ) {
        self.site = site
        self.assetContents = assetContents
        self.publicURL = publicURL
        self.pages = pages
        self.pageFolders = pageFolders
        self.editor = editor
        _localDestination = State(initialValue: PublishingDestinationStore.url(for: site.id))
        _credential = State(initialValue: PublishingCredentialStore.credential(site: site))
    }

    var body: some View {
        Form {
            Section("Destination") {
                Picker(
                    "Publish To",
                    selection: Binding(get: { site.publishingDestination }, set: editor.setPublishingDestination)
                ) {
                    ForEach(PublishingDestinationKind.allCases, id: \.self) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
                if site.publishingDestination == .local {
                    LabeledContent("Folder") {
                        HStack {
                            Text(localDestination?.path(percentEncoded: false) ?? "Not selected")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(localDestination == nil ? .secondary : .primary)
                            Button("Choose…", action: chooseLocalDestination)
                        }
                    }
                    Toggle(
                        "Remove obsolete files generated by Foundry",
                        isOn: Binding(get: { site.cleansObsoleteExportFiles }, set: editor.setCleansObsoleteExportFiles)
                    )
                    Text("Cleanup uses Foundry’s export manifest and never removes unrelated files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if site.publishingDestination == .amazonS3 {
                    TextField(
                        "Bucket",
                        text: Binding(get: { site.publishingS3Bucket }, set: editor.setPublishingS3Bucket)
                    )
                    TextField(
                        "Region",
                        text: Binding(get: { site.publishingS3Region }, set: editor.setPublishingS3Region),
                        prompt: Text("us-east-1").foregroundStyle(.secondary)
                    )
                    TextField(
                        "Path Prefix",
                        text: Binding(get: { site.publishingRemotePath }, set: editor.setPublishingRemotePath)
                    )
                    TextField(
                        "Access Key ID",
                        text: Binding(get: { site.publishingUsername }, set: editor.setPublishingUsername)
                    )
                    SecureField("Secret Access Key", text: credentialBinding)
                    Text("The secret access key is stored in your macOS Keychain, not in the project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField(
                        "Host",
                        text: Binding(get: { site.publishingHost }, set: editor.setPublishingHost)
                    )
                    TextField(
                        "Port",
                        value: Binding(get: { effectivePort }, set: editor.setPublishingPort),
                        format: .number.grouping(.never)
                    )
                    TextField(
                        "Username",
                        text: Binding(get: { site.publishingUsername }, set: editor.setPublishingUsername)
                    )
                    TextField(
                        "Remote Path",
                        text: Binding(get: { site.publishingRemotePath }, set: editor.setPublishingRemotePath),
                        prompt: Text("/public_html").foregroundStyle(.secondary)
                    )
                    if site.publishingDestination == .sftp {
                        SecureField("Password (Optional)", text: credentialBinding)
                        Text("SFTP supports your SSH keys and an optional password. Known hosts are verified using ~/.ssh/known_hosts; passwords are stored in the macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField("Password", text: credentialBinding)
                        Text(site.publishingDestination == .ftps
                             ? "FTPS requires explicit TLS. The password is stored in your macOS Keychain, not in the project."
                             : "FTP is unencrypted and should only be used with legacy hosting. The password is stored in your macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(site.publishingDestination == .ftp ? .orange : .secondary)
                    }
                }
            }

            Section("Published URLs") {
                Text("Foundry publishes pages as clean directory URLs. The home page is index.html; other pages are written as path/index.html.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(pages.prefix(4))) { page in
                    LabeledContent(page.title) {
                        Text(displayURL(for: page))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if pages.count > 4 {
                    Text("And \(pages.count - 4) more pages…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Generated Files") {
                ForEach(exportBundle.files, id: \.path) { file in
                    LabeledContent(file.path) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !publishingWarnings.isEmpty {
                Section("Warnings") {
                    ForEach(publishingWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                HStack {
                    if site.publishingDestination != .local {
                        Button("Test Connection", action: testConnection)
                            .disabled(!canPublish || isTestingConnection)
                    }
                    if site.publishingDestination == .local, localDestination != nil {
                        Button("Reveal Folder", systemImage: "macwindow.and.pointer.arrow") {
                            if let localDestination { NSWorkspace.shared.activateFileViewerSelecting([localDestination]) }
                        }
                    }
                    Spacer()
                }
                if isTestingConnection {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Testing connection…")
                        Spacer()
                        Button("Cancel") { connectionTask?.cancel() }
                    }
                    .font(.caption)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Publishing")
        .onChange(of: credentialKey) {
            credential = PublishingCredentialStore.credential(site: site)
        }
    }

    private var exportBundle: SiteExportBundle {
        StaticSiteRenderer().render(site: site, assets: assetContents)
    }

    private var effectivePort: Int {
        site.publishingPort == 0 ? site.publishingDestination.defaultPort : site.publishingPort
    }

    private var canPublish: Bool {
        switch site.publishingDestination {
        case .local: localDestination != nil
        case .sftp: remoteConfigurationIsComplete
        case .ftp, .ftps: remoteConfigurationIsComplete && !credential.isEmpty
        case .amazonS3:
            !site.publishingS3Bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !site.publishingS3Region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !site.publishingUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !credential.isEmpty
        }
    }

    private var remoteConfigurationIsComplete: Bool {
        !site.publishingHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !site.publishingUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !site.publishingRemotePath.contains("\n")
    }

    private var publishingWarnings: [String] {
        var warnings: [String] = []
        let missingAssets = site.assets.filter { assetContents[$0.id] == nil }
        if !missingAssets.isEmpty {
            warnings.append("\(missingAssets.count) project resource files are unavailable and cannot be published.")
        }
        let unavailableParts = site.pages.flatMap(\.parts).flatMap(\.flattened)
            .filter { part in
                part.packageLock != nil && part.type.definition.renderKind == .unavailable
            }
        if !unavailableParts.isEmpty {
            warnings.append("\(unavailableParts.count) parts use unavailable packages.")
        }
        if site.publishingDestination == .ftp {
            warnings.append("FTP sends credentials and content without encryption. Prefer SFTP or FTPS.")
        }
        return warnings
    }

    private var credentialKey: String {
        "\(site.publishingDestination.rawValue)|\(site.publishingHost)|\(site.publishingUsername)|\(site.publishingS3Bucket)"
    }

    private var credentialBinding: Binding<String> {
        Binding(
            get: { credential },
            set: { value in
                credential = value
                PublishingCredentialStore.setCredential(value, site: site)
            }
        )
    }

    private func chooseLocalDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Publishing Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = localDestination
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localDestination = url
        PublishingDestinationStore.setURL(url, for: site.id)
    }

    private func testConnection() {
        isTestingConnection = true
        statusMessage = nil
        connectionTask = Task {
            do {
                let result = try await SitePublisher().testConnection(site: site, credential: credential)
                statusMessage = result.message
            } catch is CancellationError {
                statusMessage = "Connection test cancelled."
            } catch {
                statusMessage = error.localizedDescription
            }
            isTestingConnection = false
            connectionTask = nil
        }
    }

    private var validBaseURL: String? {
        guard let url = URL(string: publicURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else { return nil }
        return publicURL.hasSuffix("/") ? String(publicURL.dropLast()) : publicURL
    }

    private func displayURL(for page: Page) -> String {
        let relativePath = relativeURL(for: page)
        return validBaseURL.map { $0 + relativePath } ?? relativePath
    }

    private func relativeURL(for page: Page) -> String {
        PageRouteResolver.path(for: page, pages: pages, folders: pageFolders)
    }
}

private struct GeneralProjectSettingsView: View {
    let siteName: String
    let language: String
    let publicURL: String
    let logo: String
    let logoAlt: String
    let allowsDarkMode: Bool
    let assets: [ProjectAsset]
    let assetContents: [UUID: ProjectAssetContent]
    let editor: ProjectEditor

    @State private var selectedLanguageCode: String
    @State private var customLanguage: String

    init(
        siteName: String,
        language: String,
        publicURL: String,
        logo: String,
        logoAlt: String,
        allowsDarkMode: Bool,
        assets: [ProjectAsset],
        assetContents: [UUID: ProjectAssetContent],
        editor: ProjectEditor
    ) {
        self.siteName = siteName
        self.language = language
        self.publicURL = publicURL
        self.logo = logo
        self.logoAlt = logoAlt
        self.allowsDarkMode = allowsDarkMode
        self.assets = assets
        self.assetContents = assetContents
        self.editor = editor
        let isCommonLanguage = Self.commonLanguages.contains { $0.code == language }
        _selectedLanguageCode = State(initialValue: isCommonLanguage ? language : Self.customLanguageCode)
        _customLanguage = State(initialValue: isCommonLanguage ? "" : language)
    }

    var body: some View {
        ScrollView {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                ProjectSettingsGridRow("Title") {
                    TextField(
                        "Title",
                        text: Binding(
                            get: { siteName },
                            set: editor.setSiteName
                        )
                    )
                    .labelsHidden()
                }

                ProjectSettingsGridRow("Web Address", alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        TextField(
                            "Web Address",
                            text: Binding(get: { publicURL }, set: editor.setSitePublicURL),
                            prompt: Text("https://example.com")
                                .foregroundStyle(.secondary)
                        )
                        .labelsHidden()
                        if !publicURL.isEmpty && !isValidPublicURL {
                            Text("Enter a complete HTTP or HTTPS URL, such as https://example.com.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                ProjectSettingsGridRow("Language", alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Language", selection: languageSelection) {
                            ForEach(Self.commonLanguages) { language in
                                Text("\(language.name) — \(language.code)")
                                    .tag(language.code)
                            }
                            Divider()
                            Text("Custom…").tag(Self.customLanguageCode)
                        }
                        .labelsHidden()
                        if selectedLanguageCode == Self.customLanguageCode {
                            TextField(
                                "Language Tag",
                                text: Binding(
                                    get: { customLanguage },
                                    set: { value in
                                        customLanguage = value
                                        editor.setSiteLanguage(value)
                                    }
                                ),
                                prompt: Text("e.g. cy or zh-Hant-TW")
                                    .foregroundStyle(.secondary)
                            )
                            .labelsHidden()
                        }
                        if selectedLanguageCode == Self.customLanguageCode,
                           !language.isEmpty,
                           !isValidLanguage {
                            Text("Enter a valid language tag, such as en, en-GB, or zh-Hant.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                ProjectSettingsGridRow("Logo", alignment: .top) {
                    SiteLogoImageWell(
                        selection: Binding(get: { logo }, set: editor.setSiteLogo),
                        assets: assets,
                        assetContents: assetContents,
                        importImage: editor.importSiteLogo
                    )
                }

                ProjectSettingsGridRow("Logo Alt") {
                    TextField(
                        "Logo Alt",
                        text: Binding(get: { logoAlt }, set: editor.setSiteLogoAlt),
                        prompt: Text("Describe the logo").foregroundStyle(.secondary)
                    )
                    .labelsHidden()
                }

                ProjectSettingsGridRow("Allow Dark Mode") {
                    Toggle(
                        "Allow Dark Mode",
                        isOn: Binding(get: { allowsDarkMode }, set: editor.setSiteAllowsDarkMode)
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("General")
    }

    private var isValidPublicURL: Bool {
        guard let url = URL(string: publicURL),
              let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private var isValidLanguage: Bool {
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard let languageCode = parts.first,
              (2...8).contains(languageCode.count),
              languageCode.allSatisfy(\.isLetter) else { return false }
        return parts.dropFirst().allSatisfy { part in
            (1...8).contains(part.count) && part.allSatisfy { character in
                character.isLetter || character.isNumber
            }
        }
    }

    private var languageSelection: Binding<String> {
        Binding(
            get: { selectedLanguageCode },
            set: { code in
                selectedLanguageCode = code
                if code == Self.customLanguageCode {
                    editor.setSiteLanguage(customLanguage)
                } else {
                    editor.setSiteLanguage(code)
                }
            }
        )
    }

    private static let customLanguageCode = "__custom__"

    private static let commonLanguages: [LanguageOption] = [
        .init(code: "en", name: "English"),
        .init(code: "en-GB", name: "English (United Kingdom)"),
        .init(code: "en-US", name: "English (United States)"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "es", name: "Spanish"),
        .init(code: "it", name: "Italian"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "zh-Hans", name: "Chinese (Simplified)"),
        .init(code: "zh-Hant", name: "Chinese (Traditional)")
    ]

    private struct LanguageOption: Identifiable {
        let code: String
        let name: String

        var id: String { code }
    }
}

private struct ProjectSettingsGridRow<Content: View>: View {
    let title: String
    let alignment: VerticalAlignment
    let content: Content

    init(
        _ title: String,
        alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        GridRow(alignment: alignment) {
            Text(title)
                .frame(width: 130, alignment: .trailing)
                .foregroundStyle(.primary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WebIconsProjectSettingsView: View {
    let favicon: String
    let assets: [ProjectAsset]
    let assetContents: [UUID: ProjectAssetContent]
    let editor: ProjectEditor

    var body: some View {
        ScrollView {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 18) {
                ProjectSettingsGridRow("Favicon", alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        WebIconImageWell(
                            selection: Binding(get: { favicon }, set: editor.setSiteFavicon),
                            assets: assets,
                            assetContents: assetContents,
                            importImage: editor.importSiteFavicon
                        )
                        .frame(width: 128, height: 128)
                        Text("Foundry generates favicon.ico, PNG favicons and Apple touch icons from a square image of at least 256 × 256 pixels.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            }
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Web Icons")
    }

}

private struct WebIconImageWell: View {
    @Binding var selection: String
    let assets: [ProjectAsset]
    let assetContents: [UUID: ProjectAssetContent]
    let importImage: (Data, String, String) -> Void

    @State private var isDropTargeted = false
    @State private var validationError: String?

    private static let allowedExtensions = Set(["jpeg", "jpg", "png", "tif", "tiff", "webp"])
    private static let maximumByteCount = 25 * 1_024 * 1_024

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: chooseImage) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)

                    if let image = selectedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(14)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }

                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to choose a square image, or drag one here.")
            .accessibilityLabel(selection.isEmpty ? "Choose Web Icon Source" : "Change Web Icon Source")

            if !selection.isEmpty {
                Button {
                    selection = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .padding(5)
                .help("Remove Web Icons")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.contains(where: acceptImageURL)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .contextMenu {
            if !selection.isEmpty {
                Button("Remove Web Icons", role: .destructive) {
                    selection = ""
                }
            }
        }
        .alert("Web Icon Source Not Accepted", isPresented: Binding(
            get: { validationError != nil },
            set: { if !$0 { validationError = nil } }
        )) {
            Button("OK") { validationError = nil }
        } message: {
            Text(validationError ?? "")
        }
    }

    private var selectedImage: NSImage? {
        guard let id = selection.foundryAssetID,
              let data = assetContents[id]?.data else { return nil }
        return NSImage(data: data)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Web Icon Source"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.allowedExtensions
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = acceptImageURL(url)
    }

    private func acceptImageURL(_ url: URL) -> Bool {
        if let id = draggedFoundryAssetID(from: url),
           let asset = assets.first(where: { $0.id == id }),
           let data = assetContents[id]?.data {
            return accept(
                data: data,
                filename: asset.filename,
                mediaType: asset.mediaType,
                existingAsset: asset
            )
        }

        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .contentTypeKey,
            .fileSizeKey
        ]),
        values.isRegularFile == true,
        (values.fileSize ?? 0) <= Self.maximumByteCount,
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension),
        type.conforms(to: .image),
        let data = try? Data(contentsOf: url),
        data.count <= Self.maximumByteCount else {
            validationError = "Choose a supported image no larger than 25 MB."
            return false
        }
        return accept(
            data: data,
            filename: url.lastPathComponent,
            mediaType: type.preferredMIMEType ?? "application/octet-stream",
            existingAsset: nil
        )
    }

    private func accept(
        data: Data,
        filename: String,
        mediaType: String,
        existingAsset: ProjectAsset?
    ) -> Bool {
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        guard Self.allowedExtensions.contains(fileExtension), mediaType.hasPrefix("image/") else {
            validationError = "Use a PNG, JPEG, WebP, or TIFF image."
            return false
        }
        if let error = WebIconGenerator.sourceValidationError(for: data) {
            validationError = error
            return false
        }
        validationError = nil
        if let existingAsset {
            selection = existingAsset.reference
        } else {
            importImage(data, filename, mediaType)
        }
        return true
    }

    private func draggedFoundryAssetID(from url: URL) -> UUID? {
        let filename = url.lastPathComponent
        let prefix = "foundry-image-asset-"
        guard filename.hasPrefix(prefix),
              let separator = filename.range(of: "--") else { return nil }
        let idStart = filename.index(filename.startIndex, offsetBy: prefix.count)
        return UUID(uuidString: String(filename[idStart..<separator.lowerBound]))
    }
}

private struct SiteIdentityProjectSettingsView: View {
    let titleSuffix: String
    let defaultDescription: String
    let defaultSocialImage: String
    let assets: [ProjectAsset]
    let editor: ProjectEditor

    var body: some View {
        ScrollView {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                ProjectSettingsGridRow("Title Suffix", alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        TextField(
                            "Title Suffix",
                            text: Binding(get: { titleSuffix }, set: editor.setSiteTitleSuffix),
                            prompt: Text(" – Site Name").foregroundStyle(.secondary)
                        )
                        .labelsHidden()
                        Text("Appended to page titles and used by social sharing when a page has no custom social title.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProjectSettingsGridRow("Description", alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        TextField(
                            "Description",
                            text: Binding(get: { defaultDescription }, set: editor.setSiteDefaultDescription),
                            prompt: Text("Default description for pages").foregroundStyle(.secondary),
                            axis: .vertical
                        )
                        .labelsHidden()
                        .lineLimit(3...6)
                        Text("Used for search and social metadata when a page does not provide its own description.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProjectSettingsGridRow("Social Image", alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        SiteLogoImageWell(
                            selection: Binding(get: { defaultSocialImage }, set: editor.setSiteDefaultSocialImage),
                            assets: imageAssets,
                            assetContents: editor.document.assetContents,
                            imageName: "Social Image",
                            importImage: { data, filename, mediaType in
                                importImage(data, filename: filename, mediaType: mediaType, setter: editor.setSiteDefaultSocialImage)
                            }
                        )
                        Text("Used when a page does not provide its own social image. Use a landscape image; 1200 × 630 pixels is the usual sharing size.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Site Identity")
    }

    private var imageAssets: [ProjectAsset] {
        assets
            .filter { $0.mediaType.hasPrefix("image/") }
            .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }


    private func importImage(
        _ data: Data,
        filename: String,
        mediaType: String,
        setter: (String) -> Void
    ) {
        let undoManager = editor.undoManager
        undoManager?.beginUndoGrouping()
        let id = editor.document.importAsset(
            data: data,
            filename: filename,
            mediaType: mediaType,
            undoManager: undoManager
        )
        setter("foundry-asset:\(id.uuidString)")
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Import Site Image")
    }
}

private struct SiteLogoImageWell: View {
    @Binding var selection: String
    let assets: [ProjectAsset]
    let assetContents: [UUID: ProjectAssetContent]
    let imageName: String
    let importImage: (Data, String, String) -> Void

    @State private var isDropTargeted = false

    init(
        selection: Binding<String>,
        assets: [ProjectAsset],
        assetContents: [UUID: ProjectAssetContent],
        imageName: String = "Logo",
        importImage: @escaping (Data, String, String) -> Void
    ) {
        _selection = selection
        self.assets = assets
        self.assetContents = assetContents
        self.imageName = imageName
        self.importImage = importImage
    }

    private static let allowedExtensions = Set([
        "avif", "gif", "jpeg", "jpg", "png", "svg", "webp"
    ])
    private static let maximumByteCount = 25 * 1_024 * 1_024

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: chooseImage) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)

                    if let image = selectedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }

                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to choose a \(imageName.lowercased()), or drag an image here.")
            .accessibilityLabel(selection.isEmpty ? "Choose \(imageName)" : "Change \(imageName)")

            if !selection.isEmpty {
                Button {
                    selection = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .padding(5)
                .help("Remove \(imageName)")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.contains(where: acceptImageURL)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .contextMenu {
            if !selection.isEmpty {
                Button("Remove \(imageName)", role: .destructive) {
                    selection = ""
                }
            }
        }
    }

    private var selectedImage: NSImage? {
        guard let id = selection.foundryAssetID,
              let data = assetContents[id]?.data else { return nil }
        return NSImage(data: data)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a \(imageName)"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.allowedExtensions
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = acceptImageURL(url)
    }

    private func acceptImageURL(_ url: URL) -> Bool {
        if let id = draggedFoundryAssetID(from: url),
           let asset = assets.first(where: { $0.id == id }),
           isAllowed(filename: asset.filename, mediaType: asset.mediaType) {
            selection = asset.reference
            return true
        }

        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .contentTypeKey,
            .fileSizeKey
        ]),
        values.isRegularFile == true,
        (values.fileSize ?? 0) <= Self.maximumByteCount,
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension),
        type.conforms(to: .image),
        isAllowed(filename: url.lastPathComponent, mediaType: type.preferredMIMEType),
        let data = try? Data(contentsOf: url),
        data.count <= Self.maximumByteCount else { return false }

        importImage(
            data,
            url.lastPathComponent,
            type.preferredMIMEType ?? "application/octet-stream"
        )
        return true
    }

    private func isAllowed(filename: String, mediaType: String?) -> Bool {
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        guard Self.allowedExtensions.contains(fileExtension) else { return false }
        guard let mediaType else { return true }
        return mediaType.hasPrefix("image/") || mediaType == "application/xml"
    }

    private func draggedFoundryAssetID(from url: URL) -> UUID? {
        let filename = url.lastPathComponent
        let prefix = "foundry-image-asset-"
        guard filename.hasPrefix(prefix),
              let separator = filename.range(of: "--") else { return nil }
        let idStart = filename.index(filename.startIndex, offsetBy: prefix.count)
        return UUID(uuidString: String(filename[idStart..<separator.lowerBound]))
    }
}
