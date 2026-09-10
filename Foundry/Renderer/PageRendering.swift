import Foundation

struct RenderedComponentSubtree: Equatable, Sendable {
    let componentID: UUID
    let html: String
    let instanceCSS: String
}

nonisolated protocol PageRendering: Sendable {
    func render(
        page: Page,
        language: String,
        theme: Theme,
        assets: [UUID: ProjectAssetContent],
        breakpoint: ResponsiveBreakpoint
    ) -> String
    func renderSubtree(
        componentID: UUID,
        page: Page,
        theme: Theme,
        assets: [UUID: ProjectAssetContent],
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedComponentSubtree?
}

extension PageRendering {
    func renderSubtree(
        componentID: UUID,
        page: Page,
        theme: Theme,
        assets: [UUID: ProjectAssetContent],
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedComponentSubtree? {
        nil
    }

    func render(page: Page, theme: Theme) -> String {
        render(page: page, language: "en", theme: theme, assets: [:], breakpoint: .extraLarge)
    }

    func render(page: Page, theme: Theme, assets: [UUID: ProjectAssetContent]) -> String {
        render(page: page, language: "en", theme: theme, assets: assets, breakpoint: .extraLarge)
    }
}
