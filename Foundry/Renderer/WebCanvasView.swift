import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class CanvasAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "foundry-asset"
    nonisolated static let packageScheme = "foundry-package-asset"

    private var assets: [UUID: ProjectAssetContent]
    private var packages: [String: LoadedComponentPackage]
    private var gifPreviews: [UUID: Data] = [:]

    init(
        assets: [UUID: ProjectAssetContent],
        packages: [String: LoadedComponentPackage] = [:]
    ) {
        self.assets = assets
        self.packages = packages
    }

    func update(assets: [UUID: ProjectAssetContent]) {
        gifPreviews.removeAll(keepingCapacity: true)
        self.assets = assets
    }

    func update(packages: [String: LoadedComponentPackage]) {
        self.packages = packages
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let resource = resource(for: url) else {
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
}

nonisolated enum CanvasWebOperation: Equatable, Sendable {
    case component(RenderedComponentSubtree, revision: UInt64)
    case reconcilePage(html: String, revision: UInt64)
    case reloadDocument(html: String, revision: UInt64)

    var revision: UInt64 {
        switch self {
        case .component(_, let revision), .reconcilePage(_, let revision), .reloadDocument(_, let revision):
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
    let packages: [String: LoadedComponentPackage]
    let assetRevision: UInt64
    let selectedComponentIDs: Set<UUID>
    let primarySelectedComponentID: UUID?
    let selectedPrimitive: CanvasPrimitiveSelection?
    let editorOptions: CanvasEditorOptions
    let enablesWebInspector: Bool
    let canPasteComponent: Bool
    let canClearImage: (UUID, ComponentProperty.Key, [Int]) -> Bool
    let handleMessage: (CanvasMessage) -> Void
    let handleContextMenuAction: (CanvasContextMenuAction, UUID, ComponentProperty.Key?, [Int]) -> Void
    let requestFullReconciliation: () -> Void

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
        context.coordinator.canPasteComponent = canPasteComponent
        context.coordinator.selectedComponentIDs = selectedComponentIDs
        context.coordinator.primarySelectedComponentID = primarySelectedComponentID
        context.coordinator.selectedPrimitive = selectedPrimitive
        context.coordinator.editorOptions = editorOptions
        context.coordinator.requestFullReconciliation = requestFullReconciliation
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
          let placement = null;
          let selectedComponentIDs = [];
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
          let globalMenuTarget = null;
          let globalMenuRelinks = false;

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
            .foundry-global-menu {
              display: none; position: fixed; z-index: 2; min-width: 190px; padding: 5px;
              border: 1px solid rgba(0,0,0,.12); border-radius: 9px; background: rgba(255,255,255,.98);
              box-shadow: 0 10px 30px rgba(0,0,0,.2); color: #171719; pointer-events: auto;
            }
            .foundry-global-menu.is-visible { display: block; }
            .foundry-global-menu button {
              display: block; width: 100%; padding: 7px 10px; border: 0; border-radius: 6px;
              background: transparent; color: inherit; font: 13px system-ui; text-align: left; cursor: default;
            }
            .foundry-global-menu button:hover { background: rgba(0,0,0,.08); }
          `;
          chromeRoot.appendChild(chromeStyles);

          const globalMenu = document.createElement('div');
          globalMenu.className = 'foundry-global-menu';
          globalMenu.setAttribute('role', 'menu');
          const globalMenuAction = document.createElement('button');
          globalMenuAction.type = 'button';
          globalMenuAction.setAttribute('role', 'menuitem');
          globalMenu.appendChild(globalMenuAction);

          const chromeLayer = document.createElement('div');
          chromeLayer.setAttribute('data-foundry-editor-chrome', 'layer');
          const chromeLayerStyles = {
            all: 'initial', position: 'fixed', inset: '0', width: '0', height: '0',
            margin: '0', padding: '0', border: '0', overflow: 'visible', pointerEvents: 'none'
          };
          Object.entries(chromeLayerStyles).forEach(([property, value]) => {
            chromeLayer.style.setProperty(property.replace(/[A-Z]/g, match => '-' + match.toLowerCase()), value, 'important');
          });
          chromeRoot.append(chromeLayer, globalMenu);
          document.documentElement.appendChild(chromeHost);
          if (typeof chromeHost.showPopover === 'function') chromeHost.showPopover();

          const chromeTitle = document.createElement('div');
          chromeTitle.setAttribute('data-foundry-editor-chrome', 'title');
          const chromeTitleStyles = {
            all: 'initial',
            position: 'fixed',
            display: 'none',
            boxSizing: 'border-box',
            padding: '3px 10px',
            borderRadius: '0 0 5px 0',
            overflow: 'hidden',
            color: 'white',
            background: '#0A84FF',
            font: '11px/16px system-ui, sans-serif',
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
          let hoveredComponent = null;
          let hoveredPrimitive = null;
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
          let chromeFrame = null;

          const editorChromeColor = '#0A84FF';
          const componentChromeColor = _ => editorChromeColor;

          const chromeRect = target => {
            const elementRect = target.getBoundingClientRect();
            if (elementRect.width > 0 && elementRect.height > 0) return elementRect;

            // Components whose root uses `display: contents` have no box of their own.
            // Frame their rendered contents so nested overlay text still gets canvas chrome.
            const range = document.createRange();
            range.selectNodeContents(target);
            const contentRect = range.getBoundingClientRect();
            range.detach();
            return contentRect;
          };

          const positionOutline = (outline, target, color, isPrimitive, isSelected) => {
            if (!target?.isConnected) {
              outline.style.setProperty('display', 'none', 'important');
              return;
            }
            const rect = chromeRect(target);
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
              isSelected ? '3px solid ' + color : '3px solid ' + color + '8C',
              'important'
            );
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
            const target = hoveredPrimitive || hoveredComponent;
            const isSelected = selectedChromeTargets.some(entry => entry.element === target);
            if (!target || isSelected || isDragging || !editorOptions.showsOutlines) {
              hoverChrome.style.setProperty('display', 'none', 'important');
              return;
            }
            const isPrimitive = Boolean(hoveredPrimitive);
            positionOutline(
              hoverChrome,
              target,
              editorChromeColor,
              isPrimitive,
              false
            );
          };

          const updateChromeTitle = () => {
            chromeFrame = null;
            updateSelectionChrome();
            updateHoverChrome();
            if (!hoveredComponent || !hoveredComponent.isConnected || !editorOptions.showsTitles) {
              chromeTitle.style.setProperty('display', 'none', 'important');
              return;
            }
            const rect = chromeRect(hoveredComponent);
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom < 0 || rect.top > window.innerHeight) {
              chromeTitle.style.setProperty('display', 'none', 'important');
              return;
            }
            chromeTitle.textContent = hoveredComponent.dataset.foundryName || '';
            chromeTitle.style.setProperty('background', componentChromeColor(hoveredComponent), 'important');
            chromeTitle.style.setProperty('left', Math.max(0, rect.left) + 'px', 'important');
            chromeTitle.style.setProperty('top', Math.max(0, rect.top) + 'px', 'important');
            chromeTitle.style.setProperty(
              'max-width',
              Math.max(0, Math.min(rect.width, window.innerWidth - Math.max(0, rect.left))) + 'px',
              'important'
            );
            chromeTitle.style.setProperty('display', 'block', 'important');
          };

          const scheduleChromeTitleUpdate = () => {
            if (chromeFrame === null) chromeFrame = requestAnimationFrame(updateChromeTitle);
          };

          document.addEventListener('pointermove', event => {
            const component = event.target.closest?.(selector) ?? null;
            const primitive = event.target.closest?.('[data-foundry-primitive-property]') ?? null;
            if (component === hoveredComponent && primitive === hoveredPrimitive) return;
            hoveredComponent = component;
            hoveredPrimitive = primitive;
            scheduleChromeTitleUpdate();
          }, true);
          document.addEventListener('pointerleave', () => {
            hoveredComponent = null;
            hoveredPrimitive = null;
            scheduleChromeTitleUpdate();
          }, true);
          document.addEventListener('scroll', scheduleChromeTitleUpdate, true);
          window.addEventListener('resize', scheduleChromeTitleUpdate);

          const dismissGlobalMenu = () => {
            globalMenu.classList.remove('is-visible');
            globalMenuTarget = null;
          };

          globalMenuAction.addEventListener('click', event => {
            event.preventDefault();
            event.stopPropagation();
            if (!globalMenuTarget) return;
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'setGlobalLink',
              componentID: globalMenuTarget.dataset.foundryId,
              isGlobalLinked: globalMenuRelinks
            });
            dismissGlobalMenu();
          });

          document.addEventListener('contextmenu', event => {
            if (webInspectorEnabled || event.altKey) return;
            const element = event.target.closest(selector);
            if (!element?.dataset.foundryGlobal) return;
            event.preventDefault();
            event.stopPropagation();
            const overrideOwner = element.closest('[data-foundry-global-override="true"]');
            globalMenuTarget = overrideOwner || element;
            globalMenuRelinks = Boolean(overrideOwner);
            globalMenuAction.textContent = globalMenuRelinks ? 'Relink to Global' : 'Make Local Override';
            globalMenu.classList.add('is-visible');
            const width = globalMenu.offsetWidth;
            const height = globalMenu.offsetHeight;
            globalMenu.style.left = Math.max(8, Math.min(event.clientX, window.innerWidth - width - 8)) + 'px';
            globalMenu.style.top = Math.max(8, Math.min(event.clientY, window.innerHeight - height - 8)) + 'px';
          });
          document.addEventListener('click', event => {
            if (!globalMenu.contains(event.target)) dismissGlobalMenu();
          }, true);
          document.addEventListener('keydown', event => {
            if (event.key === 'Escape') dismissGlobalMenu();
          });
          document.addEventListener('scroll', dismissGlobalMenu, true);

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
            selectedComponentIDs = Array.isArray(ids) ? ids : [];
            selectedPrimitiveSelection = primitiveSelection?.componentID ? primitiveSelection : null;
            selectedChromeTargets.length = 0;
            if (!Array.isArray(selectedComponentIDs)) return;
            let firstElement = null;
            selectedComponentIDs.forEach(componentID => {
              const element = document.querySelector('[data-foundry-id="' + CSS.escape(componentID) + '"]');
              if (!element) return;
              let selectionElement = element;
              let isPrimitive = false;
              if (selectedPrimitiveSelection?.componentID === componentID) {
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
                color: editorChromeColor,
                isPrimitive
              });
            });
            scheduleChromeTitleUpdate();
            if (firstElement && editorOptions.scrollsToSelection && shouldScroll) {
              firstElement.scrollIntoView({ block: 'nearest', inline: 'nearest' });
            }
          };

          document.addEventListener('keydown', event => {
            if (event.key !== 'Backspace' && event.key !== 'Delete') return;
            if (selectedComponentIDs.length === 0) return;
            if (selectedPrimitiveSelection) return;
            const target = event.target;
            if (target?.isContentEditable || target?.closest?.('input, textarea, select, [contenteditable="true"]')) return;
            event.preventDefault();
            event.stopPropagation();
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'deleteComponents',
              componentIDs: selectedComponentIDs
            });
          }, true);

          const dragHandlerElements = new WeakSet();
          const installComponentDragHandlers = () => {
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
              const isGroupDrag = selectedComponentIDs.length > 1 && selectedComponentIDs.includes(draggedID);
              const value = isGroupDrag
                ? 'foundry-nodes:' + selectedComponentIDs.join(',')
                : 'foundry-node:' + draggedID;
              const draggedElements = isGroupDrag
                ? selectedComponentIDs
                    .map(id => document.querySelector('[data-foundry-id="' + CSS.escape(id) + '"]'))
                    .filter(Boolean)
                : [element];
              markDragSources(draggedElements);
              if (isGroupDrag) {
                const dragImage = document.createElement('div');
                dragImage.className = 'foundry-multi-drag-image';
                dragImage.textContent = selectedComponentIDs.length + ' components';
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
          installComponentDragHandlers();

          const syncAttributes = (target, source) => {
            Array.from(target.attributes).forEach(attribute => target.removeAttribute(attribute.name));
            Array.from(source.attributes).forEach(attribute => target.setAttribute(attribute.name, attribute.value));
          };

          let latestFoundryRevision = 0;
          window.foundryReplaceComponent = (componentID, html, css, revision) => {
            if (!Number.isSafeInteger(revision) || revision < latestFoundryRevision) return false;
            const current = document.querySelector('[data-foundry-id="' + CSS.escape(componentID) + '"]');
            if (!current) return false;
            const template = document.createElement('template');
            template.innerHTML = html.trim();
            const replacement = template.content.firstElementChild;
            if (!replacement || template.content.childElementCount !== 1 || replacement.dataset.foundryId !== componentID) return false;
            current.replaceWith(replacement);
            const styleSelector = 'style[data-foundry-instance-style="' + CSS.escape(componentID) + '"]';
            let style = document.head.querySelector(styleSelector);
            if (css) {
              if (!style) {
                style = document.createElement('style');
                style.dataset.foundryInstanceStyle = componentID;
                document.head.appendChild(style);
              }
              style.textContent = css;
            } else {
              style?.remove();
            }
            latestFoundryRevision = revision;
            installComponentDragHandlers();
            hoveredComponent = null;
            hoveredPrimitive = null;
            window.foundrySetEditorOptions(editorOptions);
            window.foundrySetSelection(selectedComponentIDs, selectedPrimitiveSelection, false);
            scheduleChromeTitleUpdate();
            return true;
          };

          window.foundryReplaceDocument = html => {
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
            const changedIDs = new Set();
            replacement.querySelectorAll(selector).forEach(nextElement => {
              const componentID = nextElement.dataset.foundryId;
              const currentElement = document.querySelector('[data-foundry-id="' + CSS.escape(componentID) + '"]');
              if (!currentElement || currentElement.outerHTML === nextElement.outerHTML) return;
              const changedAncestor = nextElement.parentElement?.closest(selector);
              if (changedAncestor && changedIDs.has(changedAncestor.dataset.foundryId)) return;
              currentElement.replaceWith(document.importNode(nextElement, true));
              changedIDs.add(componentID);
            });

            if (changedIDs.size === 0 && document.body.innerHTML !== replacement.body.innerHTML) {
              const bodyNodes = Array.from(replacement.body.childNodes).map(node => document.importNode(node, true));
              document.body.replaceChildren(...bodyNodes);
            }
            installComponentDragHandlers();
            hoveredComponent = null;
            hoveredPrimitive = null;
            dismissGlobalMenu();
            window.foundrySetEditorOptions(editorOptions);
            window.foundrySetSelection(selectedComponentIDs, selectedPrimitiveSelection, false);
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
            const carriesComponentText = Array.from(event.dataTransfer.types).some(type =>
              type === 'text/plain' || type === 'public.utf8-plain-text'
            );
            if (!carriesComponentText) {
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
            placement = intendedPlacement(event);
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
                  event: image ? 'importImageAsset' : 'insertImageComponent',
                  assetID: internalAssetMatch[1]
                };
                if (image) {
                  message.componentID = image.dataset.foundryId;
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
                  event: image ? 'importImageAsset' : 'insertImageComponent',
                  assetFilename: file.name,
                  assetMediaType: file.type || 'application/octet-stream',
                  assetData: encoded
                };
                if (image) {
                  message.componentID = image.dataset.foundryId;
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
            if (value.startsWith('foundry-component-type:')) {
              message.event = 'insertComponent';
              message.componentType = value.substring('foundry-component-type:'.length);
            } else if (value.startsWith('foundry-reusable-component:')) {
              message.event = 'insertReusableComponent';
              message.reusableDefinitionID = value.substring('foundry-reusable-component:'.length);
            } else if (value.startsWith('foundry-global-component:')) {
              message.event = 'insertGlobalComponent';
              message.globalDefinitionID = value.substring('foundry-global-component:'.length);
            } else if (value.startsWith('foundry-nodes:')) {
              message.event = 'moveComponent';
              message.componentIDs = value.substring('foundry-nodes:'.length).split(',');
            } else if (value.startsWith('foundry-node:')) {
              message.event = 'moveComponent';
              message.componentID = value.substring('foundry-node:'.length);
            } else if (value.startsWith('foundry-image-asset:')) {
              message.event = image ? 'importImageAsset' : 'insertImageComponent';
              message.assetID = value.substring('foundry-image-asset:'.length);
              if (image) {
                delete message.placement;
                message.componentID = image.dataset.foundryId;
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
            const componentElement = editableElement?.closest(selector);
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
                event: 'editHTMLComponent',
                componentID: (componentElement ?? element).dataset.foundryId,
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
              event: 'editComponent',
              componentID: (componentElement ?? element).dataset.foundryId,
              propertyKey: editableProperty,
              propertyPath: propertyPath(element),
              propertyValue: source
            });
          }, true);

          window.foundryEditComponent = componentID => {
            const component = document.querySelector('[data-foundry-id="' + CSS.escape(componentID) + '"]');
            const editable = component?.matches('[data-foundry-inline-property]')
              ? component
              : component?.querySelector('[data-foundry-inline-property]');
            if (!editable) return;
            editable.dispatchEvent(new MouseEvent('dblclick', { bubbles: true, cancelable: true }));
          };

          document.addEventListener('contextmenu', event => {
            if (event.altKey) return;
            const component = event.target.closest(selector);
            if (!component) return;
            const editable = component.matches('[data-foundry-inline-property]')
              || component.querySelector('[data-foundry-inline-property]') !== null;
            const clickedImageZone = event.target.closest('[data-foundry-image-drop-zone]');
            const imageZone = clickedImageZone?.closest(selector) === component ? clickedImageZone : null;
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'contextMenu',
              componentID: component.dataset.foundryId,
              componentTypeID: component.dataset.foundryComponentType,
              componentType: component.dataset.foundryType,
              componentAuthor: component.dataset.foundryAuthor,
              componentVersion: component.dataset.foundryVersion,
              canEdit: editable,
              hasImage: imageZone?.tagName === 'IMG',
              imageProperty: imageZone?.dataset.foundryImageProperty,
              imagePropertyPath: propertyPath(imageZone),
              preservesSelection: selectedComponentIDs.includes(component.dataset.foundryId)
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
                componentID: element.dataset.foundryId,
                propertyKey: primitive.dataset.foundryPrimitiveProperty,
                propertyPath: propertyPath(primitive)
              });
              return;
            }
            window.webkit.messageHandlers.foundryCanvas.postMessage({
              version: 1,
              event: 'selectComponent',
              componentID: element.dataset.foundryId,
              extendsSelection: event.metaKey || event.shiftKey
            });
          }, true);
        })();
        """

        weak var webView: WKWebView?
        var lastHTML: String?
        var assetRevision: UInt64?
        var selectedComponentIDs: Set<UUID> = []
        var primarySelectedComponentID: UUID?
        var selectedPrimitive: CanvasPrimitiveSelection?
        var editorOptions = CanvasEditorOptions()
        var canPasteComponent = false
        var canClearImage: (UUID, ComponentProperty.Key, [Int]) -> Bool
        var handleMessage: (CanvasMessage) -> Void
        var handleContextMenuAction: (CanvasContextMenuAction, UUID, ComponentProperty.Key?, [Int]) -> Void
        var requestFullReconciliation: () -> Void
        private var contextMenuComponentID: UUID?
        private var contextMenuImageProperty: ComponentProperty.Key?
        private var pendingHTML: (html: String, revision: UInt64)?
        private var pendingComponent: (subtree: RenderedComponentSubtree, revision: UInt64)?
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
            packages: [String: LoadedComponentPackage],
            canClearImage: @escaping (UUID, ComponentProperty.Key, [Int]) -> Bool,
            handleMessage: @escaping (CanvasMessage) -> Void,
            handleContextMenuAction: @escaping (CanvasContextMenuAction, UUID, ComponentProperty.Key?, [Int]) -> Void,
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
            if let componentID = canvasMessage.componentID,
               canvasMessage.event == .selectComponent || canvasMessage.event == .selectPrimitive {
                if canvasMessage.event == .selectComponent, canvasMessage.extendsSelection == true {
                    var selection = selectedComponentIDs
                    if selection.contains(componentID) {
                        selection.remove(componentID)
                    } else {
                        selection.insert(componentID)
                    }
                    pendingCanvasSelection = selection
                } else {
                    pendingCanvasSelection = [componentID]
                }
            }
            handleMessage(canvasMessage)
        }

        private func presentContextMenu(_ request: [String: Any]) {
            guard let webView,
                  let value = request["componentID"] as? String,
                  let componentID = UUID(uuidString: value) else { return }
            contextMenuRequest = request
            contextMenuComponentID = componentID
            contextMenuImageProperty = (request["imageProperty"] as? String).map(ComponentProperty.Key.init(rawValue:))
            contextMenuImagePropertyPath = (request["imagePropertyPath"] as? [NSNumber])?.map(\.intValue) ?? []
            if request["preservesSelection"] as? Bool != true {
                pendingCanvasSelection = [componentID]
                handleMessage(.init(event: .selectComponent, componentID: componentID, extendsSelection: false))
            }

            if webView.isInspectable {
                return
            }

            let menu = NSMenu()
            menu.autoenablesItems = false
            addFoundryContextMenuItems(to: menu, request: request, componentID: componentID)
            let windowPoint = webView.window?.mouseLocationOutsideOfEventStream ?? .zero
            let webViewPoint = webView.convert(windowPoint, from: nil)
            menu.popUp(positioning: nil, at: webViewPoint, in: webView)
        }

        func prepareForNativeContextMenu() {
            contextMenuRequest = nil
        }

        func augmentNativeContextMenu(_ menu: NSMenu) {
            guard let request = contextMenuRequest,
                  let value = request["componentID"] as? String,
                  let componentID = UUID(uuidString: value) else { return }
            let nativeItems = menu.items
            menu.removeAllItems()
            menu.autoenablesItems = false
            addFoundryContextMenuItems(to: menu, request: request, componentID: componentID)
            if !nativeItems.isEmpty {
                menu.addItem(.separator())
                nativeItems.forEach(menu.addItem)
            }
        }

        private func addFoundryContextMenuItems(
            to menu: NSMenu,
            request: [String: Any],
            componentID: UUID
        ) {
            menu.addItem(contextMenuHeader(for: request))
            menu.addItem(.separator())
            if contextMenuImageProperty != nil {
                let clear = menuItem("Clear", action: #selector(performContextAction(_:)), representedAction: .clearImage)
                clear.isEnabled = contextMenuImageProperty.map { canClearImage(componentID, $0, contextMenuImagePropertyPath) } ?? false
                menu.addItem(clear)
                menu.addItem(.separator())
            } else if request["canEdit"] as? Bool == true {
                menu.addItem(menuItem("Edit", action: #selector(editComponent), key: "\r", modifiers: []))
                menu.addItem(.separator())
            }
            menu.addItem(menuItem("Duplicate", action: #selector(performContextAction(_:)), representedAction: .duplicate, key: "d"))
            menu.addItem(menuItem("Copy", action: #selector(performContextAction(_:)), representedAction: .copy, key: "c"))
            let paste = menuItem("Paste", action: #selector(performContextAction(_:)), representedAction: .paste, key: "v")
            paste.isEnabled = canPasteComponent
            menu.addItem(paste)
            menu.addItem(.separator())
            menu.addItem(menuItem("Save as Reusable Component…", action: #selector(performContextAction(_:)), representedAction: .saveReusable))
            menu.addItem(menuItem("Save as Global Component…", action: #selector(performContextAction(_:)), representedAction: .saveGlobal))
            menu.addItem(.separator())
            menu.addItem(menuItem("Move Up", action: #selector(performContextAction(_:)), representedAction: .moveUp))
            menu.addItem(menuItem("Move Down", action: #selector(performContextAction(_:)), representedAction: .moveDown))
            menu.addItem(menuItem("Move Out of Container", action: #selector(performContextAction(_:)), representedAction: .outdent))
            menu.addItem(.separator())
            menu.addItem(menuItem("Delete", action: #selector(performContextAction(_:)), representedAction: .delete, key: String(Character(UnicodeScalar(NSDeleteCharacter)!)), modifiers: []))
        }

        private func contextMenuHeader(for request: [String: Any]) -> NSMenuItem {
            let title = request["componentType"] as? String ?? "Component"
            let author = request["componentAuthor"] as? String ?? "Foundry"
            let version = request["componentVersion"] as? String ?? ""
            let subtitle = version.isEmpty ? author : "\(author)  v\(version)"
            let typeID = request["componentTypeID"] as? String
            let iconURL = typeID
                .map(ComponentType.init(rawValue:))?
                .definition.package
                .map(\.iconURL)
            let icon = NSImageView(image: NSImage(size: NSSize(width: 36, height: 36)))
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityLabel(title)
            icon.translatesAutoresizingMaskIntoConstraints = false
            if let iconURL {
                if let cached = ComponentIconLoader.cachedIcon(at: iconURL) {
                    icon.image = cached.image
                } else {
                    Task { [weak icon] in
                        guard let image = await ComponentIconLoader.shared.icon(at: iconURL)?.image else { return }
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

        @objc private func editComponent() {
            guard let webView, let contextMenuComponentID else { return }
            Task {
                _ = try? await webView.callAsyncJavaScript(
                    "window.foundryEditComponent(componentID)",
                    arguments: ["componentID": contextMenuComponentID.uuidString],
                    in: nil,
                    contentWorld: .defaultClient
                )
            }
        }

        @objc private func performContextAction(_ sender: NSMenuItem) {
            guard let contextMenuComponentID,
                  let rawValue = sender.representedObject as? String,
                  let action = CanvasContextMenuAction(rawValue: rawValue) else { return }
            handleContextMenuAction(action, contextMenuComponentID, contextMenuImageProperty, contextMenuImagePropertyPath)
        }

        func apply(_ operation: CanvasWebOperation, in webView: WKWebView) {
            switch operation {
            case .component(let subtree, let revision):
                patchComponent(subtree, revision: revision, in: webView)
            case .reconcilePage(let html, let revision):
                updateHTML(html, revision: revision, in: webView)
            case .reloadDocument(let html, let revision):
                guard revisionGate.request(revision) else { return }
                captureScrollPositionThenLoad(html, revision: revision, in: webView)
            }
        }

        private func patchComponent(
            _ subtree: RenderedComponentSubtree,
            revision: UInt64,
            in webView: WKWebView
        ) {
            guard revisionGate.request(revision) else { return }
            guard !isLoadingHTML, !isPatchingHTML, loadedHTML != nil else {
                pendingComponent = (subtree, revision)
                return
            }
            isPatchingHTML = true
            Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                let didPatch = (try? await webView.callAsyncJavaScript(
                    "return window.foundryReplaceComponent?.(componentID, html, css, revision) === true",
                    arguments: [
                        "componentID": subtree.componentID.uuidString,
                        "html": subtree.html,
                        "css": subtree.instanceCSS,
                        "revision": revision
                    ],
                    in: nil,
                    contentWorld: .defaultClient
                )) as? Bool == true
                self.isPatchingHTML = false
                guard didPatch else {
                    self.pendingComponent = nil
                    self.requestFullReconciliation()
                    return
                }
                guard self.revisionGate.apply(revision) else {
                    self.processPendingUpdate(in: webView)
                    return
                }
                self.applyCanvasState()
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
            isPatchingHTML = true
            Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                let didPatch = (try? await webView.callAsyncJavaScript(
                    "return window.foundryReplaceDocument?.(html) === true",
                    arguments: ["html": html],
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
                if let pendingHTML = self.pendingHTML, pendingHTML.html != html {
                    self.pendingHTML = nil
                    self.patchHTML(pendingHTML.html, revision: pendingHTML.revision, in: webView)
                } else {
                    self.pendingHTML = nil
                    self.applyCanvasState()
                }
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
            guard revisionGate.apply(revision) else { return }
            loadedHTML = html
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
            finishHTMLLoad(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: any Error
        ) {
            finishHTMLLoad(in: webView)
        }

        private func finishHTMLLoad(in webView: WKWebView) {
            isLoadingHTML = false
            if let pendingHTML, pendingHTML.html != loadedHTML {
                load(pendingHTML.html, revision: pendingHTML.revision, in: webView)
            } else {
                pendingHTML = nil
                applyCanvasState()
                processPendingUpdate(in: webView)
            }
        }

        private func processPendingUpdate(in webView: WKWebView) {
            if let pendingHTML,
               pendingHTML.revision >= (pendingComponent?.revision ?? 0) {
                self.pendingHTML = nil
                pendingComponent = nil
                patchHTML(pendingHTML.html, revision: pendingHTML.revision, in: webView)
            } else if let pendingComponent {
                self.pendingComponent = nil
                patchComponent(pendingComponent.subtree, revision: pendingComponent.revision, in: webView)
            }
        }

        func applyCanvasState() {
            guard let webView else { return }
            let componentIDs = selectedComponentIDs
                .sorted { lhs, rhs in
                    if lhs == primarySelectedComponentID { return true }
                    if rhs == primarySelectedComponentID { return false }
                    return lhs.uuidString < rhs.uuidString
                }
                .map(\.uuidString)
            let primitiveSelection: [String: Any] = selectedPrimitive.map {
                [
                    "componentID": $0.componentID.uuidString,
                    "propertyKey": $0.propertyKey.rawValue,
                    "propertyPath": $0.propertyPath
                ]
            } ?? [:]
            let selectionChanged = lastAppliedSelection != selectedComponentIDs
                || lastAppliedPrimarySelection != primarySelectedComponentID
            let selectionOriginatedInCanvas = pendingCanvasSelection == selectedComponentIDs
            let shouldScrollToSelection = selectionChanged && !selectionOriginatedInCanvas
            pendingCanvasSelection = nil
            lastAppliedSelection = selectedComponentIDs
            lastAppliedPrimarySelection = primarySelectedComponentID
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
                    "if (scrollPosition.x !== undefined) window.scrollTo(scrollPosition.x, scrollPosition.y); document.documentElement.style.setProperty('--foundry-editor-accent', accentColor); window.foundrySetWebInspectorEnabled?.(webInspectorEnabled); window.foundrySetEditorOptions?.(options); window.foundrySetSelection?.(componentIDs, primitiveSelection, shouldScrollToSelection)",
                    arguments: [
                        "options": options,
                        "componentIDs": componentIDs,
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
