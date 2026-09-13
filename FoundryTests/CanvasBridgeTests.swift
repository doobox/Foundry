import Foundation
import Testing
@testable import Foundry

struct CanvasBridgeTests {
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
    func canvasDefinesDistinctBlockReconciliationAndReloadOperations() {
        let id = UUID()
        let subtree = RenderedBlockSubtree(blockID: id, html: "<div></div>", instanceCSS: "")
        let operations: [CanvasWebOperation] = [
            .block(subtree, revision: 4),
            .reconcilePage(html: "page", revision: 5),
            .reloadDocument(html: "page", revision: 6)
        ]
        let interactionScript = WebCanvasView.Coordinator.interactionScript

        #expect(operations.map(\.revision) == [4, 5, 6])
        #expect(interactionScript.contains("foundryReplaceBlock"))
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
            theme: site.theme,
            assets: [:],
            breakpoint: .extraLarge,
            impact: .page,
            forcesReconciliation: false
        )

        let backgroundHTML = await Task.detached { snapshot.render() }.value
        let authoritativeHTML = renderer.render(
            page: page,
            language: site.language,
            theme: site.theme,
            assets: [:],
            breakpoint: .extraLarge
        )

        #expect(backgroundHTML == .page(authoritativeHTML))
    }

    @Test @MainActor
    func ordinaryLocalPropertyMutationUsesAuthoritativeBlockPatch() throws {
        var paragraph = BlockNode.make(.paragraph)
        let propertyKey = BlockProperty.Key(rawValue: "content")
        paragraph.setProperty(propertyKey, value: .string("Patched value"))
        let page = Page(title: "Patch", slug: "patch", blocks: [paragraph])
        let snapshot = CanvasRenderSnapshot(
            renderer: HTMLPageRenderer(),
            page: page,
            language: "en",
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge,
            impact: .blockProperty(blockID: paragraph.id, propertyKey: propertyKey),
            forcesReconciliation: false
        )

        let result = snapshot.render()
        guard case .block(let subtree) = result else {
            Issue.record("Expected a targeted block render")
            return
        }
        #expect(subtree.blockID == paragraph.id)
        #expect(HTMLPageRenderer().render(page: page, theme: .standard).contains(subtree.html))
    }

    @Test @MainActor
    func reusablePropertyMutationUsesPageFallback() {
        var paragraph = BlockNode.make(.paragraph)
        paragraph.reusableDefinitionID = UUID()
        let propertyKey = BlockProperty.Key(rawValue: "content")
        let page = Page(title: "Fallback", slug: "fallback", blocks: [paragraph])
        let snapshot = CanvasRenderSnapshot(
            renderer: HTMLPageRenderer(),
            page: page,
            language: "en",
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge,
            impact: .blockProperty(blockID: paragraph.id, propertyKey: propertyKey),
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
            "event": "selectBlock",
            "blockID": id.uuidString
        ]

        let message = CanvasMessage.decode(body)

        #expect(message?.event == .selectBlock)
        #expect(message?.blockID == id)
    }

    @Test
    func decodesPrimitiveSelectionMessage() {
        let blockID = UUID()
        let propertyKey = BlockProperty.Key(rawValue: "sourceRepeat3")

        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "selectPrimitive",
            "blockID": blockID.uuidString,
            "propertyKey": propertyKey.rawValue,
            "propertyPath": [2, 4]
        ])

        #expect(message?.event == .selectPrimitive)
        #expect(message?.blockID == blockID)
        #expect(message?.propertyKey == propertyKey)
        #expect(message?.propertyPath == [2, 4])
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "selectPrimitive",
            "blockID": blockID.uuidString
        ]) == nil)
    }

    @Test
    func rejectsUnsupportedAndMalformedMessages() {
        let id = UUID().uuidString

        #expect(CanvasMessage.decode([
            "version": 999,
            "event": "selectBlock",
            "blockID": id
        ]) == nil)
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "unknown",
            "blockID": id
        ]) == nil)
        #expect(CanvasMessage.decode("not an object") == nil)
    }

    @Test
    func decodesCanvasImageImportMessage() {
        let id = UUID()
        let propertyKey = BlockProperty.Key(rawValue: "sourceRepeat1")
        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "importImageAsset",
            "blockID": id.uuidString,
            "propertyKey": propertyKey.rawValue,
            "propertyPath": [3],
            "assetFilename": "hero.png",
            "assetMediaType": "image/png",
            "assetData": Data([1, 2, 3]).base64EncodedString()
        ])

        #expect(message?.event == .importImageAsset)
        #expect(message?.blockID == id)
        #expect(message?.propertyKey == propertyKey)
        #expect(message?.propertyPath == [3])
        #expect(message?.assetFilename == "hero.png")

        let assetID = UUID()
        let existingAssetMessage = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "importImageAsset",
            "blockID": id.uuidString,
            "propertyKey": propertyKey.rawValue,
            "assetID": assetID.uuidString
        ])
        #expect(existingAssetMessage?.assetID == assetID)
        #expect(existingAssetMessage?.propertyKey == propertyKey)
    }

    @Test
    func decodesCanvasBlockDeletionAndRejectsEmptyDeletion() {
        let ids = [UUID(), UUID()]
        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "deleteBlocks",
            "blockIDs": ids.map(\.uuidString)
        ])

        #expect(message?.event == .deleteBlocks)
        #expect(message?.blockIDs == ids)
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "deleteBlocks",
            "blockIDs": []
        ]) == nil)
    }

    @Test
    func decodesCanvasKeyboardSelectionActions() {
        let ids = [UUID(), UUID()]
        let actions: [(String, CanvasMessage.Event)] = [
            ("duplicateBlocks", .duplicateBlocks),
            ("copyBlocks", .copyBlocks),
            ("pasteBlocks", .pasteBlocks)
        ]
        for (event, expectedEvent) in actions {
            let message = CanvasMessage.decode([
                "version": CanvasMessage.currentVersion,
                "event": event,
                "blockIDs": ids.map(\.uuidString)
            ])

            #expect(message?.event == expectedEvent)
            #expect(message?.blockIDs == ids)
        }
        #expect(WebCanvasView.Coordinator.interactionScript.contains("event.metaKey"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("window.foundryEditBlock(blockID)"))
    }

    @Test @MainActor
    func rendererEmitsStableIdentityForEveryBlock() {
        let page = TestSiteFixtures.populatedSite().pages[0]
        let html = HTMLPageRenderer().render(page: page, theme: .standard)
        let blockIDs = flattened(page.blocks).map(\.id.uuidString)

        for id in blockIDs {
            #expect(html.contains("data-foundry-id=\"\(id)\""))
        }
        #expect(html.contains("data-foundry-block"))
        #expect(html.contains("data-foundry-package="))
        #expect(html.contains("data-foundry-type=\"Container\""))
        #expect(html.contains("data-foundry-type=\"Paragraph\""))
        #expect(html.contains("data-foundry-type=\"Button\""))
    }

    @Test @MainActor
    func subtreeRendererMatchesAuthoritativePageOutput() throws {
        var paragraph = BlockNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "content"), value: .string("Subtree value"))
        let page = Page(title: "Subtree", slug: "subtree", blocks: [paragraph])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            blockID: paragraph.id,
            page: page,
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ))
        let fullPage = renderer.render(page: page, theme: .standard)

        #expect(fullPage.contains(subtree.html))
        if !subtree.instanceCSS.isEmpty {
            #expect(fullPage.contains(subtree.instanceCSS))
        }
    }

    @Test @MainActor
    func subtreeRendererIncludesNestedDescendantsAndTheirStyles() throws {
        var child = BlockNode.make(.paragraph)
        child.setProperty(.init(rawValue: "content"), value: .string("Nested value"))
        var container = BlockNode.make(.container)
        container.children = [child]
        let page = Page(title: "Nested", slug: "nested", blocks: [container])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            blockID: container.id,
            page: page,
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ))
        let fullPage = renderer.render(page: page, theme: .standard)

        #expect(subtree.html.contains("data-foundry-id=\"\(child.id.uuidString)\""))
        #expect(subtree.html.contains("data-foundry-parent=\"\(container.id.uuidString)\""))
        #expect(fullPage.contains(subtree.html))
        if !subtree.instanceCSS.isEmpty {
            #expect(fullPage.contains(subtree.instanceCSS))
        }
    }

    @Test @MainActor
    func subtreeRendererPreservesInheritedGlobalIdentity() throws {
        let definitionID = UUID()
        let child = BlockNode.make(.paragraph)
        var globalContainer = BlockNode.make(.container)
        globalContainer.reusableDefinitionID = definitionID
        globalContainer.children = [child]
        let page = Page(title: "Global", slug: "global", blocks: [globalContainer])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            blockID: child.id,
            page: page,
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ))

        #expect(subtree.html.contains("data-foundry-global=\"\(definitionID.uuidString)\""))
        #expect(renderer.render(page: page, theme: .standard).contains(subtree.html))
        #expect(renderer.renderSubtree(
            blockID: UUID(),
            page: page,
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ) == nil)
    }

    @Test @MainActor
    func rendererMarksGlobalsNestedInsideNormalBlocks() {
        let definitionID = UUID()
        var global = BlockNode.make(.paragraph)
        global.reusableDefinitionID = definitionID
        var container = BlockNode.make(.container)
        container.children = [global]
        let page = Page(title: "Nested Global", slug: "nested-global", blocks: [container])

        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("data-foundry-id=\"\(global.id.uuidString)\""))
        #expect(html.contains("data-foundry-global=\"\(definitionID.uuidString)\""))
    }

    @Test @MainActor
    func emptyImageRendersAsAnExplicitDropTarget() {
        var image = BlockNode.make(.image)
        image.setProperty(.source, value: .url(""))
        let page = Page(title: "Images", slug: "images", blocks: [image])

        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("Drop image here"))
        #expect(html.contains("data-foundry-id=\"\(image.id.uuidString)\""))
    }

    @Test @MainActor
    func canvasServesAStillFirstFrameForManagedGIFsWithoutInliningIt() throws {
        let gifData = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
        let asset = ProjectAsset(filename: "animation.gif", mediaType: "image/gif", byteCount: gifData.count)
        var image = BlockNode.make(.image)
        image.setProperty(.source, value: .url(asset.reference))
        let page = Page(title: "GIF", slug: "gif", blocks: [image])

        let html = HTMLPageRenderer().render(
            page: page,
            language: "en",
            theme: .standard,
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
        let html = HTMLPageRenderer().render(page: page, theme: .standard)
        let interactionScript = WebCanvasView.Coordinator.interactionScript

        #expect(interactionScript.contains("foundry-show-titles"))
        #expect(interactionScript.contains("foundrySetEditorOptions"))
        #expect(interactionScript.contains("scrollsToSelection"))
        #expect(interactionScript.contains("shouldScroll"))
        #expect(interactionScript.contains("attachShadow"))
        #expect(interactionScript.contains("data-foundry-editor-chrome"))
        #expect(interactionScript.contains("data-foundry-editor-chrome', 'selection"))
        #expect(interactionScript.contains("position: 'fixed'"))
        #expect(interactionScript.contains("'left', Math.max(0, rect.left)"))
        #expect(interactionScript.contains("pointerEvents: 'none'"))
        #expect(interactionScript.contains("if (event.altKey) return;"))
        #expect(interactionScript.contains("selectedChromeTargets.push({"))
        #expect(interactionScript.contains("element: selectionElement"))
        #expect(interactionScript.contains("candidate.dataset.foundryPropertyPath"))
        #expect(interactionScript.contains("const globalChromeColor = '#30D158'"))
        #expect(interactionScript.contains("data-foundry-editor-chrome', 'editable"))
        #expect(interactionScript.contains("[data-foundry-inline-property]"))
        #expect(interactionScript.contains("const clickedEditable = event.target.closest('[data-foundry-inline-property]')"))
        #expect(!interactionScript.contains("block.querySelector('[data-foundry-inline-property]') !== null"))
        #expect(!html.contains("[data-foundry-id]:hover:not(:has([data-foundry-id]:hover))"))
        #expect(!html.contains("data-foundry-name); position: absolute"))
        #expect(!html.contains("position: relative; cursor: default"))
    }

    @Test
    func activatingStructureSelectsItsDockedTab() {
        var layout = WorkspaceLayout.standard

        layout.activate(.structure)

        #expect(layout.columns[0].selectedPanel == .structure)
    }

    private func flattened(_ nodes: [BlockNode]) -> [BlockNode] {
        nodes.flatMap { [$0] + flattened($0.children) }
    }
}
