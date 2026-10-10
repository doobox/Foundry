import CryptoKit
import Foundation
import Testing
@testable import Foundry

/// Bootstrap ships untouched; every Foundry addition is separate CSS emitted by Swift.
struct BootstrapBundledLibraryTests {
    private static let version = "6.0.0-alpha.1"
    private static let cssChecksum = "678508b198d9b1b8877e338f419fdada00024be2bcc638a539dd724856095112"
    private static let javaScriptChecksum = "47ea447f46e288dd9d3e83147b7ba539c6df5192c047b8f91739cd56a5721148"

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func bundledBootstrapIsTheOfficialBuildWithoutAdditions() throws {
        let css = FoundryWebLibraryRegistry.canvasCSS(for: [])
        #expect(css == FoundryWebLibraryRegistry.exportCSS(for: []))
        #expect(sha256(Data(css.utf8)) == Self.cssChecksum)
        #expect(css.hasPrefix(":root,:host{--bs-blue-025:"))
        #expect(css.contains("foundry") == false)
        // Selectors Foundry's parts, control groups and extensions rely on.
        for selector in [".btn-solid{", ".card{", ".card-body{", ".theme-primary{", ".p-5{padding:1rem}", ".gap-5{gap:1rem}",
                         ".md\\:text-center{", ".fs-lg{", ".text-lg{", ".fw-bold{", ".text-truncate{", ".container{",
                         ".md\\:container", ".\\32 xl\\:container", ".rounded-5{", ".shadow-sm{", ".z-menu{", "--bs-spacer-5:",
                         "--bs-font-size-lg:", "--bs-line-height-lg:", "--bs-font-weight-bold:", "--bs-radius-7:"] {
            #expect(css.contains(selector), "Bootstrap \(Self.version) no longer ships \(selector)")
        }
        let script = try #require(FoundryWebLibraryRegistry.exportFiles(for: []).first {
            $0.path.hasSuffix("bootstrap-\(Self.version).bundle.min.js")
        })
        #expect(sha256(script.data) == Self.javaScriptChecksum)
    }

    @Test func foundryAdditionsAreEmittedSeparately() {
        let theme = BootstrapThemeCSS.render(framework: .standard)
        #expect(theme.contains(".md\\:fs-lg{font-size:var(--bs-font-size-lg)}"))
        #expect(theme.contains(".md\\:text-lg{font-size:var(--bs-font-size-lg);line-height:var(--bs-line-height-lg)}"))
        #expect(theme.contains(".\\32 xl\\:fw-bold{font-weight:var(--bs-font-weight-bold)}"))
        #expect(theme.contains(".text-truncate{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-wrap:nowrap}"))
        #expect(theme.contains("@media (width >= 768px){") && theme.contains(".md\\:text-wrap{overflow:visible;text-overflow:clip;white-space:normal;text-wrap:wrap}"))
        // The default framework stops at large, so containers hold at 960px above it.
        #expect(theme.contains("@layer layout{@media (width >= 1280px){.container,.sm\\:container,.md\\:container,.lg\\:container,.xl\\:container{max-width:960px}}@media (width >= 1536px){.container,.sm\\:container,.md\\:container,.lg\\:container,.xl\\:container,.\\32 xl\\:container{max-width:960px}}}"))
        // Bootstrap's own spacing utilities are only re-emitted for sites with custom spacers.
        #expect(BootstrapSpacingCSS.render(.standard).isEmpty)
        #expect(theme.contains("--bs-spacer-5") == false)
        var framework = Framework.standard
        framework.spacing.custom = [.init(name: "hero", value: 2)]
        for id in BootstrapLayout.ids { framework.screens.update(id) { $0.isEnabled = true } }
        let extended = BootstrapThemeCSS.render(framework: framework)
        #expect(extended.contains("--bs-spacer-hero: 2.0rem"))
        #expect(extended.contains(".p-hero{padding:var(--bs-spacer-hero)}"))
        #expect(BootstrapUtilityExtensionsCSS.containerCSS(framework.screens).isEmpty)
    }
}
