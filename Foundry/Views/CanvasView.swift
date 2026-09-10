import AppKit
import SwiftUI
#if DEBUG
import OSLog
#endif

nonisolated struct CanvasEditorOptions: Equatable, Sendable {
    var showsTitles = true
    var showsOutlines = true
    var showsSelection = true
    var scrollsToSelection = true
}

nonisolated enum CanvasSizing {
    static func scale(availableWidth: Double, viewportWidth: Double, horizontalChromeWidth: Double) -> Double {
        min(1, max((availableWidth - horizontalChromeWidth) / viewportWidth, 0.1))
    }

    static func maximumViewportWidth(
        availableWidth: Double,
        scale: Double,
        minimumViewportWidth: Double,
        horizontalChromeWidth: Double
    ) -> Double {
        max(minimumViewportWidth, (availableWidth - horizontalChromeWidth) / scale)
    }

    static func resizedViewportWidth(
        startingWidth: Double,
        translation: Double,
        direction: Double,
        scale: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        let logicalTranslation = translation / scale
        return min(max(startingWidth + (logicalTranslation * direction * 2), minimum), maximum)
    }
}

struct CanvasView: View {
    let site: Site
    let page: Page?
    let language: String
    let theme: Theme
    let assets: [UUID: ProjectAssetContent]
    let assetRevision: UInt64
    let mutationRevision: UInt64
    let componentPackageRevision: Int
    let isComponentCatalogReady: Bool
    let selectedComponentIDs: Set<UUID>
    let selectedPrimitive: CanvasPrimitiveSelection?
    let editorOptions: CanvasEditorOptions
    let renderer: any PageRendering
    let canPasteComponent: Bool
    let canClearImage: (UUID, ComponentProperty.Key, [Int]) -> Bool
    let handleMessage: (CanvasMessage) -> Void
    let handleContextMenuAction: (CanvasContextMenuAction, UUID, ComponentProperty.Key?, [Int]) -> Void
    @Binding var viewportWidth: Double
    @AppStorage(AppPreferenceKey.overridesCanvasBackground)
    private var overridesCanvasBackground = false
    @AppStorage(AppPreferenceKey.canvasBackgroundColor)
    private var canvasBackgroundHex = CanvasBackgroundPreference.defaultColor
    @AppStorage(AppPreferenceKey.enablesCanvasWebInspector)
    private var enablesCanvasWebInspector = false
    @State private var resizeStartWidth: Double?
    @State private var resizeStartScale: Double?
    @State private var visibleCanvasWidth = 0.0
    @State private var renderedPage: CanvasRenderedPage?
    @State private var renderRevision: UInt64 = 0
    private let resizeEdgeHitTargetWidth = 12.0
    private let canvasHorizontalPadding = 24.0
    private let minimumViewportWidth = 320.0

