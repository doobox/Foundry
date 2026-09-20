import AppKit
import SwiftUI

/// The Inspector's view of a template selected in the Templates panel: what it
/// contains, what it needs, and what it carries — all read from the library
/// bundle on disk.
struct TemplateInspector: View {
    let entry: ReusablePartLibraryEntry
    let insertTemplate: (UUID) -> Void

    @State private var renameText = ""

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
        guard let url = ReusablePartLibrary.shared.previewURL(forID: entry.id) else { return nil }
        return NSImage(contentsOf: url)
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
                    .onSubmit {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != entry.name else { return }
                        ReusablePartLibrary.shared.rename(id: entry.id, to: trimmed)
                    }
            }
            LabeledContent("Parts", value: flattenedParts.count.formatted())
            if let modifiedDate {
                LabeledContent("Modified", value: modifiedDate.formatted(date: .abbreviated, time: .shortened))
            }
            Text("Available in every project. Adding it to a page places an independent copy.")
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
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
            }
        }
    }
}
