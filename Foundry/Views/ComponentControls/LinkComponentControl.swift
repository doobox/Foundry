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
    let assetLibrary: [ProjectAssetNode]
    let anchorsForPage: (Page) -> [String]
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
                    assetLibrary: assetLibrary,
                    anchorsForPage: anchorsForPage,
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
            assetLibrary: [],
            anchorsForPage: { _ in [] },
            publicURL: "https://example.com",
            absoluteURL: false,
            update: { _ in }
        )
    }
}

struct ComponentLinkEditor: View {
    private let leadingColumnWidth: CGFloat = 140

    @Binding var link: ComponentLink
    @State private var selectedAttributeID: UUID?
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let assetLibrary: [ProjectAssetNode]
    let anchorsForPage: (Page) -> [String]
    let publicURL: String
    let absoluteURL: Bool
    var remove: (() -> Void)? = nil
    let cancel: () -> Void
    let apply: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow(alignment: .firstTextBaseline) {
                    Menu {
                        Button("URL") { selectKind(.url) }
                        Button("Plain Text") { selectKind(.plainText) }
                        Divider()
                        Menu("Page") {
                            pageMenu(folderID: nil, parentPageID: nil)
                        }
                        .disabled(pages.isEmpty)
                        Menu("Resource") {
                            resourceMenu(nodes: assetLibrary)
                        }
                        .disabled(assets.isEmpty)
                    } label: {
                        HStack {
                            Text(kindTitle)
                            Spacer()
                        }
                    }
                    .menuStyle(.button)
                    .buttonSizing(.flexible)
                    .frame(width: leadingColumnWidth)

                    destinationEditor
                        .frame(maxWidth: .infinity)
                }

                GridRow(alignment: .firstTextBaseline) {
                    Text("Anchor:")
                        .frame(width: leadingColumnWidth, alignment: .trailing)

                    HStack(spacing: 12) {
                        Picker("Anchor", selection: $link.anchor) {
                            Text("None").tag("")
                            ForEach(availableAnchors, id: \.self) { anchor in
                                Text(anchor).tag(anchor)
                            }
                        }
                        .labelsHidden()
                        .buttonSizing(.flexible)
                            .disabled(selectedPage == nil)
                        Toggle("Open in New Window", isOn: $link.opensInNewWindow)
                            .fixedSize()
                    }
                }

                if absoluteURL && publicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isInternalLink {
                    GridRow {
                        Color.clear
                            .frame(height: 0)
                        Label("Set the Site URL in Project Settings to produce an absolute URL.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                GridRow(alignment: .top) {
                    Text("Custom Attributes:")
                        .frame(width: leadingColumnWidth, alignment: .trailing)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 6) {
                        Table($link.attributes, selection: $selectedAttributeID) {
                            TableColumn("Name") { $attribute in
                                TextField("Name", text: $attribute.name)
                                    .labelsHidden()
                                    .textFieldStyle(.plain)
                            }
                            TableColumn("Value") { $attribute in
                                TextField("Value", text: $attribute.value)
                                    .labelsHidden()
                                    .textFieldStyle(.plain)
                            }
                        }
                        .frame(minHeight: 134, maxHeight: .infinity)

                        HStack(spacing: 4) {
                            Button {
                                let attribute = ComponentLink.Attribute()
                                link.attributes.append(attribute)
                                selectedAttributeID = attribute.id
                            } label: {
                                Image(systemName: "plus")
                            }
                            .help("Add attribute")

                            Button {
                                guard let selectedAttributeID else { return }
                                link.attributes.removeAll { $0.id == selectedAttributeID }
                                self.selectedAttributeID = nil
                            } label: {
                                Image(systemName: "minus")
                            }
                            .disabled(selectedAttributeID == nil)
                            .help("Remove selected attribute")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxHeight: .infinity)

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
        .frame(width: 520, height: 350)
    }

    @ViewBuilder
    private var destinationEditor: some View {
        switch link.destination {
        case .url(let value):
            TextField("URL", text: destinationTextBinding(value, kind: .url), prompt: Text("https://example.com"))
        case .plainText(let value):
            TextField("Text", text: destinationTextBinding(value, kind: .plainText))
        case .page(let id):
            TextField("Page", text: .constant(pages.first { $0.id == id }?.title ?? "Missing Page"))
                .labelsHidden()
                .disabled(true)
        case .resource(let id):
            TextField("Resource", text: .constant(assets.first { $0.id == id }?.filename ?? "Missing Resource"))
                .labelsHidden()
                .disabled(true)
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

    private var kindTitle: String {
        switch link.destination {
        case .url, .none: "URL"
        case .plainText: "Plain Text"
        case .page: "Page"
        case .resource: "Resource"
        }
    }

    private var selectedPage: Page? {
        guard case .page(let id) = link.destination else { return nil }
        return pages.first { $0.id == id }
    }

    private var availableAnchors: [String] {
        guard let selectedPage else { return [] }
        let anchors = anchorsForPage(selectedPage)
        if !link.anchor.isEmpty, !anchors.contains(link.anchor) {
            return [link.anchor] + anchors
        }
        return anchors
    }

    private func selectKind(_ kind: LinkKind) {
        link.anchor = ""
        switch kind {
        case .url: link.destination = .url("")
        case .plainText: link.destination = .plainText("")
        case .page, .resource: break
        }
    }

    private func selectPage(_ page: Page) {
        link.destination = .page(page.id)
        link.anchor = ""
        setTitleAttribute(page.title)
    }

    private func selectResource(_ asset: ProjectAsset) {
        link.destination = .resource(asset.id)
        link.anchor = ""
        setTitleAttribute(asset.filename)
    }

    private func setTitleAttribute(_ title: String) {
        if let index = link.attributes.firstIndex(where: {
            $0.name.caseInsensitiveCompare("title") == .orderedSame
        }) {
            link.attributes[index].name = "title"
            link.attributes[index].value = title
        } else {
            link.attributes.append(.init(name: "title", value: title))
        }
    }

    private func pageMenu(folderID: UUID?, parentPageID: UUID?) -> AnyView {
        let childFolders = folders
            .filter { $0.parentID == folderID }
            .sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
        let childPages = pages
            .filter { $0.folderID == folderID && $0.parentPageID == parentPageID }
            .sorted { $0.order == $1.order ? $0.title < $1.title : $0.order < $1.order }
        return AnyView(Group {
            ForEach(childFolders) { folder in
                Menu(folder.name) {
                    pageMenu(folderID: folder.id, parentPageID: nil)
                }
            }
            ForEach(childPages) { page in
                let children = pages.filter { $0.parentPageID == page.id }
                if children.isEmpty {
                    Button(page.title) { selectPage(page) }
                } else {
                    Menu(page.title) {
                        Button("Select \(page.title)") { selectPage(page) }
                        Divider()
                        pageMenu(folderID: folderID, parentPageID: page.id)
                    }
                }
            }
        })
    }

    private func resourceMenu(nodes: [ProjectAssetNode]) -> AnyView {
        AnyView(ForEach(nodes) { node in
            switch node {
            case .folder(let folder):
                Menu(folder.name) {
                    resourceMenu(nodes: folder.children)
                }
            case .asset(let asset):
                Button(asset.filename) { selectResource(asset) }
            }
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
