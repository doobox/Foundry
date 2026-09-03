import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ProjectSettingsSection: String, Identifiable {
    case general
    case identity
    case publishing
    case code

    var id: String { rawValue }
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

    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(ProjectSettingsSection.general)
                Label("Site Identity", systemImage: "globe")
                    .tag(ProjectSettingsSection.identity)
                Label("Publishing", systemImage: "arrow.up.circle")
                    .tag(ProjectSettingsSection.publishing)
                Label("Code & Analytics", systemImage: "chevron.left.forwardslash.chevron.right")
                    .tag(ProjectSettingsSection.code)
            }
            .navigationTitle("Project Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                switch selection ?? .general {
                case .general:
                    GeneralProjectSettingsView(
                        siteName: siteName,
                        language: language,
                        publicURL: publicURL,
                        editor: editor
                    )
                case .identity:
                    SiteIdentityProjectSettingsView(
                        siteName: siteName,
                        publicURL: publicURL,
                        titleSuffix: titleSuffix,
                        defaultDescription: defaultDescription,
                        favicon: favicon,
                        defaultSocialImage: defaultSocialImage,
                        pages: pages,
                        assets: assets,
                        editor: editor,
                        openPageMetadata: openPageMetadata
                    )
                case .publishing:
                    PublishingProjectSettingsView(
                        site: site,
                        assetContents: assetContents,
                        publicURL: publicURL,
                        pages: pages,
                        pageFolders: pageFolders,
                        generatesCanonicalURLs: generatesCanonicalURLs,
                        generatesSitemap: generatesSitemap,
                        generatesRobotsTXT: generatesRobotsTXT,
                        allowsSearchIndexing: allowsSearchIndexing,
                        editor: editor
                    )
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
                Divider()
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 420, idealHeight: 480)
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
                Text("Inserted at the end of every page after Foundry’s component scripts.")
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

