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
        theme: Theme,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> String
    func renderSubtree(
        partID: UUID,
        page: Page,
        theme: Theme,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedPartSubtree?
}

extension PageRendering {
    func renderSubtree(
        partID: UUID,
        page: Page,
        theme: Theme,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedPartSubtree? {
        nil
    }

    func render(page: Page, theme: Theme) -> String {
        render(page: page, language: "en", theme: theme, assets: [:], breakpoint: .extraLarge)
    }

    func render(page: Page, theme: Theme, assets: ProjectAssetContents) -> String {
        render(page: page, language: "en", theme: theme, assets: assets, breakpoint: .extraLarge)
    }
}
