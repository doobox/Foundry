import AppKit
import SwiftUI

nonisolated struct CanvasEditorOptions: Equatable, Sendable {
    var showsTitles = true
    var showsOutlines = true
    var showsSelection = true
    var scrollsToSelection = true
}

nonisolated enum CanvasViewportPreset: String, CaseIterable, Identifiable, Sendable {
    case mobile
    case tabletPortrait
    case tabletLandscape
    case desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mobile: "Mobile"
        case .tabletPortrait: "Tablet Portrait"
        case .tabletLandscape: "Tablet Landscape"
        case .desktop: "Desktop"
        }
    }

    var systemImage: String {
        switch self {
        case .mobile: "iphone"
        case .tabletPortrait: "ipad"
        case .tabletLandscape: "ipad.landscape"
        case .desktop: "desktopcomputer"
        }
    }

    var viewportWidth: Double {
        switch self {
        case .mobile: 390
        case .tabletPortrait: 768
        case .tabletLandscape: 1024
        case .desktop: 1440
        }
    }

    var breakpoint: ResponsiveBreakpoint {
        ResponsiveBreakpoint.forViewportWidth(viewportWidth)
    }
}

struct CanvasView: View {
    let page: Page?
    let language: String
    let theme: Theme
    let assets: [UUID: ProjectAssetContent]
    let selectedComponentIDs: Set<UUID>
    let editorOptions: CanvasEditorOptions
    let renderer: any PageRendering
    let handleMessage: (CanvasMessage) -> Void
    @Binding var viewportWidth: Double
    @AppStorage(AppPreferenceKey.overridesCanvasBackground)
    private var overridesCanvasBackground = false
    @AppStorage(AppPreferenceKey.canvasBackgroundColor)
    private var canvasBackgroundHex = CanvasBackgroundPreference.defaultColor
    @State private var resizeStartWidth: Double?
    @State private var resizeStartScale: Double?
    @State private var visibleCanvasWidth = 0.0
    private let resizeHandleWidth = 12.0
    private let canvasHorizontalPadding = 24.0

    var body: some View {
        GeometryReader { geometry in
            if let page {
                let availableWidth = visibleCanvasWidth > 0
                    ? min(geometry.size.width, visibleCanvasWidth)
                    : geometry.size.width
                let scale = canvasScale(availableWidth: availableWidth)
                let logicalHeight = max((geometry.size.height - 29) / scale, 600)

                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        HStack(spacing: 0) {
                            Spacer(minLength: canvasHorizontalPadding)
                            HStack(spacing: 0) {
                                resizeHandle(
                                    direction: -1,
                                    scale: scale
                                )
                                ZStack(alignment: .top) {
                                    WebCanvasView(
                                        html: renderer.render(
                                            page: page,
                                            language: language,
                                            theme: theme,
                                            assets: assets,
                                            breakpoint: ResponsiveBreakpoint.forViewportWidth(viewportWidth)
                                        ),
                                        selectedComponentIDs: selectedComponentIDs,
                                        editorOptions: editorOptions,
                                        handleMessage: handleMessage
                                    )
                                    .frame(width: viewportWidth, height: logicalHeight)
                                    .background(.white)
                                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                                    .scaleEffect(scale, anchor: .top)
                                }
                                .frame(
                                    width: viewportWidth * scale,
                                    height: logicalHeight * scale,
                                    alignment: .top
                                )
                                .contentShape(Rectangle())
                                .clipped()
                                resizeHandle(
                                    direction: 1,
                                    scale: scale
                                )
                            }
                            Spacer(minLength: canvasHorizontalPadding)
                        }
                        .frame(width: geometry.size.width)
                    }

                    Divider()
                    CanvasStatusBar(
                        viewportWidth: viewportWidth,
                        scale: scale,
                        breakpoint: ResponsiveBreakpoint.forViewportWidth(viewportWidth)
                    )
                }
            } else {
                ContentUnavailableView(
                    "No Page Selected",
                    systemImage: "doc",
                    description: Text("Choose a page in the navigator.")
                )
            }
        }
        .background {
            CanvasVisibleWidthReader { width in
                if abs(visibleCanvasWidth - width) > 0.5 {
                    visibleCanvasWidth = width
                }
            }
        }
        .background(canvasBackgroundStyle)
        .navigationTitle(page?.title ?? "Canvas")
    }

    private var canvasBackgroundStyle: AnyShapeStyle {
        guard overridesCanvasBackground else {
            return AnyShapeStyle(Color("CanvasWorkspaceBackground"))
        }
        let color = Color(hex: canvasBackgroundHex)
            ?? Color(hex: CanvasBackgroundPreference.defaultColor)
            ?? Color(nsColor: .windowBackgroundColor)
        return AnyShapeStyle(color)
    }

    private var canvasHorizontalChromeWidth: Double {
        (canvasHorizontalPadding * 2) + (resizeHandleWidth * 2)
    }

    private func canvasScale(availableWidth: Double) -> Double {
        min(1, max((availableWidth - canvasHorizontalChromeWidth) / viewportWidth, 0.1))
    }

    private func resizeHandle(
        direction: Double,
        scale: Double
    ) -> some View {
        CanvasResizeHandle(
            onChanged: { translation in
                let startingWidth = resizeStartWidth ?? viewportWidth
                let startingScale = resizeStartScale ?? scale
                resizeStartWidth = startingWidth
                resizeStartScale = startingScale
                let logicalTranslation = Double(translation) / startingScale
                viewportWidth = min(
                    max(startingWidth + (logicalTranslation * direction * 2), 320),
                    1600
                )
            },
            onEnded: {
                resizeStartWidth = nil
                resizeStartScale = nil
            }
        )
            .frame(width: resizeHandleWidth)
            .frame(height: 44)
            .zIndex(2)
            .accessibilityLabel("Resize canvas")
    }
}

