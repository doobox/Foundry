import SwiftUI

struct LinkComponentControl: View {
    @State private var showsEditor = false
    @State private var draft = ComponentLink()

    let label: String
    let subtitle: String?
    let currentLink: ComponentLink
    let summary: String
    let indicator: InspectorRowIndicator?
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let publicURL: String
    let absoluteURL: Bool
    let update: (ComponentLink) -> Void

    var body: some View {
        InspectorRow(title: label, alignment: .top, indicator: indicator) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button(summary) {
                        draft = currentLink
                        if draft.destination == .none {
                            draft.destination = .url("")
                        }
                        showsEditor = true
                    }
                    if currentLink.destination != .none {
                        Button {
                            update(.init())
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Clear link")
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showsEditor) {
                ComponentLinkEditor(
                    link: $draft,
                    pages: pages,
                    folders: folders,
                    assets: assets,
                    publicURL: publicURL,
                    absoluteURL: absoluteURL,
                    cancel: { showsEditor = false },
                    apply: {
                        update(draft)
                        showsEditor = false
                    }
                )
            }
        }
    }
}

#Preview {
    ComponentControlPreview {
        LinkComponentControl(
            label: "Link",
            subtitle: "Choose where this link should lead.",
            currentLink: .init(),
            summary: "Choose Link…",
            indicator: .preview,
            pages: [],
            folders: [],
            assets: [],
            publicURL: "https://example.com",
            absoluteURL: false,
            update: { _ in }
        )
    }
}

struct ComponentLinkEditor: View {
    @Binding var link: ComponentLink
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let publicURL: String
    let absoluteURL: Bool
    var remove: (() -> Void)? = nil
    let cancel: () -> Void
    let apply: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Form {
                Picker("Type", selection: kindBinding) {
                    Text("URL").tag(LinkKind.url)
                    Text("Plain Text").tag(LinkKind.plainText)
                    Text("Page").tag(LinkKind.page)
                    Text("Resource").tag(LinkKind.resource)
                }
                destinationEditor
                TextField("Anchor", text: $link.anchor, prompt: Text("Optional anchor"))
                Toggle("Open in New Window", isOn: $link.opensInNewWindow)
                if absoluteURL && publicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isInternalLink {
                    Label("Set the Site URL in Project Settings to produce an absolute URL.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Section("Custom Attributes") {
                    ForEach($link.attributes) { $attribute in
                        HStack {
                            TextField("Name", text: $attribute.name)
                            TextField("Value", text: $attribute.value)
                            Button(role: .destructive) {
                                link.attributes.removeAll { $0.id == attribute.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Attribute", systemImage: "plus") {
                        link.attributes.append(.init())
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if let remove {
                    Button("Remove", role: .destructive, action: remove)
                }
                Spacer()
                Button("Cancel", action: cancel)
                Button("Set Link", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 680, height: 500)
    }

    @ViewBuilder
    private var destinationEditor: some View {
        switch link.destination {
        case .url(let value):
            TextField("URL", text: destinationTextBinding(value, kind: .url), prompt: Text("https://example.com"))
        case .plainText(let value):
            TextField("Text", text: destinationTextBinding(value, kind: .plainText))
        case .page(let id):
            Picker("Page", selection: destinationIDBinding(id, kind: .page)) {
                Text("Choose a page").tag(nil as UUID?)
                ForEach(pages) { page in Text(page.title).tag(page.id as UUID?) }
            }
        case .resource(let id):
            Picker("Resource", selection: destinationIDBinding(id, kind: .resource)) {
                Text("Choose a resource").tag(nil as UUID?)
                ForEach(assets) { asset in Text(asset.filename).tag(asset.id as UUID?) }
            }
        case .none:
            TextField(
                "URL",
                text: destinationTextBinding("", kind: .url),
                prompt: Text("https://example.com")
            )
        }
    }

    private var kindBinding: Binding<LinkKind> {
        Binding(get: {
            switch link.destination {
            case .url: .url
            case .plainText: .plainText
            case .page: .page
            case .resource: .resource
            case .none: .url
            }
        }, set: { kind in
            switch kind {
            case .url: link.destination = .url("")
            case .plainText: link.destination = .plainText("")
            case .page: link.destination = .page(pages.first?.id ?? UUID())
            case .resource: link.destination = .resource(assets.first?.id ?? UUID())
            }
        })
    }

    private func destinationTextBinding(_ value: String, kind: LinkKind) -> Binding<String> {
        Binding(get: {
            switch link.destination {
            case .url(let value), .plainText(let value): value
            default: value
            }
        }, set: { link.destination = kind == .url ? .url($0) : .plainText($0) })
    }

    private func destinationIDBinding(_ value: UUID, kind: LinkKind) -> Binding<UUID?> {
        Binding(get: {
            switch link.destination {
            case .page(let id), .resource(let id): id
            default: value
            }
        }, set: { id in
            guard let id else { link.destination = .none; return }
            link.destination = kind == .page ? .page(id) : .resource(id)
        })
    }

    private var isInternalLink: Bool {
        if case .page = link.destination { return true }
        if case .resource = link.destination { return true }
        return false
    }

    private var isValid: Bool {
        switch link.destination {
        case .none: false
        case .url(let value), .plainText(let value): !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .page(let id): pages.contains { $0.id == id }
        case .resource(let id): assets.contains { $0.id == id }
        }
    }

    private enum LinkKind: Hashable { case url, plainText, page, resource }
}
