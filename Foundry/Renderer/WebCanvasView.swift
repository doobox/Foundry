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

    private var assets: [UUID: ProjectAssetContent]
    private var packages: [String: LoadedPartPackage]
    private var gifPreviews: [UUID: Data] = [:]

    init(
        assets: [UUID: ProjectAssetContent],
        packages: [String: LoadedPartPackage] = [:]
    ) {
        self.assets = assets
        self.packages = packages
    }

    func update(assets: [UUID: ProjectAssetContent]) {
        gifPreviews.removeAll(keepingCapacity: true)
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
        if let preview = gifPreviews[id] {
            return preview
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
        gifPreviews[id] = preview
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
    case part(RenderedPartSubtree, revision: UInt64)
    case reconcilePage(html: String, revision: UInt64)
    case reloadDocument(html: String, revision: UInt64)

    var revision: UInt64 {
        switch self {
        case .part(_, let revision), .reconcilePage(_, let revision), .reloadDocument(_, let revision):
            revision
        }
    }
}

@MainActor
final class CanvasWebView: WKWebView {
    weak var canvasCoordinator: WebCanvasView.Coordinator?

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
    let assets: [UUID: ProjectAssetContent]
    let packages: [String: LoadedPartPackage]
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
        nonisolated static let interactionScript = """
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
            borderRadius: '999px',
            overflow: 'hidden',
            color: 'white',
            background: '#0A84FF',
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
          let hoveredPart = null;
          let hoveredPrimitive = null;
          let hoveredEditable = null;
          let selectedChromeTargets = [];
          let selectedChrome = [];
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
          let chromeFrame = null;

          const chromeStrokeWidth = 3;
          const editorChromeColor = '#0A84FF';
          const globalChromeColor = '#30D158';
          const partChromeColor = element => {
            if (!element || element.closest('[data-foundry-global-override="true"]')) {
              return editorChromeColor;
            }
            return element.closest('[data-foundry-global]') ? globalChromeColor : editorChromeColor;
          };

          const chromeRect = target => {
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

          const innerCornerRadius = (value, horizontalInset, verticalInset) => {
            const radii = String(value || '').split(/\\s+/).map(pixelWidth);
            const horizontal = Math.max(0, (radii[0] || 0) - horizontalInset);
            const vertical = Math.max(0, (radii[1] ?? radii[0] ?? 0) - verticalInset);
            return [horizontal + 'px', vertical + 'px'];
          };

          const outlineGeometry = (target, isPrimitive) => {
            const rect = chromeRect(target);
            if (isPrimitive || rect.width <= 0 || rect.height <= 0) {
              return { rect, radius: '0' };
            }
            const style = getComputedStyle(target);
            const top = pixelWidth(style.borderTopWidth);
            const right = pixelWidth(style.borderRightWidth);
            const bottom = pixelWidth(style.borderBottomWidth);
            const left = pixelWidth(style.borderLeftWidth);
            const corners = [
              innerCornerRadius(style.borderTopLeftRadius, left, top),
              innerCornerRadius(style.borderTopRightRadius, right, top),
              innerCornerRadius(style.borderBottomRightRadius, right, bottom),
              innerCornerRadius(style.borderBottomLeftRadius, left, bottom)
            ];
            return {
              rect: {
                left: rect.left + left,
                top: rect.top + top,
                right: rect.right - right,
                bottom: rect.bottom - bottom,
                width: Math.max(0, rect.width - left - right),
                height: Math.max(0, rect.height - top - bottom)
              },
              radius: corners.map(corner => corner[0]).join(' ')
                + ' / ' + corners.map(corner => corner[1]).join(' ')
            };
          };

          const positionOutline = (outline, target, color, isPrimitive, isSelected) => {
            if (!target?.isConnected) {
              outline.style.setProperty('display', 'none', 'important');
              return;
            }
            const geometry = outlineGeometry(target, isPrimitive);
            const rect = geometry.rect;
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight) {
              outline.style.setProperty('display', 'none', 'important');
              return;
            }
            outline.style.setProperty('left', rect.left + 'px', 'important');
            outline.style.setProperty('top', rect.top + 'px', 'important');
            outline.style.setProperty('width', rect.width + 'px', 'important');
            outline.style.setProperty('height', rect.height + 'px', 'important');
            outline.style.setProperty(
              'border',
              chromeStrokeWidth + 'px solid ' + (isSelected ? color : color + '8C'),
              'important'
            );
            outline.style.setProperty('border-radius', geometry.radius, 'important');
            outline.style.setProperty('display', 'block', 'important');
          };

          const updateSelectionChrome = () => {
            while (selectedChrome.length < selectedChromeTargets.length) {
              const outline = document.createElement('div');
              outline.setAttribute('data-foundry-editor-chrome', 'selection');
              applyOutlineBaseStyles(outline);
              chromeLayer.appendChild(outline);
              selectedChrome.push(outline);
            }
            selectedChrome.forEach((outline, index) => {
              const entry = selectedChromeTargets[index];
              if (!entry || !editorOptions.showsSelection) {
                outline.style.setProperty('display', 'none', 'important');
              } else {
                positionOutline(outline, entry.element, entry.color, entry.isPrimitive, true);
              }
            });
          };

          const hideSelectionChromeForImageDrop = imageTarget => {
            const owner = imageTarget?.closest(selector);
            selectedChrome.forEach((outline, index) => {
              const entry = selectedChromeTargets[index];
              const sharesImageRegion = entry && (
                entry.element === imageTarget
                || entry.element === owner
                || (entry.isPrimitive && entry.element.closest(selector) === owner)
              );
              if (sharesImageRegion) {
                outline.style.setProperty('display', 'none', 'important');
              }
            });
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
              partChromeColor(target),
              isPrimitive,
              false
            );
          };

          const updateEditableChrome = () => {
            const target = hoveredEditable;
            if (!target?.isConnected || target.isContentEditable || isDragging || !editorOptions.showsOutlines) {
              editableChrome.style.setProperty('display', 'none', 'important');
              return;
            }
            const rect = chromeRect(target);
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight) {
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
            updateSelectionChrome();
            updateHoverChrome();
            updateEditableChrome();
            if (!hoveredPart || !hoveredPart.isConnected || !editorOptions.showsTitles) {
              chromeTitle.style.setProperty('display', 'none', 'important');
              return;
            }
            const geometry = outlineGeometry(hoveredPart, false);
            const rect = geometry.rect;
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight) {
              chromeTitle.style.setProperty('display', 'none', 'important');
              return;
            }
            chromeTitle.textContent = hoveredPart.dataset.foundryName || '';
            chromeTitle.style.setProperty('background', partChromeColor(hoveredPart), 'important');
            chromeTitle.style.setProperty('left', (rect.left + rect.width / 2) + 'px', 'important');
            chromeTitle.style.setProperty('top', (rect.top + chromeStrokeWidth / 2) + 'px', 'important');
            chromeTitle.style.setProperty('transform', 'translate(-50%, -50%)', 'important');
            chromeTitle.style.setProperty(
              'max-width',
              Math.max(0, rect.width) + 'px',
              'important'
            );
            chromeTitle.style.setProperty('display', 'block', 'important');
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
          document.addEventListener('pointerleave', () => {
            hoveredPart = null;
            hoveredPrimitive = null;
            hoveredEditable = null;
            scheduleChromeTitleUpdate();
          }, true);
          document.addEventListener('scroll', scheduleChromeTitleUpdate, true);
          window.addEventListener('resize', scheduleChromeTitleUpdate);

          const clearDrop = () => {
            document.querySelectorAll('.foundry-drop-before,.foundry-drop-after,.foundry-drop-inside')
              .forEach(e => e.classList.remove('foundry-drop-before','foundry-drop-after','foundry-drop-inside'));
            placement = null;
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

          const intendedPlacement = event => {
            const emptyParent = event.target.closest('[data-foundry-empty-parent]');
            if (emptyParent) {
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
              const rect = adjacentZone.getBoundingClientRect();
              return {
                kind: event.clientY < rect.top + rect.height / 2 ? 'before' : 'after',
                targetID: adjacentZone.dataset.foundryAdjacentTarget,
                element: adjacentZone
              };
            }
            const element = event.target.closest(selector);
            if (!element) return { kind: 'end' };
            const rect = element.getBoundingClientRect();
            const distanceFromTop = event.clientY - rect.top;
            const distanceFromBottom = rect.bottom - event.clientY;
            if (distanceFromTop <= 18) {
              return { kind: 'before', targetID: element.dataset.foundryId, element };
            }
            if (distanceFromBottom <= 18) {
              return { kind: 'after', targetID: element.dataset.foundryId, element };
            }
            const edgeTargetHeight = Math.min(Math.max(rect.height * 0.25, 18), rect.height / 2);
            if (distanceFromTop <= edgeTargetHeight) {
              return { kind: 'before', targetID: element.dataset.foundryId, element };
            }
            if (distanceFromTop >= rect.height - edgeTargetHeight) {
              return { kind: 'after', targetID: element.dataset.foundryId, element };
            }
            if (element.dataset.foundryAcceptsChildren === 'true') {
              return { kind: 'inside', targetID: element.dataset.foundryId, element };
            }
            return {
              kind: distanceFromTop < rect.height / 2 ? 'before' : 'after',
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
              if (selectedPrimitiveSelection?.partID === partID) {
                const expectedPath = Array.isArray(selectedPrimitiveSelection.propertyPath)
                  ? selectedPrimitiveSelection.propertyPath.join(',')
                  : '';
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
                if (primitive) {
                  selectionElement = primitive;
                  isPrimitive = true;
                }
              }
              if (!firstElement) firstElement = selectionElement;
              selectedChromeTargets.push({
                element: selectionElement,
                color: partChromeColor(selectionElement),
                isPrimitive
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
              if (!selectedPrimitiveSelection) postSelectionAction('deleteParts');
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
          const installPartDragHandlers = () => {
            document.querySelectorAll(selector).forEach(element => {
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
                  getComputedStyle(element).getPropertyValue('--foundry-editor-chrome').trim() || '#0A84FF'
                );
                document.body.appendChild(dragImage);
                event.dataTransfer.setDragImage(dragImage, 28, 20);
                requestAnimationFrame(() => dragImage.remove());
              }
              event.dataTransfer.setData('text/plain', value);
              event.dataTransfer.effectAllowed = 'move';
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
            Array.from(target.attributes).forEach(attribute => target.removeAttribute(attribute.name));
            Array.from(source.attributes).forEach(attribute => target.setAttribute(attribute.name, attribute.value));
          };

          let latestFoundryRevision = 0;
          window.foundryReplacePart = (partID, html, css, revision) => {
            if (!Number.isSafeInteger(revision) || revision < latestFoundryRevision) return false;
            const current = document.querySelector('[data-foundry-id="' + CSS.escape(partID) + '"]');
            if (!current) return false;
            const template = document.createElement('template');
            template.innerHTML = html.trim();
            const replacement = template.content.firstElementChild;
            if (!replacement || template.content.childElementCount !== 1 || replacement.dataset.foundryId !== partID) return false;
            current.replaceWith(replacement);
            const styleSelector = 'style[data-foundry-instance-style="' + CSS.escape(partID) + '"]';
            let style = document.head.querySelector(styleSelector);
            if (css) {
              if (!style) {
                style = document.createElement('style');
                style.dataset.foundryInstanceStyle = partID;
                document.head.appendChild(style);
              }
              style.textContent = css;
            } else {
              style?.remove();
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

          window.foundryReplaceDocument = (html, revision = latestFoundryRevision) => {
            if (!Number.isSafeInteger(revision) || revision < latestFoundryRevision) return false;
            const replacement = new DOMParser().parseFromString(html, 'text/html');
            replacement.querySelectorAll(selector).forEach(element => { element.draggable = true; });

            const currentHeadNodes = Array.from(document.head.childNodes);
            const replacementHeadNodes = Array.from(replacement.head.childNodes);
            replacementHeadNodes.forEach((node, index) => {
              const current = currentHeadNodes[index];
              if (!current) {
                document.head.appendChild(document.importNode(node, true));
              } else if (current.nodeName === 'STYLE' && node.nodeName === 'STYLE') {
                if (current.textContent !== node.textContent) current.textContent = node.textContent;
              } else if (current.outerHTML !== node.outerHTML && current.textContent !== node.textContent) {
                current.replaceWith(document.importNode(node, true));
              }
            });
            currentHeadNodes.slice(replacementHeadNodes.length).forEach(node => node.remove());

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

              if (changedIDs.size === 0 && document.body.innerHTML !== replacement.body.innerHTML) {
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

          document.addEventListener('dragover', event => {
            isDragging = true;
            clearDrop();
            updateSelectionChrome();
            hoverChrome.style.setProperty('display', 'none', 'important');
            if (event.dataTransfer.types.includes('Files')) {
              event.preventDefault();
              const imageZone = event.target.closest('[data-foundry-image-drop-zone]');
              const image = imageZone?.closest(selector);
              if (image) {
                imageZone.classList.add('foundry-drop-inside');
                hideSelectionChromeForImageDrop(imageZone);
              } else {
                placement = intendedPlacement(event);
                if (placement.element) placement.element.classList.add('foundry-drop-' + placement.kind);
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
            const imageZone = carriesImageAsset
              ? event.target.closest('[data-foundry-image-drop-zone]')
              : null;
            const image = imageZone?.closest(selector);
            if (image) {
              imageZone.classList.add('foundry-drop-inside');
              hideSelectionChromeForImageDrop(imageZone);
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
            if (placement.element) placement.element.classList.add('foundry-drop-' + placement.kind);
            const allowedEffect = event.dataTransfer.effectAllowed;
            event.dataTransfer.dropEffect = allowedEffect === 'move' ? 'move' : 'copy';
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
              const imageZone = event.target.closest('[data-foundry-image-drop-zone]');
              const image = imageZone?.closest(selector);
              const target = placement || intendedPlacement(event);
              clearDrop();
              const isImage = file.type.startsWith('image/') || /\\.(?:avif|gif|heic|heif|jpe?g|png|svg|webp)$/i.test(file.name);
              if (!isImage || file.size > 25000000) return;
              const internalAssetMatch = file.name.match(/^foundry-image-asset-([0-9a-f-]{36})--/i);
              if (internalAssetMatch) {
                const message = {
                  version: 1,
                  event: image ? 'importImageAsset' : 'insertImagePart',
                  assetID: internalAssetMatch[1]
                };
                if (image) {
                  message.partID = image.dataset.foundryId;
                  message.propertyKey = imageZone.dataset.foundryImageProperty;
                  message.propertyPath = propertyPath(imageZone);
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
                  event: image ? 'importImageAsset' : 'insertImagePart',
                  assetFilename: file.name,
                  assetMediaType: file.type || 'application/octet-stream',
                  assetData: encoded
                };
                if (image) {
                  message.partID = image.dataset.foundryId;
                  message.propertyKey = imageZone.dataset.foundryImageProperty;
                  message.propertyPath = propertyPath(imageZone);
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
            } else if (value.startsWith('foundry-node:')) {
              message.event = 'movePart';
              message.partID = value.substring('foundry-node:'.length);
            } else if (value.startsWith('foundry-image-asset:')) {
              message.event = image ? 'importImageAsset' : 'insertImagePart';
              message.assetID = value.substring('foundry-image-asset:'.length);
              if (image) {
                delete message.placement;
                message.partID = image.dataset.foundryId;
                message.propertyKey = imageZone.dataset.foundryImageProperty;
                message.propertyPath = propertyPath(imageZone);
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
            const clickedImageZone = event.target.closest('[data-foundry-image-drop-zone]');
            const imageZone = clickedImageZone?.closest(selector) === part ? clickedImageZone : null;
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'contextMenu',
              partID: part.dataset.foundryId,
              partTypeID: part.dataset.foundryPartType,
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
              hasImage: selectionCount === 1 && imageZone?.tagName === 'IMG',
              imageProperty: selectionCount === 1 ? imageZone?.dataset.foundryImageProperty : undefined,
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
            if (!element) return;
            event.preventDefault();
            event.stopPropagation();
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
            assets: [UUID: ProjectAssetContent],
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
            if contextMenuGlobalTargetID != nil {
                let isLinked = request["isGlobalLinked"] as? Bool == true
                menu.addItem(menuItem(
                    isLinked ? "Make Local Override" : "Relink to Global",
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
            let outdent = menuItem("Move Out of Container", action: #selector(performContextAction(_:)), representedAction: .outdent)
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
            let iconURL = typeID
                .map(PartType.init(rawValue:))?
                .definition.package
                .map(\.iconURL)
            let icon = NSImageView(image: NSImage(size: NSSize(width: 36, height: 36)))
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 36 * 0.16
            icon.layer?.masksToBounds = true
            icon.setAccessibilityLabel(title)
            icon.translatesAutoresizingMaskIntoConstraints = false
            if let iconURL {
                if let cached = PartIconLoader.cachedIcon(at: iconURL) {
                    icon.image = cached.image
                } else {
                    Task { [weak icon] in
                        guard let image = await PartIconLoader.shared.icon(at: iconURL)?.image else { return }
                        icon?.image = image
                    }
                }
            }

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
            case .part(let subtree, let revision):
                patchPart(subtree, revision: revision, in: webView)
            case .reconcilePage(let html, let revision):
                updateHTML(html, revision: revision, in: webView)
            case .reloadDocument(let html, let revision):
                guard revisionGate.request(revision) else { return }
                captureScrollPositionThenLoad(html, revision: revision, in: webView)
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
                    "return window.foundryReplacePart?.(partID, html, css, revision) === true",
                    arguments: [
                        "partID": subtree.partID.uuidString,
                        "html": subtree.html,
                        "css": subtree.instanceCSS,
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