private struct CanvasVisibleWidthReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> CanvasVisibleWidthView {
        CanvasVisibleWidthView(onChange: onChange)
    }

    func updateNSView(_ view: CanvasVisibleWidthView, context: Context) {
        view.onChange = onChange
        view.reportVisibleWidth()
    }
}

private final class CanvasVisibleWidthView: NSView {
    var onChange: (CGFloat) -> Void
    private var windowResizeObserver: NSObjectProtocol?

    init(onChange: @escaping (CGFloat) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        if let windowResizeObserver {
            NotificationCenter.default.removeObserver(windowResizeObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowResizeObserver {
            NotificationCenter.default.removeObserver(windowResizeObserver)
        }
        windowResizeObserver = window.map { window in
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.reportVisibleWidth()
            }
        }
        reportVisibleWidth()
    }

    override func layout() {
        super.layout()
        reportVisibleWidth()
    }

    func reportVisibleWidth() {
        guard let window, let contentView = window.contentView else { return }
        let frameInWindowContent = convert(bounds, to: contentView)
        let width = frameInWindowContent.intersection(contentView.bounds).width
        guard width > 0 else { return }
        onChange(width)
    }
}

private struct CanvasResizeHandle: NSViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        ResizeHandleView(onChanged: onChanged, onEnded: onEnded)
    }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.needsDisplay = true
    }
}

private final class ResizeHandleView: NSView {
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void
    private var dragStartX: CGFloat?

    init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping () -> Void) {
        self.onChanged = onChanged
        self.onEnded = onEnded
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.systemBlue.withAlphaComponent(0.8).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: (bounds.width - 4) / 2, y: 0, width: 4, height: bounds.height),
            xRadius: 2,
            yRadius: 2
        ).fill()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        NSCursor.resizeLeftRight.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX else { return }
        NSCursor.resizeLeftRight.set()
        onChanged(event.locationInWindow.x - dragStartX)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartX = nil
        NSCursor.pop()
        onEnded()
    }
}

private struct CanvasStatusBar: View {
    let viewportWidth: Double
    let scale: Double
    let breakpoint: ResponsiveBreakpoint

    var body: some View {
        HStack(spacing: 12) {
            Label("\(Int(viewportWidth)) px", systemImage: "ruler")
            Text(breakpoint.displayName)
            Spacer()
            Label(
                scale.formatted(.percent.precision(.fractionLength(0))),
                systemImage: "magnifyingglass"
            )
        }
        .font(.caption)
        .imageScale(.medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}
