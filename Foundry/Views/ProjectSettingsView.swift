import SwiftUI

private enum ProjectSettingsSection: String, Identifiable {
    case general

    var id: String { rawValue }
}

struct ProjectSettingsView: View {
    let siteName: String
    let language: String
    let publicURL: String
    let editor: ProjectEditor

    @Environment(\.dismiss) private var dismiss
    @State private var selection: ProjectSettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(ProjectSettingsSection.general)
            }
            .navigationTitle("Project Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                GeneralProjectSettingsView(
                    siteName: siteName,
                    language: language,
                    publicURL: publicURL,
                    editor: editor
                )
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
                TextField(
                    "Site URL",
                    text: Binding(get: { publicURL }, set: editor.setSitePublicURL),
                    prompt: Text("https://example.com")
                        .foregroundStyle(.secondary)
                )
                Text("Used to create absolute links to pages and resources. Include https:// and omit a trailing slash.")
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
}
