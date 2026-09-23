import AppKit
import SwiftUI

/// What the Inspector needs to know about a selected template beyond its
/// contents: where it lives (project or pack) and how to rename it there.
struct TemplateInspectorContext {
    let entry: ReusablePartLibraryEntry
    let isProjectTemplate: Bool
    let isEditable: Bool
    let rename: (String) -> Void
}

/// The Inspector's view of a template selected in the Templates panel: what it
/// contains, what it needs, and what it carries. Pack templates are read from
/// their bundle on disk; project templates live inside the document itself.
struct TemplateInspector: View {
    let context: TemplateInspectorContext
    let insertTemplate: (UUID) -> Void

    @State private var renameText = ""

    private var entry: ReusablePartLibraryEntry { context.entry }

    private struct PartTypeUsage: Identifiable {
        let type: PartType
        let count: Int
        var id: String { type.rawValue }
        var isInstalled: Bool { type.definition.renderKind != .unavailable }
        var displayName: String {
            isInstalled ? type.definition.displayName : type.rawValue
        }
    }

    private var flattenedParts: [PartNode] {
        func flatten(_ node: PartNode) -> [PartNode] {
            [node] + node.children.flatMap(flatten)
        }
        return flatten(entry.definition.root)
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

    private var bundleURL: URL {
        ReusablePartLibrary.shared.bundleURL(forID: entry.id)
    }

    private var modifiedDate: Date? {
        try? FileManager.default
            .attributesOfItem(atPath: bundleURL.path)[.modificationDate] as? Date
    }

    private var embeddedAssetBytes: Int {
        entry.assets.reduce(0) { $0 + $1.byteCount }
    }

    private var previewImage: NSImage? {
        // Reading the revision re-runs this body when a fresh preview lands.
        _ = ReusablePartLibrary.shared.previewRevision
        guard !context.isProjectTemplate,
              let url = ReusablePartLibrary.shared.previewURL(forID: entry.id) else { return nil }
        return NSImage(contentsOf: url)
    }

    private var availabilityCaption: String {
        if context.isProjectTemplate {
            return "Available in this project only. Adding it to a page places an independent copy. Drag it to a pack in the Templates panel to use it everywhere."
        }
        if context.isEditable {
            return "Available in every project. Adding it to a page places an independent copy."
        }
        return "From an installed pack, so it is read-only. Adding it to a page places an independent copy; duplicate it to My Library to edit it."
    }

    var body: some View {
        if let previewImage {
            Section {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }

        Section("Template") {
            LabeledContent("Name") {
                TextField("Name", text: $renameText)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .disabled(!context.isEditable)
                    .onSubmit {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != entry.name else { return }
                        context.rename(trimmed)
                    }
            }
            LabeledContent("Parts", value: flattenedParts.count.formatted())
            if !context.isProjectTemplate, let modifiedDate {
                LabeledContent("Modified", value: modifiedDate.formatted(date: .abbreviated, time: .shortened))
            }
            Text(availabilityCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { renameText = entry.name }
        .onChange(of: entry.id) { renameText = entry.name }

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

        if !entry.assets.isEmpty {
            Section("Embedded Assets") {
                LabeledContent("Files", value: entry.assets.count.formatted())
                LabeledContent(
                    "Size",
                    value: ByteCountFormatter.string(fromByteCount: Int64(embeddedAssetBytes), countStyle: .file)
                )
                ForEach(entry.assets.prefix(6)) { asset in
                    Label {
                        Text(asset.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: asset.mediaType.hasPrefix("video/") ? "film" : "photo")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if entry.assets.count > 6 {
                    Text("and \(entry.assets.count - 6) more…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("These files import into a project's Resources when the template is added, reusing identical content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Button("Add to Page") { insertTemplate(entry.id) }
            if !context.isProjectTemplate {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                }
            }
        }
    }
}
