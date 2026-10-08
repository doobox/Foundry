import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor
private enum CanvasDiagnostics {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Foundry", category: "Canvas")

    static func navigationFailed(_ error: any Error, phase: String, url: URL?) {
        let failure = error as NSError
        let failingURL = (failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
            ?? url?.absoluteString ?? "unknown"
        // Replacing a navigation can cancel the previous load; keep that diagnostic at debug level.
        if failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled {
            logger.debug("Canvas navigation cancelled (\(phase, privacy: .public)); URL=\(failingURL, privacy: .private(mask: .hash))")
        } else {
            logger.error("Canvas navigation failed (\(phase, privacy: .public)); domain=\(failure.domain, privacy: .public) code=\(failure.code); URL=\(failingURL, privacy: .private(mask: .hash)); detail=\(failure.localizedDescription, privacy: .private)")
        }
    }
}

@MainActor
final class CanvasAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "foundry-asset"
    nonisolated static let packageScheme = "foundry-package-asset"

    private var assets: ProjectAssetContents
    private var packages: [String: LoadedPartPackage]
    private let gifPreviews = NSCache<NSString, NSData>()

    init(
        assets: ProjectAssetContents,
        packages: [String: LoadedPartPackage] = [:]
    ) {
        self.assets = assets
        self.packages = packages
        gifPreviews.totalCostLimit = 64 * 1_024 * 1_024
        gifPreviews.countLimit = 128
    }

    func update(assets: ProjectAssetContents) {
        gifPreviews.removeAllObjects()
        self.assets = assets
    }

