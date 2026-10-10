import Foundation

nonisolated struct RenderedPartSubtree: Equatable, Sendable {
    let partID: UUID
    let html: String
    /// Scoped CSS per part instance in the subtree, keyed by instance ID.
    /// Each instance owns exactly one `<style>` in the canvas, so patches to
    /// nested parts can never shadow one another's later updates.
    let instanceStyles: [String: String]
}

nonisolated protocol PageRendering: Sendable {
    func render(
        page: Page,
        language: String,
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> String
    func renderSubtree(
        partID: UUID,
        page: Page,
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedPartSubtree?
}

extension PageRendering {
    func renderSubtree(
        partID: UUID,
        page: Page,
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedPartSubtree? {
        nil
    }

    func render(page: Page, framework: Framework) -> String {
        render(page: page, language: "en", framework: framework, assets: [:], breakpoint: .extraLarge)
    }

    func render(page: Page, framework: Framework, assets: ProjectAssetContents) -> String {
        render(page: page, language: "en", framework: framework, assets: assets, breakpoint: .extraLarge)
    }
}
