import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct TypedCustomColourTests {
    @Test(.timeLimit(.minutes(1)), arguments: BootstrapColourKind.allCases)
    func customColoursBelongToTheirFamily(kind: BootstrapColourKind) async throws {
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "editorial", kind: kind)
        let palette = try #require(model.storedPalettes.first { $0.name == "editorial" })
        #expect(palette.colourKind == kind)
        var theme = Theme.standard
        theme.colourPalettes = model.storedPalettes
        #expect(BootstrapPaletteTheme.selectablePalettes(in: theme).contains(palette) == (kind == .theme))
        #expect(try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(palette)) == palette)
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(theme: theme, mode: .both)
        for mode in ["light", "dark"] {
            let expressions = palette.colourTokens.map { "var(--bs-\($0))" }
            let expected = kind.sourceTokens.map { "var(--bs-\($0))" }
            let values = try await BootstrapScalePreviewResolver().resolve(expressions: expressions + expected, css: css, mode: mode)
            #expect(Array(values.prefix(expressions.count)) == Array(values.suffix(expected.count)))
        }
        if kind != .theme {
            let groups = PartColourToken.groups(for: [kind.section], palettes: theme.colourPalettes)
            #expect(groups.flatMap { $0.1 }.suffix(palette.colourTokens.count) == palette.colourTokens[...])
            for token in palette.colourTokens { #expect(PartColourToken.parse("token:" + token) != nil) }
            model.renameTheme(id: palette.id, name: "renamed", undoManager: nil)
            #expect(model.storedPalettes.first { $0.id == palette.id }?.colourTokens == palette.colourTokens)
            #expect(model.storedPalettes.first { $0.id == palette.id }?.name == "renamed")
        }
        if kind == .link {
            let links = PartColourToken.groups(for: ["links"], palettes: theme.colourPalettes, linksOnly: true)
            #expect(links.first?.1 == ["link-color", palette.colourTokens[0]])
        }
    }

    @Test func pickerLabelsMatchCustomColourClasses() throws {
        for (kind, expected) in [
            (BootstrapColourKind.theme, "theme-new"),
            (.surface, "bg-new-body"),
            (.foreground, "fg-new-body"),
            (.border, "border-new-body"),
            (.link, "link-new")
        ] {
            let model = ThemeColourPreviewModel()
            model.addTheme(named: "new", kind: kind)
            let palette = try #require(model.storedPalettes.first { $0.origin == .custom })
            if kind == .theme {
                #expect(palette.pickerLabel == expected)
            } else {
                let token = try #require(palette.colourTokens.first)
                #expect(PartColourToken.label(token, palettes: [palette]) == expected)
                #expect(PartColourToken.label(token, palettes: [palette], linksOnly: true) == expected)
            }
        }
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "new", kind: .surface)
        let surface = try #require(model.storedPalettes.first { $0.origin == .custom })
        #expect(PartColourToken.label(surface.colourToken("bg-3"), palettes: [surface]) == "bg-new-3")
        model.addTheme(named: "links", kind: .link)
        let links = try #require(model.storedPalettes.first { $0.colourKind == .link })
        #expect(PartColourToken.label(links.colourToken("link-hover-color"), palettes: [links]) == "link-links-hover")
    }

    @Test func resetKeepsCustomColours() throws {
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "paper", kind: .surface)
        let custom = try #require(model.storedPalettes.first { $0.name == "paper" })
        var background = BootstrapColourCatalogue.palette(role: .background, hue: "pink")
        background.bootstrapTokens["bg-body"] = .init(light: .native("black"))
        model.update(.init(stored: background), session: UUID(), undoManager: nil)
        #expect(model.canReset(.surface))
        model.reset(.surface, undoManager: nil)
        #expect(model.storedPalettes.contains(custom))
        #expect(model.canReset(.surface) == false)
    }

    @Test func deletingInUseSwatchesReplacesTheirReferences() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "ink", kind: .foreground)
        let palette = try #require(model.storedPalettes.first { $0.name == "ink" })
        let document = FoundryDocument()
        document.site.theme.colourPalettes = model.storedPalettes
        var paragraph = PartNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "foreground.theme"), value: .choice("token:" + palette.colourTokens[2]))
        document.site.pages = [Page(title: "Test", slug: "index", parts: [paragraph])]
        let session = ThemeEditorSession(document: document, undoManager: nil)
        #expect(session.colourIsInUse(palette.id))
        session.deleteColour(palette.id, replacement: "framework.foreground")
        #expect(document.site.pages[0].parts[0].property(.init(rawValue: "foreground.theme")) == "token:fg-2")
        #expect(document.site.theme.colourPalettes.contains { $0.id == palette.id } == false)
    }

    @Test(.timeLimit(.minutes(1))) func customPaintTokensReachPartsInBothModes() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "ink", kind: .foreground)
        let foreground = try #require(model.storedPalettes.first { $0.name == "ink" })
        model.addTheme(named: "outline", kind: .border)
        let border = try #require(model.storedPalettes.first { $0.name == "outline" })
        var theme = Theme.standard
        theme.colourPalettes = model.storedPalettes
        var node = PartNode.make(.flex)
        node.anchor = "paint"
        node.setProperty(.init(rawValue: "foreground.theme"), value: .choice("token:" + foreground.colourTokens[1]))
        node.setProperty(.init(rawValue: "borders.theme"), value: .choice("token:" + border.colourTokens[2]))
        node.setProperty(.init(rawValue: "borders.colourEnabled"), value: .boolean(true))
        let browser = BootstrapTokenBrowser()
        try await browser.load(HTMLPageRenderer().render(page: Page(title: "Paint", slug: "index", parts: [node]), theme: theme))
        let result = try await browser.web.evaluateJavaScript("""
            (()=>{const a=document.getElementById('paint'),ref=document.createElement('span');document.body.append(ref);
            return ['light','dark'].map(mode=>{document.documentElement.dataset.bsTheme=mode;
              ref.style.color='var(--bs-fg-1)';ref.style.borderColor='var(--bs-border-muted)';
              return getComputedStyle(a).color===getComputedStyle(ref).color && getComputedStyle(a).borderTopColor===getComputedStyle(ref).borderTopColor;
            });})()
            """) as? [Bool]
        #expect(result == [true, true])
    }
}
