import Foundation
import Testing
@testable import Foundry

struct CanvasBridgeTests {
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
        let message = CanvasMessage.decode([
            "version": CanvasMessage.currentVersion,
            "event": "importImageAsset",
            "componentID": id.uuidString,
            "assetFilename": "hero.png",
            "assetMediaType": "image/png",
            "assetData": Data([1, 2, 3]).base64EncodedString()
        ])

        #expect(message?.event == .importImageAsset)
        #expect(message?.componentID == id)
        #expect(message?.assetFilename == "hero.png")
    }

    @Test @MainActor
    func rendererEmitsStableIdentityForEveryComponent() {
        let page = Site.starter().pages[0]
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

        #expect(html.contains("Drop an image here"))
        #expect(html.contains("data-foundry-id=\"\(image.id.uuidString)\""))
    }

    @Test @MainActor
    func canvasRendererIncludesEditorOptionHooks() {
        let page = Site.starter().pages[0]
        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(WebCanvasView.Coordinator.interactionScript.contains("foundry-show-titles"))
        #expect(html.contains("foundry-show-outlines"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("foundrySetEditorOptions"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("scrollsToSelection"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("attachShadow({ mode: 'closed' })"))
        #expect(WebCanvasView.Coordinator.interactionScript.contains("pointer-events', 'none'"))
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
