import SwiftUI

private enum ProjectSettingsSection: String, Identifiable {
    case general
    case identity

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
                        titleSuffix: titleSuffix,
                        defaultDescription: defaultDescription,
                        favicon: favicon,
                        defaultSocialImage: defaultSocialImage,
                        assets: assets,
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

private struct GeneralProjectSettingsView: View {
    let siteName: String
    let language: String
    let publicURL: String
    let editor: ProjectEditor

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
                TextField(
                    "Language",
                    text: Binding(
                        get: { language },
                        set: editor.setSiteLanguage
                    ),
                    prompt: Text("en")
                )
                Text("Use a language code such as en, en-GB, or fr.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !language.isEmpty && !isValidLanguage {
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
        let parts = language.split(separator: "-", omittingEmptySubsequences: false)
        guard let languageCode = parts.first,
              (2...3).contains(languageCode.count),
              languageCode.allSatisfy(\.isLetter) else { return false }
        return parts.dropFirst().allSatisfy { part in
            (1...8).contains(part.count) && part.allSatisfy { character in
                character.isLetter || character.isNumber
            }
        }
    }
}

private struct SiteIdentityProjectSettingsView: View {
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
                imagePicker(
                    "Site Icon",
                    selection: Binding(get: { favicon }, set: editor.setSiteFavicon)
                )
                Text("Used as the favicon in exported pages. Add image files to Project Resources before selecting one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                imagePicker(
                    "Social Image",
                    selection: Binding(get: { defaultSocialImage }, set: editor.setSiteDefaultSocialImage)
                )
                Text("Used for social sharing when a page does not provide its own image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func imagePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag("")
            ForEach(imageAssets) { asset in
                Text(asset.filename).tag(asset.reference)
            }
        }
    }
}
