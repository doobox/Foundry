import AppKit
import SwiftUI
import WebKit

struct WebCanvasView: NSViewRepresentable {
    let html: String
    let selectedComponentIDs: Set<UUID>
    let editorOptions: CanvasEditorOptions
    let enablesWebInspector: Bool
    let handleMessage: (CanvasMessage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(handleMessage: handleMessage)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = enablesWebInspector
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
        context.coordinator.handleMessage = handleMessage
        context.coordinator.selectedComponentIDs = selectedComponentIDs
        context.coordinator.editorOptions = editorOptions
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            context.coordinator.applyCanvasState()
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let handlerName = "foundryCanvas"
        static let interactionScript = """
        (() => {
          if (window.foundryCanvasInstalled) return;
          window.foundryCanvasInstalled = true;
          const selector = '[data-foundry-id]';
          let placement = null;
          let selectedComponentIDs = [];
          let activeDragSources = [];
          let activeInlineEdit = null;
          let globalMenuTarget = null;
          let globalMenuRelinks = false;
          const globalMenu = document.createElement('div');
          globalMenu.className = 'foundry-global-menu';
          globalMenu.setAttribute('role', 'menu');
          const globalMenuAction = document.createElement('button');
          globalMenuAction.type = 'button';
          globalMenuAction.setAttribute('role', 'menuitem');
          globalMenu.appendChild(globalMenuAction);
          document.body.appendChild(globalMenu);

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
          document.documentElement.appendChild(chromeTitle);
          let hoveredComponent = null;
          let chromeFrame = null;

          const componentChromeColor = element => {
            const overrideOwner = element.closest('[data-foundry-global-override="true"]');
            return element.dataset.foundryGlobal && !overrideOwner ? '#34C759' : '#0A84FF';
          };

          const updateChromeTitle = () => {
            chromeFrame = null;
            if (!hoveredComponent || !hoveredComponent.isConnected || !editorOptions.showsTitles || activeInlineEdit) {
              chromeTitle.style.setProperty('display', 'none', 'important');
              return;
            }
            const rect = hoveredComponent.getBoundingClientRect();
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
            if (component === hoveredComponent) return;
            hoveredComponent = component;
            scheduleChromeTitleUpdate();
          }, true);
          document.addEventListener('pointerleave', () => {
            hoveredComponent = null;
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
            if (event.altKey) return;
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
            const edgeCandidates = [];
            let edgeElement = event.target.closest(selector);
            let depth = 0;
            while (edgeElement) {
              const edgeRect = edgeElement.getBoundingClientRect();
              if (event.clientX >= edgeRect.left && event.clientX <= edgeRect.right) {
                const topDistance = Math.abs(event.clientY - edgeRect.top);
                const bottomDistance = Math.abs(event.clientY - edgeRect.bottom);
                if (topDistance <= 18) {
                  edgeCandidates.push({ kind: 'before', distance: topDistance, depth, element: edgeElement });
                }
                if (bottomDistance <= 18) {
                  edgeCandidates.push({ kind: 'after', distance: bottomDistance, depth, element: edgeElement });
                }
              }
              edgeElement = edgeElement.parentElement?.closest(selector);
              depth += 1;
            }
            edgeCandidates.sort((left, right) => left.distance - right.distance || right.depth - left.depth);
            const edge = edgeCandidates[0];
            if (edge) {
              return {
                kind: edge.kind,
                targetID: edge.element.dataset.foundryId,
                element: edge.element
              };
            }

            const element = event.target.closest(selector);
            if (!element) return { kind: 'end' };
            const rect = element.getBoundingClientRect();
            const distanceFromTop = event.clientY - rect.top;
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

          window.foundrySetSelection = ids => {
            selectedComponentIDs = Array.isArray(ids) ? ids : [];
            document.querySelectorAll('.foundry-selected').forEach(e => e.classList.remove('foundry-selected'));
            if (!Array.isArray(selectedComponentIDs)) return;
            let firstElement = null;
            selectedComponentIDs.forEach(componentID => {
              const element = document.querySelector('[data-foundry-id="' + CSS.escape(componentID) + '"]');
              if (!element) return;
              if (!firstElement) firstElement = element;
              if (editorOptions.showsSelection) element.classList.add('foundry-selected');
            });
            if (firstElement && editorOptions.scrollsToSelection) {
              firstElement.scrollIntoView({ block: 'nearest', inline: 'nearest' });
            }
          };

          document.querySelectorAll(selector).forEach(element => {
            element.draggable = true;
            element.addEventListener('dragstart', event => {
              if (element.isContentEditable) {
                event.preventDefault();
                return;
              }
              const draggedID = element.dataset.foundryId;
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
              clearDrop();
              clearDragSources();
            });
          });

          document.addEventListener('dragover', event => {
            clearDrop();
            if (event.dataTransfer.types.includes('Files')) {
              event.preventDefault();
              const imageZone = event.target.closest('[data-foundry-image-drop-zone]');
              const image = imageZone?.closest(selector);
              if (image) {
                image.classList.add('foundry-drop-inside');
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
            placement = intendedPlacement(event);
            if (placement.element) placement.element.classList.add('foundry-drop-' + placement.kind);
            const allowedEffect = event.dataTransfer.effectAllowed;
            event.dataTransfer.dropEffect = allowedEffect === 'move' ? 'move' : 'copy';
          });

          document.addEventListener('dragleave', event => {
            if (!document.documentElement.contains(event.relatedTarget)) clearDrop();
          });

          document.addEventListener('drop', event => {
            event.preventDefault();
            clearDragSources();
            const file = event.dataTransfer.files[0];
            if (file) {
              const imageZone = event.target.closest('[data-foundry-image-drop-zone]');
              const image = imageZone?.closest(selector);
              const target = placement || intendedPlacement(event);
              clearDrop();
              const isImage = file.type.startsWith('image/') || /\\.(?:avif|gif|heic|heif|jpe?g|png|svg|webp)$/i.test(file.name);
              if (!isImage || file.size > 25000000) return;
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
                } else {
                  message.placement = { kind: target.kind, targetID: target.targetID, slotID: target.slotID };
                }
                window.webkit.messageHandlers.foundryCanvas.postMessage(message);
              };
              reader.readAsDataURL(file);
              return;
            }
            const value = event.dataTransfer.getData('text/plain');
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
              message.event = 'insertImageComponent';
              message.assetID = value.substring('foundry-image-asset:'.length);
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
            if (activeInlineEdit && activeInlineEdit.element !== element) {
              activeInlineEdit.finish(true);
            }
            event.preventDefault();
            event.stopPropagation();

            const original = element.innerText;
            const commitsOnReturn = (componentElement ?? element).dataset.foundryType !== 'Text';
            let finished = false;
            element.contentEditable = 'true';
            element.draggable = false;
            element.classList.add('foundry-editing');
            element.focus();

            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(element);
            selection.removeAllRanges();
            selection.addRange(range);

            const finish = commit => {
              if (finished) return;
              finished = true;
              if (activeInlineEdit?.element === element) activeInlineEdit = null;
              element.contentEditable = 'false';
              element.draggable = true;
              element.classList.remove('foundry-editing');
              if (!commit) {
                element.textContent = original;
                return;
              }
              const value = element.innerText;
              if (value !== original) {
                window.webkit.messageHandlers.foundryCanvas.postMessage({
                  version: 1,
                  event: 'editComponent',
                  componentID: (componentElement ?? element).dataset.foundryId,
                  propertyKey: editableProperty,
                  propertyValue: value
                });
              }
            };

            activeInlineEdit = { element, finish };
            element.addEventListener('keydown', keyEvent => {
              if (keyEvent.key === 'Escape') {
                keyEvent.preventDefault();
                finish(false);
                element.blur();
              } else if (keyEvent.key === 'Enter' && (commitsOnReturn || keyEvent.metaKey || keyEvent.ctrlKey)) {
                keyEvent.preventDefault();
                finish(true);
                element.blur();
              }
            });
          }, true);

          document.addEventListener('click', event => {
            const element = event.target.closest(selector);
            if (activeInlineEdit && !activeInlineEdit.element.contains(event.target)) {
              activeInlineEdit.finish(true);
            }
            if (element?.isContentEditable) return;
            if (!element) return;
            event.preventDefault();
            event.stopPropagation();
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
        var selectedComponentIDs: Set<UUID> = []
        var editorOptions = CanvasEditorOptions()
        var handleMessage: (CanvasMessage) -> Void

        init(handleMessage: @escaping (CanvasMessage) -> Void) {
            self.handleMessage = handleMessage
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
            guard message.name == Self.handlerName,
                  message.frameInfo.isMainFrame,
                  let canvasMessage = CanvasMessage.decode(message.body) else { return }
            handleMessage(canvasMessage)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            applyCanvasState()
        }

        func applyCanvasState() {
            guard let webView else { return }
            let componentIDs = selectedComponentIDs.map(\.uuidString)
            let options: [String: Any] = [
                "showsTitles": editorOptions.showsTitles,
                "showsOutlines": editorOptions.showsOutlines,
                "showsSelection": editorOptions.showsSelection,
                "scrollsToSelection": editorOptions.scrollsToSelection
            ]
            let accentColor = cssAccentColor
            Task {
                _ = try? await webView.callAsyncJavaScript(
                    "document.documentElement.style.setProperty('--foundry-editor-accent', accentColor); window.foundrySetEditorOptions?.(options); window.foundrySetSelection?.(componentIDs)",
                    arguments: ["options": options, "componentIDs": componentIDs, "accentColor": accentColor],
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
