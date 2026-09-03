import Foundation

@MainActor
protocol PageRendering {
    func render(
        page: Page,
        language: String,
        theme: Theme,
        assets: [UUID: ProjectAssetContent],
        breakpoint: ResponsiveBreakpoint
    ) -> String
}

extension PageRendering {
    func render(page: Page, theme: Theme) -> String {
        render(page: page, language: "en", theme: theme, assets: [:], breakpoint: .extraLarge)
    }

    func render(page: Page, theme: Theme, assets: [UUID: ProjectAssetContent]) -> String {
        render(page: page, language: "en", theme: theme, assets: assets, breakpoint: .extraLarge)
    }
}