private struct PublishingProjectSettingsView: View {
    let site: Site
    let assetContents: [UUID: ProjectAssetContent]
    let publicURL: String
    let pages: [Page]
    let pageFolders: [PageFolder]
    let generatesCanonicalURLs: Bool
    let generatesSitemap: Bool
    let generatesRobotsTXT: Bool
    let allowsSearchIndexing: Bool
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
        generatesCanonicalURLs: Bool,
        generatesSitemap: Bool,
        generatesRobotsTXT: Bool,
        allowsSearchIndexing: Bool,
        editor: ProjectEditor
    ) {
        self.site = site
        self.assetContents = assetContents
        self.publicURL = publicURL
        self.pages = pages
        self.pageFolders = pageFolders
        self.generatesCanonicalURLs = generatesCanonicalURLs
        self.generatesSitemap = generatesSitemap
        self.generatesRobotsTXT = generatesRobotsTXT
        self.allowsSearchIndexing = allowsSearchIndexing
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

            Section("Search Engines") {
                Toggle(
                    "Allow search engines to index this site",
                    isOn: Binding(get: { allowsSearchIndexing }, set: editor.setAllowsSearchIndexing)
                )
                Text(allowsSearchIndexing
                     ? "Exported pages may be indexed by search engines."
                     : "Exported pages include a noindex directive and robots.txt blocks crawling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(
                    "Generate canonical URLs",
                    isOn: Binding(get: { generatesCanonicalURLs }, set: editor.setGeneratesCanonicalURLs)
                )
                Toggle(
                    "Generate sitemap.xml",
                    isOn: Binding(get: { generatesSitemap }, set: editor.setGeneratesSitemap)
                )
                Toggle(
                    "Generate robots.txt",
                    isOn: Binding(get: { generatesRobotsTXT }, set: editor.setGeneratesRobotsTXT)
                )
                if needsPublicURL && validBaseURL == nil {
                    Label("Set a valid Site URL in General to generate canonical URLs and a sitemap.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
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

    private var needsPublicURL: Bool {
        generatesCanonicalURLs || generatesSitemap
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
        let unavailableComponents = site.pages.flatMap(\.components).flatMap(\.flattened)
            .filter { component in
                component.packageLock != nil && component.type.definition.renderKind == .unavailable
            }
        if !unavailableComponents.isEmpty {
            warnings.append("\(unavailableComponents.count) components use unavailable packages.")
        }
        if needsPublicURL && validBaseURL == nil {
            warnings.append("Canonical URLs and sitemap.xml require a valid Site URL.")
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
                try await SitePublisher().testConnection(site: site, credential: credential)
                statusMessage = "Connection succeeded."
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
    let editor: ProjectEditor

    @State private var selectedLanguageCode: String
    @State private var customLanguage: String

    init(siteName: String, language: String, publicURL: String, editor: ProjectEditor) {
        self.siteName = siteName
        self.language = language
        self.publicURL = publicURL
        self.editor = editor
        let isCommonLanguage = Self.commonLanguages.contains { $0.code == language }
        _selectedLanguageCode = State(initialValue: isCommonLanguage ? language : Self.customLanguageCode)
        _customLanguage = State(initialValue: isCommonLanguage ? "" : language)
    }

    var body: some View {
        Form {
            Section("General") {
                TextField(
                    "Site Name",
                    text: Binding(
                        get: { siteName },
                        set: editor.setSiteName
                    )
                )
                Picker("Language", selection: languageSelection) {
                    ForEach(Self.commonLanguages) { language in
                        Text("\(language.name) — \(language.code)")
                            .tag(language.code)
                    }
                    Divider()
                    Text("Custom…").tag(Self.customLanguageCode)
                }
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
                }
                Text("Sets the language of exported pages for browsers, search engines and assistive technologies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if selectedLanguageCode == Self.customLanguageCode,
                   !language.isEmpty,
                   !isValidLanguage {
                    Text("Enter a valid language tag, such as en, en-GB, or zh-Hant.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TextField(
                    "Site URL",
                    text: Binding(get: { publicURL }, set: editor.setSitePublicURL),
                    prompt: Text("https://example.com")
                        .foregroundStyle(.secondary)
                )
                Text("Used to create absolute links to pages and resources. Include http:// or https://. Foundry removes a trailing slash automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !publicURL.isEmpty && !isValidPublicURL {
                    Text("Enter a complete HTTP or HTTPS URL, such as https://example.com.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
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

private struct SiteIdentityProjectSettingsView: View {
    let siteName: String
    let publicURL: String
    let titleSuffix: String
    let defaultDescription: String
    let favicon: String
    let defaultSocialImage: String
    let pages: [Page]
    let assets: [ProjectAsset]
    let editor: ProjectEditor
    let openPageMetadata: (UUID) -> Void

    @State private var selectedPreviewPageID: UUID?

    var body: some View {
        Form {
            Section("Browser") {
                TextField(
                    "Title Suffix",
                    text: Binding(get: { titleSuffix }, set: editor.setSiteTitleSuffix),
                    prompt: Text(" – Site Name").foregroundStyle(.secondary)
                )
                Text("Appended to page titles in the browser and used by social sharing when a page has no custom social title.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SiteIdentityImageField(
                    title: "Site Icon",
                    guidance: "Square PNG, SVG or ICO files work best. A 512 × 512 source gives browsers room to scale.",
                    selection: Binding(get: { favicon }, set: editor.setSiteFavicon),
                    assets: imageAssets,
                    assetContents: editor.document.assetContents,
                    importImage: { data, filename, mediaType in
                        importImage(data, filename: filename, mediaType: mediaType, setter: editor.setSiteFavicon)
                    }
                )
            }

            Section("Defaults") {
                TextField(
                    "Description",
                    text: Binding(get: { defaultDescription }, set: editor.setSiteDefaultDescription),
                    prompt: Text("Default description for pages").foregroundStyle(.secondary),
                    axis: .vertical
                )
                .lineLimit(3...6)
                Text("Used for search and social metadata when a page does not provide its own description.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SiteIdentityImageField(
                    title: "Social Image",
                    guidance: "Use a landscape image. 1200 × 630 pixels is the usual social-sharing size.",
                    selection: Binding(get: { defaultSocialImage }, set: editor.setSiteDefaultSocialImage),
                    assets: imageAssets,
                    assetContents: editor.document.assetContents,
                    importImage: { data, filename, mediaType in
                        importImage(data, filename: filename, mediaType: mediaType, setter: editor.setSiteDefaultSocialImage)
                    }
                )
            }

            Section("Social Preview") {
                Picker("Preview Page", selection: $selectedPreviewPageID) {
                    ForEach(pages) { page in
                        Text(page.title).tag(Optional(page.id))
                    }
                }
                if let previewPage {
                    metadataSourceRow("Title", source: titleSource)
                    metadataSourceRow("Description", source: descriptionSource)
                    metadataSourceRow("Image", source: imageSource)
                    if effectiveDescription.isEmpty || effectiveImageReference.isEmpty {
                        Label(missingMetadataMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    SocialMetadataPreview(
                        title: effectiveTitle,
                        description: effectiveDescription,
                        siteName: siteName,
                        publicURL: publicURL,
                        image: image(for: effectiveImageReference)
                    )
                    HStack {
                        Text("Title \(effectiveTitle.count)/60 · Description \(effectiveDescription.count)/160")
                            .font(.caption)
                            .foregroundStyle(characterCountColor)
                        Spacer()
                        Button("Open Page Metadata") {
                            openPageMetadata(previewPage.id)
                        }
                    }
                } else {
                    ContentUnavailableView("No Pages", systemImage: "doc")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Site Identity")
        .onAppear {
            if selectedPreviewPageID == nil {
                selectedPreviewPageID = pages.first?.id
            }
        }
    }

    private var imageAssets: [ProjectAsset] {
        assets
            .filter { $0.mediaType.hasPrefix("image/") }
            .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    private func image(for reference: String) -> NSImage? {
        guard let id = reference.foundryAssetID,
              let data = editor.document.assetContents[id]?.data else { return nil }
        return NSImage(data: data)
    }

    private var previewPage: Page? {
        guard let selectedPreviewPageID else { return pages.first }
        return pages.first(where: { $0.id == selectedPreviewPageID }) ?? pages.first
    }

    private var effectiveTitle: String {
        guard let page = previewPage else { return "" }
        if !page.metadata.socialTitle.isEmpty { return page.metadata.socialTitle }
        let pageTitle = page.metadata.browserTitle.isEmpty ? page.title : page.metadata.browserTitle
        return pageTitle + titleSuffix
    }

    private var effectiveDescription: String {
        guard let page = previewPage else { return defaultDescription }
        if !page.metadata.socialDescription.isEmpty { return page.metadata.socialDescription }
        return page.metadata.description.isEmpty ? defaultDescription : page.metadata.description
    }

    private var effectiveImageReference: String {
        guard let page = previewPage else { return defaultSocialImage }
        return page.metadata.socialImage.isEmpty ? defaultSocialImage : page.metadata.socialImage
    }

    private var titleSource: String {
        guard let page = previewPage else { return "Site default" }
        if !page.metadata.socialTitle.isEmpty || !page.metadata.browserTitle.isEmpty { return "Page override" }
        return "Page title + site suffix"
    }

    private var descriptionSource: String {
        guard let page = previewPage else { return "Site default" }
        return page.metadata.socialDescription.isEmpty && page.metadata.description.isEmpty
            ? "Site default"
            : "Page override"
    }

    private var imageSource: String {
        guard let page = previewPage else { return "Site default" }
        return page.metadata.socialImage.isEmpty ? "Site default" : "Page override"
    }

    private var missingMetadataMessage: String {
        switch (effectiveDescription.isEmpty, effectiveImageReference.isEmpty) {
        case (true, true): "Add a description and social image for a complete sharing card."
        case (true, false): "Add a description for a complete sharing card."
        case (false, true): "Add a social image for a complete sharing card."
        case (false, false): ""
        }
    }

    private var characterCountColor: Color {
        effectiveTitle.count > 60 || effectiveDescription.count > 160 ? .orange : .secondary
    }

    private func metadataSourceRow(_ title: String, source: String) -> some View {
        LabeledContent(title) {
            Text(source)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

private struct SiteIdentityImageField: View {
    let title: String
    let guidance: String
    @Binding var selection: String
    let assets: [ProjectAsset]
    let assetContents: [UUID: ProjectAssetContent]
    let importImage: (Data, String, String) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    imagePreview
                    Picker("", selection: $selection) {
                        Text("None").tag("")
                        ForEach(assets) { asset in
                            Text(asset.filename).tag(asset.reference)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                Text(guidance + " Drag an image here to import it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.quaternary.opacity(isDropTargeted ? 1 : 0), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: acceptImageProviders)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = selectedImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var selectedImage: NSImage? {
        guard let id = selection.foundryAssetID,
              let data = assetContents[id]?.data else { return nil }
        return NSImage(data: data)
    }

    private func acceptImageProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
                  values.isRegularFile == true,
                  let type = values.contentType ?? UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image),
                  let data = try? Data(contentsOf: url) else { return }
            let filename = provider.suggestedName.flatMap { suggestedName in
                (suggestedName as NSString).pathExtension.isEmpty
                    ? suggestedName + "." + url.pathExtension
                    : suggestedName
            } ?? url.lastPathComponent
            Task { @MainActor in
                importImage(data, filename, type.preferredMIMEType ?? "application/octet-stream")
            }
        }
        return true
    }
}

private struct SocialMetadataPreview: View {
    let title: String
    let description: String
    let siteName: String
    let publicURL: String
    let image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 150)
                    .clipped()
            } else {
                ZStack {
                    Color.secondary.opacity(0.08)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
                .frame(height: 110)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(previewHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title.isEmpty ? "Page Title" : title)
                    .font(.headline)
                    .lineLimit(2)
                Text(description.isEmpty ? "Your default site description will appear here." : description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var previewHost: String {
        URL(string: publicURL)?.host ?? (siteName.isEmpty ? "Your Website" : siteName)
    }
}
