import AppKit
import SwiftUI

struct ImagePartControl: View {
    @Environment(\.inspectorLabelWidth) private var labelWidth
    @State private var isDropTarget = false

    let label: String
    let previewImage: NSImage?
    let supportsFocalPoint: Bool
    let focalPoint: CGPoint
    let focalPointIndicator: InspectorRowIndicator
    let isClearDisabled: Bool
    @Binding var altText: String
    let chooseImage: () -> Void
    let clearImage: () -> Void
    let importImage: (URL) -> Bool
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
                    Button("Pick", action: chooseImage)
                        .buttonStyle(.bordered)
                        .buttonSizing(.flexible)
                        .frame(maxWidth: .infinity)
                    Button("Clear", action: clearImage)
                        .buttonStyle(.bordered)
                        .buttonSizing(.flexible)
                        .frame(maxWidth: .infinity)
                        .disabled(isClearDisabled)
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

    private var imageWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.background)
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
                if supportsFocalPoint {
                    ImageFocalPointEditor(
                        imageSize: previewImage.size,
                        focalPoint: focalPoint,
                        onCommit: setFocalPoint
                    )
                    .padding(6)
                }
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
            urls.contains(where: importImage)
        } isTargeted: {
            isDropTarget = $0
        }
    }
}

#Preview {
    @Previewable @State var altText = "Preview image"
    PartControlPreview {
        ImagePartControl(
            label: "Image",
            previewImage: NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil),
            supportsFocalPoint: true,
            focalPoint: CGPoint(x: 0.5, y: 0.5),
            focalPointIndicator: .preview,
            isClearDisabled: false,
            altText: $altText,
            chooseImage: {},
            clearImage: {},
            importImage: { _ in false },
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
