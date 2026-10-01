import AppKit
import SwiftUI

struct ImagePartControl: View {
    @Environment(\.inspectorLabelWidth) private var labelWidth
    @State private var isDropTarget = false
    /// Whether the focal-point marker is showing. Starts on when the image
    /// already has a focal point away from the centre.
    @State private var isEditingFocalPoint: Bool?
    /// Entry for an image that lives on the web.
    @State private var showsURLEntry = false
    @State private var enteredURL = ""
    @State private var isImportingRemoteImage = false
    @State private var remoteImageError: String?
    /// A linked image, fetched so the well can show it and place a focal point on it.
    @State private var remotePreview: NSImage?

    let label: String
    let previewImage: NSImage?
    /// Set when the value links to an image on the web instead of a project asset.
    let remoteURL: URL?
    let supportsFocalPoint: Bool
    let focalPoint: CGPoint
    let focalPointIndicator: InspectorRowIndicator
    let isClearDisabled: Bool
    @Binding var altText: String
    let chooseImage: () -> Void
    let clearImage: () -> Void
    let importImage: (URL) -> Bool
    /// Keeps a web address as the value; the page loads the image from there.
    let linkImage: (URL) -> Void
    /// Downloads a web image into the project, returning false when the
    /// address did not yield an image Foundry can import.
    let importRemoteImage: (URL) async -> Bool
    let setFocalPoint: (CGPoint) -> Void

