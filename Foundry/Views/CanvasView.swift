import AppKit
import SwiftUI

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
    @Environment(\.canvasAppearance) private var appearance
    @State private var renderedAppearance: SiteAppearance?
    @State private var renderedBreakpoint: ResponsiveBreakpoint?
    let site: Site
    let page: Page?
    let language: String
    let framework: Framework
    let assets: ProjectAssetContents
    let assetRevision: UInt64
    let mutationEvent: ProjectMutationEvent
    let partPackageRevision: Int
    let isPartCatalogReady: Bool
    let selectedPartIDs: Set<UUID>
    let primarySelectedPartID: UUID?
    let selectedPrimitive: CanvasPrimitiveSelection?
    let editorOptions: CanvasEditorOptions
    let renderer: any PageRendering
    let canPastePart: Bool
    let canClearImage: (UUID, PartProperty.Key, [Int]) -> Bool
    let handleMessage: (CanvasMessage) -> Void
    let handleContextMenuAction: (CanvasContextMenuAction, UUID, PartProperty.Key?, [Int]) -> Void
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
    @State private var forcedReconciliationRevision: UInt64?
    @State private var reconciliationRequest: UInt64 = 0
    @State private var renderedRequest: CanvasRenderRequestID?
    @State private var acknowledgedRenderRevision: UInt64 = 0
    private let resizeEdgeHitTargetWidth = 12.0
    private let canvasHorizontalPadding = 24.0
    private let minimumViewportWidth = 320.0

    var body: some View {
        GeometryReader { geometry in
            if !isPartCatalogReady {
                PartCatalogLoadingView()
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
                                            operation: renderedPage.operation,
                                            assets: assets,
                                            packages: canvasPackages(for: page),
                                            appearance: appearance,
                                            assetRevision: assetRevision,
                                            selectedPartIDs: selectedPartIDs,
                                            primarySelectedPartID: primarySelectedPartID,
                                            selectedPrimitive: selectedPrimitive,
                                            editorOptions: editorOptions,
                                            enablesWebInspector: enablesCanvasWebInspector,
                                            canPastePart: canPastePart,
                                            canClearImage: canClearImage,
                                            handleMessage: handleMessage,
                                            handleContextMenuAction: handleContextMenuAction,
                                            requestFullReconciliation: {
                                                forcedReconciliationRevision = mutationEvent.revision
                                                reconciliationRequest &+= 1
                                            },
                                            didApplyRevision: { revision in
                                                acknowledgedRenderRevision = max(acknowledgedRenderRevision, revision)
                                            }
                                        )
                                        .id(enablesCanvasWebInspector)
                                        .frame(width: viewportWidth, height: logicalHeight)
                                        .background(Color(hex: page.backgroundColour(framework: framework, appearance: appearance)) ?? .white)
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
        let breakpoint = ResponsiveBreakpoint.forViewportWidth(viewportWidth, screens: framework.screens)
        return CanvasRenderRequestID(
            pageID: page.id,
            mutationRevision: mutationEvent.revision,
            assetRevision: assetRevision,
            partPackageRevision: partPackageRevision,
            breakpoint: breakpoint,
            forcesReconciliation: forcedReconciliationRevision == mutationEvent.revision,
            appearance: appearance,
            reconciliationRequest: reconciliationRequest
        )
    }

    private func renderCurrentPage() async {
        guard let page, let requestID = renderRequestID else {
            renderedPage = nil
            return
        }
        renderRevision &+= 1
        let revision = renderRevision
        let requiresInitialPage = renderedPage?.pageID != page.id
        let snapshot = CanvasRenderSnapshot(
            renderer: renderer,
            page: page,
            language: language,
            framework: framework,
            assets: assets,
            breakpoint: requestID.breakpoint,
            impact: mutationEvent.impact,
            forcesReconciliation: requestID.forcesReconciliation || requiresInitialPage || renderedAppearance != appearance
                || !requestID.canPatch(after: renderedRequest,
                                       submittedRevision: renderedPage?.operation.revision,
                                       acknowledgedRevision: acknowledgedRenderRevision),
            previousBreakpoint: renderedBreakpoint
        )
        let operation = await Task.detached(priority: .userInitiated) {
            snapshot.render()
        }.value
        guard !Task.isCancelled, requestID == renderRequestID, revision == renderRevision else { return }
        renderedPage = .init(pageID: page.id, operation: operation.withRevision(revision))
        renderedAppearance = appearance
        renderedBreakpoint = requestID.breakpoint
        renderedRequest = requestID
    }

    private func canvasPackages(for page: Page) -> [String: LoadedPartPackage] {
        Dictionary(
            page.parts
                .flatMap(flattened)
                .compactMap(\.type.definition.package)
                .map { ($0.manifest.identifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private func flattened(_ node: PartNode) -> [PartNode] {
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

struct PartCatalogLoadingView: View {
    @State private var catalog = PartPackageCatalog.shared

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
            return "Finding parts…"
        case .loading:
            return "Loading part files… \(catalog.completedPackageCount) of \(catalog.totalPackageCount)"
        case .savingIndex:
            return "Saving part index…"
        case .preparing:
            return "Preparing part library… \(catalog.completedPackageCount) of \(catalog.totalPackageCount)"
        case .publishing:
            return "Publishing part library…"
        case .ready:
            return "Parts ready"
        }
    }
}

struct CanvasRenderRequestID: Hashable {
    let pageID: UUID
    let mutationRevision: UInt64
    let assetRevision: UInt64
    let partPackageRevision: Int
    let breakpoint: ResponsiveBreakpoint
    let forcesReconciliation: Bool
    let appearance: SiteAppearance
    var reconciliationRequest: UInt64 = 0

    // A part patch is a delta, not a complete snapshot. It is only safe when
    // the immediately preceding mutation has reached WebKit successfully.
    func canPatch(after previous: Self?, submittedRevision: UInt64?, acknowledgedRevision: UInt64) -> Bool {
        guard let previous, let submittedRevision,
              submittedRevision == acknowledgedRevision else { return false }
        return previous.mutationRevision &+ 1 == mutationRevision
            && previous.pageID == pageID
            && previous.assetRevision == assetRevision
            && previous.partPackageRevision == partPackageRevision
            && previous.breakpoint == breakpoint
            && previous.appearance == appearance
            && previous.reconciliationRequest == reconciliationRequest
    }
}

struct CanvasRenderedPage: Equatable {
    let pageID: UUID
    let operation: CanvasWebOperation
}

nonisolated struct CanvasRenderSnapshot: Sendable {
    let renderer: any PageRendering
    let page: Page
    let language: String
    let framework: Framework
    let assets: ProjectAssetContents
    let breakpoint: ResponsiveBreakpoint
    let impact: ProjectMutationImpact
    let forcesReconciliation: Bool

    var previousBreakpoint: ResponsiveBreakpoint? = nil

    func render() -> CanvasRenderResult {
        if !forcesReconciliation,
           previousBreakpoint == nil || previousBreakpoint == breakpoint,
           case .partProperty(let partID, let propertyKey) = impact,
           allowsPartPatch(partID: partID, propertyKey: propertyKey),
           let subtree = renderer.renderSubtree(
               partID: partID,
               page: page,
               framework: framework,
               assets: assets,
               breakpoint: breakpoint
           ) {
            return .part(subtree)
        }
        let html = renderer.render(
            page: page,
            language: language,
            framework: framework,
            assets: assets,
            breakpoint: breakpoint
        )
        return .page(html)
    }

    private func allowsPartPatch(partID: UUID, propertyKey: PartProperty.Key) -> Bool {
        guard let path = partPath(to: partID, in: page.parts),
              path.allSatisfy({ $0.reusableDefinitionID == nil }),
              let part = path.last,
              let package = part.type.definition.package,
              let property = part.type.definition.properties.first(where: { $0.key == propertyKey }) else {
            return false
        }
        guard package.pageCSS.isEmpty,
              package.siteCSS.isEmpty,
              package.placedHTML.isEmpty,
              package.instanceJavaScript.isEmpty,
              package.pageJavaScript.isEmpty,
              package.manifest.assets.isEmpty else {
            return false
        }
        if property.control.isMedia { return false }
        return true
    }

    private func partPath(to partID: UUID, in nodes: [PartNode]) -> [PartNode]? {
        for node in nodes {
            if node.id == partID { return [node] }
            if let childPath = partPath(to: partID, in: node.children) {
                return [node] + childPath
            }
        }
        return nil
    }
}

nonisolated enum CanvasRenderResult: Equatable, Sendable {
    case part(RenderedPartSubtree)
    case page(String)

    func withRevision(_ revision: UInt64) -> CanvasWebOperation {
        switch self {
        case .part(let subtree): .part(subtree, revision: revision)
        case .page(let html): .reconcilePage(html: html, revision: revision)
        }
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
