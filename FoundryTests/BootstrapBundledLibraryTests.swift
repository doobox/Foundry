import CryptoKit
import Foundation
import Testing
@testable import Foundry

/// Pin the official Bootstrap CSS and JavaScript.
struct BootstrapBundledLibraryTests {
    private static let version = "6.0.0-alpha.1"
    private static let cssChecksum = "678508b198d9b1b8877e338f419fdada00024be2bcc638a539dd724856095112"
    private static let javaScriptChecksum = "47ea447f46e288dd9d3e83147b7ba539c6df5192c047b8f91739cd56a5721148"

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func bundledBootstrapIsTheOfficialBuildWithoutAdditions() throws {
        let cssData = try #require(FoundryWebLibraryRegistry.resourceData(at: "bootstrap-\(Self.version).min.css"))
        let css = String(decoding: cssData, as: UTF8.self)
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
        let script = try #require(FoundryWebLibraryRegistry.resourceData(at: "bootstrap-\(Self.version).bundle.min.js"))
        #expect(sha256(script) == Self.javaScriptChecksum)
    }

    @Test func generatedBootstrapOmitsOnlyUnavailableSourceMapReferences() throws {
        let originalCSS = String(decoding: try #require(FoundryWebLibraryRegistry.resourceData(at: "bootstrap-\(Self.version).min.css")), as: UTF8.self)
        let originalJS = String(decoding: try #require(FoundryWebLibraryRegistry.resourceData(at: "bootstrap-\(Self.version).bundle.min.js")), as: UTF8.self)
        let css = try #require(FoundryWebLibraryRegistry.exportFiles(for: []).first {
            $0.path == FoundryWebLibraryRegistry.bootstrapStylesheetPath
        }).contents
        let script = try #require(FoundryWebLibraryRegistry.exportFiles(for: []).first {
            $0.path.hasSuffix("bootstrap-\(Self.version).bundle.min.js")
        })
        #expect(sha256(Data(originalCSS.utf8)) == Self.cssChecksum)
        #expect(originalCSS.contains("sourceMappingURL="))
        #expect(originalCSS.contains(".p-13{") == false)
        #expect(originalJS.contains("sourceMappingURL="))
        #expect(css.contains("sourceMappingURL=") == false)
        #expect(script.contents.contains("sourceMappingURL=") == false)
        #expect(css == originalCSS.replacingOccurrences(of: "/*# sourceMappingURL=bootstrap.min.css.map */", with: ""))
        #expect(script.contents == originalJS.replacingOccurrences(of: "//# sourceMappingURL=bootstrap.bundle.min.js.map", with: ""))
    }

    @Test @MainActor func bootstrapIsLinkedBeforeSiteAndPageStylesAtEveryDepth() throws {
        let site = Site(name: "Linked Bootstrap", pages: [
            Page(title: "Home", slug: "index"), Page(title: "About", slug: "about")
        ])
        for environment in [PartTemplateEnvironment.preview, .published] {
            let bundle = StaticSiteRenderer(environment: environment).render(site: site)
            #expect(bundle.errors.isEmpty)
            let vendorPath = FoundryWebLibraryRegistry.bootstrapStylesheetPath
            #expect(bundle.files.filter { $0.path == vendorPath }.count == 1)
            let vendor = try #require(bundle.file(at: vendorPath)?.contents)
            #expect(vendor.contains(".btn-solid{"))
            let siteCSS = try #require(bundle.file(at: "files/site.css")?.contents)
            #expect(siteCSS.contains(vendor) == false)
            for (path, prefix) in [("index.html", ""), ("about/index.html", "../")] {
                let html = try #require(bundle.file(at: path)?.contents)
                let bootstrap = try #require(html.range(of: "href=\"" + prefix + vendorPath))
                let shared = try #require(html.range(of: "href=\"" + prefix + "files/site.css"))
                let page = try #require(html.range(of: "href=\"files/page.css"))
                #expect(bootstrap.lowerBound < shared.lowerBound)
                #expect(shared.lowerBound < page.lowerBound)
            }
        }
    }

    @Test func foundryAdditionsAreEmittedSeparately() {
        let themeCSS = BootstrapThemeCSS.render(theme: .standard)
        #expect(themeCSS.contains(".md\\:fs-lg{font-size:var(--bs-font-size-lg)}"))
        #expect(themeCSS.contains(".md\\:text-lg{font-size:var(--bs-font-size-lg);line-height:var(--bs-line-height-lg)}"))
        #expect(themeCSS.contains(".\\32 xl\\:fw-bold{font-weight:var(--bs-font-weight-bold)}"))
        #expect(themeCSS.contains(".text-truncate{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-wrap:nowrap}"))
        #expect(themeCSS.contains("@media (width >= 768px){") && themeCSS.contains(".md\\:text-wrap{overflow:visible;text-overflow:clip;white-space:normal;text-wrap:wrap}"))
        // The default theme stops at large, so containers hold at 960px above it.
        #expect(themeCSS.contains("@layer layout{@media (width >= 1280px){.container,.sm\\:container,.md\\:container,.lg\\:container,.xl\\:container{max-width:960px}}@media (width >= 1536px){.container,.sm\\:container,.md\\:container,.lg\\:container,.xl\\:container,.\\32 xl\\:container{max-width:960px}}}"))
        // Bootstrap's own spacing utilities are only re-emitted for sites with custom spacers.
        #expect(BootstrapSpacingCSS.render(.standard).isEmpty)
        #expect(themeCSS.contains("--bs-spacer-5") == false)
        var theme = Theme.standard
        theme.spacing.custom = [.init(name: "hero", value: 2)]
        for id in BootstrapLayout.ids { theme.screens.update(id) { $0.isEnabled = true } }
        let extended = BootstrapThemeCSS.render(theme: theme)
        #expect(extended.contains("--bs-spacer-hero: 2.0rem"))
        #expect(extended.contains(".p-hero{padding:var(--bs-spacer-hero)}"))
        #expect(BootstrapUtilityExtensionsCSS.containerCSS(theme.screens).isEmpty)
    }
}