    var body: some View {
        GridRow(alignment: .top) {
            HStack(alignment: .top, spacing: 3) {
                InspectorResponsiveIndicator(
                    isVisible: focalPointIndicator.isVisible,
                    isOverridden: focalPointIndicator.isOverridden,
                    breakpointName: focalPointIndicator.breakpointName,
                    toggle: focalPointIndicator.toggle
                )
                .frame(width: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .help(label)
                    HStack(spacing: 4) {
                        Button("Pick", action: chooseImage)
                            .buttonSizing(.flexible)
                            .frame(maxWidth: .infinity)
                        Button("Image on the Web", systemImage: "link", action: showURLEntry)
                            .labelStyle(.iconOnly)
                            .help("Link or import an image from the web")
                            .popover(isPresented: $showsURLEntry, arrowEdge: .trailing) { urlEntry }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    Button("Clear", action: clearImage)
                        .buttonStyle(.bordered)
                        .buttonSizing(.flexible)
                        .frame(maxWidth: .infinity)
                        .disabled(isClearDisabled)
                    if supportsFocalPoint {
                        // A plain toggle's on state is barely visible in the
                        // bordered style, so on uses the prominent accent fill.
                        Group {
                            if showsFocalPoint {
                                Button("Focal Point") { focalPointToggle.wrappedValue = false }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Button("Focal Point") { focalPointToggle.wrappedValue = true }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .buttonSizing(.flexible)
                        .frame(maxWidth: .infinity)
                        .disabled(displayedImage == nil)
                        .help(showsFocalPoint
                            ? "Turn off the focal point and centre the image"
                            : "Choose the point the image stays centred on when it is cropped")
                        .accessibilityAddTraits(showsFocalPoint ? .isSelected : [])
                    }
                }
            }
            .frame(width: InspectorMetrics.clampedLabelWidth(labelWidth))
            .gridColumnAlignment(.trailing)

            imageWell.gridColumnAlignment(.leading)
        }

        InspectorRow(title: "Alt") {
            InspectorTextField(text: $altText, accessibilityLabel: "Alt", help: "Alt")
        }
    }

    private static let centre = CGPoint(x: 0.5, y: 0.5)

    private var displayedImage: NSImage? {
        previewImage ?? remotePreview
    }

    private var enteredWebURL: URL? {
        Self.webURL(enteredURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }

    private var urlEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Image on the Web")
                .font(.headline)
            TextField("https://example.com/photo.jpg", text: $enteredURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(linkEnteredURL)
            if let remoteImageError {
                Text(remoteImageError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Import Copy", action: importEnteredURL)
                    .buttonStyle(.bordered)
                    .help("Download the image into the project")
                if isImportingRemoteImage {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Link", action: linkEnteredURL)
                    .buttonStyle(.borderedProminent)
                    .help("Use the image where it is. Visitors load it from that address.")
            }
            .disabled(enteredWebURL == nil || isImportingRemoteImage)
        }
        .padding()
    }

    private func showURLEntry() {
        enteredURL = remoteURL?.absoluteString ?? ""
        remoteImageError = nil
        showsURLEntry = true
    }

    private func linkEnteredURL() {
        guard let url = enteredWebURL, !isImportingRemoteImage else { return }
        linkImage(url)
        showsURLEntry = false
    }

    private func importEnteredURL() {
        guard let url = enteredWebURL, !isImportingRemoteImage else { return }
        isImportingRemoteImage = true
        remoteImageError = nil
        Task {
            let imported = await importRemoteImage(url)
            isImportingRemoteImage = false
            if imported {
                showsURLEntry = false
            } else {
                remoteImageError = "That address did not return an image Foundry can import."
            }
        }
    }

    private var hasCustomFocalPoint: Bool {
        abs(focalPoint.x - Self.centre.x) > 0.001 || abs(focalPoint.y - Self.centre.y) > 0.001
    }

    private var showsFocalPoint: Bool {
        isEditingFocalPoint ?? hasCustomFocalPoint
    }

    /// On shows the marker; off hides it and returns the image to centre.
    private var focalPointToggle: Binding<Bool> {
        Binding(
            get: { showsFocalPoint },
            set: { isOn in
                isEditingFocalPoint = isOn
                if !isOn, hasCustomFocalPoint {
                    setFocalPoint(Self.centre)
                }
            }
        )
    }

    private var imageWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.background)
            if let displayedImage {
                Image(nsImage: displayedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
                if supportsFocalPoint && showsFocalPoint {
                    ImageFocalPointEditor(
                        imageSize: displayedImage.size,
                        focalPoint: focalPoint,
                        onCommit: setFocalPoint
                    )
                    .padding(6)
                }
            } else if let remoteURL {
                VStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.title2)
                    Text(remoteURL.host() ?? remoteURL.absoluteString)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .help(remoteURL.absoluteString)
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTarget ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isDropTarget ? 2 : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: URL.self) { urls, _ in
            // Files import at once; an image dragged from a browser arrives
            // as a web address and is downloaded into the project.
            if urls.contains(where: { $0.isFileURL && importImage($0) }) { return true }
            guard let url = urls.lazy.compactMap({ Self.webURL($0.absoluteString) }).first else { return false }
            Task { _ = await importRemoteImage(url) }
            return true
        } isTargeted: {
            isDropTarget = $0
        }
        .task(id: remoteURL) {
            remotePreview = nil
            guard let remoteURL, previewImage == nil,
                  let (data, _) = try? await URLSession.shared.data(from: remoteURL) else { return }
            remotePreview = NSImage(data: data)
        }
    }
}

#Preview {
    @Previewable @State var altText = "Preview image"
    PartControlPreview {
        ImagePartControl(
            label: "Image",
            previewImage: NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil),
            remoteURL: nil,
            supportsFocalPoint: true,
            focalPoint: CGPoint(x: 0.5, y: 0.5),
            focalPointIndicator: .preview,
            isClearDisabled: false,
            altText: $altText,
            chooseImage: {},
            clearImage: {},
            importImage: { _ in false },
            linkImage: { _ in },
            importRemoteImage: { _ in false },
            setFocalPoint: { _ in }
        )
    }
}

private struct ImageFocalPointEditor: View {
    @State private var draft: CGPoint?
    let imageSize: CGSize
    let focalPoint: CGPoint
    let onCommit: (CGPoint) -> Void

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = fittedImageFrame(in: proxy.size)
            let displayedPoint = draft ?? focalPoint
            ZStack(alignment: .topLeading) {
                Color.clear
                ZStack {
                    Circle().fill(.black.opacity(0.55))
                    Circle().stroke(.white, lineWidth: 2)
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
                .shadow(radius: 2)
                .position(
                    x: imageFrame.minX + imageFrame.width * displayedPoint.x,
                    y: imageFrame.minY + imageFrame.height * displayedPoint.y
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { draft = normalizedPoint($0.location, in: imageFrame) }
                    .onEnded {
                        let point = normalizedPoint($0.location, in: imageFrame)
                        draft = nil
                        onCommit(point)
                    }
            )
            .help("Drag to set the image focal point")
            .accessibilityLabel("Image focal point")
            .accessibilityValue("Horizontal \(Int(displayedPoint.x * 100)) percent, vertical \(Int(displayedPoint.y * 100)) percent")
        }
    }

    private func fittedImageFrame(in availableSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              availableSize.width > 0, availableSize.height > 0 else {
            return CGRect(origin: .zero, size: availableSize)
        }
        let scale = min(availableSize.width / imageSize.width, availableSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (availableSize.width - size.width) / 2,
            y: (availableSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func normalizedPoint(_ location: CGPoint, in imageFrame: CGRect) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return focalPoint }
        return CGPoint(
            x: min(max((location.x - imageFrame.minX) / imageFrame.width, 0), 1),
            y: min(max((location.y - imageFrame.minY) / imageFrame.height, 0), 1)
        )
    }
}
