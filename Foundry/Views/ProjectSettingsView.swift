import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ProjectSettingsSection: String, Identifiable {
    case general
    case identity
    case publishing

    var id: String { rawValue }
}

struct ProjectSettingsView: View {
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
    let editor: ProjectEditor

    @Environment(\.dismiss) private var dismiss
    @State private var selection: ProjectSettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(ProjectSettingsSection.general)
                Label("Site Identity", systemImage: "globe")
                    .tag(ProjectSettingsSection.identity)
                Label("Publishing", systemImage: "arrow.up.circle")
                    .tag(ProjectSettingsSection.publishing)
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
                        assets: assets,
                        editor: editor
                    )
                case .publishing:
                    PublishingProjectSettingsView(
                        publicURL: publicURL,
                        pages: pages,
                        pageFolders: pageFolders,
                        generatesCanonicalURLs: generatesCanonicalURLs,
                        generatesSitemap: generatesSitemap,
                        generatesRobotsTXT: generatesRobotsTXT,
                        allowsSearchIndexing: allowsSearchIndexing,
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

private struct PublishingProjectSettingsView: View {
    let publicURL: String
    let pages: [Page]
    let pageFolders: [PageFolder]
    let generatesCanonicalURLs: Bool
    let generatesSitemap: Bool
    let generatesRobotsTXT: Bool
    let allowsSearchIndexing: Bool
    let editor: ProjectEditor

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .navigationTitle("Publishing")
    }

    private var needsPublicURL: Bool {
        generatesCanonicalURLs || generatesSitemap
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
        guard page.slug != "index" else { return "/" }
        var currentID = page.folderID
        var slugs: [String] = []
        var visited = Set<UUID>()
        while let id = currentID,
              visited.insert(id).inserted,
              let folder = pageFolders.first(where: { $0.id == id }) {
            slugs.insert(folder.slug, at: 0)
            currentID = folder.parentID
        }
        slugs.append(page.slug)
        return "/" + slugs.joined(separator: "/") + "/"
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
    let assets: [ProjectAsset]
    let editor: ProjectEditor

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
                SocialMetadataPreview(
                    title: "Page Title" + titleSuffix,
                    description: defaultDescription,
                    siteName: siteName,
                    publicURL: publicURL,
                    image: image(for: defaultSocialImage)
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Site Identity")
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
