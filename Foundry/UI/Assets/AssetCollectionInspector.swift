import AppKit
import AVFoundation
import SwiftUI

/// What the Assets panel's Library/Dev tabs have selected, resolved for the
/// Inspector: a collection, one of its folders, or one of its files.
enum AssetCollectionInspectorSelection {
    case collection(AssetCollection, source: AssetCollectionSource)
    case folder(AssetCollectionFolder, collection: AssetCollection, source: AssetCollectionSource)
    case file(AssetCollectionFile, collection: AssetCollection, source: AssetCollectionSource)
}

/// Inspector form content for asset-collection selections — the Library/Dev
/// counterpart to `AssetLibraryNodeInspector`, plus licence metadata and the
/// Add to Project gesture.
struct AssetCollectionInspector: View {
    let selection: AssetCollectionInspectorSelection
    let importFiles: ([AssetCollectionFile]) -> Void

    private var library: AssetCollectionLibrary { .shared }

    var body: some View {
        switch selection {
        case .collection(let collection, let source):
            collectionSections(collection, source: source)
        case .folder(let folder, let collection, let source):
            folderSections(folder, collection: collection, source: source)
        case .file(let file, let collection, let source):
            fileSections(file, collection: collection, source: source)
        }
    }

    /// Folders are organization only — identity and licence stay with the
    /// collection, so the name reads here and renames inline in the panel.
    @ViewBuilder
    private func folderSections(
        _ folder: AssetCollectionFolder,
        collection: AssetCollection,
        source: AssetCollectionSource
    ) -> some View {
        Section("Folder") {
            LabeledContent("Name", value: folder.name)
            LabeledContent("Collection", value: collection.title)
            LabeledContent("Source", value: source.title)
            LabeledContent("Files", value: folder.files.count.formatted())
            LabeledContent(
                "Size",
                value: folder.files.reduce(0) { $0 + $1.byteCount }
                    .formatted(.byteCount(style: .file))
            )
        }
        licenceSection(collection, isEditable: false)
        Section {
            Button("Add All to Project") { importFiles(folder.files) }
                .disabled(folder.files.isEmpty)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            }
            Text("Adds copies of every file in this folder to this project's assets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func collectionSections(_ collection: AssetCollection, source: AssetCollectionSource) -> some View {
        Section("Collection") {
            if source.isEditable {
                TextField(
                    "Name",
                    text: Binding(
                        get: { collection.title },
                        set: { name in
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            library.renameCollection(id: collection.identifier, to: trimmed)
                        }
                    )
                )
            } else {
                LabeledContent("Name", value: collection.title)
            }
            LabeledContent("Source", value: source.title)
            LabeledContent("Files", value: collection.files.count.formatted())
            LabeledContent(
                "Size",
                value: collection.files.reduce(0) { $0 + $1.byteCount }
                    .formatted(.byteCount(style: .file))
            )
        }
        licenceSection(collection, isEditable: source.isEditable)
        Section {
            Button("Add All to Project") { importFiles(collection.files) }
                .disabled(collection.files.isEmpty)
            Text("Adds copies of every file to this project's assets. The collection is unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func licenceSection(_ collection: AssetCollection, isEditable: Bool) -> some View {
        if isEditable {
            Section("Licence") {
                TextField(
                    "Licence",
                    text: licenceBinding(collection, get: { $0.license }, set: { details, value in
                        details.license = value
                    })
                )
                TextField(
                    "Licence URL",
                    text: licenceBinding(collection, get: { $0.licenseURL?.absoluteString }, set: { details, value in
                        details.licenseURL = value.flatMap(URL.init(string:))
                    })
                )
                TextField(
                    "Attribution",
                    text: licenceBinding(collection, get: { $0.attribution }, set: { details, value in
                        details.attribution = value
                    })
                )
            }
        } else if collection.license != nil || collection.attribution != nil {
            Section("Licence") {
                if let license = collection.license {
                    if let url = collection.licenseURL {
                        LabeledContent("Licence") { Link(license, destination: url) }
                    } else {
                        LabeledContent("Licence", value: license)
                    }
                }
                if let attribution = collection.attribution {
                    LabeledContent("Attribution", value: attribution)
                }
            }
        }
    }

    @ViewBuilder
    private func fileSections(
        _ file: AssetCollectionFile,
        collection: AssetCollection,
        source: AssetCollectionSource
    ) -> some View {
        if file.isImage || file.isVideo {
            Section("Preview") {
                AssetCollectionFilePreview(file: file)
            }
        }
        Section("File") {
            LabeledContent("Filename", value: file.filename)
            LabeledContent("Type", value: file.mediaType)
            LabeledContent("Size", value: file.byteCount.formatted(.byteCount(style: .file)))
            LabeledContent("Collection", value: collection.title)
            LabeledContent("Source", value: source.title)
        }
        if file.isFont {
            AssetCollectionFontSection(file: file)
        }
        licenceSection(collection, isEditable: false)
        Section {
            Button("Add to Project") { importFiles([file]) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Text("Adds a copy of this file to this project's assets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Licence fields save through `setLicence` as they edit, preserving the
    /// other two fields each time.
    private func licenceBinding(
        _ collection: AssetCollection,
        get: @escaping (AssetCollection) -> String?,
        set: @escaping (inout LicenceDetails, String?) -> Void
    ) -> Binding<String> {
        Binding(
            get: { get(collection) ?? "" },
            set: { value in
                var details = LicenceDetails(
                    license: collection.license,
                    licenseURL: collection.licenseURL,
                    attribution: collection.attribution
                )
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                set(&details, trimmed.isEmpty ? nil : trimmed)
                library.setLicence(
                    id: collection.identifier,
                    license: details.license,
                    licenseURL: details.licenseURL,
                    attribution: details.attribution
                )
            }
        )
    }

    private struct LicenceDetails {
        var license: String?
        var licenseURL: URL?
        var attribution: String?
    }
}

/// Font details read from the file bytes — the same section the project
/// asset inspector shows after import.
private struct AssetCollectionFontSection: View {
    let file: AssetCollectionFile

    @State private var metadata: FontFileMetadata?
    @State private var isLoading = true

    var body: some View {
        Section("Font") {
            if let metadata {
                LabeledContent("Family", value: metadata.family)
                LabeledContent("Face", value: metadata.face)
                LabeledContent("Weight", value: metadata.weight == metadata.maximumWeight
                    ? String(metadata.weight)
                    : "\(metadata.weight)–\(metadata.maximumWeight)")
                LabeledContent("Style", value: metadata.italic ? "Italic" : "Normal")
            } else if !isLoading {
                Text("Font metadata is unavailable for this file.")
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
        .task(id: file.id) {
            isLoading = true
            metadata = (try? Data(contentsOf: file.url)).flatMap(FontFileMetadata.read)
            isLoading = false
        }
    }
}

/// Downsampled image preview for a collection file, decoded off the main
/// thread from its on-disk URL. Vector formats CGImageSource can't decode —
/// SVG — fall back to NSImage, which renders them natively. Video shows its
/// opening frame.
private struct AssetCollectionFilePreview: View {
    let file: AssetCollectionFile

    @State private var preview: CGImage?
    @State private var vectorPreview: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .accessibilityLabel("Preview of \(file.filename)")
            } else if let vectorPreview {
                Image(nsImage: vectorPreview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .accessibilityLabel("Preview of \(file.filename)")
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Label("No preview available", systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .task(id: file.id) {
            isLoading = true
            preview = nil
            vectorPreview = nil
            if file.isVideo {
                preview = await Self.videoPosterFrame(for: file.url)
            } else {
                preview = await AssetCollectionThumbnailLoader.thumbnail(for: file.url)
                if preview == nil, let image = NSImage(contentsOf: file.url), image.isValid {
                    vectorPreview = image
                }
            }
            isLoading = false
        }
    }

    private static func videoPosterFrame(for url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let result = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600))
        return result?.image
    }
}
