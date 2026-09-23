import AppKit
import SwiftUI

struct VideoPartControl: View {
    struct Choice: Identifiable {
        let id: UUID
        let title: String
    }

    @Environment(\.inspectorLabelWidth) private var labelWidth
    @State private var isDropTarget = false

    let label: String
    let filename: String?
    let posterImage: NSImage?
    let hasCustomPoster: Bool
    let details: String?
    let compatibilityWarning: String?
    let isProcessing: Bool
    let errorMessage: String?
    let choices: [Choice]
    let indicator: InspectorRowIndicator
    let showsPlaybackOptions: Bool
    @Binding var autoplay: String
    @Binding var muted: Bool
    @Binding var showsControls: Bool
    @Binding var loops: Bool
    @Binding var startAt: Double
    let isClearDisabled: Bool
    let importVideoFromMac: () -> Void
    let selectVideo: (UUID) -> Void
    let clearVideo: () -> Void
    let importVideo: (URL) -> Bool
    let choosePoster: () -> Void
    let clearPoster: () -> Void

    var body: some View {
        Group {
            GridRow(alignment: .top) {
                HStack(alignment: .top, spacing: 3) {
                    InspectorResponsiveIndicator(
                        isVisible: indicator.isVisible,
                        isOverridden: indicator.isOverridden,
                        breakpointName: indicator.breakpointName,
                        toggle: indicator.toggle
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
                        Menu(filename == nil ? "Choose" : "Replace") {
                            if !choices.isEmpty {
                                Section("Project Resources") {
                                    ForEach(choices) { choice in
                                        Button(choice.title) { selectVideo(choice.id) }
                                    }
                                }
                            }
                            Button("Import from Mac…", action: importVideoFromMac)
                        }
                        .buttonStyle(.bordered)
                        .menuStyle(.button)
                        .frame(maxWidth: .infinity)
                        Button("Clear", action: clearVideo)
                            .buttonStyle(.bordered)
                            .buttonSizing(.flexible)
                            .frame(maxWidth: .infinity)
                            .disabled(isClearDisabled)
                    }
                }
                .frame(width: InspectorMetrics.clampedLabelWidth(labelWidth))
                .gridColumnAlignment(.trailing)

                videoWell.gridColumnAlignment(.leading)
            }
            posterRow
            if showsPlaybackOptions {
                playbackOptions
            }
        }
    }

    @ViewBuilder
    private var playbackOptions: some View {
        sectionDivider
        sectionHeading("Options")
        InspectorRow(title: "Autoplay") {
            InspectorPopup(
                selection: $autoplay,
                options: [
                    .init(title: "Never", value: "never"),
                    .init(title: "On page load", value: "onLoad")
                ],
                accessibilityLabel: "Autoplay",
                help: "Choose whether playback starts automatically when the page loads."
            )
        }
        InspectorRow(title: "Muted") {
            Toggle("", isOn: $muted).labelsHidden()
        }
        InspectorRow(title: "Controls") {
            Toggle("", isOn: $showsControls).labelsHidden()
        }
        InspectorRow(title: "Loop") {
            Toggle("", isOn: $loops).labelsHidden()
        }
        sectionDivider
        sectionHeading("Start At")
        InspectorRow(title: "Time (seconds)", alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    InspectorNumberField(
                        value: $startAt,
                        range: 0...86_400,
                        step: 1,
                        accessibilityLabel: "Video start time",
                        help: "Start playback at this time in seconds."
                    )
                    InspectorStepper(
                        value: $startAt,
                        range: 0...86_400,
                        increment: 1,
                        accessibilityLabel: "Video start time"
                    )
                }
                Text("Start playback at this time in seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sectionDivider: some View {
        GridRow {
            Divider()
                .gridCellColumns(2)
                .padding(.vertical, 6)
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        GridRow {
            Color.clear.frame(
                width: InspectorMetrics.clampedLabelWidth(labelWidth),
                height: 0
            )
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var videoWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.background)
            if let posterImage {
                Image(nsImage: posterImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
            } else {
                VStack(spacing: 8) {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.title)
                            .foregroundStyle(filename == nil ? .secondary : .primary)
                    }
                    videoSummary
                }
                .padding(8)
            }
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isDropTarget ? Color.accentColor : Color.secondary.opacity(0.35),
                    lineWidth: isDropTarget ? 2 : 1
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: URL.self) { urls, _ in
            urls.contains(where: importVideo)
        } isTargeted: {
            isDropTarget = $0
        }
        .accessibilityLabel(filename.map { "Video, \($0)" } ?? "No video selected")
        .help(errorMessage ?? compatibilityWarning ?? "Drop a video here, or choose one from project Resources")
    }

    private var posterRow: some View {
        InspectorRow(title: "Poster") {
            HStack(spacing: 6) {
                Button("Choose…", action: choosePoster)
                    .buttonStyle(.bordered)
                Button("Clear", action: clearPoster)
                    .buttonStyle(.bordered)
                    .disabled(!hasCustomPoster)
            }
        }
    }

    private var videoSummary: some View {
        VStack(spacing: 2) {
            if let filename {
                Text(filename)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Drop a video here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let details {
                Text(details).font(.caption2).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let compatibilityWarning {
                Label(compatibilityWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}

#Preview {
    @Previewable @State var autoplay = "never"
    @Previewable @State var muted = false
    @Previewable @State var showsControls = true
    @Previewable @State var loops = false
    @Previewable @State var startAt = 0.0
    PartControlPreview {
        VideoPartControl(
            label: "Video",
            filename: "background.mp4",
            posterImage: nil,
            hasCustomPoster: false,
            details: "1920 × 1080 · 0:18 · 4.2 MB",
            compatibilityWarning: nil,
            isProcessing: false,
            errorMessage: nil,
            choices: [],
            indicator: .preview,
            showsPlaybackOptions: true,
            autoplay: $autoplay,
            muted: $muted,
            showsControls: $showsControls,
            loops: $loops,
            startAt: $startAt,
            isClearDisabled: false,
            importVideoFromMac: {},
            selectVideo: { _ in },
            clearVideo: {},
            importVideo: { _ in false },
            choosePoster: {},
            clearPoster: {}
        )
    }
}