    func update(packages: [String: LoadedPartPackage]) {
        self.packages = packages
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let resource = resource(for: url) else {
            let requestURL = urlSchemeTask.request.url
            CanvasDiagnostics.logger.error("Canvas asset unavailable; scheme=\(requestURL?.scheme ?? "unknown", privacy: .public); URL=\(requestURL?.absoluteString ?? "missing", privacy: .private(mask: .hash))")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: resource.mediaType,
            expectedContentLength: resource.data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(resource.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    func resource(for url: URL) -> (data: Data, mediaType: String)? {
        if url.scheme == Self.packageScheme {
            return packageResource(for: url)
        }
        guard let id = url.absoluteString.foundryAssetID,
              let content = assets[id] else { return nil }
        if content.asset.mediaType.caseInsensitiveCompare("image/gif") == .orderedSame,
           let preview = gifPreview(for: id, data: content.data) {
            return (preview, UTType.png.preferredMIMEType ?? "image/png")
        }
        return (content.data, content.asset.mediaType)
    }

    private func packageResource(for url: URL) -> (data: Data, mediaType: String)? {
        guard let packageIdentifier = url.host,
              let package = packages[packageIdentifier] else { return nil }
        let path = url.path.removingPercentEncoding?.drop(while: { $0 == "/" }) ?? ""
        let relativePath = String(path)
        guard !relativePath.isEmpty,
              !relativePath.split(separator: "/").contains(".."),
              package.manifest.assetDeclaration(containing: relativePath) != nil else { return nil }

        let resourceRoot = package.resourceRootURL.resolvingSymlinksInPath().standardizedFileURL
        let resourceURL = resourceRoot
            .appending(path: relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard resourceURL.path.hasPrefix(resourceRoot.path + "/"),
              let data = try? Data(contentsOf: resourceURL) else { return nil }
        let mediaType = UTType(filenameExtension: resourceURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        return (data, mediaType)
    }

    private func gifPreview(for id: UUID, data: Data) -> Data? {
        let key = id.uuidString as NSString
        if let cached = gifPreviews.object(forKey: key) {
            return cached as Data
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let preview = output as Data
        gifPreviews.setObject(preview as NSData, forKey: key, cost: preview.count)
        return preview
    }
}

nonisolated enum CanvasContextMenuAction: String, Sendable {
    case clearImage
    case duplicate
    case copy
    case paste
    case saveReusable
    case saveGlobal
    case makeLocalOverride
    case relinkGlobal
    case explodeGlobal
    case customizeLayoutItem
    case moveUp
    case moveDown
    case outdent
    case delete
}

struct CanvasUpdateRevisionGate {
    private(set) var latestRequested: UInt64 = 0
    private(set) var latestApplied: UInt64 = 0

    mutating func request(_ revision: UInt64) -> Bool {
        guard revision >= latestRequested else { return false }
        latestRequested = revision
        return true
    }

    mutating func apply(_ revision: UInt64) -> Bool {
        guard revision >= latestRequested, revision >= latestApplied else { return false }
        latestApplied = revision
        return true
    }

    func isCurrent(_ revision: UInt64) -> Bool {
        revision >= latestRequested && revision >= latestApplied
    }
}

nonisolated enum CanvasWebOperation: Equatable, Sendable {
    case scene(CanvasSceneUpdate, revision: UInt64)
    case part(RenderedPartSubtree, revision: UInt64)
    case reconcilePage(html: String, revision: UInt64)
    case reloadDocument(html: String, revision: UInt64)

    var revision: UInt64 {
        switch self {
        case .part(_, let revision), .scene(_, let revision), .reconcilePage(_, let revision), .reloadDocument(_, let revision):
            revision
        }
    }
}

@MainActor
final class CanvasWebView: WKWebView {
    weak var canvasCoordinator: WebCanvasView.Coordinator?
    private var canvasTrackingArea: NSTrackingArea?
    private var hoverTransitionRevision = 0

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let canvasTrackingArea { removeTrackingArea(canvasTrackingArea) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        canvasTrackingArea = trackingArea
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHoverChrome()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hoverTransitionRevision += 1
        let revision = hoverTransitionRevision
        Task { @MainActor [weak self] in
            guard let self, revision == hoverTransitionRevision else { return }
            _ = try? await callAsyncJavaScript(
                "window.foundrySetCanvasPointerInside?.(true)",
                arguments: [:], in: nil, contentWorld: .defaultClient
            )
        }
    }

    @discardableResult
    func clearHoverChrome() -> Task<Void, Never> {
        hoverTransitionRevision += 1
        let revision = hoverTransitionRevision
        return Task { @MainActor [weak self] in
            guard let self, revision == hoverTransitionRevision else { return }
            _ = try? await callAsyncJavaScript(
                "window.foundryClearHoverChrome?.()",
                arguments: [:],
                in: nil,
                contentWorld: .defaultClient
            )
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        canvasCoordinator?.prepareForNativeContextMenu()
        return super.menu(for: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        if isInspectable {
            canvasCoordinator?.augmentNativeContextMenu(menu)
        }
        super.willOpenMenu(menu, with: event)
    }
}

struct WebCanvasView: NSViewRepresentable {
    let operation: CanvasWebOperation
    let assets: ProjectAssetContents
    let packages: [String: LoadedPartPackage]
    let appearance: SiteAppearance
    let assetRevision: UInt64
    let selectedPartIDs: Set<UUID>
    let primarySelectedPartID: UUID?
    let selectedPrimitive: CanvasPrimitiveSelection?
    let editorOptions: CanvasEditorOptions
    let enablesWebInspector: Bool
    let canPastePart: Bool
    let canClearImage: (UUID, PartProperty.Key, [Int]) -> Bool
    let handleMessage: (CanvasMessage) -> Void
    let handleContextMenuAction: (CanvasContextMenuAction, UUID, PartProperty.Key?, [Int]) -> Void
    let requestFullReconciliation: () -> Void
    var didApplyRevision: (UInt64) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            assets: assets,
            packages: packages,
            canClearImage: canClearImage,
            handleMessage: handleMessage,
            handleContextMenuAction: handleContextMenuAction,
            requestFullReconciliation: requestFullReconciliation
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            context.coordinator.assetSchemeHandler,
            forURLScheme: CanvasAssetSchemeHandler.scheme
        )
        configuration.setURLSchemeHandler(
            context.coordinator.assetSchemeHandler,
            forURLScheme: CanvasAssetSchemeHandler.packageScheme
        )
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        if enablesWebInspector {
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }
        let controller = configuration.userContentController
        controller.add(context.coordinator, contentWorld: .defaultClient, name: Coordinator.handlerName)
        controller.addUserScript(.init(
            source: Coordinator.interactionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))

        let webView = CanvasWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = enablesWebInspector
        webView.canvasCoordinator = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.webView = webView
        return webView
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WKWebView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.isInspectable = enablesWebInspector
        // Follow the canvas appearance toggle in the web view itself so
        // prefers-color-scheme agrees with the document's colour scheme —
        // light-dark() and media queries must never disagree in the editor.
        webView.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        context.coordinator.assetSchemeHandler.update(packages: packages)
        if context.coordinator.assetRevision != assetRevision {
            context.coordinator.assetSchemeHandler.update(assets: assets)
            context.coordinator.assetRevision = assetRevision
        }
        context.coordinator.handleMessage = handleMessage
        context.coordinator.handleContextMenuAction = handleContextMenuAction
        context.coordinator.canClearImage = canClearImage
        context.coordinator.canPastePart = canPastePart
        context.coordinator.selectedPartIDs = selectedPartIDs
        context.coordinator.primarySelectedPartID = primarySelectedPartID
        context.coordinator.selectedPrimitive = selectedPrimitive
        context.coordinator.editorOptions = editorOptions
        context.coordinator.requestFullReconciliation = requestFullReconciliation
        context.coordinator.didApplyRevision = didApplyRevision
        if context.coordinator.lastSubmittedRevision != operation.revision {
            context.coordinator.lastSubmittedRevision = operation.revision
            context.coordinator.apply(operation, in: webView)
        } else {
            context.coordinator.applyCanvasState()
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let handlerName = "foundryCanvas"
        let assetSchemeHandler: CanvasAssetSchemeHandler
        nonisolated static let interactionScript = CanvasHoverGuard.javaScript + "\n" + CanvasYouTubeThumbnails.javaScript + "\n" + """
        (() => {
          if (window.foundryCanvasInstalled) return;
          window.foundryCanvasInstalled = true;
          const selector = '[data-foundry-id]';
          const interactionStyles = document.createElement('style');
          interactionStyles.textContent = `
            [data-foundry-inline-property]:not([contenteditable="true"]) {
              -webkit-user-select: none !important;
              user-select: none !important;
            }
          `;
          document.documentElement.appendChild(interactionStyles);
          let placement = null;
          let selectedPartIDs = [];
          let selectedPrimitiveSelection = null;
          let isDragging = false;
          let webInspectorEnabled = false;
          window.foundrySetWebInspectorEnabled = enabled => {
            webInspectorEnabled = enabled === true;
          };
          const propertyPath = element => {
            const raw = element?.dataset.foundryPropertyPath;
            if (!raw) return [];
            return raw.split(',').map(Number).filter(Number.isInteger);
          };
          let activeDragSources = [];

          const chromeHost = document.createElement('div');
          chromeHost.setAttribute('popover', 'manual');
          chromeHost.setAttribute('data-foundry-editor-chrome', 'host');
          const chromeHostStyles = {
            all: 'initial', position: 'fixed', inset: '0', width: '0', height: '0',
            margin: '0', padding: '0', border: '0', overflow: 'visible', pointerEvents: 'none'
          };
          Object.entries(chromeHostStyles).forEach(([property, value]) => {
            chromeHost.style.setProperty(property.replace(/[A-Z]/g, match => '-' + match.toLowerCase()), value, 'important');
          });
          const chromeRoot = chromeHost.attachShadow({ mode: 'open' });
          const chromeStyles = document.createElement('style');
          chromeStyles.textContent = `
            *, *::before, *::after { box-sizing: border-box; }
          `;
          chromeRoot.appendChild(chromeStyles);

          const chromeLayer = document.createElement('div');
          chromeLayer.setAttribute('data-foundry-editor-chrome', 'layer');
          const chromeLayerStyles = {
            all: 'initial', position: 'fixed', inset: '0', width: '0', height: '0',
            margin: '0', padding: '0', border: '0', overflow: 'visible', pointerEvents: 'none'
          };
          Object.entries(chromeLayerStyles).forEach(([property, value]) => {
            chromeLayer.style.setProperty(property.replace(/[A-Z]/g, match => '-' + match.toLowerCase()), value, 'important');
          });
          chromeRoot.appendChild(chromeLayer);
          document.documentElement.appendChild(chromeHost);
          if (typeof chromeHost.showPopover === 'function') chromeHost.showPopover();

          const chromeTitle = document.createElement('div');
          chromeTitle.setAttribute('data-foundry-editor-chrome', 'title');
          const chromeTitleStyles = {
            all: 'initial',
            position: 'fixed',
            display: 'none',
            boxSizing: 'border-box',
            padding: '1px 10px 2px',
            borderRadius: '0 0 5px 0',
            overflow: 'hidden',
            color: 'white',
            background: '#007BFF',
            font: '11px/14px system-ui, sans-serif',
            textAlign: 'center',
            whiteSpace: 'nowrap',
            textOverflow: 'ellipsis',
            pointerEvents: 'none',
            zIndex: '2147483647'
          };
          Object.entries(chromeTitleStyles).forEach(([property, value]) => {
            chromeTitle.style.setProperty(
              property.replace(/[A-Z]/g, match => '-' + match.toLowerCase()),
              value,
              'important'
            );
          });
          chromeLayer.appendChild(chromeTitle);
          const makeSelectionTitle = () => {
            const title = chromeTitle.cloneNode(false);
            title.setAttribute('data-foundry-editor-chrome', 'selection-title');
            title.style.setProperty('z-index', '2147483646', 'important');
            chromeLayer.appendChild(title);
            return title;
          };
          let hoveredPart = null;
          let hoveredPrimitive = null;
          let hoveredEditable = null;
          let selectedChromeTargets = [];
          let selectedChrome = [];
          let selectedChromeTitles = [];
          const hoverChrome = document.createElement('div');
          hoverChrome.setAttribute('data-foundry-editor-chrome', 'hover');
          const applyOutlineBaseStyles = element => {
            const styles = {
              all: 'initial', position: 'fixed', display: 'none', boxSizing: 'border-box',
              borderRadius: '0', pointerEvents: 'none', zIndex: '2147483646'
            };
            Object.entries(styles).forEach(([property, value]) => {
              element.style.setProperty(property.replace(/[A-Z]/g, match => '-' + match.toLowerCase()), value, 'important');
            });
          };
          applyOutlineBaseStyles(hoverChrome);
          chromeLayer.appendChild(hoverChrome);
          const editableChrome = document.createElement('div');
          editableChrome.setAttribute('data-foundry-editor-chrome', 'editable');
          applyOutlineBaseStyles(editableChrome);
          chromeLayer.appendChild(editableChrome);
          const dropChrome = document.createElement('div');
          dropChrome.setAttribute('data-foundry-editor-chrome', 'drop');
          applyOutlineBaseStyles(dropChrome);
          dropChrome.style.setProperty('z-index', '2147483647', 'important');
          chromeLayer.appendChild(dropChrome);
          const collectionToolbar = document.createElement('div');
          collectionToolbar.setAttribute('data-foundry-editor-chrome', 'collection-toolbar');
          const collectionToolbarStyles = {
            all: 'initial', position: 'fixed', display: 'none', alignItems: 'center',
            minHeight: '22px', padding: '0 8px', borderRadius: '0 0 5px 0',
            overflow: 'hidden', color: 'white', background: '#007BFF',
            font: '11px/14px system-ui, sans-serif', whiteSpace: 'nowrap',
            pointerEvents: 'none', zIndex: '2147483647'
          };
          Object.entries(collectionToolbarStyles).forEach(([property, value]) => {
            collectionToolbar.style.setProperty(property.replace(/[A-Z]/g, match => '-' + match.toLowerCase()), value, 'important');
          });
          const collectionToolbarLabel = document.createElement('span');
          collectionToolbar.appendChild(collectionToolbarLabel);
          chromeLayer.appendChild(collectionToolbar);
          let activeDropChrome = null;
          let chromeFrame = null;

          const chromeStrokeWidth = 3;
          const editorChromeColor = '#007BFF';
          const hoverChromeColor = '#409CFF';
          const globalChromeColor = '#30D158';
          // The hover tint lightens each family the same way: blue #007BFF
          // hovers as #409CFF, green #30D158 hovers as #64DC82.
          const globalHoverChromeColor = '#64DC82';
          const partChromeColor = element => {
            if (!element || element.closest('[data-foundry-global-override="true"]')) {
              return editorChromeColor;
            }
            return element.closest('[data-foundry-global]') ? globalChromeColor : editorChromeColor;
          };
          const partHoverChromeColor = element => {
            if (!element || element.closest('[data-foundry-global-override="true"]')) {
              return hoverChromeColor;
            }
            return element.closest('[data-foundry-global]') ? globalHoverChromeColor : hoverChromeColor;
          };
          // The green chrome already marks globals; the label stays plain.
          const partChromeTitle = part => part?.dataset.foundryName || '';

          const chromeRect = target => {
            // A constrained empty Section keeps its readable drop target
            // outside the smaller layout box. Highlight the visible target.
            if (target.matches('.foundry-empty-drop-zone')) {
              const label = target.querySelector(':scope > .foundry-drop-label');
              if (label && getComputedStyle(label).position === 'absolute') {
                return label.getBoundingClientRect();
              }
            }
            const elementRect = target.getBoundingClientRect();
            if (elementRect.width > 0 && elementRect.height > 0) return elementRect;

            // Parts whose root uses `display: contents` have no box of their own.
            // Frame their rendered contents so nested overlay text still gets canvas chrome.
            const range = document.createRange();
            range.selectNodeContents(target);
            const contentRect = range.getBoundingClientRect();
            range.detach();
            return contentRect;
          };

          const pixelWidth = value => {
            const number = Number.parseFloat(value);
            return Number.isFinite(number) ? Math.max(0, number) : 0;
          };

          const outlineGeometry = (target, isPrimitive) => {
            const rect = chromeRect(target);
            if (isPrimitive || rect.width <= 0 || rect.height <= 0) {
              return { rect };
            }
            const style = getComputedStyle(target);
            const top = pixelWidth(style.borderTopWidth);
            const right = pixelWidth(style.borderRightWidth);
            const bottom = pixelWidth(style.borderBottomWidth);
            const left = pixelWidth(style.borderLeftWidth);
            return {
              rect: {
                left: rect.left + left,
                top: rect.top + top,
                right: rect.right - right,
                bottom: rect.bottom - bottom,
                width: Math.max(0, rect.width - left - right),
                height: Math.max(0, rect.height - top - bottom)
              }
            };
          };

          const rectanglesOverlap = (lhs, rhs) => !(
            lhs.right <= rhs.left || lhs.left >= rhs.right || lhs.bottom <= rhs.top || lhs.top >= rhs.bottom
          );

          const positionChromeTitle = (title, target, text, color, isPrimitive, opacity, occupied = []) => {
            if (!target?.isConnected) {
              title.style.setProperty('display', 'none', 'important');
              return false;
            }
            const geometry = outlineGeometry(target, isPrimitive);
            const rect = geometry.rect;
            const visibleLeft = Math.max(0, rect.left);
            const visibleRight = Math.min(window.innerWidth, rect.right);
            const visibleTop = Math.max(0, rect.top);
            const visibleBottom = Math.min(window.innerHeight, rect.bottom);
            if (rect.width <= 0 || rect.height <= 0 || visibleRight <= visibleLeft || visibleBottom <= visibleTop) {
              title.style.setProperty('display', 'none', 'important');
              return false;
            }
            title.textContent = text || '';
            title.style.setProperty('background', color, 'important');
            title.style.setProperty('opacity', String(opacity), 'important');
            title.style.setProperty('transform', 'none', 'important');
            title.style.setProperty('max-width', Math.max(0, visibleRight - visibleLeft) + 'px', 'important');
            title.style.setProperty('visibility', 'hidden', 'important');
            title.style.setProperty('display', 'block', 'important');
            const measured = title.getBoundingClientRect();
            const width = Math.min(measured.width, visibleRight - visibleLeft);
            const height = measured.height;
            const maximumLeft = Math.max(0, window.innerWidth - width);
            const maximumTop = Math.max(0, window.innerHeight - height);
            const leftCandidates = [
              Math.min(Math.max(visibleLeft, 0), maximumLeft),
              Math.min(Math.max(visibleRight - width, 0), maximumLeft)
            ];
            const startTop = Math.min(Math.max(visibleTop, 0), maximumTop);
            const candidates = [];
            leftCandidates.forEach(left => {
              for (let offset = 0; offset < 8; offset += 1) {
                const top = Math.min(startTop + offset * (height + 2), maximumTop);
                if (!candidates.some(candidate => candidate.left === left && candidate.top === top)) {
                  candidates.push({ left, top, right: left + width, bottom: top + height });
                }
              }
            });
            const position = candidates.find(candidate =>
              !occupied.some(existing => rectanglesOverlap(candidate, existing))
            );
            if (!position) {
              title.style.setProperty('display', 'none', 'important');
              return false;
            }
            title.style.setProperty('left', position.left + 'px', 'important');
            title.style.setProperty('top', position.top + 'px', 'important');
            title.style.setProperty('visibility', 'visible', 'important');
            occupied.push(position);
            return true;
          };

          const positionOutline = (outline, target, color, isPrimitive, isCollection = false) => {
            if (!target?.isConnected) {
              outline.style.setProperty('display', 'none', 'important');
              return;
            }
            const geometry = outlineGeometry(target, isPrimitive);
            const rect = geometry.rect;
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight
                || rect.right < 0 || rect.left > window.innerWidth) {
              outline.style.setProperty('display', 'none', 'important');
              return;
            }
            const inset = isCollection ? 1 : 0;
            outline.style.setProperty('left', rect.left + inset + 'px', 'important');
            outline.style.setProperty('top', rect.top + inset + 'px', 'important');
            outline.style.setProperty('width', Math.max(0, rect.width - inset * 2) + 'px', 'important');
            outline.style.setProperty('height', Math.max(0, rect.height - inset * 2) + 'px', 'important');
            outline.style.setProperty('border-width', (isCollection ? 2 : chromeStrokeWidth) + 'px', 'important');
            outline.style.setProperty('border-style', 'solid', 'important');
            outline.style.setProperty('border-color', color, 'important');
            outline.style.setProperty('border-radius', '0', 'important');
            outline.style.setProperty('display', 'block', 'important');
          };

          const selectionIsSuppressedByDrop = entry => {
            if (!entry || activeDropChrome?.kind !== 'inside') return false;
            const dropOwner = activeDropChrome.element?.closest(selector);
            return entry.part === dropOwner
              || entry.element === activeDropChrome.element
              || (entry.isPrimitive && entry.element.closest(selector) === dropOwner);
          };

          const updateSelectionChrome = (occupiedTitles = []) => {
            while (selectedChrome.length < selectedChromeTargets.length) {
              const outline = document.createElement('div');
              outline.setAttribute('data-foundry-editor-chrome', 'selection');
              applyOutlineBaseStyles(outline);
              chromeLayer.appendChild(outline);
              selectedChrome.push(outline);
              selectedChromeTitles.push(makeSelectionTitle());
            }
            selectedChrome.forEach((outline, index) => {
              const entry = selectedChromeTargets[index];
              const title = selectedChromeTitles[index];
              if (!entry || !editorOptions.showsSelection || selectionIsSuppressedByDrop(entry)) {
                outline.style.setProperty('display', 'none', 'important');
                title.style.setProperty('display', 'none', 'important');
              } else {
                const isPrimary = index === 0;
                // Keep every selection layer below active drop feedback. The primary
                // selection still paints above secondary selections.
                outline.style.setProperty('z-index', isPrimary ? '2147483646' : '2147483645', 'important');
                title.style.setProperty('z-index', isPrimary ? '2147483646' : '2147483645', 'important');
                positionOutline(outline, entry.element, entry.color, entry.isPrimitive, entry.isCollection);
                if (editorOptions.showsTitles && !entry.isCollection) {
                  positionChromeTitle(
                    title,
                    entry.element,
                    partChromeTitle(entry.part),
                    entry.color,
                    entry.isPrimitive,
                    1,
                    occupiedTitles
                  );
                } else {
                  title.style.setProperty('display', 'none', 'important');
                }
              }
            });
            const collectionEntry = selectedChromeTargets.find(entry => entry.isCollection);
            if (!collectionEntry || !editorOptions.showsSelection || !collectionEntry.element?.isConnected) {
              collectionToolbar.style.setProperty('display', 'none', 'important');
              return;
            }
            const rect = chromeRect(collectionEntry.element);
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight
                || rect.right < 0 || rect.left > window.innerWidth) {
              collectionToolbar.style.setProperty('display', 'none', 'important');
              return;
            }
            collectionToolbarLabel.textContent = collectionEntry.title;
            collectionToolbar.style.setProperty('background', collectionEntry.color, 'important');
            collectionToolbar.style.setProperty('left', Math.max(0, rect.left) + 'px', 'important');
            collectionToolbar.style.setProperty('top', Math.max(0, rect.top) + 'px', 'important');
            collectionToolbar.style.setProperty('display', 'flex', 'important');
          };

          // Mirrors FoundryDropZoneGlyphs so the accepting overlay shows the
          // same symbol as the resting zone, slightly darkened.
          const dropGlyphs = {
            part: '<svg viewBox="0 0 147 147" width="22" height="22" fill="currentColor"><path fill-rule="evenodd" d="M43.629,146.562C29.456,146.562 18.484,142.625 11.21,135.352C3.838,128.046 -0,117.071 -0,102.933L-0,43.629C-0,29.491 3.873,18.48 11.21,11.21C18.413,4.008 29.456,0 43.629,0L103.036,0C117.209,0 128.082,3.905 135.387,11.21C142.827,18.516 146.665,29.491 146.665,43.629L146.665,102.933C146.665,117.071 142.792,128.082 135.387,135.352C128.185,142.554 117.209,146.562 103.036,146.562L43.629,146.562ZM43.629,135.491L103.036,135.491C113.642,135.491 121.932,132.503 127.269,127.269C132.741,121.797 135.594,113.674 135.594,102.933L135.594,43.629C135.594,32.888 132.741,24.765 127.269,19.293C121.864,13.992 113.642,11.07 103.036,11.07L43.629,11.07C32.955,11.07 24.698,14.059 19.36,19.293C13.924,24.765 11.07,32.888 11.07,43.629L11.07,102.933C11.07,113.674 13.924,121.797 19.36,127.269C24.765,132.57 32.955,135.491 43.629,135.491Z"/><path d="M68.262,98.329L67.932,86.478L67.932,38.195C67.932,35.342 70.377,32.862 73.4,32.862C76.32,32.862 78.868,35.342 78.868,38.195L78.868,86.478L78.487,98.346L83.674,92.885L96.98,78.905C97.896,77.817 99.392,77.239 100.717,77.239C103.499,77.239 105.709,79.313 105.709,82.131C105.709,83.591 105.165,84.678 104.078,85.765L77.372,111.764C76.015,113.121 74.757,113.597 73.4,113.597C72.007,113.597 70.75,113.121 69.428,111.764L42.584,85.765C41.599,84.678 40.988,83.591 40.988,82.131C40.988,79.313 43.059,77.239 45.98,77.239C47.27,77.239 48.765,77.817 49.785,78.905L63.055,92.885L68.262,98.329Z"/></svg>',
            image: '<svg viewBox="0 0 147 147" width="22" height="22" fill="currentColor"><g transform="translate(-9.091185 -0.438)"><path fill-rule="evenodd" d="M52.72,147C38.547,147 27.575,143.063 20.302,135.79C12.929,128.484 9.091,117.509 9.091,103.371L9.091,44.067C9.091,29.929 12.964,18.918 20.302,11.648C27.504,4.446 38.547,0.438 52.72,0.438L112.127,0.438C126.3,0.438 137.173,4.343 144.478,11.648C151.918,18.954 155.756,29.929 155.756,44.067L155.756,103.371C155.756,117.509 151.883,128.52 144.478,135.79C137.276,142.992 126.3,147 112.127,147L52.72,147ZM52.72,135.929L112.127,135.929C122.733,135.929 131.023,132.941 136.36,127.707C141.832,122.235 144.685,114.112 144.685,103.371L144.685,44.067C144.685,33.326 141.832,25.203 136.36,19.731C130.955,14.429 122.733,11.508 112.127,11.508L52.72,11.508C42.046,11.508 33.789,14.497 28.452,19.731C23.015,25.203 20.162,33.326 20.162,44.067L20.162,103.371C20.162,114.112 23.015,122.235 28.452,127.707C33.856,133.008 42.046,135.929 52.72,135.929ZM30.162,98.861L36.146,93.384C39.44,90.328 42.831,88.816 46.511,88.816C50.497,88.816 54.061,90.431 57.458,93.487L72.564,107.297L109.117,74.624C112.964,71.22 116.872,69.57 121.443,69.57C125.95,69.57 130.132,71.323 133.844,74.727L134.685,75.51L134.685,103.371C134.685,110.885 133.154,116.725 129.35,120.574C125.558,124.269 119.584,125.929 112.127,125.929L52.72,125.929C45.241,125.929 39.349,124.33 35.533,120.645C31.704,116.758 30.162,110.906 30.162,103.371L30.162,98.861ZM59.536,74.562C49.036,74.562 40.493,66.018 40.493,55.518C40.493,45.121 49.036,36.475 59.536,36.475C69.933,36.475 78.476,45.121 78.476,55.518C78.476,66.018 69.933,74.562 59.536,74.562Z"/></g></svg>',
            video: '<svg viewBox="0 0 147 147" width="22" height="22" fill="currentColor"><g transform="translate(-9.091185 -0.438)"><path fill-rule="evenodd" d="M52.72,147C38.547,147 27.575,143.063 20.302,135.79C12.929,128.484 9.091,117.509 9.091,103.371L9.091,44.067C9.091,29.929 12.964,18.918 20.302,11.648C27.504,4.446 38.547,0.438 52.72,0.438L112.127,0.438C126.3,0.438 137.173,4.343 144.478,11.648C151.918,18.954 155.756,29.929 155.756,44.067L155.756,103.371C155.756,117.509 151.883,128.52 144.478,135.79C137.276,142.992 126.3,147 112.127,147L52.72,147ZM52.72,135.929L112.127,135.929C122.733,135.929 131.023,132.941 136.36,127.707C141.832,122.235 144.685,114.112 144.685,103.371L144.685,44.067C144.685,33.326 141.832,25.203 136.36,19.731C130.955,14.429 122.733,11.508 112.127,11.508L52.72,11.508C42.046,11.508 33.789,14.497 28.452,19.731C23.015,25.203 20.162,33.326 20.162,44.067L20.162,103.371C20.162,114.112 23.015,122.235 28.452,127.707C33.856,133.008 42.046,135.929 52.72,135.929ZM49.179,106.225C41.111,106.225 36.382,101.596 36.382,93.599L36.382,54.515C36.382,46.451 41.313,41.889 49.179,41.889L92.062,41.889C100.126,41.889 104.552,46.451 104.552,54.515L104.552,93.599C104.552,101.596 99.856,106.225 91.791,106.225L49.179,106.225ZM108.94,85.11L108.94,62.968L124.322,50.031C125.66,48.934 127.233,48.146 128.674,48.146C131.544,48.146 133.493,50.262 133.493,53.447L133.493,94.599C133.493,97.851 131.544,99.968 128.674,99.968C127.233,99.968 125.728,99.18 124.322,98.015L108.94,85.11Z"/></g></svg>'
          };

          const updateDropChrome = () => {
            const candidate = activeDropChrome;
            const target = candidate?.element;
            if (!target?.isConnected) {
              dropChrome.style.setProperty('display', 'none', 'important');
              return;
            }
            const rect = chromeRect(target);
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight
                || rect.right < 0 || rect.left > window.innerWidth) {
              dropChrome.style.setProperty('display', 'none', 'important');
              return;
            }
            const color = partChromeColor(target);
            dropChrome.style.setProperty('background', 'transparent', 'important');
            dropChrome.style.setProperty('border', '0', 'important');
            dropChrome.style.setProperty('box-shadow', 'none', 'important');
            // The overlay is reused between states; the inside indicator's
            // backdrop lift must not linger on the insertion bars.
            dropChrome.style.setProperty('backdrop-filter', 'none', 'important');
            dropChrome.style.setProperty('-webkit-backdrop-filter', 'none', 'important');
            if (candidate.kind === 'before' || candidate.kind === 'after') {
              if (candidate.axis === 'inline') {
                const flow = insertionFlow(target);
                const beforeIsLeft = !flow.reversed;
                const useLeftEdge = candidate.kind === 'before' ? beforeIsLeft : !beforeIsLeft;
                const left = useLeftEdge ? rect.left : rect.right - 4;
                dropChrome.style.setProperty('left', left + 'px', 'important');
                dropChrome.style.setProperty('top', rect.top + 'px', 'important');
                dropChrome.style.setProperty('width', '4px', 'important');
                dropChrome.style.setProperty('height', rect.height + 'px', 'important');
              } else {
                const top = candidate.kind === 'before' ? rect.top : rect.bottom - 4;
                dropChrome.style.setProperty('left', rect.left + 'px', 'important');
                dropChrome.style.setProperty('top', top + 'px', 'important');
                dropChrome.style.setProperty('width', rect.width + 'px', 'important');
                dropChrome.style.setProperty('height', '4px', 'important');
              }
              dropChrome.style.setProperty('background', color, 'important');
              dropChrome.style.setProperty('border-radius', '0', 'important');
              dropChrome.textContent = '';
            } else {
              // The inside indicator sits 1px inside the target — within an
              // empty zone's hairline border — and carries its own label,
              // styled to match the resting zones.
              dropChrome.style.setProperty('left', rect.left + 1 + 'px', 'important');
              dropChrome.style.setProperty('top', rect.top + 1 + 'px', 'important');
              dropChrome.style.setProperty('width', Math.max(0, rect.width - 2) + 'px', 'important');
              dropChrome.style.setProperty('height', Math.max(0, rect.height - 2) + 'px', 'important');
              dropChrome.style.setProperty('background', '#ffffff', 'important');
              dropChrome.style.setProperty('border-radius', '3px', 'important');
              dropChrome.style.setProperty('place-items', 'center', 'important');
              dropChrome.style.setProperty('color', '#6e6e6e', 'important');
              dropChrome.innerHTML = target.matches('[data-foundry-image-drop-zone]')
                ? dropGlyphs.image
                : target.matches('[data-foundry-video-drop-zone]')
                  ? dropGlyphs.video
                  : dropGlyphs.part;
            }
            const isBar = candidate.kind === 'before' || candidate.kind === 'after';
            dropChrome.style.setProperty('display', isBar ? 'block' : 'grid', 'important');
          };

          const updateHoverChrome = () => {
            const target = hoveredPrimitive || hoveredPart;
            const isSelected = selectedChromeTargets.some(entry => entry.element === target);
            if (!target || isSelected || isDragging || !editorOptions.showsOutlines) {
              hoverChrome.style.setProperty('display', 'none', 'important');
              return;
            }
            const isPrimitive = Boolean(hoveredPrimitive);
            positionOutline(
              hoverChrome,
              target,
              partHoverChromeColor(target),
              isPrimitive
            );
          };

          const updateEditableChrome = () => {
            const target = hoveredEditable;
            if (!target?.isConnected || target.isContentEditable || isDragging || !editorOptions.showsOutlines) {
              editableChrome.style.setProperty('display', 'none', 'important');
              return;
            }
            const rect = chromeRect(target);
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight
                || rect.right < 0 || rect.left > window.innerWidth) {
              editableChrome.style.setProperty('display', 'none', 'important');
              return;
            }
            const color = partChromeColor(target);
            editableChrome.style.setProperty('left', rect.left + 'px', 'important');
            editableChrome.style.setProperty('top', rect.top + 'px', 'important');
            editableChrome.style.setProperty('width', rect.width + 'px', 'important');
            editableChrome.style.setProperty('height', rect.height + 'px', 'important');
            editableChrome.style.setProperty('background', color + '14', 'important');
            editableChrome.style.setProperty('display', 'block', 'important');
          };

          const updateChromeTitle = () => {
            chromeFrame = null;
            const occupiedTitles = [];
            updateSelectionChrome(occupiedTitles);
            updateHoverChrome();
            updateEditableChrome();
            updateDropChrome();
            const hoveredPartIsSelected = selectedChromeTargets.some(entry => entry.part === hoveredPart);
            if (!hoveredPart || !hoveredPart.isConnected || hoveredPartIsSelected || !editorOptions.showsTitles) {
              chromeTitle.style.setProperty('display', 'none', 'important');
              return;
            }
            positionChromeTitle(
              chromeTitle,
              hoveredPart,
              partChromeTitle(hoveredPart),
              partHoverChromeColor(hoveredPart),
              false,
              1,
              occupiedTitles
            );
          };

          const scheduleChromeTitleUpdate = () => {
            if (chromeFrame === null) chromeFrame = requestAnimationFrame(updateChromeTitle);
          };

          // Fonts and other late-loading content can change geometry without
          // a scroll or window resize. Observe content, never the chrome itself.
          const chromeResizeObserver = new ResizeObserver(scheduleChromeTitleUpdate);
          const observeChromeGeometry = () => {
            chromeResizeObserver.disconnect();
            chromeResizeObserver.observe(document.body);
            document.querySelectorAll(selector).forEach(element => chromeResizeObserver.observe(element));
          };
          observeChromeGeometry();
          document.fonts.addEventListener('loadingdone', scheduleChromeTitleUpdate);
          document.fonts.addEventListener('loadingerror', scheduleChromeTitleUpdate);

          document.addEventListener('pointermove', event => {
            const part = event.target.closest?.(selector) ?? null;
            const primitive = event.target.closest?.('[data-foundry-primitive-property]') ?? null;
            const editable = event.target.closest?.('[data-foundry-inline-property]') ?? null;
            if (part === hoveredPart && primitive === hoveredPrimitive && editable === hoveredEditable) return;
            hoveredPart = part;
            hoveredPrimitive = primitive;
            hoveredEditable = editable;
            scheduleChromeTitleUpdate();
          }, true);
          const clearHoverChrome = () => {
            window.foundrySetCanvasPointerInside(false);
            hoveredPart = null;
            hoveredPrimitive = null;
            hoveredEditable = null;
            updateChromeTitle();
          };
          window.foundryClearHoverChrome = clearHoverChrome;
          document.documentElement.addEventListener('pointerleave', clearHoverChrome);
          window.addEventListener('pointerout', event => {
            if (event.relatedTarget === null) clearHoverChrome();
          });
          window.addEventListener('blur', clearHoverChrome);
          document.addEventListener('scroll', scheduleChromeTitleUpdate, true);
          window.addEventListener('resize', scheduleChromeTitleUpdate);

          const clearDrop = () => {
            placement = null;
            activeDropChrome = null;
            dropChrome.style.setProperty('display', 'none', 'important');
          };

          const showDropChrome = candidate => {
            activeDropChrome = candidate?.element ? candidate : null;
            updateChromeTitle();
          };

          const clearDragSources = () => {
            activeDragSources.forEach(source => source.classList.remove('foundry-drag-source'));
            activeDragSources.length = 0;
          };

          const markDragSources = elements => {
            clearDragSources();
            const roots = elements.filter(candidate =>
              !elements.some(other => other !== candidate && other.contains(candidate))
            );
            roots.forEach(source => {
              source.classList.add('foundry-drag-source');
              activeDragSources.push(source);
            });
          };

          const slotContextForPlacement = candidate => {
            if (!candidate || candidate.kind === 'end') return null;
            if (candidate.kind === 'inside') {
              const parent = document.querySelector(
                '[data-foundry-id="' + CSS.escape(candidate.targetID || '') + '"]'
              );
              return {
                parentID: candidate.targetID,
                slotID: candidate.slotID || parent?.dataset.foundryDefaultSlot
              };
            }
            const target = document.querySelector(
              '[data-foundry-id="' + CSS.escape(candidate.targetID || '') + '"]'
            );
            return target ? {
              parentID: target.dataset.foundryParent,
              slotID: target.dataset.foundrySlot
            } : null;
          };

          const respectsLockedContainment = candidate => {
            const lockedSources = activeDragSources.filter(
              source => source.dataset.foundrySlotContainment === 'locked'
            );
            if (lockedSources.length === 0) return true;
            const destination = slotContextForPlacement(candidate);
            return destination && lockedSources.every(source =>
              destination.parentID === source.dataset.foundryParent
              && destination.slotID === source.dataset.foundrySlot
            );
          };

          const insertionFlow = element => {
            const parent = element?.parentElement;
            if (!parent) return { axis: 'block', reversed: false };
            const style = getComputedStyle(parent);
            if (style.display === 'flex' || style.display === 'inline-flex') {
              const inline = style.flexDirection === 'row' || style.flexDirection === 'row-reverse';
              return {
                axis: inline ? 'inline' : 'block',
                reversed: inline && style.flexDirection === 'row-reverse'
              };
            }
            if (style.display === 'grid' || style.display === 'inline-grid') {
              const tracks = style.gridTemplateColumns
                .split(/\\s+/)
                .filter(track => track.length > 0 && track !== 'none');
              return {
                axis: tracks.length > 1 ? 'inline' : 'block',
                reversed: tracks.length > 1 && style.direction === 'rtl'
              };
            }
            return { axis: 'block', reversed: false };
          };

          const adjacentPlacement = (element, event) => {
            const rect = element.getBoundingClientRect();
            const flow = insertionFlow(element);
            if (flow.axis === 'inline') {
              const firstHalf = event.clientX < rect.left + rect.width / 2;
              const before = flow.reversed ? !firstHalf : firstHalf;
              return { kind: before ? 'before' : 'after', axis: 'inline' };
            }
            return {
              kind: event.clientY < rect.top + rect.height / 2 ? 'before' : 'after',
              axis: 'block'
            };
          };

          const intendedPlacement = event => {
            // A populated container never shows the inside slab: hovering its
            // gaps or padding snaps to an insertion line beside the nearest
            // child, so the slab is reserved for genuinely empty targets.
            const insertionAmongChildren = container => {
              // Direct part-children only: a child's nearest part ancestor is
              // the container itself — or none at all when the container is
              // the page body rather than a part.
              const owner = container.matches(selector) ? container : null;
              const children = Array.from(container.querySelectorAll(selector))
                .filter(child => (child.parentElement?.closest(selector) || null) === owner);
              if (!children.length) return null;
              const pointerX = Number.isFinite(event.clientX) ? event.clientX : 0;
              const pointerY = Number.isFinite(event.clientY) ? event.clientY : 0;
              let best = children[0];
              let bestDistance = Infinity;
              for (const child of children) {
                const childRect = child.getBoundingClientRect();
                const dx = Math.max(childRect.left - pointerX, 0, pointerX - childRect.right);
                const dy = Math.max(childRect.top - pointerY, 0, pointerY - childRect.bottom);
                const distance = Math.hypot(dx, dy);
                if (distance < bestDistance) { bestDistance = distance; best = child; }
              }
              const flow = insertionFlow(best);
              const bestRect = best.getBoundingClientRect();
              const firstHalf = flow.axis === 'inline'
                ? pointerX < (bestRect.left + bestRect.right) / 2
                : pointerY < (bestRect.top + bestRect.bottom) / 2;
              const before = flow.reversed ? !firstHalf : firstHalf;
              return {
                kind: before ? 'before' : 'after',
                axis: flow.axis,
                targetID: best.dataset.foundryId,
                element: best
              };
            };
            // Sibling-insertion bands along the flow axis: the outer 25%
            // (at least 18px) of a part means before/after it. Returns null
            // in the middle so callers can fall through to inside/half-split.
            // maxBand caps the band for targets whose interior is itself the
            // visible drop affordance.
            const edgePlacement = (element, maxBand) => {
              const rect = element.getBoundingClientRect();
              const flow = insertionFlow(element);
              const cap = maxBand || Infinity;
              if (flow.axis === 'inline') {
                const distanceFromStart = flow.reversed
                  ? rect.right - event.clientX
                  : event.clientX - rect.left;
                const distanceFromEnd = flow.reversed
                  ? event.clientX - rect.left
                  : rect.right - event.clientX;
                const edgeTargetWidth = Math.min(Math.max(rect.width * 0.25, 18), rect.width / 2, cap);
                if (distanceFromStart <= edgeTargetWidth) {
                  return { kind: 'before', axis: 'inline', targetID: element.dataset.foundryId, element };
                }
                if (distanceFromEnd <= edgeTargetWidth) {
                  return { kind: 'after', axis: 'inline', targetID: element.dataset.foundryId, element };
                }
                return null;
              }
              const distanceFromTop = event.clientY - rect.top;
              const distanceFromBottom = rect.bottom - event.clientY;
              const edgeTargetHeight = Math.min(Math.max(rect.height * 0.25, 18), rect.height / 2, cap);
              if (distanceFromTop <= edgeTargetHeight) {
                return { kind: 'before', axis: 'block', targetID: element.dataset.foundryId, element };
              }
              if (distanceFromBottom <= edgeTargetHeight) {
                return { kind: 'after', axis: 'block', targetID: element.dataset.foundryId, element };
              }
              return null;
            };
            const emptyParent = event.target.closest('[data-foundry-empty-parent]');
            if (emptyParent) {
              // The zone fills its host part, so without edge bands an empty
              // container as last sibling would swallow every hover as
              // "inside" and you could never drop after it. But the slab is
              // the visible target here, so the bands stay a thin sliver —
              // anywhere the cursor reads as "in the zone" drops inside.
              const host = emptyParent.closest(selector);
              const banded = host ? edgePlacement(host, 8) : null;
              if (banded) return banded;
              return {
                kind: 'inside',
                targetID: emptyParent.dataset.foundryEmptyParent,
                slotID: emptyParent.dataset.foundrySlotId,
                element: emptyParent
              };
            }
            const rootDropZone = event.target.closest('[data-foundry-root-drop-zone]');
            if (rootDropZone) return { kind: 'end', element: rootDropZone };
            const adjacentZone = event.target.closest('[data-foundry-adjacent-target]');
            if (adjacentZone) {
              const adjacent = adjacentPlacement(adjacentZone, event);
              return {
                kind: adjacent.kind,
                axis: adjacent.axis,
                targetID: adjacentZone.dataset.foundryAdjacentTarget,
                element: adjacentZone
              };
            }
            const element = event.target.closest(selector);
            if (!element) {
              // Bare page area around the content: snap to the nearest
              // top-level part so the drop shows an insertion bar instead of
              // silently appending with no indicator.
              return insertionAmongChildren(document.body) || { kind: 'end' };
            }
            const banded = edgePlacement(element);
            if (banded) return banded;
            if (element.dataset.foundryAcceptsChildren === 'true') {
              return insertionAmongChildren(element)
                || { kind: 'inside', targetID: element.dataset.foundryId, element };
            }
            const rect = element.getBoundingClientRect();
            const flow = insertionFlow(element);
            if (flow.axis === 'inline') {
              const distanceFromStart = flow.reversed
                ? rect.right - event.clientX
                : event.clientX - rect.left;
              return {
                kind: distanceFromStart < rect.width / 2 ? 'before' : 'after',
                axis: 'inline',
                targetID: element.dataset.foundryId,
                element
              };
            }
            return {
              kind: event.clientY - rect.top < rect.height / 2 ? 'before' : 'after',
              axis: 'block',
              targetID: element.dataset.foundryId,
              element
            };
          };

          let editorOptions = {
            showsTitles: true,
            showsOutlines: true,
            showsSelection: true,
            scrollsToSelection: true
          };

          window.foundrySetEditorOptions = options => {
            editorOptions = { ...editorOptions, ...options };
            document.documentElement.classList.toggle('foundry-show-titles', editorOptions.showsTitles);
            document.documentElement.classList.toggle('foundry-show-outlines', editorOptions.showsOutlines);
            scheduleChromeTitleUpdate();
          };

          window.foundrySetSelection = (ids, primitiveSelection = {}, shouldScroll = true) => {
            selectedPartIDs = Array.isArray(ids) ? ids : [];
            selectedPrimitiveSelection = primitiveSelection?.partID ? primitiveSelection : null;
            selectedChromeTargets.length = 0;
            if (!Array.isArray(selectedPartIDs)) return;
            let firstElement = null;
            selectedPartIDs.forEach(partID => {
              const element = document.querySelector('[data-foundry-id="' + CSS.escape(partID) + '"]');
              if (!element) return;
              let selectionElement = element;
              let isPrimitive = false;
              let isCollection = false;
              let selectionTitle = partChromeTitle(element);
              if (selectedPrimitiveSelection?.partID === partID) {
                const expectedPath = Array.isArray(selectedPrimitiveSelection.propertyPath)
                  ? selectedPrimitiveSelection.propertyPath.join(',')
                  : '';
                const collectionSelector = '[data-foundry-collection-property="'
                  + CSS.escape(selectedPrimitiveSelection.propertyKey || '') + '"]';
                const collectionCandidates = [
                  ...(element.matches(collectionSelector) ? [element] : []),
                  ...element.querySelectorAll(collectionSelector)
                ];
                const collectionItem = collectionCandidates.find(candidate =>
                  candidate.closest(selector) === element
                  && (candidate.dataset.foundryPropertyPath || '') === expectedPath
                );
                const primitiveSelector = '[data-foundry-primitive-property="'
                  + CSS.escape(selectedPrimitiveSelection.propertyKey || '') + '"]';
                const candidates = [
                  ...(element.matches(primitiveSelector) ? [element] : []),
                  ...element.querySelectorAll(primitiveSelector)
                ];
                const primitive = candidates.find(candidate =>
                  candidate.closest(selector) === element
                  && (candidate.dataset.foundryPropertyPath || '') === expectedPath
                );
                if (collectionItem) {
                  selectionElement = collectionItem;
                  isPrimitive = true;
                  isCollection = true;
                  const position = Number.parseInt(expectedPath.split(',').at(-1), 10) + 1;
                  selectionTitle = (collectionItem.dataset.foundryCollectionLabel || 'Item') + ' ' + position;
                } else if (primitive) {
                  selectionElement = primitive;
                  isPrimitive = true;
                }
              }
              if (!firstElement) firstElement = selectionElement;
              selectedChromeTargets.push({
                element: selectionElement,
                part: element,
                color: partChromeColor(selectionElement),
                isPrimitive,
                isCollection,
                title: selectionTitle,
                propertyKey: selectedPrimitiveSelection?.propertyKey,
                propertyPath: selectedPrimitiveSelection?.propertyPath || []
              });
            });
            updateChromeTitle();
            if (firstElement && editorOptions.scrollsToSelection && shouldScroll) {
              firstElement.scrollIntoView({ block: 'nearest', inline: 'nearest' });
            }
          };

          document.addEventListener('keydown', event => {
            const target = event.target;
            if (target?.isContentEditable || target?.closest?.('input, textarea, select, [contenteditable="true"]')) return;
            if (event.key === 'Escape' && selectedPartIDs.length > 0) {
              event.preventDefault();
              event.stopPropagation();
              window.webkit.messageHandlers.foundryCanvas.postMessage({
                version: 1,
                event: 'clearSelection'
              });
              return;
            }
            if (selectedPartIDs.length === 0) return;

            const postSelectionAction = action => {
              event.preventDefault();
              event.stopPropagation();
              window.webkit.messageHandlers.foundryCanvas.postMessage({
                version: 1,
                event: action,
                partIDs: selectedPartIDs
              });
            };

            if (!event.metaKey && !event.altKey && !event.ctrlKey && !event.shiftKey
                && (event.key === 'Backspace' || event.key === 'Delete')) {
              // A primitive selection still selects its owning part, and inline
              // editing is already excluded by the contenteditable check above, so
              // Delete removes the part exactly like the context menu does.
              postSelectionAction('deleteParts');
              return;
            }

            if (!event.metaKey && !event.altKey && !event.ctrlKey && !event.shiftKey
                && event.key === 'Enter' && selectedPartIDs.length === 1) {
              const partID = selectedPartIDs[0];
              const part = document.querySelector('[data-foundry-id="' + CSS.escape(partID) + '"]');
              if (selectedEditableElement(part)) {
                event.preventDefault();
                event.stopPropagation();
                window.foundryEditPart(partID);
              }
              return;
            }

            if (event.metaKey && !event.altKey && !event.ctrlKey && !event.shiftKey) {
              const key = event.key.toLowerCase();
              if (key === 'd') postSelectionAction('duplicateParts');
              else if (key === 'c') postSelectionAction('copyParts');
              else if (key === 'v') postSelectionAction('pasteParts');
              return;
            }

            if (!event.metaKey || !event.altKey || event.ctrlKey || event.shiftKey
                || selectedPartIDs.length !== 1) return;
            const part = document.querySelector(
              '[data-foundry-id="' + CSS.escape(selectedPartIDs[0]) + '"]'
            );
            if (!part) return;
            const parentPart = part.parentElement?.closest(selector) ?? null;
            const siblings = [...document.querySelectorAll(selector)].filter(candidate =>
              (candidate.parentElement?.closest(selector) ?? null) === parentPart
            );
            const index = siblings.indexOf(part);
            let placement = null;
            if (event.key === 'ArrowUp' && index > 0) {
              placement = { kind: 'before', targetID: siblings[index - 1].dataset.foundryId };
            } else if (event.key === 'ArrowDown' && index >= 0 && index < siblings.length - 1) {
              placement = { kind: 'after', targetID: siblings[index + 1].dataset.foundryId };
            } else if (event.key === 'ArrowLeft' && parentPart) {
              placement = { kind: 'after', targetID: parentPart.dataset.foundryId };
            }
            if (!placement) return;
            event.preventDefault();
            event.stopPropagation();
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'movePart',
              partID: selectedPartIDs[0],
              placement
            });
          }, true);

          const dragHandlerElements = new WeakSet();
          const installPartDragHandlers = (elements = document.querySelectorAll(selector)) => {
            elements.forEach(element => {
              if (dragHandlerElements.has(element)) return;
              dragHandlerElements.add(element);
              element.draggable = true;
              element.addEventListener('dragstart', event => {
              const primitive = event.target.closest('[data-foundry-primitive-property]');
              if (primitive && primitive !== element) {
                event.preventDefault();
                return;
              }
              if (element.isContentEditable) {
                event.preventDefault();
                return;
              }
              const draggedID = element.dataset.foundryId;
              isDragging = true;
              const isGroupDrag = selectedPartIDs.length > 1 && selectedPartIDs.includes(draggedID);
              const value = isGroupDrag
                ? 'foundry-nodes:' + selectedPartIDs.join(',')
                : 'foundry-node:' + draggedID;
              const draggedElements = isGroupDrag
                ? selectedPartIDs
                    .map(id => document.querySelector('[data-foundry-id="' + CSS.escape(id) + '"]'))
                    .filter(Boolean)
                : [element];
              markDragSources(draggedElements);
              if (isGroupDrag) {
                const dragImage = document.createElement('div');
                dragImage.className = 'foundry-multi-drag-image';
                dragImage.textContent = selectedPartIDs.length + ' parts';
                dragImage.style.setProperty(
                  '--foundry-drag-color',
                  getComputedStyle(element).getPropertyValue('--foundry-editor-chrome').trim() || '#007BFF'
                );
                document.body.appendChild(dragImage);
                event.dataTransfer.setDragImage(dragImage, 28, 20);
                requestAnimationFrame(() => dragImage.remove());
              }
              event.dataTransfer.setData('text/plain', value);
              event.dataTransfer.effectAllowed = 'copyMove';
              event.stopPropagation();
              });
              element.addEventListener('dragend', () => {
                isDragging = false;
                clearDrop();
                clearDragSources();
                scheduleChromeTitleUpdate();
              });
            });
          };
          installPartDragHandlers();

          const syncAttributes = (target, source) => {
            const pointerOutside = target === document.documentElement && target.hasAttribute('data-foundry-pointer-outside');
            Array.from(target.attributes).forEach(attribute => target.removeAttribute(attribute.name));
            Array.from(source.attributes).forEach(attribute => target.setAttribute(attribute.name, attribute.value));
            if (pointerOutside) target.setAttribute('data-foundry-pointer-outside', '');
          };

          let latestFoundryRevision = 0;
          let retainedParts = null;
          let retainedStyles = null;
          window.foundryApplyScene = (html, styles, removed, roots, revision, styleMoves = [], childMoves = {}) => {
            if (!Number.isSafeInteger(revision) || revision < latestFoundryRevision) return false;
            if (!retainedParts) {
              retainedParts = new Map();
              for (const part of document.querySelectorAll(selector)) {
                if (retainedParts.has(part.dataset.foundryId)) { retainedParts = null; return false; }
                retainedParts.set(part.dataset.foundryId, part);
              }
            }
            // Instance stylesheets are addressed by identifier on every
            // transaction. Keep them in a map so a page of any size costs one
            // lookup per sheet the edit actually touches.
            if (!retainedStyles) {
              retainedStyles = new Map();
              for (const style of document.head.querySelectorAll('style[data-foundry-instance-style]')) {
                const styleID = style.dataset.foundryInstanceStyle;
                if (retainedStyles.has(styleID)) { retainedStyles = null; return false; }
                retainedStyles.set(styleID, style);
              }
            }
            const replacements = new Map();
            const references = new Map();
            // Validate the entire transaction before touching the live document.
            for (const [id, source] of Object.entries(html)) {
              const template = document.createElement('template');
              template.innerHTML = source.trim();
              const element = template.content.firstElementChild;
              if (!element || template.content.childElementCount !== 1 || element.dataset.foundryId !== id) return false;
              const walker = document.createTreeWalker(element, NodeFilter.SHOW_COMMENT);
              const refs = [];
              while (walker.nextNode()) {
                const comment = walker.currentNode;
                if (comment.data.startsWith('foundry-child:')) refs.push([comment, comment.data.slice(14)]);
              }
              replacements.set(id, element);
              references.set(id, refs);
            }
            const available = id => !removed.includes(id) && (replacements.has(id) || retainedParts.has(id));
            const owners = new Set();
            for (const refs of references.values()) {
              for (const [, id] of refs) {
                if (!available(id) || owners.has(id)) return false;
                owners.add(id);
              }
            }
            const visiting = new Set(), visited = new Set();
            const acyclic = id => {
              if (visiting.has(id)) return false;
              if (visited.has(id)) return true;
              visiting.add(id);
              for (const [, child] of references.get(id) || []) if (!acyclic(child)) return false;
              visiting.delete(id); visited.add(id); return true;
            };
            for (const id of replacements.keys()) if (!acyclic(id)) return false;
            // A child placement needs both the child and the sibling it anchors
            // against to survive this transaction.
            for (const moves of Object.values(childMoves)) {
              for (const [childID, position, anchorID] of moves) {
                if (position !== 'before' && position !== 'after') return false;
                if (childID === anchorID) return false;
                if (!available(childID) || !available(anchorID)) return false;
              }
            }
            // A stylesheet instruction is only meaningful if both the sheet and
            // its anchor survive this transaction.
            const styleBoundary = document.head.querySelector('[data-foundry-shared-styles]');
            const styledAfter = id => {
              if (removed.includes(id)) return false;
              if (Object.prototype.hasOwnProperty.call(styles, id)) return styles[id] !== '';
              return retainedStyles.has(id);
            };
            if (styleMoves.length > 0 && !styleBoundary) return false;
            for (const [id, anchorID] of styleMoves) {
              if (!styledAfter(id)) return false;
              if (anchorID !== '' && !styledAfter(anchorID)) return false;
            }
            let start, end;
            if (roots !== null) {
              for (const node of document.body.childNodes) {
                if (node.nodeType === Node.COMMENT_NODE && node.data === 'foundry-roots-start') start = node;
                if (node.nodeType === Node.COMMENT_NODE && node.data === 'foundry-roots-end') end = node;
              }
              if (!start || !end || roots.some(id => !available(id))) return false;
            }
            for (const [id, element] of replacements) {
              const current = retainedParts.get(id);
              if (current) chromeResizeObserver.unobserve(current);
              current?.replaceWith(element);
              retainedParts.set(id, element);
              chromeResizeObserver.observe(element);
            }
            for (const refs of references.values()) {
              for (const [comment, id] of refs) comment.replaceWith(retainedParts.get(id));
            }
            for (const id of removed) {
              const current = retainedParts.get(id);
              if (current) chromeResizeObserver.unobserve(current);
              current?.remove();
              retainedParts.delete(id);
              retainedStyles.get(id)?.remove();
              retainedStyles.delete(id);
            }
            if (roots !== null) {
              const fragment = document.createDocumentFragment();
              roots.forEach(id => fragment.appendChild(retainedParts.get(id)));
              while (start.nextSibling && start.nextSibling !== end) start.nextSibling.remove();
              end.before(fragment);
            }
            // Re-seat only the children whose position changed. Their elements
            // and everything beneath them stay exactly where they are.
            for (const moves of Object.values(childMoves)) {
              for (const [childID, position, anchorID] of moves) {
                const child = retainedParts.get(childID);
                const anchor = retainedParts.get(anchorID);
                if (!child || !anchor) continue;
                if (position === 'before') anchor.before(child);
                else anchor.after(child);
              }
            }
            for (const [id, css] of Object.entries(styles)) {
              let style = retainedStyles.get(id);
              if (!css) { style?.remove(); retainedStyles.delete(id); continue; }
              if (!style) {
                style = document.createElement('style');
                style.dataset.foundryInstanceStyle = id;
                // Instance sheets all live ahead of the shared boundary; the
                // move instructions below settle the exact position.
                if (styleBoundary) styleBoundary.before(style);
                else document.head.appendChild(style);
                retainedStyles.set(id, style);
              }
              style.textContent = css;
            }
            // CSS source order is observable, including package-scoped :host
            // rules and custom HTML CSS. Keep it identical to a fresh render —
            // by moving only the sheets whose position actually changed.
            for (const [id, anchorID] of styleMoves) {
              const style = retainedStyles.get(id);
              if (!style) continue;
              const anchor = anchorID === '' ? styleBoundary : retainedStyles.get(anchorID);
              anchor?.before(style);
            }
            latestFoundryRevision = revision;
            installPartDragHandlers(Array.from(replacements.values()));
            hoveredPart = null; hoveredPrimitive = null;
            window.foundrySetEditorOptions(editorOptions);
            window.foundrySetSelection(selectedPartIDs, selectedPrimitiveSelection, false);
            scheduleChromeTitleUpdate();
            return true;
          };
          window.foundryReplacePart = (partID, html, styles, revision) => {
            if (!Number.isSafeInteger(revision) || revision < latestFoundryRevision) return false;
            const current = document.querySelector('[data-foundry-id="' + CSS.escape(partID) + '"]');
            if (!current) return false;
            const template = document.createElement('template');
            template.innerHTML = html.trim();
            const replacement = template.content.firstElementChild;
            if (!replacement || template.content.childElementCount !== 1 || replacement.dataset.foundryId !== partID) return false;
            current.replaceWith(replacement);
            retainedParts = null;
            retainedStyles = null;
            // One <style> per instance: a parent's patch must update each
            // descendant's own element rather than bundling their rules, or
            // the bundle would shadow the descendant's later patches.
            Object.entries(styles || {}).forEach(([styleID, css]) => {
              const styleSelector = 'style[data-foundry-instance-style="' + CSS.escape(styleID) + '"]';
              let style = document.head.querySelector(styleSelector);
              if (css) {
                if (!style) {
                  style = document.createElement('style');
                  style.dataset.foundryInstanceStyle = styleID;
                  document.head.appendChild(style);
                }
                style.textContent = css;
              } else {
                style?.remove();
              }
            });
            latestFoundryRevision = revision;
            installPartDragHandlers();
            observeChromeGeometry();
            hoveredPart = null;
            hoveredPrimitive = null;
            window.foundrySetEditorOptions(editorOptions);
            window.foundrySetSelection(selectedPartIDs, selectedPrimitiveSelection, false);
            scheduleChromeTitleUpdate();
            return true;
          };

          window.foundryReplaceDocument = (html, revision = latestFoundryRevision) => {
            if (!Number.isSafeInteger(revision) || revision < latestFoundryRevision) return false;
            const replacement = new DOMParser().parseFromString(html, 'text/html');
            retainedParts = null;
            retainedStyles = null;
            replacement.querySelectorAll(selector).forEach(element => { element.draggable = true; });

            const currentHeadNodes = Array.from(document.head.childNodes);
            const replacementHeadNodes = Array.from(replacement.head.childNodes);
            replacementHeadNodes.forEach((node, index) => {
              const current = currentHeadNodes[index];
              if (!current) {
                document.head.appendChild(document.importNode(node, true));
              } else if (current.nodeName === 'STYLE' && node.nodeName === 'STYLE') {
                syncAttributes(current, node);
                if (current.textContent !== node.textContent) current.textContent = node.textContent;
              } else if (!current.isEqualNode(node)) {
                current.replaceWith(document.importNode(node, true));
              }
            });
            currentHeadNodes.slice(replacementHeadNodes.length).forEach(node => node.remove());

            syncAttributes(document.documentElement, replacement.documentElement);
            syncAttributes(document.body, replacement.body);
            // Part patches cannot reconcile moves, removals or reordering:
            // replacing a parent can leave the child's former DOM node behind.
            // Compare generic element topology, including part and slot identity,
            // before touching the live tree. No package-specific knowledge is needed.
            const topology = root => JSON.stringify(Array.from(root.children, function describe(element) {
              return [element.localName, element.getAttribute('data-foundry-id'),
                element.getAttribute('data-foundry-slot-id'), Array.from(element.children, describe)];
            }));
            const structureChanged = topology(document.body) !== topology(replacement.body);
            if (structureChanged) {
              const bodyNodes = Array.from(replacement.body.childNodes).map(node => document.importNode(node, true));
              document.body.replaceChildren(...bodyNodes);
            } else {
              const changedIDs = new Set();
              replacement.querySelectorAll(selector).forEach(nextElement => {
                const partID = nextElement.dataset.foundryId;
                const currentElement = document.querySelector('[data-foundry-id="' + CSS.escape(partID) + '"]');
                if (!currentElement || currentElement.outerHTML === nextElement.outerHTML) return;
                const changedAncestor = nextElement.parentElement?.closest(selector);
                if (changedAncestor && changedIDs.has(changedAncestor.dataset.foundryId)) return;
                currentElement.replaceWith(document.importNode(nextElement, true));
                changedIDs.add(partID);
              });

              if (document.body.innerHTML !== replacement.body.innerHTML) {
                const bodyNodes = Array.from(replacement.body.childNodes).map(node => document.importNode(node, true));
                document.body.replaceChildren(...bodyNodes);
              }
            }
            latestFoundryRevision = revision;
            installPartDragHandlers();
            observeChromeGeometry();
            hoveredPart = null;
            hoveredPrimitive = null;
            window.foundrySetEditorOptions(editorOptions);
            window.foundrySetSelection(selectedPartIDs, selectedPrimitiveSelection, false);
            scheduleChromeTitleUpdate();
            return true;
          };

          // Image wells and video wells share one drop pipeline. A zone may
          // carry both markers — a filled video element takes an image as its
          // poster and a movie as its replacement — so the dropped file's
          // kind picks the property key.
          const mediaZoneAt = target => {
            const zone = target.closest('[data-foundry-image-drop-zone], [data-foundry-video-drop-zone]');
            if (!zone) return null;
            return {
              zone,
              imageKey: zone.matches('[data-foundry-image-drop-zone]') ? zone.dataset.foundryImageProperty : undefined,
              videoKey: zone.matches('[data-foundry-video-drop-zone]') ? zone.dataset.foundryVideoProperty : undefined
            };
          };

          document.addEventListener('dragover', event => {
            isDragging = true;
            clearDrop();
            updateSelectionChrome();
            hoverChrome.style.setProperty('display', 'none', 'important');
            if (event.dataTransfer.types.includes('Files')) {
              event.preventDefault();
              const media = mediaZoneAt(event.target);
              const mediaPart = media?.zone.closest(selector);
              if (mediaPart) {
                showDropChrome({ kind: 'inside', targetID: mediaPart.dataset.foundryId, element: media.zone });
              } else {
                placement = intendedPlacement(event);
                showDropChrome(placement);
              }
              event.dataTransfer.dropEffect = 'copy';
              return;
            }
            const carriesPartText = Array.from(event.dataTransfer.types).some(type =>
              type === 'text/plain' || type === 'public.utf8-plain-text'
            );
            if (!carriesPartText) {
              event.dataTransfer.dropEffect = 'none';
              return;
            }
            event.preventDefault();
            const draggedValue = event.dataTransfer.getData('text/plain');
            const carriesImageAsset = event.dataTransfer.types.includes('uk.co.garysimpson.foundry.image-asset')
              || draggedValue.startsWith('foundry-image-asset:');
            const carriesVideoAsset = event.dataTransfer.types.includes('uk.co.garysimpson.foundry.video-asset')
              || draggedValue.startsWith('foundry-video-asset:');
            const mediaZone = carriesImageAsset
              ? event.target.closest('[data-foundry-image-drop-zone]')
              : carriesVideoAsset
                ? event.target.closest('[data-foundry-video-drop-zone]')
                : null;
            const mediaPart = mediaZone?.closest(selector);
            if (mediaPart) {
              showDropChrome({ kind: 'inside', targetID: mediaPart.dataset.foundryId, element: mediaZone });
              event.dataTransfer.dropEffect = 'copy';
              return;
            }
            const candidate = intendedPlacement(event);
            if (!respectsLockedContainment(candidate)) {
              placement = null;
              event.dataTransfer.dropEffect = 'none';
              return;
            }
            placement = candidate;
            showDropChrome(placement);
            const isPartDrag = draggedValue.startsWith('foundry-node:')
              || draggedValue.startsWith('foundry-nodes:');
            const allowedEffect = event.dataTransfer.effectAllowed;
            event.dataTransfer.dropEffect = isPartDrag
              ? (event.altKey ? 'copy' : 'move')
              : (allowedEffect === 'move' ? 'move' : 'copy');
          });

          document.addEventListener('dragleave', event => {
            if (!document.documentElement.contains(event.relatedTarget)) {
              isDragging = false;
              clearDrop();
              scheduleChromeTitleUpdate();
            }
          });

          document.addEventListener('drop', event => {
            isDragging = false;
            event.preventDefault();
            scheduleChromeTitleUpdate();
            clearDragSources();
            const file = event.dataTransfer.files[0];
            if (file) {
              const media = mediaZoneAt(event.target);
              const mediaPart = media?.zone.closest(selector);
              const target = placement || intendedPlacement(event);
              clearDrop();
              const isImage = file.type.startsWith('image/') || /\\.(?:avif|gif|heic|heif|jpe?g|png|svg|webp)$/i.test(file.name);
              const isVideo = file.type.startsWith('video/') || /\\.(?:m4v|mov|mp4|webm)$/i.test(file.name);
              let mediaPropertyKey = null;
              if (media && mediaPart) {
                if (isVideo && media.videoKey) {
                  if (file.size > 100000000) return;
                  mediaPropertyKey = media.videoKey;
                } else if (isImage && media.imageKey) {
                  if (file.size > 25000000) return;
                  mediaPropertyKey = media.imageKey;
                } else {
                  return;
                }
              } else if (isVideo) {
                if (file.size > 100000000) return;
              } else if (!isImage || file.size > 25000000) {
                return;
              }
              const internalAssetMatch = file.name.match(/^foundry-asset-([0-9a-f-]{36})--/i);
              if (internalAssetMatch) {
                const message = {
                  version: 1,
                  event: mediaPropertyKey ? 'importImageAsset' : 'insertImagePart',
                  assetID: internalAssetMatch[1]
                };
                if (mediaPropertyKey) {
                  message.partID = mediaPart.dataset.foundryId;
                  message.propertyKey = mediaPropertyKey;
                  message.propertyPath = propertyPath(media.zone);
                } else {
                  message.placement = { kind: target.kind, targetID: target.targetID, slotID: target.slotID };
                }
                window.webkit.messageHandlers.foundryCanvas.postMessage(message);
                return;
              }
              const reader = new FileReader();
              reader.onload = () => {
                const encoded = String(reader.result).split(',', 2)[1];
                const message = {
                  version: 1,
                  event: mediaPropertyKey ? 'importImageAsset' : 'insertImagePart',
                  assetFilename: file.name,
                  assetMediaType: file.type || 'application/octet-stream',
                  assetData: encoded
                };
                if (mediaPropertyKey) {
                  message.partID = mediaPart.dataset.foundryId;
                  message.propertyKey = mediaPropertyKey;
                  message.propertyPath = propertyPath(media.zone);
                } else {
                  message.placement = { kind: target.kind, targetID: target.targetID, slotID: target.slotID };
                }
                window.webkit.messageHandlers.foundryCanvas.postMessage(message);
              };
              reader.readAsDataURL(file);
              return;
            }
            const value = event.dataTransfer.getData('text/plain');
            const imageZone = event.target.closest('[data-foundry-image-drop-zone]');
            const image = imageZone?.closest(selector);
            const target = placement || intendedPlacement(event);
            clearDrop();
            const message = {
              version: 1,
              placement: { kind: target.kind, targetID: target.targetID, slotID: target.slotID }
            };
            if (value.startsWith('foundry-part-type:')) {
              message.event = 'insertPart';
              message.partType = value.substring('foundry-part-type:'.length);
            } else if (value.startsWith('foundry-reusable-part:')) {
              message.event = 'insertReusablePart';
              message.reusableDefinitionID = value.substring('foundry-reusable-part:'.length);
            } else if (value.startsWith('foundry-global-part:')) {
              message.event = 'insertGlobalPart';
              message.globalDefinitionID = value.substring('foundry-global-part:'.length);
            } else if (value.startsWith('foundry-nodes:')) {
              message.event = 'movePart';
              message.partIDs = value.substring('foundry-nodes:'.length).split(',');
              message.isCopy = event.altKey;
            } else if (value.startsWith('foundry-node:')) {
              message.event = 'movePart';
              message.partID = value.substring('foundry-node:'.length);
              message.isCopy = event.altKey;
            } else if (value.startsWith('foundry-image-asset:')) {
              message.event = image ? 'importImageAsset' : 'insertImagePart';
              message.assetID = value.substring('foundry-image-asset:'.length);
              if (image) {
                delete message.placement;
                message.partID = image.dataset.foundryId;
                message.propertyKey = imageZone.dataset.foundryImageProperty;
                message.propertyPath = propertyPath(imageZone);
              }
            } else if (value.startsWith('foundry-video-asset:')) {
              message.assetID = value.substring('foundry-video-asset:'.length);
              const videoZone = event.target.closest('[data-foundry-video-drop-zone]');
              const videoPart = videoZone?.closest(selector);
              if (videoPart) {
                message.event = 'importImageAsset';
                delete message.placement;
                message.partID = videoPart.dataset.foundryId;
                message.propertyKey = videoZone.dataset.foundryVideoProperty;
                message.propertyPath = propertyPath(videoZone);
              } else {
                message.event = 'insertImagePart';
              }
            } else {
              return;
            }
            window.webkit.messageHandlers.foundryCanvas.postMessage(message);
          });

          document.addEventListener('dblclick', event => {
            const editableElement = event.target.closest('[data-foundry-inline-property]');
            const partElement = editableElement?.closest(selector);
            const element = editableElement ?? event.target.closest(selector);
            const editableProperty = element?.dataset.foundryInlineProperty;
            if (!element || !editableProperty) return;
            event.preventDefault();
            event.stopPropagation();

            const editsHTML = element.hasAttribute('data-foundry-inline-html');
            const decodeSource = encoded => new TextDecoder().decode(
              Uint8Array.from(atob(encoded), character => character.charCodeAt(0))
            );
            if (editsHTML) {
              const source = element.dataset.foundryInlineSource
                ? decodeSource(element.dataset.foundryInlineSource)
                : element.innerHTML;
              window.webkit.messageHandlers.foundryCanvas.postMessage({
                version: 1,
                event: 'editHTMLPart',
                partID: (partElement ?? element).dataset.foundryId,
                propertyKey: editableProperty,
                propertyPath: propertyPath(element),
                propertyValue: source
              });
              return;
            }

            const source = element.dataset.foundryInlineSource
              ? decodeSource(element.dataset.foundryInlineSource)
              : element.innerText;
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'editPart',
              partID: (partElement ?? element).dataset.foundryId,
              propertyKey: editableProperty,
              propertyPath: propertyPath(element),
              propertyValue: source
            });
          }, true);

          const selectedEditableElement = part => {
            if (!part || !selectedPartIDs.includes(part.dataset.foundryId)) return null;
            if (selectedPrimitiveSelection?.partID === part.dataset.foundryId) {
              const expectedPath = Array.isArray(selectedPrimitiveSelection.propertyPath)
                ? selectedPrimitiveSelection.propertyPath.join(',')
                : '';
              const property = selectedPrimitiveSelection.propertyKey || '';
              const candidates = [
                ...(part.matches('[data-foundry-inline-property]') ? [part] : []),
                ...part.querySelectorAll('[data-foundry-inline-property]')
              ];
              return candidates.find(candidate =>
                candidate.dataset.foundryInlineProperty === property
                && (candidate.dataset.foundryPropertyPath || '') === expectedPath
                && candidate.closest(selector) === part
              ) ?? null;
            }
            return part.matches('[data-foundry-inline-property]') ? part : null;
          };

          window.foundryEditPart = partID => {
            const part = document.querySelector('[data-foundry-id="' + CSS.escape(partID) + '"]');
            const editable = selectedEditableElement(part);
            if (!editable) return;
            editable.dispatchEvent(new MouseEvent('dblclick', { bubbles: true, cancelable: true }));
          };

          document.addEventListener('contextmenu', event => {
            if (event.altKey) return;
            const part = event.target.closest(selector);
            if (!part) return;
            const clickedPrimitiveCandidate = event.target.closest('[data-foundry-primitive-property]');
            const clickedPrimitive = clickedPrimitiveCandidate?.closest(selector) === part
              ? clickedPrimitiveCandidate
              : null;
            const primitiveProperty = clickedPrimitive?.dataset.foundryPrimitiveProperty;
            const primitivePath = propertyPath(clickedPrimitive);
            const primitiveWasSelected = Boolean(
              primitiveProperty
              && selectedPrimitiveSelection?.partID === part.dataset.foundryId
              && selectedPrimitiveSelection?.propertyKey === primitiveProperty
              && (selectedPrimitiveSelection?.propertyPath || []).join(',') === primitivePath.join(',')
            );
            const partWasSelected = selectedPartIDs.includes(part.dataset.foundryId);
            const preservesSelection = clickedPrimitive
              ? primitiveWasSelected
              : partWasSelected && selectedPrimitiveSelection?.partID !== part.dataset.foundryId;
            const selectionCount = preservesSelection ? selectedPartIDs.length : 1;
            const parentPart = part.parentElement?.closest(selector) ?? null;
            const siblings = [...document.querySelectorAll(selector)].filter(candidate =>
              (candidate.parentElement?.closest(selector) ?? null) === parentPart
            );
            const siblingIndex = siblings.indexOf(part);
            const clickedEditable = event.target.closest('[data-foundry-inline-property]');
            const editable = selectionCount === 1
              && clickedEditable?.closest(selector) === part
              && (!clickedPrimitive || clickedEditable === clickedPrimitive);
            const overrideOwner = part.closest('[data-foundry-global-override="true"]');
            const globalTarget = overrideOwner || (part.dataset.foundryGlobal ? part : null);
            const clickedMediaZone = event.target.closest('[data-foundry-image-drop-zone], [data-foundry-video-drop-zone]');
            const imageZone = clickedMediaZone?.closest(selector) === part ? clickedMediaZone : null;
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'contextMenu',
              partID: part.dataset.foundryId,
              partTypeID: part.dataset.foundryPartType,
              parentPartTypeID: parentPart?.dataset.foundryPartType,
              partType: part.dataset.foundryType,
              partAuthor: part.dataset.foundryAuthor,
              partVersion: part.dataset.foundryVersion,
              canEdit: editable,
              primitiveProperty: primitiveProperty,
              primitivePath: primitivePath,
              selectionCount: selectionCount,
              canMoveUp: selectionCount === 1 && siblingIndex > 0,
              canMoveDown: selectionCount === 1 && siblingIndex >= 0 && siblingIndex < siblings.length - 1,
              canOutdent: selectionCount === 1 && parentPart !== null,
              canSaveAsPart: selectionCount === 1 && !part.dataset.foundryGlobal,
              globalTargetID: selectionCount === 1 ? globalTarget?.dataset.foundryId : undefined,
              isGlobalLinked: Boolean(globalTarget && !overrideOwner && selectionCount === 1),
              isGlobalRoot: Boolean(selectionCount === 1 && part.dataset.foundryGlobalRoot === 'true'),
              hasImage: selectionCount === 1 && (imageZone?.tagName === 'IMG' || imageZone?.tagName === 'VIDEO'),
              imageProperty: selectionCount === 1
                ? (imageZone?.dataset.foundryImageProperty || imageZone?.dataset.foundryVideoProperty)
                : undefined,
              imagePropertyPath: selectionCount === 1 ? propertyPath(imageZone) : [],
              preservesSelection: preservesSelection
            });
            if (webInspectorEnabled) return;
            event.preventDefault();
            event.stopPropagation();
          }, true);

          document.addEventListener('click', event => {
            const element = event.target.closest(selector);
            if (element?.isContentEditable) return;
            if (!element) {
              if (event.button === 0 && selectedPartIDs.length > 0) {
                event.preventDefault();
                event.stopPropagation();
                window.webkit.messageHandlers.foundryCanvas.postMessage({
                  version: 1,
                  event: 'clearSelection'
                });
              }
              return;
            }
            event.preventDefault();
            event.stopPropagation();
            if (event.altKey && !event.metaKey && !event.shiftKey) {
              const ancestors = [];
              let candidate = element;
              while (candidate) {
                ancestors.push(candidate);
                candidate = candidate.parentElement?.closest(selector) ?? null;
              }
              const selectedIndex = ancestors.findIndex(candidatePart =>
                candidatePart.dataset.foundryId === selectedPartIDs[0]
              );
              const nextPart = ancestors[(selectedIndex + 1) % ancestors.length];
              window.webkit.messageHandlers.foundryCanvas.postMessage({
                version: 1,
                event: 'selectPart',
                partID: nextPart.dataset.foundryId,
                extendsSelection: false
              });
              return;
            }
            const collectionItem = event.target.closest('[data-foundry-collection-property]');
            if (collectionItem && collectionItem.closest(selector) === element && !(event.metaKey || event.shiftKey)) {
              window.webkit.messageHandlers.foundryCanvas.postMessage({
                version: 1,
                event: 'selectPrimitive',
                partID: element.dataset.foundryId,
                propertyKey: collectionItem.dataset.foundryCollectionProperty,
                propertyPath: propertyPath(collectionItem)
              });
              return;
            }
            const primitive = event.target.closest('[data-foundry-primitive-property]');
            if (primitive && primitive.closest(selector) === element && !(event.metaKey || event.shiftKey)) {
              window.webkit.messageHandlers.foundryCanvas.postMessage({
                version: 1,
                event: 'selectPrimitive',
                partID: element.dataset.foundryId,
                propertyKey: primitive.dataset.foundryPrimitiveProperty,
                propertyPath: propertyPath(primitive)
              });
              return;
            }
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'selectPart',
              partID: element.dataset.foundryId,
              extendsSelection: event.metaKey || event.shiftKey
            });
          }, true);
        })();
        """

        weak var webView: WKWebView?
        var lastHTML: String?
        var assetRevision: UInt64?
        var selectedPartIDs: Set<UUID> = []
        var primarySelectedPartID: UUID?
        var selectedPrimitive: CanvasPrimitiveSelection?
        var editorOptions = CanvasEditorOptions()
        var canPastePart = false
        var canClearImage: (UUID, PartProperty.Key, [Int]) -> Bool
        var handleMessage: (CanvasMessage) -> Void
        var handleContextMenuAction: (CanvasContextMenuAction, UUID, PartProperty.Key?, [Int]) -> Void
        var requestFullReconciliation: () -> Void
        var didApplyRevision: (UInt64) -> Void = { _ in }
        private var loadingRevision: UInt64?
        private var contextMenuPartID: UUID?
        private var contextMenuImageProperty: PartProperty.Key?
        private var contextMenuGlobalTargetID: UUID?
        private var pendingHTML: (html: String, revision: UInt64)?
        private var loadedHTML: String?
        fileprivate var lastSubmittedRevision: UInt64?
        private var revisionGate = CanvasUpdateRevisionGate()
        private var isLoadingHTML = false
        private var contextMenuImagePropertyPath: [Int] = []
        private var contextMenuRequest: [String: Any]?
        private var pendingCanvasSelection: Set<UUID>?
        private var lastAppliedSelection: Set<UUID>?
        private var lastAppliedPrimarySelection: UUID?
        private var scrollPositionBeforeLoad: CGPoint?
        private var isCapturingScrollPosition = false
        private var isPatchingHTML = false

        init(
            assets: ProjectAssetContents,
            packages: [String: LoadedPartPackage],
            canClearImage: @escaping (UUID, PartProperty.Key, [Int]) -> Bool,
            handleMessage: @escaping (CanvasMessage) -> Void,
            handleContextMenuAction: @escaping (CanvasContextMenuAction, UUID, PartProperty.Key?, [Int]) -> Void,
            requestFullReconciliation: @escaping () -> Void
        ) {
            assetSchemeHandler = CanvasAssetSchemeHandler(assets: assets, packages: packages)
            self.canClearImage = canClearImage
            self.handleMessage = handleMessage
            self.handleContextMenuAction = handleContextMenuAction
            self.requestFullReconciliation = requestFullReconciliation
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(systemColorsDidChange),
                name: NSColor.systemColorsDidChangeNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func systemColorsDidChange() {
            applyCanvasState()
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let request = message.body as? [String: Any],
               request["event"] as? String == "contextMenu" {
                presentContextMenu(request)
                return
            }
            guard message.name == Self.handlerName,
                  message.frameInfo.isMainFrame,
                  let canvasMessage = CanvasMessage.decode(message.body) else { return }
            if canvasMessage.event == .clearSelection {
                pendingCanvasSelection = []
            }
            if let partID = canvasMessage.partID,
               canvasMessage.event == .selectPart || canvasMessage.event == .selectPrimitive {
                if canvasMessage.event == .selectPart, canvasMessage.extendsSelection == true {
                    var selection = selectedPartIDs
                    if selection.contains(partID) {
                        selection.remove(partID)
                    } else {
                        selection.insert(partID)
                    }
                    pendingCanvasSelection = selection
                } else {
                    pendingCanvasSelection = [partID]
                }
            }
            handleMessage(canvasMessage)
        }

        private func presentContextMenu(_ request: [String: Any]) {
            guard let webView,
                  let value = request["partID"] as? String,
                  let partID = UUID(uuidString: value) else { return }
            contextMenuRequest = request
            contextMenuPartID = partID
            contextMenuImageProperty = (request["imageProperty"] as? String).map(PartProperty.Key.init(rawValue:))
            contextMenuGlobalTargetID = (request["globalTargetID"] as? String).flatMap(UUID.init(uuidString:))
            contextMenuImagePropertyPath = (request["imagePropertyPath"] as? [NSNumber])?.map(\.intValue) ?? []
            if request["preservesSelection"] as? Bool != true {
                pendingCanvasSelection = [partID]
                if let property = request["primitiveProperty"] as? String {
                    let path = (request["primitivePath"] as? [NSNumber])?.map(\.intValue) ?? []
                    handleMessage(.init(
                        event: .selectPrimitive,
                        partID: partID,
                        propertyKey: .init(rawValue: property),
                        propertyPath: path
                    ))
                } else {
                    handleMessage(.init(event: .selectPart, partID: partID, extendsSelection: false))
                }
            }

            if webView.isInspectable {
                return
            }

            let menu = NSMenu()
            menu.autoenablesItems = false
            addFoundryContextMenuItems(to: menu, request: request, partID: partID)
            let windowPoint = webView.window?.mouseLocationOutsideOfEventStream ?? .zero
            let webViewPoint = webView.convert(windowPoint, from: nil)
            menu.popUp(positioning: nil, at: webViewPoint, in: webView)
        }

        func prepareForNativeContextMenu() {
            contextMenuRequest = nil
        }

        func augmentNativeContextMenu(_ menu: NSMenu) {
            guard let request = contextMenuRequest,
                  let value = request["partID"] as? String,
                  let partID = UUID(uuidString: value) else { return }
            let nativeItems = menu.items
            menu.removeAllItems()
            menu.autoenablesItems = false
            addFoundryContextMenuItems(to: menu, request: request, partID: partID)
            if !nativeItems.isEmpty {
                menu.addItem(.separator())
                nativeItems.forEach(menu.addItem)
            }
        }

        private func addFoundryContextMenuItems(
            to menu: NSMenu,
            request: [String: Any],
            partID: UUID
        ) {
            menu.addItem(contextMenuHeader(for: request))
            menu.addItem(.separator())
            if contextMenuImageProperty != nil {
                let clear = menuItem("Clear", action: #selector(performContextAction(_:)), representedAction: .clearImage)
                clear.isEnabled = contextMenuImageProperty.map { canClearImage(partID, $0, contextMenuImagePropertyPath) } ?? false
                menu.addItem(clear)
                menu.addItem(.separator())
            } else if request["canEdit"] as? Bool == true {
                menu.addItem(menuItem("Edit", action: #selector(editPart), key: "\r", modifiers: []))
                menu.addItem(.separator())
            }
            if (request["selectionCount"] as? Int ?? 1) == 1,
               let parentTypeID = request["parentPartTypeID"] as? String,
               let childTypeID = request["partTypeID"] as? String,
               let customization = LayoutItemCustomization(
                   parentType: PartType(rawValue: parentTypeID),
                   childType: PartType(rawValue: childTypeID)
               ) {
                menu.addItem(menuItem(
                    customization.actionTitle,
                    action: #selector(performContextAction(_:)),
                    representedAction: .customizeLayoutItem
                ))
                menu.addItem(.separator())
            }
            // The global root explodes back into plain parts; overriding is a
            // child-level affair and never offered on the root itself.
            if request["isGlobalRoot"] as? Bool == true {
                menu.addItem(menuItem(
                    "Explode Global",
                    action: #selector(performContextAction(_:)),
                    representedAction: .explodeGlobal
                ))
                menu.addItem(.separator())
            } else if contextMenuGlobalTargetID != nil {
                let isLinked = request["isGlobalLinked"] as? Bool == true
                menu.addItem(menuItem(
                    isLinked ? "Unpin from Global" : "Pin to Global",
                    action: #selector(performContextAction(_:)),
                    representedAction: isLinked ? .makeLocalOverride : .relinkGlobal
                ))
                menu.addItem(.separator())
            }
            let duplicate = menuItem("Duplicate", action: #selector(performContextAction(_:)), representedAction: .duplicate, key: "d")
            duplicate.isEnabled = (request["selectionCount"] as? Int ?? 1) > 0
            menu.addItem(duplicate)
            menu.addItem(menuItem("Copy", action: #selector(performContextAction(_:)), representedAction: .copy, key: "c"))
            let paste = menuItem("Paste", action: #selector(performContextAction(_:)), representedAction: .paste, key: "v")
            paste.isEnabled = canPastePart
            menu.addItem(paste)
            menu.addItem(.separator())
            let saveReusable = menuItem("Save as Template…", action: #selector(performContextAction(_:)), representedAction: .saveReusable)
            let saveGlobal = menuItem("Save as Global Part…", action: #selector(performContextAction(_:)), representedAction: .saveGlobal)
            saveReusable.isEnabled = request["canSaveAsPart"] as? Bool == true
            saveGlobal.isEnabled = request["canSaveAsPart"] as? Bool == true
            menu.addItem(saveReusable)
            menu.addItem(saveGlobal)
            menu.addItem(.separator())
            let moveUp = menuItem("Move Up", action: #selector(performContextAction(_:)), representedAction: .moveUp)
            let moveDown = menuItem("Move Down", action: #selector(performContextAction(_:)), representedAction: .moveDown)
            let outdent = menuItem("Move Out of Section", action: #selector(performContextAction(_:)), representedAction: .outdent)
            moveUp.isEnabled = request["canMoveUp"] as? Bool == true
            moveDown.isEnabled = request["canMoveDown"] as? Bool == true
            outdent.isEnabled = request["canOutdent"] as? Bool == true
            menu.addItem(moveUp)
            menu.addItem(moveDown)
            menu.addItem(outdent)
            menu.addItem(.separator())
            menu.addItem(menuItem("Delete", action: #selector(performContextAction(_:)), representedAction: .delete, key: String(Character(UnicodeScalar(NSDeleteCharacter)!)), modifiers: []))
        }

        private func contextMenuHeader(for request: [String: Any]) -> NSMenuItem {
            let selectionCount = request["selectionCount"] as? Int ?? 1
            let title = selectionCount > 1
                ? "\(selectionCount) Parts"
                : request["partType"] as? String ?? "Part"
            let author = request["partAuthor"] as? String ?? "Foundry"
            let version = request["partVersion"] as? String ?? ""
            let subtitle = version.isEmpty ? author : "\(author)  v\(version)"
            let typeID = request["partTypeID"] as? String
            let iconSpecification = typeID.map(PartType.init(rawValue:))?.iconSpecification
                ?? .init(glyph: .symbol(PartDefinition.genericSystemImage), tint: .gray)
            let icon = NSImageView(image: iconSpecification.tileImage(size: NSSize(width: 36, height: 36)))
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityLabel(title)
            icon.translatesAutoresizingMaskIntoConstraints = false

            let titleField = NSTextField(labelWithString: title)
            titleField.font = .systemFont(ofSize: 15, weight: .semibold)
            titleField.lineBreakMode = .byTruncatingTail
            let subtitleField = NSTextField(labelWithString: subtitle)
            subtitleField.font = .systemFont(ofSize: 12)
            subtitleField.textColor = .secondaryLabelColor
            subtitleField.lineBreakMode = .byTruncatingTail

            let labels = NSStackView(views: [titleField, subtitleField])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 2

            let content = NSStackView(views: [icon, labels])
            content.orientation = .horizontal
            content.alignment = .centerY
            content.spacing = 12
            content.edgeInsets = .init(top: 9, left: 10, bottom: 9, right: 10)
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 36),
                icon.heightAnchor.constraint(equalToConstant: 36),
                content.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
                content.heightAnchor.constraint(equalToConstant: 58)
            ])

            let item = NSMenuItem()
            item.view = content
            return item
        }

        private func menuItem(
            _ title: String,
            action: Selector,
            representedAction: CanvasContextMenuAction? = nil,
            key: String = "",
            modifiers: NSEvent.ModifierFlags = .command
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.representedObject = representedAction?.rawValue
            item.keyEquivalentModifierMask = modifiers
            return item
        }

        @objc private func editPart() {
            guard let webView, let contextMenuPartID else { return }
            Task {
                _ = try? await webView.callAsyncJavaScript(
                    "window.foundryEditPart(partID)",
                    arguments: ["partID": contextMenuPartID.uuidString],
                    in: nil,
                    contentWorld: .defaultClient
                )
            }
        }

        @objc private func performContextAction(_ sender: NSMenuItem) {
            guard let contextMenuPartID,
                  let rawValue = sender.representedObject as? String,
                  let action = CanvasContextMenuAction(rawValue: rawValue) else { return }
            let targetID: UUID
            switch action {
            case .makeLocalOverride, .relinkGlobal:
                guard let contextMenuGlobalTargetID else { return }
                targetID = contextMenuGlobalTargetID
            default:
                targetID = contextMenuPartID
            }
            handleContextMenuAction(action, targetID, contextMenuImageProperty, contextMenuImagePropertyPath)
        }

        func apply(_ operation: CanvasWebOperation, in webView: WKWebView) {
            switch operation {
            case .scene(let update, let revision):
                applyScene(update, revision: revision, in: webView)
            case .part(let subtree, let revision):
                patchPart(subtree, revision: revision, in: webView)
            case .reconcilePage(let html, let revision):
                updateHTML(html, revision: revision, in: webView)
            case .reloadDocument(let html, let revision):
                guard revisionGate.request(revision) else { return }
                captureScrollPositionThenLoad(html, revision: revision, in: webView)
            }
        }

        private func applyScene(_ update: CanvasSceneUpdate, revision: UInt64, in webView: WKWebView) {
            guard revisionGate.request(revision) else { return }
            guard !isLoadingHTML, !isCapturingScrollPosition, !isPatchingHTML, loadedHTML != nil else {
                Task { @MainActor [weak self] in self?.requestFullReconciliation() }
                return
            }
            isPatchingHTML = true
            Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                let applied = (try? await webView.callAsyncJavaScript(
                    "return window.foundryApplyScene?.(html, styles, removed, roots, revision, styleMoves, childMoves) === true",
                    arguments: ["html": update.html, "styles": update.styles,
                        "removed": update.removed, "roots": update.roots as Any? ?? NSNull(),
                        "styleMoves": update.styleMoves, "childMoves": update.childMoves,
                        "revision": revision],
                    in: nil, contentWorld: .defaultClient)) as? Bool == true
                self.isPatchingHTML = false
                guard applied else {
                    self.requestFullReconciliation()
                    self.processPendingUpdate(in: webView)
                    return
                }
                if self.revisionGate.apply(revision) {
                    self.didApplyRevision(revision)
                    self.applyCanvasState()
                }
                self.processPendingUpdate(in: webView)
            }
        }

        private func patchPart(
            _ subtree: RenderedPartSubtree,
            revision: UInt64,
            in webView: WKWebView
        ) {
            guard revisionGate.request(revision) else { return }
            guard !isLoadingHTML, !isCapturingScrollPosition, !isPatchingHTML, loadedHTML != nil else {
                // A newer delta cannot stand in for an unapplied older delta.
                // Ask for a complete current-page snapshot instead of dropping edits.
                Task { @MainActor [weak self] in self?.requestFullReconciliation() }
                return
            }
            isPatchingHTML = true
            Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                guard self.revisionGate.isCurrent(revision) else {
                    self.isPatchingHTML = false
                    self.processPendingUpdate(in: webView)
                    return
                }
                let didPatch = (try? await webView.callAsyncJavaScript(
                    "return window.foundryReplacePart?.(partID, html, styles, revision) === true",
                    arguments: [
                        "partID": subtree.partID.uuidString,
                        "html": subtree.html,
                        "styles": subtree.instanceStyles,
                        "revision": revision
                    ],
                    in: nil,
                    contentWorld: .defaultClient
                )) as? Bool == true
                self.isPatchingHTML = false
                guard didPatch else {
                    self.requestFullReconciliation()
                    return
                }
                guard self.revisionGate.apply(revision) else {
                    self.processPendingUpdate(in: webView)
                    return
                }
                self.applyCanvasState()
                self.didApplyRevision(revision)
                self.processPendingUpdate(in: webView)
            }
        }

        func updateHTML(_ html: String, revision: UInt64, in webView: WKWebView) {
            guard revisionGate.request(revision) else { return }
            lastHTML = html
            guard !isLoadingHTML, !isCapturingScrollPosition, !isPatchingHTML else {
                pendingHTML = (html, revision)
                return
            }
            if loadedHTML == nil {
                captureScrollPositionThenLoad(html, revision: revision, in: webView)
            } else {
                patchHTML(html, revision: revision, in: webView)
            }
        }

        private func patchHTML(_ html: String, revision: UInt64, in webView: WKWebView) {
            guard revisionGate.isCurrent(revision) else {
                processPendingUpdate(in: webView)
                return
            }
            isPatchingHTML = true
            Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                guard self.revisionGate.isCurrent(revision) else {
                    self.isPatchingHTML = false
                    self.processPendingUpdate(in: webView)
                    return
                }
                let didPatch = (try? await webView.callAsyncJavaScript(
                    "return window.foundryReplaceDocument?.(html, revision) === true",
                    arguments: ["html": html, "revision": revision],
                    in: nil,
                    contentWorld: .defaultClient
                )) as? Bool == true
                self.isPatchingHTML = false
                guard self.revisionGate.apply(revision) else {
                    self.processPendingUpdate(in: webView)
                    return
                }
                guard didPatch else {
                    let fallback = self.pendingHTML ?? (html, revision)
                    self.captureScrollPositionThenLoad(fallback.html, revision: fallback.revision, in: webView)
                    return
                }
                self.loadedHTML = html
                self.didApplyRevision(revision)
                self.applyCanvasState()
                self.processPendingUpdate(in: webView)
            }
        }

        private func captureScrollPositionThenLoad(_ html: String, revision: UInt64, in webView: WKWebView) {
            isCapturingScrollPosition = true
            webView.evaluateJavaScript("[window.scrollX, window.scrollY]") { [weak self, weak webView] result, _ in
                guard let self, let webView else { return }
                self.isCapturingScrollPosition = false
                if let coordinates = result as? [NSNumber], coordinates.count == 2 {
                    self.scrollPositionBeforeLoad = CGPoint(
                        x: coordinates[0].doubleValue,
                        y: coordinates[1].doubleValue
                    )
                }
                let latest = self.pendingHTML ?? (html, revision)
                self.load(latest.html, revision: latest.revision, in: webView)
            }
        }

        private func load(_ html: String, revision: UInt64, in webView: WKWebView) {
            pendingHTML = nil
            guard revisionGate.apply(revision) else {
                processPendingUpdate(in: webView)
                return
            }
            loadedHTML = html
            loadingRevision = revision
            isLoadingHTML = true
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            finishHTMLLoad(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: any Error
        ) {
            CanvasDiagnostics.navigationFailed(error, phase: "committed", url: webView.url)
            loadingRevision = nil
            finishHTMLLoad(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: any Error
        ) {
            CanvasDiagnostics.navigationFailed(error, phase: "provisional", url: webView.url)
            loadingRevision = nil
            finishHTMLLoad(in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            CanvasDiagnostics.logger.error("Canvas WebContent process terminated; loading=\(self.isLoadingHTML); URL=\(webView.url?.absoluteString ?? "unknown", privacy: .private(mask: .hash))")
        }

        private func finishHTMLLoad(in webView: WKWebView) {
            isLoadingHTML = false
            if let revision = loadingRevision, revisionGate.isCurrent(revision) {
                didApplyRevision(revision)
            }
            loadingRevision = nil
            if let pendingHTML, pendingHTML.html != loadedHTML {
                load(pendingHTML.html, revision: pendingHTML.revision, in: webView)
            } else {
                pendingHTML = nil
                applyCanvasState()
                processPendingUpdate(in: webView)
            }
        }

        private func processPendingUpdate(in webView: WKWebView) {
            guard !isLoadingHTML, !isCapturingScrollPosition, !isPatchingHTML else { return }
            if let pendingHTML {
                self.pendingHTML = nil
                patchHTML(pendingHTML.html, revision: pendingHTML.revision, in: webView)
            }
        }

        func applyCanvasState() {
            guard let webView else { return }
            let partIDs = selectedPartIDs
                .sorted { lhs, rhs in
                    if lhs == primarySelectedPartID { return true }
                    if rhs == primarySelectedPartID { return false }
                    return lhs.uuidString < rhs.uuidString
                }
                .map(\.uuidString)
            let primitiveSelection: [String: Any] = selectedPrimitive.map {
                [
                    "partID": $0.partID.uuidString,
                    "propertyKey": $0.propertyKey.rawValue,
                    "propertyPath": $0.propertyPath
                ]
            } ?? [:]
            let selectionChanged = lastAppliedSelection != selectedPartIDs
                || lastAppliedPrimarySelection != primarySelectedPartID
            let selectionOriginatedInCanvas = pendingCanvasSelection == selectedPartIDs
            let shouldScrollToSelection = selectionChanged && !selectionOriginatedInCanvas
            pendingCanvasSelection = nil
            lastAppliedSelection = selectedPartIDs
            lastAppliedPrimarySelection = primarySelectedPartID
            let scrollPosition = scrollPositionBeforeLoad.map {
                ["x": $0.x, "y": $0.y]
            } ?? [:]
            scrollPositionBeforeLoad = nil
            let options: [String: Any] = [
                "showsTitles": editorOptions.showsTitles,
                "showsOutlines": editorOptions.showsOutlines,
                "showsSelection": editorOptions.showsSelection,
                "scrollsToSelection": editorOptions.scrollsToSelection
            ]
            let accentColor = cssAccentColor
            Task {
                _ = try? await webView.callAsyncJavaScript(
                    "if (scrollPosition.x !== undefined) window.scrollTo(scrollPosition.x, scrollPosition.y); document.documentElement.style.setProperty('--foundry-editor-accent', accentColor); window.foundrySetWebInspectorEnabled?.(webInspectorEnabled); window.foundrySetEditorOptions?.(options); window.foundrySetSelection?.(partIDs, primitiveSelection, shouldScrollToSelection)",
                    arguments: [
                        "options": options,
                        "partIDs": partIDs,
                        "primitiveSelection": primitiveSelection,
                        "accentColor": accentColor,
                        "webInspectorEnabled": webView.isInspectable,
                        "shouldScrollToSelection": shouldScrollToSelection,
                        "scrollPosition": scrollPosition
                    ],
                    in: nil,
                    contentWorld: .defaultClient
                )
            }
        }

        private var cssAccentColor: String {
            guard let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) else {
                return "rgb(10 132 255)"
            }
            return "rgb(\(Int((color.redComponent * 255).rounded())) \(Int((color.greenComponent * 255).rounded())) \(Int((color.blueComponent * 255).rounded())))"
        }
    }
}
