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
    func canvasDefinesDistinctComponentReconciliationAndReloadOperations() {
        let id = UUID()
        let subtree = RenderedComponentSubtree(componentID: id, html: "<div></div>", instanceCSS: "")
        let operations: [CanvasWebOperation] = [
            .component(subtree, revision: 4),
            .reconcilePage(html: "page", revision: 5),
            .reloadDocument(html: "page", revision: 6)
        ]

        #expect(operations.map(\.revision) == [4, 5, 6])
        #expect(WebCanvasView.Coordinator.interactionScript.contains("foundryReplaceComponent"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("data-foundry-instance-style"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("revision < latestFoundryRevision"))
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
    func ordinaryLocalPropertyMutationUsesAuthoritativeComponentPatch() throws {
        var paragraph = ComponentNode.make(.paragraph)
        let propertyKey = ComponentProperty.Key(rawValue: "content1")
        paragraph.setProperty(propertyKey, value: .string("Patched value"))
        let page = Page(title: "Patch", slug: "patch", components: [paragraph])
        let snapshot = CanvasRenderSnapshot(
            renderer: HTMLPageRenderer(),
            page: page,
            language: "en",
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge,
            impact: .componentProperty(componentID: paragraph.id, propertyKey: propertyKey),
            forcesReconciliation: false
        )

        let result = snapshot.render()
        guard case .component(let subtree) = result else {
            Issue.record("Expected a targeted component render")
            return
        }
        #expect(subtree.componentID == paragraph.id)
        #expect(HTMLPageRenderer().render(page: page, theme: .standard).contains(subtree.html))
    }

    @Test @MainActor
    func reusablePropertyMutationUsesPageFallback() {
        var paragraph = ComponentNode.make(.paragraph)
        paragraph.reusableDefinitionID = UUID()
        let propertyKey = ComponentProperty.Key(rawValue: "content1")
        let page = Page(title: "Fallback", slug: "fallback", components: [paragraph])
        let snapshot = CanvasRenderSnapshot(
            renderer: HTMLPageRenderer(),
            page: page,
            language: "en",
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge,
            impact: .componentProperty(componentID: paragraph.id, propertyKey: propertyKey),
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
            "event": "selectComponent",
            "componentID": id.uuidString
        ]

        let message = CanvasMessage.decode(body)

        #expect(message?.event == .selectComponent)
        #expect(message?.componentID == id)
    }

    @Test
    func decodesPrimitiveSelectionMessage() {
        let componentID = UUID()
        let propertyKey = ComponentProperty.Key(rawValue: "sourceRepeat3")

        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "selectPrimitive",
            "componentID": componentID.uuidString,
            "propertyKey": propertyKey.rawValue,
            "propertyPath": [2, 4]
        ])

        #expect(message?.event == .selectPrimitive)
        #expect(message?.componentID == componentID)
        #expect(message?.propertyKey == propertyKey)
        #expect(message?.propertyPath == [2, 4])
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "selectPrimitive",
            "componentID": componentID.uuidString
        ]) == nil)
    }

    @Test
    func rejectsUnsupportedAndMalformedMessages() {
        let id = UUID().uuidString

        #expect(CanvasMessage.decode([
            "version": 999,
            "event": "selectComponent",
            "componentID": id
        ]) == nil)
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "unknown",
            "componentID": id
        ]) == nil)
        #expect(CanvasMessage.decode("not an object") == nil)
    }

    @Test
    func decodesCanvasImageImportMessage() {
        let id = UUID()
        let propertyKey = ComponentProperty.Key(rawValue: "sourceRepeat1")
        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "importImageAsset",
            "componentID": id.uuidString,
            "propertyKey": propertyKey.rawValue,
            "propertyPath": [3],
            "assetFilename": "hero.png",
            "assetMediaType": "image/png",
            "assetData": Data([1, 2, 3]).base64EncodedString()
        ])

        #expect(message?.event == .importImageAsset)
        #expect(message?.componentID == id)
        #expect(message?.propertyKey == propertyKey)
        #expect(message?.propertyPath == [3])
        #expect(message?.assetFilename == "hero.png")

        let assetID = UUID()
        let existingAssetMessage = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "importImageAsset",
            "componentID": id.uuidString,
            "propertyKey": propertyKey.rawValue,
            "assetID": assetID.uuidString
        ])
        #expect(existingAssetMessage?.assetID == assetID)
        #expect(existingAssetMessage?.propertyKey == propertyKey)
    }

    @Test
    func decodesCanvasComponentDeletionAndRejectsEmptyDeletion() {
        let ids = [UUID(), UUID()]
        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "deleteComponents",
            "componentIDs": ids.map(\.uuidString)
        ])

        #expect(message?.event == .deleteComponents)
        #expect(message?.componentIDs == ids)
        #expect(CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "deleteComponents",
            "componentIDs": []
        ]) == nil)
    }

    @Test @MainActor
    func rendererEmitsStableIdentityForEveryComponent() {
        let page = TestSiteFixtures.populatedSite().pages[0]
        let html = HTMLPageRenderer().render(page: page, theme: .standard)
        let componentIDs = flattened(page.components).map(\.id.uuidString)

        for id in componentIDs {
            #expect(html.contains("data-foundry-id=\"\(id)\""))
        }
        #expect(html.contains("data-foundry-type=\"Container\""))
        #expect(html.contains("data-foundry-type=\"Paragraph\""))
        #expect(html.contains("data-foundry-type=\"Button\""))
    }

    @Test @MainActor
    func subtreeRendererMatchesAuthoritativePageOutput() throws {
        var paragraph = ComponentNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "content1"), value: .string("Subtree value"))
        let page = Page(title: "Subtree", slug: "subtree", components: [paragraph])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            componentID: paragraph.id,
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
        var child = ComponentNode.make(.paragraph)
        child.setProperty(.init(rawValue: "content1"), value: .string("Nested value"))
        var container = ComponentNode.make(.container)
        container.children = [child]
        let page = Page(title: "Nested", slug: "nested", components: [container])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            componentID: container.id,
            page: page,
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ))
        let fullPage = renderer.render(page: page, theme: .standard)

        #expect(subtree.html.contains("data-foundry-id=\"\(child.id.uuidString)\""))
        #expect(fullPage.contains(subtree.html))
        if !subtree.instanceCSS.isEmpty {
            #expect(fullPage.contains(subtree.instanceCSS))
        }
    }

    @Test @MainActor
    func subtreeRendererPreservesInheritedGlobalIdentity() throws {
        let definitionID = UUID()
        let child = ComponentNode.make(.paragraph)
        var globalContainer = ComponentNode.make(.container)
        globalContainer.reusableDefinitionID = definitionID
        globalContainer.children = [child]
        let page = Page(title: "Global", slug: "global", components: [globalContainer])
        let renderer = HTMLPageRenderer()

        let subtree = try #require(renderer.renderSubtree(
            componentID: child.id,
            page: page,
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ))

        #expect(subtree.html.contains("data-foundry-global=\"\(definitionID.uuidString)\""))
        #expect(renderer.render(page: page, theme: .standard).contains(subtree.html))
        #expect(renderer.renderSubtree(
            componentID: UUID(),
            page: page,
            theme: .standard,
            assets: [:],
            breakpoint: .extraLarge
        ) == nil)
    }

    @Test @MainActor
    func rendererMarksGlobalsNestedInsideNormalComponents() {
        let definitionID = UUID()
        var global = ComponentNode.make(.paragraph)
        global.reusableDefinitionID = definitionID
        var container = ComponentNode.make(.container)
        container.children = [global]
        let page = Page(title: "Nested Global", slug: "nested-global", components: [container])

        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("data-foundry-id=\"\(global.id.uuidString)\""))
        #expect(html.contains("data-foundry-global=\"\(definitionID.uuidString)\""))
    }

    @Test @MainActor
    func emptyImageRendersAsAnExplicitDropTarget() {
        var image = ComponentNode.make(.image)
        image.setProperty(.source, value: .url(""))
        let page = Page(title: "Images", slug: "images", components: [image])

        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("Drop image here"))
        #expect(html.contains("data-foundry-id=\"\(image.id.uuidString)\""))
    }

    @Test @MainActor
    func canvasServesAStillFirstFrameForManagedGIFsWithoutInliningIt() throws {
        let gifData = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
        let asset = ProjectAsset(filename: "animation.gif", mediaType: "image/gif", byteCount: gifData.count)
        var image = ComponentNode.make(.image)
        image.setProperty(.source, value: .url(asset.reference))
        let page = Page(title: "GIF", slug: "gif", components: [image])

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

        #expect(WebCanvasView.Coordinator.interactionScript.contains("foundry-show-titles"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("foundrySetEditorOptions"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("scrollsToSelection"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("shouldScroll"))
        #expect(!WebCanvasView.Coordinator.interactionScript.contains("attachShadow"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("data-foundry-editor-chrome"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("data-foundry-editor-chrome', 'selection"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("position: 'fixed'"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("'left', Math.max(0, rect.left)"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("pointerEvents: 'none'"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("if (event.altKey) return;"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("selectedChromeTargets.push({"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("element,\n        color: editorChromeColor"))
        #expect(!WebCanvasView.Coordinator.interactionScript.contains("const selectedElement = primitive || element"))
        #expect(!html.contains("[data-foundry-id]:hover:not(:has([data-foundry-id]:hover))"))
        #expect(!html.contains("data-foundry-name); position: absolute"))
    }

    @Test
    func activatingStructureSelectsItsDockedTab() {
        var layout = WorkspaceLayout.standard

        layout.activate(.structure)

        #expect(layout.columns[0].selectedPanel == .structure)
    }

    private func flattened(_ nodes: [ComponentNode]) -> [ComponentNode] {
        nodes.flatMap { [$0] + flattened($0.children) }
    }
}
