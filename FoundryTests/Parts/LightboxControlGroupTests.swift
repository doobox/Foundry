import Foundation
import Testing
import WebKit
@testable import Foundry

struct LightboxControlGroupTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts")
    }

    @Test(arguments: ["Image", "SVG", "Video", "Lightbox"])
    func builtInsExposeThePublicGroup(_ name: String) throws {
        let package = try PartPackageLoader.load(from: root.appending(path: name))
        #expect(package.manifest.controlGroups.contains { $0.type == .lightbox })
        let group = try #require(package.manifest.controlGroups.first { $0.type == .lightbox })
        #expect(group.properties.map(\.id) == ["lightbox.enabled", "lightbox.backdropColor", "lightbox.backdropBlur"])
        #expect(package.manifest.slots.contains { $0.id == "lightbox-content" } == false)
        _ = try package.preparePayload()
    }

    @Test(arguments: ["Section", "Flexbox", "FlexItem", "Grid", "GridItem", "Button"])
    func layoutAndButtonPartsDoNotOfferLightbox(_ name: String) throws {
        let package = try PartPackageLoader.load(from: root.appending(path: name))
        #expect(package.manifest.controlGroups.contains { $0.type == .lightbox } == false)
        _ = try package.preparePayload()
    }

    @Test @MainActor func enabledGroupExportsRuntimeAndSuppressesWholePartLink() throws {
        let package = try PartPackageLoader.load(from: root.appending(path: "Image"))
        let previous = PartType.image.definition.package
        PartRegistry.register(package)
        defer {
            if let previous { PartRegistry.register(previous) }
            else { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        }
        var part = PartNode(type: .image)
        part.setProperty(.init(rawValue: "source"), value: .url("https://example.com/picture.jpg"))
        part.setProperty(.init(rawValue: "lightbox.enabled"), value: .boolean(true))
        part.setProperty(.init(rawValue: "link.destination"), value: .url("https://example.com"))
        let site = Site(name: "Lightbox", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(canvas.contains("dialog.showModal()") == false)
        #expect(canvas.contains("data-foundry-root-link=\"link\"") == false)
        let export = StaticSiteRenderer().render(site: site)
        #expect(export.errors.isEmpty)
        #expect(export.files.contains { String(decoding: $0.data, as: UTF8.self).contains("dialog.showModal()") })
    }

    @Test @MainActor func selectedYouTubeVideoExportsPlayer() throws {
        let package = try PartPackageLoader.load(from: root.appending(path: "Video"))
        let previous = PartType.video.definition.package
        PartRegistry.register(package)
        defer {
            if let previous { PartRegistry.register(previous) }
            else { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        }
        var part = PartNode(type: .video)
        part.setProperty(.init(rawValue: "lightbox.enabled"), value: .boolean(true))
        part.setProperty(.init(rawValue: "source"), value: .url("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let site = Site(name: "Lightbox", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let export = StaticSiteRenderer().render(site: site)
        #expect(export.errors.isEmpty)
        #expect(export.files.contains { String(decoding: $0.data, as: UTF8.self).contains("data-foundry-youtube-play=\"") })
    }

    @Test @MainActor func customSlotRendersInCanvasAndExport() throws {
        let package = try PartPackageLoader.load(from: root.appending(path: "Lightbox"))
        let previous = PartType.lightbox.definition.package
        let section = try PartPackageLoader.load(from: root.appending(path: "Section"))
        let previousSection = PartType.section.definition.package
        PartRegistry.register(section)
        PartRegistry.register(package)
        defer {
            if let previous { PartRegistry.register(previous) }
            else { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
            if let previousSection { PartRegistry.register(previousSection) }
            else { PartRegistry.unregisterPackage(identifier: section.manifest.identifier) }
        }
        var part = PartNode(type: .lightbox)
        part.setProperty(.init(rawValue: "lightbox.enabled"), value: .boolean(true))
        part.children = [PartNode(type: .section, slotID: "content", anchor: "modal-child")]
        let site = Site(name: "Lightbox", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(canvas.contains("id=\"modal-child\""))
        let export = StaticSiteRenderer().render(site: site)
        #expect(export.errors.isEmpty)
        #expect(export.files.contains { String(decoding: $0.data, as: UTF8.self).contains("id=\"modal-child\"") })
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func nativeDialogRestoresCustomContentAndFocus() async throws {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        defer { view.stopLoading() }
        view.loadHTMLString("""
        <html><body><div data-foundry-id="root"><div data-foundry-lightbox-trigger><button id="trigger">Open</button></div>
        <div id="config" hidden data-backdrop-color="rgb(0 0 0 / .5)" data-backdrop-blur="8"></div>
        <div id="storage" hidden><div data-foundry-lightbox-content aria-label="Example"><input id="field" value="Keep me"></div></div></div></body></html>
        """, baseURL: nil)
        let deadline = ContinuousClock.now + .seconds(10)
        var ready = false
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            ready = (try? await view.callAsyncJavaScript("return !!document.getElementById('field');", arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            await Task.yield()
        }
        try #require(ready)
        let result = try await view.callAsyncJavaScript(FoundryLightbox.javaScript + """
        const root = document.querySelector('[data-foundry-id]');
        const config = document.getElementById('config');
        const trigger = document.getElementById('trigger');
        globalThis.foundryLightbox.connect(root, config);
        trigger.click();
        const dialog = document.querySelector('dialog');
        const opened = dialog.open && dialog.getAttribute('aria-label') === 'Example'
          && dialog.contains(document.getElementById('field'))
          && document.documentElement.style.overflow === 'hidden';
        document.getElementById('field').value = 'Edited';
        const closed = new Promise(resolve => dialog.addEventListener('close', resolve, {once:true}));
        dialog.querySelector('.fd-lightbox-close').click();
        const animatedClose = dialog.open && dialog.classList.contains('fd-lightbox-closing');
        // Detached WebKit views may suspend the animation clock. Finish the
        // actual exit animations rather than sleeping for their duration.
        dialog.getAnimations({subtree:true}).filter(animation => animation.animationName?.startsWith('fd-lightbox-')).forEach(animation => animation.finish());
        await closed;
        const restored = document.getElementById('storage').contains(document.getElementById('field'))
          && document.getElementById('field').value === 'Edited'
          && document.documentElement.style.overflow === ''
          && document.activeElement === trigger;
        trigger.click();
        const reused = document.querySelectorAll('dialog').length === 1 && dialog.open;
        const secondClose = new Promise(resolve => dialog.addEventListener('close', resolve, {once:true}));
        dialog.close();
        await secondClose;
        const blur = dialog.style.getPropertyValue('--fd-lightbox-blur') === '8px';
        const vectorRoot = document.createElement('div');
        vectorRoot.id = 'vectorRoot'; vectorRoot.dataset.foundryId = 'vector';
        vectorRoot.innerHTML = '<style>#vectorRoot path{fill:rgb(255,0,0)}</style><svg viewBox="0 0 10 10"><path d="M0 0h10v10H0z"/></svg><div hidden data-foundry-lightbox-config></div>';
        document.body.append(vectorRoot);
        globalThis.foundryLightbox.connect(vectorRoot, vectorRoot.querySelector('[data-foundry-lightbox-config]'));
        vectorRoot.click();
        const vector = dialog.querySelector('path');
        const paintPreserved = getComputedStyle(vector).fill === 'rgb(255, 0, 0)' && getComputedStyle(dialog).backgroundColor === 'rgba(0, 0, 0, 0)';
        const vectorClose = new Promise(resolve => dialog.addEventListener('close', resolve, {once:true}));
        dialog.close(); await vectorClose;
        const vectorReturned = vectorRoot.contains(vector);
        const vectorStyleRestored = vector.style.length === 0;
        return {opened, animatedClose, restored, reused, blur, paintPreserved, vectorReturned, vectorStyleRestored};
        """, arguments: [:], in: nil, contentWorld: .defaultClient)
        let checks = try #require(result as? [String: Bool])
        for (name, passed) in checks { #expect(passed, "Lightbox lifecycle: \(name)") }
    }
}
