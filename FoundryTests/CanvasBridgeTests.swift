import Foundation
import Testing
@testable import Foundry

struct CanvasBridgeTests {
    @Test @MainActor
    func breakpointChangeRefreshesAllPartsDespiteLastPropertyMutation() {
        let key = PartProperty.Key(rawValue: "content")
        var first = PartNode.make(.paragraph)
        var second = PartNode.make(.paragraph)
        first.setProperty(key, value: .string("First mobile"))
        second.setProperty(key, value: .string("Second mobile"))
        first.setResponsiveProperty(key, value: .string("First medium"), at: .medium)
        second.setResponsiveProperty(key, value: .string("Second medium"), at: .medium)
        let page = Page(title: "Responsive", slug: "responsive", parts: [first, second])
        let transitions: [(ResponsiveBreakpoint, ResponsiveBreakpoint)] = [(.mobile, .medium), (.medium, .mobile)]
        for (previous, current) in transitions {
            let snapshot = CanvasRenderSnapshot(
                renderer: HTMLPageRenderer(), page: page, language: "en", framework: .standard,
                assets: [:], breakpoint: current,
                impact: .partProperty(partID: first.id, propertyKey: key),
                forcesReconciliation: false, previousBreakpoint: previous
            )
            guard case .page(let html) = snapshot.render() else {
                Issue.record("Changing breakpoint must refresh every part, not just the last edited part")
                continue
            }
            let suffix = current == .mobile ? "mobile" : "medium"
            #expect(html.contains("First \(suffix)"))
            #expect(html.contains("Second \(suffix)"))
        }
    }

    @Test
    func revisionGateRejectsStaleRequestsAndResults() {
        var gate = CanvasUpdateRevisionGate()

        let acceptedFirstRequest = gate.request(1)
        let acceptedNewestRequest = gate.request(3)
        let acceptedStaleRequest = gate.request(2)
        let appliedStaleResult = gate.apply(1)
        let appliedNewestResult = gate.apply(3)
        let reappliedStaleResult = gate.apply(2)

        #expect(acceptedFirstRequest)
        #expect(acceptedNewestRequest)
        #expect(!acceptedStaleRequest)
        #expect(!appliedStaleResult)
        #expect(appliedNewestResult)
        #expect(!reappliedStaleResult)
    }

    @Test
    func canvasDefinesDistinctPartReconciliationAndReloadOperations() {
        let id = UUID()
        let subtree = RenderedPartSubtree(partID: id, html: "<div></div>", instanceStyles: [:])
        let operations: [CanvasWebOperation] = [
            .part(subtree, revision: 4),
            .reconcilePage(html: "page", revision: 5),
            .reloadDocument(html: "page", revision: 6)
        ]
        let interactionScript = WebCanvasView.Coordinator.interactionScript

        #expect(operations.map(\.revision) == [4, 5, 6])
        #expect(interactionScript.contains("foundryReplacePart"))
        #expect(interactionScript.contains("data-foundry-instance-style"))
        #expect(interactionScript.contains("revision < latestFoundryRevision"))
    }

    @Test
    func immutableCanvasSnapshotMatchesAuthoritativeRenderer() async {
        let site = TestSiteFixtures.populatedSite()
        let page = site.pages[0]
        let renderer = HTMLPageRenderer(site: site)
        let snapshot = CanvasRenderSnapshot(
            renderer: renderer,
            page: page,
            language: site.language,
            framework: site.framework,
            assets: [:],
            breakpoint: .extraLarge,
            impact: .page,
            forcesReconciliation: false
        )

        let backgroundHTML = await Task.detached { snapshot.render() }.value
        let authoritativeHTML = renderer.render(
            page: page,
            language: site.language,
            framework: site.framework,
            assets: [:],
            breakpoint: .extraLarge
        )

        #expect(backgroundHTML == .page(authoritativeHTML))
    }

    @Test @MainActor
    func ordinaryLocalPropertyMutationUsesAuthoritativePartPatch() throws {
        var paragraph = PartNode.make(.paragraph)
        let propertyKey = PartProperty.Key(rawValue: "content")
        paragraph.setProperty(propertyKey, value: .string("Patched value"))
        let page = Page(title: "Patch", slug: "patch", parts: [paragraph])
        let snapshot = CanvasRenderSnapshot(
            renderer: HTMLPageRenderer(),
            page: page,
            language: "en",
            framework: .standard,
            assets: [:],
            breakpoint: .extraLarge,
            impact: .partProperty(partID: paragraph.id, propertyKey: propertyKey),
            forcesReconciliation: false
        )

        let result = snapshot.render()
        guard case .part(let subtree) = result else {
            Issue.record("Expected a targeted part render")
            return
        }
        #expect(subtree.partID == paragraph.id)
        #expect(HTMLPageRenderer().render(page: page, framework: .standard).contains(subtree.html))
    }

