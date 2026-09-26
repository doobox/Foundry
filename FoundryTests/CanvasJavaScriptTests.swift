import Testing
import WebKit
@testable import Foundry

@MainActor
struct CanvasJavaScriptTests {
    @Test(.timeLimit(.minutes(1)))
    func blankCanvasEscapeAndOptionClickDriveExpectedSelection() async throws {
        let outerID = UUID()
        let innerID = UUID()
        let recorder = CanvasMessageRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(
            recorder,
            contentWorld: .defaultClient,
            name: WebCanvasView.Coordinator.handlerName
        )
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer {
            configuration.userContentController.removeScriptMessageHandler(
                forName: WebCanvasView.Coordinator.handlerName,
                contentWorld: .defaultClient
            )
            webView.stopLoading()
        }
        webView.loadHTMLString("""
            <html><body><section data-foundry-id="\(outerID.uuidString)" data-foundry-name="Outer">
            <p data-foundry-id="\(innerID.uuidString)" data-foundry-name="Inner">Text</p>
            </section></body></html>
            """, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return typeof window.foundrySetSelection === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)

        let blankClickMessageCount = recorder.messages.count
        _ = try await webView.callAsyncJavaScript("""
            window.foundrySetSelection([innerID], {}, false);
            document.body.dispatchEvent(new MouseEvent('click', { bubbles: true, button: 0 }));
            """, arguments: ["innerID": innerID.uuidString], in: nil, contentWorld: .defaultClient)
        for _ in 0..<40 where recorder.messages.count == blankClickMessageCount {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.messages.last?.event == .clearSelection)

        let escapeMessageCount = recorder.messages.count
        _ = try await webView.callAsyncJavaScript("""
            window.foundrySetSelection([innerID], {}, false);
            document.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
            """, arguments: ["innerID": innerID.uuidString], in: nil, contentWorld: .defaultClient)
        for _ in 0..<40 where recorder.messages.count == escapeMessageCount {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.messages.last?.event == .clearSelection)

        let optionClickMessageCount = recorder.messages.count
        _ = try await webView.callAsyncJavaScript("""
            window.foundrySetSelection([innerID], {}, false);
            document.querySelector('[data-foundry-id="' + CSS.escape(innerID) + '"]')
              .dispatchEvent(new MouseEvent('click', { bubbles: true, button: 0, altKey: true }));
            """, arguments: ["innerID": innerID.uuidString], in: nil, contentWorld: .defaultClient)
        for _ in 0..<40 where recorder.messages.count == optionClickMessageCount {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.messages.last?.event == .selectPart)
        #expect(recorder.messages.last?.partID == outerID)

        let imageDropMessageCount = recorder.messages.count
        _ = try await webView.callAsyncJavaScript("""
            const part = document.querySelector('[data-foundry-id="' + CSS.escape(innerID) + '"]');
            const zone = document.createElement('img');
            zone.setAttribute('data-foundry-image-drop-zone', '');
            zone.dataset.foundryImageProperty = 'source';
            part.appendChild(zone);
            const file = new File(['image bytes'], 'photo.png', { type: 'image/png' });
            const transfer = {
              types: ['Files'], files: [file], effectAllowed: 'copy', dropEffect: 'none', getData: () => ''
            };
            for (const name of ['dragover', 'drop']) {
              const event = new Event(name, { bubbles: true, cancelable: true });
              Object.defineProperty(event, 'dataTransfer', { value: transfer });
              zone.dispatchEvent(event);
            }
            """, arguments: ["innerID": innerID.uuidString], in: nil, contentWorld: .defaultClient)
        for _ in 0..<80 where recorder.messages.count == imageDropMessageCount {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.messages.last?.event == .importImageAsset)
        #expect(recorder.messages.last?.partID == innerID)
        #expect(recorder.messages.last?.propertyKey?.rawValue == "source")
    }