    var body: some View {
        GeometryReader { geometry in
            if !isComponentCatalogReady {
                ComponentCatalogLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let page {
                let availableWidth = visibleCanvasWidth > 0
                    ? min(geometry.size.width, visibleCanvasWidth)
                    : geometry.size.width
                let scale = resizeStartScale ?? canvasScale(availableWidth: availableWidth)
                let maximumViewportWidth = CanvasSizing.maximumViewportWidth(
                    availableWidth: availableWidth,
                    scale: scale,
                    minimumViewportWidth: minimumViewportWidth,
                    horizontalChromeWidth: canvasHorizontalChromeWidth
                )
                let logicalHeight = max((geometry.size.height - 29) / scale, 600)

                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        HStack(spacing: 0) {
                            Spacer(minLength: canvasHorizontalPadding)
                            ZStack(alignment: .top) {
                                ZStack(alignment: .top) {
                                    if let renderedPage {
                                        WebCanvasView(
                                            html: renderedPage.html,
                                            revision: renderedPage.revision,
                                            assets: assets,
                                            packages: canvasPackages(for: page),
                                            assetRevision: assetRevision,
                                            selectedComponentIDs: selectedComponentIDs,
                                            selectedPrimitive: selectedPrimitive,
                                            editorOptions: editorOptions,
                                            enablesWebInspector: enablesCanvasWebInspector,
                                            canPasteComponent: canPasteComponent,
                                            canClearImage: canClearImage,
                                            handleMessage: handleMessage,
                                            handleContextMenuAction: handleContextMenuAction
                                        )
                                        .id(enablesCanvasWebInspector)
                                        .frame(width: viewportWidth, height: logicalHeight)
                                        .background(Color(hex: theme.colors.background) ?? .white)
                                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                                        .scaleEffect(scale, anchor: .top)
                                    } else {
                                        ProgressView()
                                            .frame(width: viewportWidth, height: logicalHeight)
                                            .scaleEffect(scale, anchor: .top)
                                    }
                                }
                                .frame(
                                    width: viewportWidth * scale,
                                    height: logicalHeight * scale,
                                    alignment: .top
                                )
                                .contentShape(Rectangle())
                                .clipped()
                                HStack(spacing: 0) {
                                    resizeEdge(
                                        direction: -1,
                                        scale: scale,
                                        maximumViewportWidth: maximumViewportWidth,
                                        accessibilityIdentifier: "canvas-resize-left"
                                    )
                                    Spacer(minLength: 0)
                                    resizeEdge(
                                        direction: 1,
                                        scale: scale,
                                        maximumViewportWidth: maximumViewportWidth,
                                        accessibilityIdentifier: "canvas-resize-right"
                                    )
                                }
                            }
                            .frame(width: viewportWidth * scale, height: logicalHeight * scale)
                            Spacer(minLength: canvasHorizontalPadding)
                        }
                        .frame(width: geometry.size.width)
                    }

                    Divider()
                    CanvasStatusBar(
                        pageName: page.title,
                        viewportWidth: viewportWidth,
                        scale: scale
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
        .task(id: renderRequestID) {
            await renderCurrentPage()
        }
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

    private var renderRequestID: CanvasRenderRequestID? {
        guard let page else { return nil }
        let breakpoint = ResponsiveBreakpoint.forViewportWidth(viewportWidth, screens: theme.screens)
        return CanvasRenderRequestID(
            pageID: page.id,
            mutationRevision: mutationRevision,
            assetRevision: assetRevision,
            componentPackageRevision: componentPackageRevision,
            breakpoint: breakpoint
        )
    }

    private func renderCurrentPage() async {
        guard let page, let requestID = renderRequestID else {
            renderedPage = nil
            return
        }
        renderRevision &+= 1
        let revision = renderRevision
        let snapshot = CanvasRenderSnapshot(
            renderer: renderer,
            page: page,
            language: language,
            theme: theme,
            assets: assets,
            breakpoint: requestID.breakpoint
        )
        let html = await Task.detached(priority: .userInitiated) {
            snapshot.render()
        }.value
        guard !Task.isCancelled, requestID == renderRequestID, revision == renderRevision else { return }
        renderedPage = .init(html: html, revision: revision)
    }

    private func canvasPackages(for page: Page) -> [String: LoadedComponentPackage] {
        Dictionary(
            page.components
                .flatMap(flattened)
                .compactMap(\.type.definition.package)
                .map { ($0.manifest.identifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private func flattened(_ node: ComponentNode) -> [ComponentNode] {
        [node] + node.children.flatMap(flattened)
    }

    private var canvasHorizontalChromeWidth: Double {
        canvasHorizontalPadding * 2
    }

    private func canvasScale(availableWidth: Double) -> Double {
        CanvasSizing.scale(
            availableWidth: availableWidth,
            viewportWidth: viewportWidth,
            horizontalChromeWidth: canvasHorizontalChromeWidth
        )
    }

    private func resizeEdge(
        direction: Double,
        scale: Double,
        maximumViewportWidth: Double,
        accessibilityIdentifier: String
    ) -> some View {
        CanvasResizeHandle(
            onChanged: { translation in
                let startingWidth = resizeStartWidth ?? viewportWidth
                let startingScale = resizeStartScale ?? scale
                resizeStartWidth = startingWidth
                resizeStartScale = startingScale
                viewportWidth = CanvasSizing.resizedViewportWidth(
                    startingWidth: startingWidth,
                    translation: Double(translation),
                    direction: direction,
                    scale: startingScale,
                    minimum: minimumViewportWidth,
                    maximum: maximumViewportWidth
                )
            },
            onEnded: {
                resizeStartWidth = nil
                resizeStartScale = nil
            },
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityValue: "viewport=\(Int(viewportWidth));scale=\(Int((scale * 100).rounded()))"
        )
            .frame(width: resizeEdgeHitTargetWidth)
            .frame(maxHeight: .infinity)
            .zIndex(2)
    }
}

struct ComponentCatalogLoadingView: View {
    @State private var catalog = ComponentPackageCatalog.shared

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: catalog.loadingProgress)
                .progressViewStyle(.linear)
                .frame(width: 180)
            Text(loadingDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(loadingDescription)
    }

    private var loadingDescription: String {
        switch catalog.loadingStage {
        case .finding:
            return "Finding components…"
        case .loading:
            return "Loading component files… \(catalog.completedPackageCount) of \(catalog.totalPackageCount)"
        case .savingIndex:
            return "Saving component index…"
        case .preparing:
            return "Preparing component library… \(catalog.completedPackageCount) of \(catalog.totalPackageCount)"
        case .publishing:
            return "Publishing component library…"
        case .ready:
            return "Components ready"
        }
    }
}

private struct CanvasRenderRequestID: Hashable {
    let pageID: UUID
    let mutationRevision: UInt64
    let assetRevision: UInt64
    let componentPackageRevision: Int
    let breakpoint: ResponsiveBreakpoint
}

struct CanvasRenderedPage: Equatable {
    let html: String
    let revision: UInt64
}

nonisolated struct CanvasRenderSnapshot: Sendable {
    let renderer: any PageRendering
    let page: Page
    let language: String
    let theme: Theme
    let assets: [UUID: ProjectAssetContent]
    let breakpoint: ResponsiveBreakpoint

    func render() -> String {
#if DEBUG
        let startedAt = ContinuousClock.now
        Logger.foundryPerformance.debug("Canvas background full-page render started")
#endif
        let html = renderer.render(
            page: page,
            language: language,
            theme: theme,
            assets: assets,
            breakpoint: breakpoint
        )
#if DEBUG
        let completedAt = ContinuousClock.now
        Logger.foundryPerformance.debug(
            "Canvas background full-page render completed: render=\(startedAt.milliseconds(to: completedAt), format: .fixed(precision: 3))ms, bytes=\(html.utf8.count)"
        )
#endif
        return html
    }
}


private struct CanvasVisibleWidthReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> CanvasVisibleWidthView {
        CanvasVisibleWidthView(onChange: onChange)
    }

    func updateNSView(_ view: CanvasVisibleWidthView, context: Context) {
        view.onChange = onChange
        view.scheduleVisibleWidthReport()
    }
}

private final class CanvasVisibleWidthView: NSView {
    var onChange: (CGFloat) -> Void
    private var windowResizeObserver: NSObjectProtocol?
    private var reportIsScheduled = false

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
                self?.scheduleVisibleWidthReport()
            }
        }
        scheduleVisibleWidthReport()
    }

    override func layout() {
        super.layout()
        scheduleVisibleWidthReport()
    }

    func scheduleVisibleWidthReport() {
        guard !reportIsScheduled else { return }
        reportIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reportIsScheduled = false
            self.reportVisibleWidth()
        }
    }

    private func reportVisibleWidth() {
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
    let accessibilityIdentifier: String
    let accessibilityValue: String

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView(onChanged: onChanged, onEnded: onEnded)
        configureAccessibility(for: view)
        return view
    }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
        configureAccessibility(for: view)
    }

    private func configureAccessibility(for view: ResizeHandleView) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.slider)
        view.setAccessibilityLabel("Resize canvas")
        view.setAccessibilityIdentifier(accessibilityIdentifier)
        view.setAccessibilityValue(accessibilityValue)
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

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow:
            onChanged(-20)
            onEnded()
        case .rightArrow:
            onChanged(20)
            onEnded()
        default:
            super.keyDown(with: event)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
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
    let pageName: String
    let viewportWidth: Double
    let scale: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(pageName)
            Spacer()
            Text("\(Int(viewportWidth)) px")
            Label(
                scale.formatted(.percent.precision(.fractionLength(0))),
                systemImage: "magnifyingglass"
            )
            .foregroundStyle(scale < 1 ? Color.orange : Color.secondary)
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
