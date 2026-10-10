import AppKit
import SwiftUI

/// The Inspector's view of a global part selected in the Global Parts panel:
/// what it contains, where it is used, and what it needs — read live from the
/// project.
struct GlobalPartInspector: View {
    let definition: ReusablePartDefinition
    let pages: [Page]
    let currentPage: Page?
    let editor: ProjectEditor
    let assetContents: ProjectAssetContents
    let insertGlobalPart: (UUID) -> Void

    @State private var renameText = ""
    @State private var previewImage: NSImage?

    /// Re-renders the preview whenever anything it depends on changes: the
    /// definition, or the current page's background. Previews always render
    /// in light mode, matching the templates library's baked previews.
    private struct PreviewKey: Equatable {
        let definition: ReusablePartDefinition
        let background: String?
    }

    private var previewKey: PreviewKey {
        PreviewKey(definition: definition, background: currentPage?.backgroundOverride)
    }

    private struct PartTypeUsage: Identifiable {
        let type: PartType
        let count: Int
        var id: String { type.rawValue }
        var isInstalled: Bool { type.definition.renderKind != .unavailable }
        var displayName: String {
            isInstalled ? type.definition.displayName : type.rawValue
        }
    }

    private struct PageUsage: Identifiable {
        let id: UUID
        let title: String
        let count: Int
    }

    private var flattenedParts: [PartNode] {
        func flatten(_ node: PartNode) -> [PartNode] {
            [node] + node.children.flatMap(flatten)
        }
        return flatten(definition.root)
    }

    private var typeUsage: [PartTypeUsage] {
        let counts = Dictionary(grouping: flattenedParts, by: \.type)
            .mapValues(\.count)
        return counts
            .map { PartTypeUsage(type: $0.key, count: $0.value) }
            .sorted {
                $0.count != $1.count ? $0.count > $1.count
                    : $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var missingTypes: [PartTypeUsage] { typeUsage.filter { !$0.isInstalled } }

    private var pageUsage: [PageUsage] {
        pages.compactMap { page in
            let count = page.parts.reduce(0) { $0 + instanceCount(in: $1) }
            guard count > 0 else { return nil }
            return PageUsage(id: page.id, title: page.title, count: count)
        }
    }

    private var instanceTotal: Int { pageUsage.reduce(0) { $0 + $1.count } }

    private func instanceCount(in node: PartNode) -> Int {
        let selfCount = node.reusableDefinitionID == definition.id ? 1 : 0
        return selfCount + node.children.reduce(0) { $0 + instanceCount(in: $1) }
    }

    var body: some View {
        Section {
            ZStack {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
        }

        Section("Global Part") {
            LabeledContent("Name") {
                TextField("Name", text: $renameText)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .onSubmit {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != definition.name else { return }
                        editor.renameGlobalPart(definitionID: definition.id, name: trimmed)
                    }
            }
            LabeledContent("Parts", value: flattenedParts.count.formatted())
            Text("Linked everywhere: editing any instance updates every page.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { renameText = definition.name }
        .onChange(of: definition.id) { renameText = definition.name }
        .task(id: previewKey) { await renderPreview() }

        Section("Used On") {
            if pageUsage.isEmpty {
                Text("Not placed on any page yet.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Instances", value: instanceTotal.formatted())
                ForEach(pageUsage) { usage in
                    LabeledContent {
                        Text(usage.count.formatted())
                    } label: {
                        Label(usage.title, systemImage: "doc.text")
                    }
                }
            }
        }

        Section("Contents") {
            ForEach(typeUsage) { usage in
                LabeledContent {
                    Text(usage.count.formatted())
                } label: {
                    Label {
                        Text(usage.displayName)
                    } icon: {
                        Image(systemName: usage.isInstalled
                            ? usage.type.systemImage
                            : "exclamationmark.triangle")
                            .foregroundStyle(usage.isInstalled ? Color.primary : Color.orange)
                    }
                }
            }
            if !missingTypes.isEmpty {
                Text("Parts marked with a warning come from packs that are not installed on this Mac; they will show placeholders until their packs are installed.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        Section {
            Button("Add to Page") { insertGlobalPart(definition.id) }
        }
    }

    private func renderPreview() async {
        previewImage = nil
        let site = editor.document.site
        let contents = assetContents
        let captured = await withCheckedContinuation { continuation in
            TemplatePreviewRenderer.shared.capturePreview(
                definition: definition,
                site: site,
                assetContents: contents,
                pageBackground: currentPage?.backgroundOverride
            ) { data in
                continuation.resume(returning: data)
            }
        }
        guard let captured else { return }
        previewImage = NSImage(data: captured)
    }
}