    @Test @MainActor
    func reusablePropertyMutationUsesPageFallback() {
        var paragraph = PartNode.make(.paragraph)
        paragraph.reusableDefinitionID = UUID()
        let propertyKey = PartProperty.Key(rawValue: "content")
        let page = Page(title: "Fallback", slug: "fallback", parts: [paragraph])
        let snapshot = CanvasRenderSnapshot(
            renderer: HTMLPageRenderer(),
            page: page,
            language: "en",
            framework: .standard,
            assets: [:],
            breakpoint: .extraLarge,
            impact: .partProperty(partID: paragraph.id, propertyKey: propertyKey),
            forcesReconciliation: false
        )

        guard case .page = snapshot.render() else {
            Issue.record("Expected the authoritative page fallback")
            return
        }
    }

    @Test
    func decodesCurrentSelectionMessage() {
        let id = UUID()
        let body: [String: Any] = [
            "version": CanvasMessage.currentVersion,
            "event": "selectPart",
            "partID": id.uuidString
        ]

        let message = CanvasMessage.decode(body)

        #expect(message?.event == .selectPart)
        #expect(message?.partID == id)
    }

    @Test
    func decodesSelectionClearingMessageWithoutPayload() {
        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "clearSelection"
        ])

        #expect(message?.event == .clearSelection)
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "clearSelection",
            "partID": UUID().uuidString
        ]) == nil)
    }

    @Test
    func decodesPrimitiveSelectionMessage() {
        let partID = UUID()
        let propertyKey = PartProperty.Key(rawValue: "sourceRepeat3")

        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "selectPrimitive",
            "partID": partID.uuidString,
            "propertyKey": propertyKey.rawValue,
            "propertyPath": [2, 4]
        ])

        #expect(message?.event == .selectPrimitive)
        #expect(message?.partID == partID)
        #expect(message?.propertyKey == propertyKey)
        #expect(message?.propertyPath == [2, 4])
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "selectPrimitive",
            "partID": partID.uuidString
        ]) == nil)
    }

    @Test
    func rejectsUnsupportedAndMalformedMessages() {
        let id = UUID().uuidString

        #expect(CanvasMessage.decode([
            "version": 999,
            "event": "selectPart",
            "partID": id
        ]) == nil)
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "unknown",
            "partID": id
        ]) == nil)
        #expect(CanvasMessage.decode("not an object") == nil)
    }

    @Test
    func decodesCanvasImageImportMessage() {
        let id = UUID()
        let propertyKey = PartProperty.Key(rawValue: "sourceRepeat1")
        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "importImageAsset",
            "partID": id.uuidString,
            "propertyKey": propertyKey.rawValue,
            "propertyPath": [3],
            "assetFilename": "hero.png",
            "assetMediaType": "image/png",
            "assetData": Data([1, 2, 3]).base64EncodedString()
        ])

        #expect(message?.event == .importImageAsset)
        #expect(message?.partID == id)
        #expect(message?.propertyKey == propertyKey)
        #expect(message?.propertyPath == [3])
        #expect(message?.assetFilename == "hero.png")

        let assetID = UUID()
        let existingAssetMessage = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "importImageAsset",
            "partID": id.uuidString,
            "propertyKey": propertyKey.rawValue,
            "assetID": assetID.uuidString
        ])
        #expect(existingAssetMessage?.assetID == assetID)
        #expect(existingAssetMessage?.propertyKey == propertyKey)
    }

    @Test
    func decodesCanvasPartDeletionAndRejectsEmptyDeletion() {
        let ids = [UUID(), UUID()]
        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "deleteParts",
            "partIDs": ids.map(\.uuidString)
        ])

        #expect(message?.event == .deleteParts)
        #expect(message?.partIDs == ids)
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "deleteParts",
            "partIDs": []
        ]) == nil)
    }

    @Test
    func decodesCanvasKeyboardSelectionActions() {
        let ids = [UUID(), UUID()]
        let actions: [(String, CanvasMessage.Event)] = [
            ("duplicateParts", .duplicateParts),
            ("copyParts", .copyParts),
            ("pasteParts", .pasteParts)
        ]
        for (event, expectedEvent) in actions {
            let message = CanvasMessage.decode([
                "version": CanvasMessage.currentVersion,
                "event": event,
                "partIDs": ids.map(\.uuidString)
            ])

            #expect(message?.event == expectedEvent)
            #expect(message?.partIDs == ids)
        }
        #expect(WebCanvasView.Coordinator.interactionScript.contains("event.metaKey"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("window.foundryEditPart(partID)"))
    }

    @Test @MainActor
    func rendererEmitsStableIdentityForEveryPart() {
        let page = TestSiteFixtures.populatedSite().pages[0]
        let html = HTMLPageRenderer().render(page: page, framework: .standard)
        let partIDs = flattened(page.parts).map(\.id.uuidString)

        for id in partIDs {
            #expect(html.contains("data-foundry-id=\"\(id)\""))
        }
        #expect(html.contains("data-foundry-part"))
        #expect(html.contains("data-foundry-package="))
        #expect(html.contains("data-foundry-type=\"Container\""))
        #expect(html.contains("data-foundry-type=\"Paragraph\""))
        #expect(html.contains("data-foundry-type=\"Button\""))
    }

    @Test @MainActor
    func subtreeRendererMatchesAuthoritativePageOutput() throws {
        var paragraph = PartNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "content"), value: .string("Subtree value"))
        let page = Page(title: "Subtree", slug: "subtree", parts: [paragraph])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            partID: paragraph.id,
            page: page,
            framework: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ))
        let fullPage = renderer.render(page: page, framework: .standard)

        #expect(fullPage.contains(subtree.html))
        for css in subtree.instanceStyles.values {
            #expect(fullPage.contains(css))
        }
    }

    @Test @MainActor
    func subtreeRendererIncludesNestedDescendantsAndTheirStyles() throws {
        var child = PartNode.make(.paragraph)
        child.setProperty(.init(rawValue: "content"), value: .string("Nested value"))
        var container = PartNode.make(.container)
        container.children = [child]
        let page = Page(title: "Nested", slug: "nested", parts: [container])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            partID: container.id,
            page: page,
            framework: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ))
        let fullPage = renderer.render(page: page, framework: .standard)

        #expect(subtree.html.contains("data-foundry-id=\"\(child.id.uuidString)\""))
        #expect(subtree.html.contains("data-foundry-parent=\"\(container.id.uuidString)\""))
        #expect(fullPage.contains(subtree.html))
        for css in subtree.instanceStyles.values {
            #expect(fullPage.contains(css))
        }
        // Styles are keyed per instance so the canvas gives every part its
        // own <style>: a parent's patch updating a descendant's element in
        // place can never shadow the descendant's own later patches.
        #expect(subtree.instanceStyles[container.id.uuidString]?.contains(container.id.uuidString) == true)
        #expect(subtree.instanceStyles[child.id.uuidString]?.contains(child.id.uuidString) == true)
    }

    @Test @MainActor
    func subtreePatchesCarryFreshPerInstanceStylesForNestedLayouts() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var grid = PartNode.make(.grid)
        grid.children = (0..<3).map { _ in PartNode.make(.paragraph) }
        var container = PartNode.make(.container)
        container.children = [grid]
        var page = Page(title: "Home", slug: "index", parts: [container])
        let renderer = HTMLPageRenderer()

        // Patch the container first — its subtree styles include the grid.
        let containerPatch = try #require(renderer.renderSubtree(
            partID: container.id, page: page, framework: .standard, assets: [:], breakpoint: .large
        ))
        #expect(containerPatch.instanceStyles[grid.id.uuidString]?.contains("justify-items: stretch") == true)

        // A later grid edit must surface in the grid's own style entry, which
        // the canvas updates in place regardless of earlier parent patches.
        grid.setProperty(.init(rawValue: "justifyItems"), value: .choice("center"))
        container.children = [grid]
        page.parts = [container]
        let gridPatch = try #require(renderer.renderSubtree(
            partID: grid.id, page: page, framework: .standard, assets: [:], breakpoint: .large
        ))
        #expect(gridPatch.partID == grid.id)
        #expect(gridPatch.instanceStyles[grid.id.uuidString]?.contains("justify-items: center") == true)
        for item in grid.children {
            #expect(gridPatch.instanceStyles[item.id.uuidString]?.isEmpty == false)
        }
    }

    @Test @MainActor
    func subtreeRendererPreservesInheritedGlobalIdentity() throws {
        let definitionID = UUID()
        let child = PartNode.make(.paragraph)
        var globalContainer = PartNode.make(.container)
        globalContainer.reusableDefinitionID = definitionID
        globalContainer.children = [child]
        let page = Page(title: "Global", slug: "global", parts: [globalContainer])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            partID: child.id,
            page: page,
            framework: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ))

        #expect(subtree.html.contains("data-foundry-global=\"\(definitionID.uuidString)\""))
        #expect(renderer.render(page: page, framework: .standard).contains(subtree.html))
        #expect(renderer.renderSubtree(
            partID: UUID(),
            page: page,
            framework: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ) == nil)
    }

    @Test @MainActor
    func rendererMarksGlobalsNestedInsideNormalParts() {
        let definitionID = UUID()
        var global = PartNode.make(.paragraph)
        global.reusableDefinitionID = definitionID
        var container = PartNode.make(.container)
        container.children = [global]
        let page = Page(title: "Nested Global", slug: "nested-global", parts: [container])

        let html = HTMLPageRenderer().render(page: page, framework: .standard)

        #expect(html.contains("data-foundry-id=\"\(global.id.uuidString)\""))
        #expect(html.contains("data-foundry-global=\"\(definitionID.uuidString)\""))
    }

    @Test @MainActor
    func pageRenderKeepsEveryInstanceStyleInItsOwnPatchableElement() {
        // A patch replaces <style data-foundry-instance-style="id"> by key. If
        // the page render bundled instance CSS into the shared sheet instead,
        // a patch could only append — leaving declarations the part no longer
        // emits (a dropped max-width, say) live in the original block.
        let flex = PartNode.make(.flex)
        let page = Page(title: "Styles", slug: "styles", parts: [flex])

        let html = HTMLPageRenderer().render(page: page, framework: .standard)

        #expect(html.contains("<style data-foundry-instance-style=\"\(flex.id.uuidString)\">"))
    }

    @Test @MainActor
    func emptyImageRendersAsAnExplicitDropTarget() {
        var image = PartNode.make(.image)
        image.setProperty(.source, value: .url(""))
        let page = Page(title: "Images", slug: "images", parts: [image])

        let html = HTMLPageRenderer().render(page: page, framework: .standard)

        #expect(html.contains("data-foundry-image-drop-zone"))
        #expect(html.contains("data-foundry-id=\"\(image.id.uuidString)\""))
    }

    @Test @MainActor
    func canvasServesAStillFirstFrameForManagedGIFsWithoutInliningIt() throws {
        let gifData = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
        let asset = ProjectAsset(
            filename: "animation.gif",
            mediaType: "image/gif",
            byteCount: gifData.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: gifData)
        )
        var image = PartNode.make(.image)
        image.setProperty(.source, value: .url(asset.reference))
        let page = Page(title: "GIF", slug: "gif", parts: [image])

        let html = HTMLPageRenderer().render(
            page: page,
            language: "en",
            framework: .standard,
            assets: [asset.id: ProjectAssetContent(asset: asset, data: gifData)],
            breakpoint: .extraLarge
        )

        #expect(html.contains(asset.reference))
        #expect(!html.contains("base64,"))

        let handler = CanvasAssetSchemeHandler(
            assets: [asset.id: ProjectAssetContent(asset: asset, data: gifData)]
        )
        let assetURL = try #require(URL(string: asset.reference))
        let resource = try #require(handler.resource(for: assetURL))
        #expect(resource.mediaType == "image/png")
        #expect(resource.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test @MainActor
    func canvasRendererIncludesEditorOptionHooks() {
        let page = Site.starter().pages[0]
        let html = HTMLPageRenderer().render(page: page, framework: .standard)
        let interactionScript = WebCanvasView.Coordinator.interactionScript

        #expect(interactionScript.contains("foundry-show-titles"))
        #expect(interactionScript.contains("foundrySetEditorOptions"))
        #expect(interactionScript.contains("scrollsToSelection"))
        #expect(interactionScript.contains("shouldScroll"))
        #expect(interactionScript.contains("attachShadow"))
        #expect(interactionScript.contains("data-foundry-editor-chrome"))
        #expect(interactionScript.contains("data-foundry-editor-chrome', 'selection"))
        #expect(interactionScript.contains("position: 'fixed'"))
        #expect(interactionScript.contains("const visibleLeft = Math.max(0, rect.left)"))
        #expect(interactionScript.contains("pointerEvents: 'none'"))
        #expect(interactionScript.contains("if (event.altKey) return;"))
        #expect(interactionScript.contains("selectedChromeTargets.push({"))
        #expect(interactionScript.contains("element: selectionElement"))
        #expect(interactionScript.contains("candidate.dataset.foundryPropertyPath"))
        #expect(interactionScript.contains("const globalChromeColor = '#30D158'"))
        #expect(interactionScript.contains("data-foundry-editor-chrome', 'editable"))
        #expect(interactionScript.contains("[data-foundry-inline-property]"))
        #expect(interactionScript.contains("const clickedEditable = event.target.closest('[data-foundry-inline-property]')"))
        #expect(!interactionScript.contains("part.querySelector('[data-foundry-inline-property]') !== null"))
        #expect(!html.contains("[data-foundry-id]:hover:not(:has([data-foundry-id]:hover))"))
        #expect(!html.contains("data-foundry-name); position: absolute"))
        #expect(!html.contains("position: relative; cursor: default"))
        #expect(!html.contains(".foundry-drop-before"))
    }

    @Test
    func activatingStructureSelectsItsDockedTab() {
        var layout = WorkspaceLayout.standard

        layout.activate(.structure)

        #expect(layout.columns[0].selectedPanel == .structure)
    }

    private func flattened(_ nodes: [PartNode]) -> [PartNode] {
        nodes.flatMap { [$0] + flattened($0.children) }
    }
}