    @Test(.timeLimit(.minutes(1)))
    func builtInGridsLayOutAtBaseAndMediumIncludingNestedGrids() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var inner = PartNode.make(.grid)
        inner.setResponsiveProperty(.init(rawValue: "columnCount"), value: .number(3), at: .medium)
        inner.children = (0..<3).map { _ in PartNode.make(.paragraph) }
        var outer = PartNode.make(.grid)
        outer.children = [inner, .make(.paragraph)]
        let page = Page(title: "Grid test", slug: "index", parts: [outer])
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        defer { webView.stopLoading() }
        for breakpoint in [ResponsiveBreakpoint.mobile, .medium] {
            let html = HTMLPageRenderer().render(page: page, language: "en", framework: .standard, assets: [:], breakpoint: breakpoint)
            webView.loadHTMLString(html.replacingOccurrences(of: "<html ", with: "<html data-layout-test=\"\(breakpoint.rawValue)\" "), baseURL: nil)
            var ready = false
            for _ in 0..<200 {
                ready = (try? await webView.evaluateJavaScript("document.readyState === 'complete' && document.documentElement.dataset.layoutTest === '\(breakpoint.rawValue)' && document.querySelectorAll('.foundry-grid').length === 2")) as? Bool == true
                if ready { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            try #require(ready)
            let measurements = try #require(try await webView.evaluateJavaScript("""
                (() => {
                  const outer = document.querySelector('.foundry-grid');
                  const inner = outer.children[0];
                  return [outer.getBoundingClientRect().width, inner.getBoundingClientRect().width,
                    parseFloat(getComputedStyle(outer).columnGap), inner.children[0].getBoundingClientRect().width,
                    parseFloat(getComputedStyle(inner).columnGap)];
                })()
                """) as? [Double])
            if breakpoint == .mobile {
                #expect(abs(measurements[0] - measurements[1]) < 1)
            } else {
                #expect(abs(measurements[0] - (measurements[1] * 2 + measurements[2])) < 1)
                #expect(abs(measurements[1] - (measurements[3] * 3 + measurements[4] * 2)) < 1)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionChromeTracksLateContentResizing() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = CanvasWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        defer { webView.stopLoading(); window.close() }
        webView.loadHTMLString(page(colour: "#123456"), baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && typeof window.foundrySetSelection === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        _ = try await webView.callAsyncJavaScript("""
            const part = document.querySelector('[data-foundry-id]');
            part.dataset.foundryName = 'Example';
            part.style.cssText = 'box-sizing:content-box;width:100px;height:100px;border:10px solid red;border-radius:20px';
            part.dispatchEvent(new PointerEvent('pointermove', { bubbles: true }));
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        var titleAligned = false
        for _ in 0..<240 {
            titleAligned = (try? await webView.callAsyncJavaScript("""
                const host = document.querySelector('[data-foundry-editor-chrome="host"]');
                const title = host.shadowRoot.querySelector('[data-foundry-editor-chrome="title"]');
                return title.style.display === 'block'
                  && title.style.left === '18px' && title.style.top === '18px'
                  && title.style.transform === 'none'
                  && title.style.maxWidth === '100px'
                  && title.style.opacity === '1'
                  && getComputedStyle(title).backgroundColor === 'rgb(64, 156, 255)'
                  && getComputedStyle(title).borderRadius === '0px 0px 5px';
                """, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if titleAligned { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(titleAligned)
        webView.clearHoverChrome()
        var hoverCleared = false
        for _ in 0..<240 {
            hoverCleared = (try? await webView.callAsyncJavaScript("""
                const root = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot;
                return root.querySelector('[data-foundry-editor-chrome="title"]').style.display === 'none'
                  && root.querySelector('[data-foundry-editor-chrome="hover"]').style.display === 'none';
                """, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if hoverCleared { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(hoverCleared)
        _ = try await webView.callAsyncJavaScript(
            "document.querySelector('[data-foundry-id]').style.cssText = ''",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        _ = try await webView.callAsyncJavaScript(
            "window.foundrySetSelection(['test-part'], {}, false)",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        webView.clearHoverChrome()
        var selectionTitleRemains = false
        for _ in 0..<240 {
            selectionTitleRemains = (try? await webView.callAsyncJavaScript("""
                const title = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot
                  .querySelector('[data-foundry-editor-chrome="selection-title"]');
                return title.style.display === 'block'
                  && title.style.opacity === '1'
                  && title.textContent === 'Example';
                """, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if selectionTitleRemains { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(selectionTitleRemains)
        try await Task.sleep(for: .milliseconds(100))
        // Emulate asynchronous text reflow after the initial chrome update.
        _ = try await webView.callAsyncJavaScript(
            "document.querySelector('[data-foundry-id]').style.height = '120px'",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        var aligned = false
        for _ in 0..<240 {
            aligned = (try? await webView.callAsyncJavaScript("""
                const part = document.querySelector('[data-foundry-id]');
                const outline = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot
                  .querySelector('[data-foundry-editor-chrome="selection"]');
                return outline && Math.abs(parseFloat(outline.style.height) - part.getBoundingClientRect().height) < 1;
                """, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if aligned { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(aligned)

        _ = try await webView.callAsyncJavaScript("""
            const child = document.querySelector('[data-foundry-id="test-part"]');
            const parent = document.createElement('div');
            parent.dataset.foundryId = 'parent-part';
            parent.dataset.foundryName = 'Parent';
            child.before(parent);
            parent.appendChild(child);
            parent.dispatchEvent(new PointerEvent('pointermove', { bubbles: true }));
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        var parentHoverTitleIsFrontmost = false
        for _ in 0..<240 {
            parentHoverTitleIsFrontmost = (try? await webView.callAsyncJavaScript("""
                const root = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot;
                const hoverTitle = root.querySelector('[data-foundry-editor-chrome="title"]');
                const selectionTitle = root.querySelector('[data-foundry-editor-chrome="selection-title"]');
                const hoverRect = hoverTitle.getBoundingClientRect();
                const selectionRect = selectionTitle.getBoundingClientRect();
                const overlap = !(hoverRect.right <= selectionRect.left || hoverRect.left >= selectionRect.right
                  || hoverRect.bottom <= selectionRect.top || hoverRect.top >= selectionRect.bottom);
                return hoverTitle.style.display === 'block'
                  && hoverTitle.textContent === 'Parent'
                  && selectionTitle.style.display === 'block'
                  && !overlap
                  && Number(getComputedStyle(hoverTitle).zIndex) > Number(getComputedStyle(selectionTitle).zIndex);
                """, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if parentHoverTitleIsFrontmost { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(parentHoverTitleIsFrontmost)

        let multipleSelectionLabelsAreOrderedAndSeparated = try await webView.callAsyncJavaScript("""
            window.foundrySetSelection(['test-part', 'parent-part'], {}, false);
            window.foundryClearHoverChrome();
            const root = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot;
            const titles = [...root.querySelectorAll('[data-foundry-editor-chrome="selection-title"]')]
              .filter(title => title.style.display === 'block');
            const first = titles[0].getBoundingClientRect();
            const second = titles[1].getBoundingClientRect();
            const overlap = !(first.right <= second.left || first.left >= second.right
              || first.bottom <= second.top || first.top >= second.bottom);
            return titles.length === 2 && !overlap
              && Number(getComputedStyle(titles[0]).zIndex) > Number(getComputedStyle(titles[1]).zIndex);
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(multipleSelectionLabelsAreOrderedAndSeparated as? Bool == true)

        let partiallyClippedPartKeepsVisibleLabel = try await webView.callAsyncJavaScript("""
            const parent = document.querySelector('[data-foundry-id="parent-part"]');
            parent.style.cssText = 'position:fixed;left:-20px;top:-20px;width:160px;height:100px';
            window.foundrySetSelection(['parent-part'], {}, false);
            const title = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot
              .querySelector('[data-foundry-editor-chrome="selection-title"]');
            const rect = title.getBoundingClientRect();
            const visible = title.style.display === 'block' && rect.left >= 0 && rect.top >= 0;
            parent.style.cssText = '';
            return visible;
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(partiallyClippedPartKeepsVisibleLabel as? Bool == true)

        let activeDropStateIsExclusive = try await webView.callAsyncJavaScript("""
            const parent = document.querySelector('[data-foundry-id="parent-part"]');
            parent.dataset.foundryAcceptsChildren = 'true';
            window.foundrySetSelection(['parent-part'], {}, false);
            const rect = parent.getBoundingClientRect();
            const drag = new Event('dragover', { bubbles: true, cancelable: true });
            Object.defineProperties(drag, {
              clientY: { value: rect.top + rect.height / 2 },
              dataTransfer: { value: {
                types: ['text/plain'], effectAllowed: 'copy', dropEffect: 'none',
                getData: () => 'foundry-part-type:foundry.content.button'
              }}
            });
            parent.dispatchEvent(drag);
            const root = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot;
            const outline = root.querySelector('[data-foundry-editor-chrome="selection"]');
            const title = root.querySelector('[data-foundry-editor-chrome="selection-title"]');
            const drop = root.querySelector('[data-foundry-editor-chrome="drop"]');
            // The parent already holds a child, so hovering its middle snaps
            // to an insertion bar beside that child — never the inside slab.
            // Bars sit at edges, so they never suppress the selection chrome.
            return !parent.classList.contains('foundry-drop-inside')
              && drop.style.display === 'block'
              && drop.textContent === ''
              && outline.style.display === 'block' && title.style.display === 'block';
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(activeDropStateIsExclusive as? Bool == true)

        let selectionStaysSuppressedDuringDropUpdates = try await webView.callAsyncJavaScript("""
            window.foundrySetSelection(['parent-part'], {}, false);
            const root = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot;
            return root.querySelector('[data-foundry-editor-chrome="selection"]').style.display === 'block'
              && root.querySelector('[data-foundry-editor-chrome="selection-title"]').style.display === 'block'
              && root.querySelector('[data-foundry-editor-chrome="drop"]').style.display === 'block';
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(selectionStaysSuppressedDuringDropUpdates as? Bool == true)

        _ = try await webView.callAsyncJavaScript("""
            const leave = new Event('dragleave', { bubbles: true });
            Object.defineProperty(leave, 'relatedTarget', { value: null });
            document.querySelector('[data-foundry-id="parent-part"]').dispatchEvent(leave);
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        var selectionRestoredAfterDropExit = false
        for _ in 0..<80 {
            selectionRestoredAfterDropExit = (try? await webView.callAsyncJavaScript("""
                const root = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot;
                return root.querySelector('[data-foundry-editor-chrome="selection"]').style.display === 'block'
                  && root.querySelector('[data-foundry-editor-chrome="selection-title"]').style.display === 'block'
                  && root.querySelector('[data-foundry-editor-chrome="drop"]').style.display === 'none';
                """, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if selectionRestoredAfterDropExit { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(selectionRestoredAfterDropExit)
    }

    @Test(.timeLimit(.minutes(1)))
    func pendingFontStylesheetKeepsCanvasLayoutAndBodyIntact() async throws {
        let handler = DelayedCanvasFontStylesheet()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "canvas-font-test")
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { handler.finish(); webView.stopLoading() }
        let page = Page(title: "Font test", slug: "index", parts: (0..<30).map { _ in PartNode.make(.paragraph) })
        var framework = Framework.standard
        let renderer = HTMLPageRenderer()
        webView.loadHTMLString(renderer.render(page: page, framework: framework), baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        _ = try await webView.callAsyncJavaScript("""
            window.probePart = document.querySelector('[data-foundry-id]');
            window.probeReplacements = 0;
            const original = document.body.replaceChildren;
            document.body.replaceChildren = function(...nodes) {
              window.probeReplacements++;
              return original.apply(this, nodes);
            };
            window.scrollTo(0, 300);
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        framework.typography.bodyFont.source = .remote(stylesheetURL: URL(string: "canvas-font-test://font/styles.css")!)
        _ = try await webView.callAsyncJavaScript(
            "return window.foundryReplaceDocument(html)",
            arguments: ["html": renderer.render(page: page, framework: framework)], in: nil, contentWorld: .defaultClient)
        for _ in 0..<200 {
            if handler.hasPendingRequest { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(handler.hasPendingRequest)
        let result = try await webView.callAsyncJavaScript("""
            return { boxSizing: getComputedStyle(window.probePart).boxSizing,
              samePart: window.probePart === document.querySelector('[data-foundry-id]'),
              replacements: window.probeReplacements, scrollY: window.scrollY };
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        let measurements = try #require(result as? [String: Any])
        print("PENDING FONT PROBE: \(measurements)")
        #expect(measurements["boxSizing"] as? String == "border-box")
        #expect(measurements["samePart"] as? Bool == true)
        #expect(measurements["replacements"] as? Int == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func stylesheetOnlyUpdatePreservesBodyNodes() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { webView.stopLoading() }
        webView.loadHTMLString(page(colour: "#123456"), baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let result = try await webView.callAsyncJavaScript("""
            const part = document.querySelector('[data-foundry-id="test-part"]');
            let replacements = 0;
            const original = document.body.replaceChildren;
            document.body.replaceChildren = function(...nodes) {
              replacements++;
              return original.apply(this, nodes);
            };
            const updated = window.foundryReplaceDocument(html);
            return { updated, replacements,
              samePart: part === document.querySelector('[data-foundry-id="test-part"]') };
            """, arguments: ["html": page(colour: "#ABCDEF")], in: nil, contentWorld: .defaultClient)
        let measurements = try #require(result as? [String: Any])
        print("STYLESHEET-ONLY PROBE: \(measurements)")
        #expect(measurements["updated"] as? Bool == true)
        #expect(measurements["replacements"] as? Int == 0)
        #expect(measurements["samePart"] as? Bool == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func structuralUpdatesDoNotLeaveDuplicateOrRemovedParts() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { webView.stopLoading() }
        func part(_ id: String, _ contents: String) -> String {
            "<article data-foundry-id=\"\(id)\"><div class=\"slot\">\(contents)</div></article>"
        }
        let empty = "<div class=\"foundry-empty-drop-zone\">Drop part here</div>"
        let child = part("third-party-child", empty)
        let parent = "third-party-parent"
        let initial = part(parent, empty) + child
        webView.loadHTMLString("<html><body>\(initial)</body></html>", baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        // Nest, unnest, reorder, add and delete arbitrary part identities.
        let bodies = [part(parent, child), initial, child + part(parent, empty),
                      part(parent, part("another-wrapper", child)),
                      part(parent, empty), ""]
        for body in bodies {
            let matches = try await webView.callAsyncJavaScript("""
                const html = '<html><body>' + body + '</body></html>';
                const expected = new DOMParser().parseFromString(html, 'text/html');
                const signature = root => [...root.querySelectorAll('[data-foundry-id]')].map(element => [
                  element.dataset.foundryId,
                  element.parentElement.closest('[data-foundry-id]')?.dataset.foundryId ?? null
                ]);
                window.foundryReplaceDocument(html);
                return JSON.stringify(signature(document)) === JSON.stringify(signature(expected))
                  && document.querySelectorAll('.foundry-empty-drop-zone').length === expected.querySelectorAll('.foundry-empty-drop-zone').length;
                """, arguments: ["body": body], in: nil, contentWorld: .defaultClient)
            #expect(matches as? Bool == true, "Canvas must match the authoritative part hierarchy")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func liveFrameworkUpdatesCompleteWithoutReloadingDocument() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { webView.stopLoading() }
        webView.loadHTMLString(page(colour: "#123456"), baseURL: nil)

        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient
            )) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready, "The real canvas interaction script must be installed")

        // A reload would discard this client-world state. Reconcile several successive
        // framework shades, as happens while changing a colour or dragging Soften.
        _ = try await webView.callAsyncJavaScript(
            "window.canvasTestSentinel = {}; window.originalCanvasTestSentinel = window.canvasTestSentinel",
            arguments: [:], in: nil, contentWorld: .defaultClient
        )
        for colour in ["#ABCDEF", "#556677", "#223344"] {
            let result = try await webView.callAsyncJavaScript(
                """
                const updated = window.foundryReplaceDocument(html);
                return updated === true
                  && document.querySelector('#framework').textContent.includes(colour)
                  && document.querySelector('[data-foundry-id="test-part"]').textContent === 'Example'
                  && window.canvasTestSentinel !== undefined
                  && window.canvasTestSentinel === window.originalCanvasTestSentinel;
                """,
                arguments: ["html": page(colour: colour), "colour": colour],
                in: nil, contentWorld: .defaultClient
            )
            #expect(result as? Bool == true)
        }
    }

    private func page(colour: String) -> String {
        """
        <!doctype html><html><head><style id="framework">:root { --foundry-color-accent: \(colour); }</style></head>
        <body><div data-foundry-id="test-part">Example</div></body></html>
        """
    }
}

@MainActor
private final class CanvasMessageRecorder: NSObject, WKScriptMessageHandler {
    var messages: [CanvasMessage] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let decoded = CanvasMessage.decode(message.body) {
            messages.append(decoded)
        }
    }
}

@MainActor
private final class DelayedCanvasFontStylesheet: NSObject, WKURLSchemeHandler {
    private var tasks: [any WKURLSchemeTask] = []
    var hasPendingRequest: Bool { !tasks.isEmpty }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        tasks.append(urlSchemeTask)
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeAll { $0 === urlSchemeTask }
    }
    func finish() {
        let pending = tasks
        tasks.removeAll()
        for task in pending {
            task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/css", expectedContentLength: 0, textEncodingName: "utf-8"))
            task.didReceive(Data())
            task.didFinish()
        }
    }
}
