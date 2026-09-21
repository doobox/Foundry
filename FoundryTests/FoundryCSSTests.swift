import Foundation
import Testing
@testable import Foundry

@Suite("Foundry CSS")
@MainActor
struct FoundryCSSTests {
    private func build(_ framework: Framework) -> String {
        FoundryCSS.build(
            framework: framework,
            colour: { framework.color(for: $0) },
            colorScheme: "light"
        )
    }

    @Test func layersAreDeclaredInPrecedenceOrder() throws {
        let css = build(.standard)
        #expect(css.contains("@layer foundry.tokens, foundry.base, foundry.utilities;"))
        let tokens = try #require(css.range(of: "@layer foundry.tokens {"))
        let base = try #require(css.range(of: "@layer foundry.base {"))
        let utilities = try #require(css.range(of: "@layer foundry.utilities {"))
        #expect(tokens.lowerBound < base.lowerBound)
        #expect(base.lowerBound < utilities.lowerBound)
        #expect(css.contains("/* Foundry CSS 1 */"))
    }

    @Test func tokensIncludeEveryFrameworkScaleAndTheReservedAdditions() {
        let css = build(.standard)
        for token in ["--foundry-color-page:", "--foundry-color-muted:", "--foundry-color-brand:", "--foundry-font-body:",
                      "--foundry-font-size-base:", "--foundry-space-sm:", "--foundry-border-radius-md:",
                      "--foundry-border-width-sm:", "--foundry-z-index-", "--foundry-motion-fast:150ms",
                      "--foundry-motion-ease:cubic-bezier", "--foundry-focus-ring:2px solid var(--foundry-color-accent)",
                      "--foundry-container-width:"] {
            #expect(css.contains(token), "missing \(token)")
        }
    }

    @Test func baseLayerShipsTokenDrivenDefaults() {
        let css = build(.standard)
        // Reduced motion zeroes the motion tokens so every part honouring them complies.
        #expect(css.contains("@media (prefers-reduced-motion:reduce){:root{--foundry-motion-fast:0ms;--foundry-motion-normal:0ms;--foundry-motion-slow:0ms}}"))
        // Native form controls follow the accent role; long words cannot overflow.
        #expect(css.contains("accent-color:var(--foundry-color-accent)"))
        #expect(css.contains("overflow-wrap:break-word"))
        // The default focus style consumes the contract token rather than restating it.
        #expect(css.contains(":focus-visible{outline:var(--foundry-focus-ring);outline-offset:2px}"))
        #expect(css.contains("h1,h2,h3,h4,h5,h6{font-family:var(--foundry-font-heading);text-wrap:balance}"))
        // Preflight: user-agent margins never fight part spacing controls.
        #expect(css.contains("h1,h2,h3,h4,h5,h6,p,figure,dl,dd{margin:0}"))
        #expect(css.contains("ul,ol,menu{margin:0;padding-inline-start:var(--foundry-space-lg)}"))
        #expect(css.contains("border-width:0;border-style:solid;border-color:currentColor"))
        #expect(css.contains("::placeholder{color:var(--foundry-color-muted);opacity:1}"))
        // Plain HTML content with no part CSS still styles from tokens.
        #expect(css.contains("hr{border:none;border-top:1px solid color-mix(in srgb, var(--foundry-color-text) 20%, transparent);margin-block:var(--foundry-space-lg)}"))
        #expect(css.contains("blockquote{margin:var(--foundry-space-lg) 0;"))
        #expect(css.contains("table{border-collapse:collapse}"))
    }

    @Test func utilitiesMirrorTokensIncludingCustomOnes() {
        var framework = Framework.standard
        framework.spacing.custom.append(.init(name: "Hero Gap!", value: 40))
        let css = build(framework)
        #expect(css.contains(".fd-p-sm{padding:var(--foundry-space-sm)}"))
        #expect(css.contains(".fd-px-lg{padding-left:var(--foundry-space-lg);padding-right:var(--foundry-space-lg)}"))
        #expect(css.contains(".fd-mx-auto{margin-left:auto;margin-right:auto}"))
        #expect(css.contains(".fd-gap-md{gap:var(--foundry-space-md)}"))
        #expect(css.contains(".fd-p-hero-gap{padding:var("))
        #expect(css.contains(".fd-text-2xl{font-size:var(--foundry-font-size-2xl);line-height:var(--foundry-font-size-2xl-line-height)}"))
        #expect(css.contains(".fd-bg-surface{background-color:var(--foundry-color-surface)}"))
        #expect(css.contains(".fd-text-muted{color:var(--foundry-color-muted)}"))
        #expect(css.contains(".fd-radius-full{border-radius:var(--foundry-border-radius-full)}"))
        #expect(css.contains(".fd-border-sm{border:var(--foundry-border-width-sm) solid}"))
        #expect(css.contains(".fd-container{width:100%;max-width:var(--foundry-container-width);margin-inline:auto}"))
    }

    @Test func responsiveVariantsCoverOnlyEnabledScreens() {
        var framework = Framework.standard
        framework.screens.update(.medium) { $0.isEnabled = false }
        let css = build(framework)
        #expect(css.contains(".fd-sm\\:p-sm{padding:var(--foundry-space-sm)}"))
        #expect(css.contains(".fd-lg\\:text-xl{"))
        #expect(!css.contains(".fd-md\\:"))
    }

    @Test func slugsAreClassSafe() {
        #expect(FoundryCSS.slug("Hero Gap!") == "hero-gap")
        #expect(FoundryCSS.slug("  Wide -- Spacing  ") == "wide-spacing")
        #expect(FoundryCSS.slug("§§") == "token")
    }
}
