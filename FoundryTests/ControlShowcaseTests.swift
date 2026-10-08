import Foundation
import Testing
@testable import Foundry

/// The bundled Controls showcase: one hidden part per control and control
/// group, each carrying the snippets a developer copies to get started.
@Suite(.serialized)
struct ControlShowcaseTests {
    @MainActor
    private func showcasePackages() async -> [LoadedPartPackage] {
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        await catalog.loadControlShowcase()
        return catalog.packages.values.filter(\.isControlShowcase)
    }

    @Test @MainActor
    func showcaseLoadsOnDemandAndUnloadsAgain() async throws {
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        catalog.unloadControlShowcase()
        // Nothing at start-up (or after an unload): the pack costs nothing
        // until the Controls section asks for it.
        #expect(!catalog.hasControlShowcase)
        #expect(PartType(rawValue: "foundry.showcase.toggle").definition.renderKind == .unavailable)
        await catalog.loadControlShowcase()
        #expect(catalog.hasControlShowcase)
        #expect(PartType(rawValue: "foundry.showcase.toggle").definition.renderKind == .package)
        catalog.unloadControlShowcase()
        #expect(!catalog.hasControlShowcase)
        #expect(PartType(rawValue: "foundry.showcase.toggle").definition.renderKind == .unavailable)
    }

    @Test @MainActor
    func showcasePartsLoadCleanlyAndStayOutOfThePartsList() async throws {
        let packages = await showcasePackages()
        #expect(!packages.isEmpty)
        let catalog = PartPackageCatalog.shared
        for package in packages {
            // Built-ins may load without the full validation pass, so run it
            // here: a showcase that fails validation teaches the wrong thing.
            let validation = PartPackageValidator.validate(package.manifest, rootURL: package.resourceRootURL)
            let errors = ((catalog.diagnostics[package.rootURL] ?? []) + validation).filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(package.manifest.identifier): \(errors.map { "\($0.location): \($0.message)" })")
            #expect(package.isBuiltIn)
            #expect(!package.manifest.showsInPartLibrary)
            #expect(package.manifest.identifier.hasPrefix("foundry.showcase."))
            #expect(package.manifest.helpURL != nil, "\(package.manifest.identifier) links its reference page")
            // Every showcase ships its declaration, and its template usage
            // unless the control is Inspector-only and has none.
            let snippets = package.showcaseSnippets.map(\.id)
            let inspectorOnly = ["foundry.showcase.divider", "foundry.showcase.spacer", "foundry.showcase.note"]
            #expect(snippets.contains("json"), "\(package.manifest.identifier) snippets: \(snippets)")
            #expect(snippets.contains("html") || inspectorOnly.contains(package.manifest.identifier), "\(package.manifest.identifier) snippets: \(snippets)")
        }
    }

    @Test @MainActor
    func everyControlAndGroupHasAShowcase() async throws {
        let packages = await showcasePackages()
        let identifiers = Set(packages.map(\.manifest.identifier))
        // Separate font controls were folded into frameworkFont; the rest is
        // the developer's whole vocabulary.
        let withoutDedicatedShowcase: Set<PartPackageControl.Kind> = [.fontWeight, .fontStyle, .svg]
        for kind in PartPackageControl.Kind.allCases where !withoutDedicatedShowcase.contains(kind) {
            #expect(identifiers.contains(Self.showcaseIdentifier(for: kind.rawValue)), "No showcase for \(kind.rawValue)")
        }
        let groupsWithoutDedicatedShowcase: Set<PartPackageControlGroup.Kind> = [
            .transitions, .filters, .transforms, .linkOverlay, .lightbox
        ]
        for kind in PartPackageControlGroup.Kind.allCases where !groupsWithoutDedicatedShowcase.contains(kind) {
            #expect(identifiers.contains("foundry.showcase.\(kind.rawValue)"), "No showcase for the \(kind.rawValue) group")
        }
    }

    @Test @MainActor
    func everyShowcaseRendersItsSheetFromDefaults() async throws {
        let packages = await showcasePackages()
        for package in packages {
            // Child pickers start with their initial children in place.
            let part = PartNode.make(.init(rawValue: package.manifest.identifier))
            let site = Site(name: "Showcase", pages: [Page(title: "Home", slug: "index", parts: [part])])
            let html = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
            #expect(html.contains("foundry-showcase"), "\(package.manifest.identifier) did not render its sheet")
            // A leftover tag means an expression the renderer did not understand.
            #expect(!html.contains("{{"), "\(package.manifest.identifier) left a template tag unrendered")
            let css = StaticSiteRenderer().render(site: site).files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined()
            #expect(!css.contains("{{"), "\(package.manifest.identifier) left a template tag in its CSS")
        }
    }

    /// Part identifiers are lowercase reverse-DNS, so a camelCase control
    /// type becomes kebab-case: `textArea` → `foundry.showcase.text-area`.
    private static func showcaseIdentifier(for kind: String) -> String {
        var result = ""
        for character in kind {
            if character.isUppercase { result.append("-") }
            result.append(character.lowercased())
        }
        return "foundry.showcase." + result
    }

    @Test @MainActor
    func showingAControlUsesAnInMemoryScratchPage() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        await PartPackageCatalog.shared.loadControlShowcase()
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let authored = document.site.pages
        let toggle = PartType(rawValue: "foundry.showcase.toggle")
        let slider = PartType(rawValue: "foundry.showcase.slider")
        let first = try #require(editor.showControlShowcase(type: toggle))
        let second = try #require(editor.showControlShowcase(type: slider))
        #expect(first.pageID == second.pageID)
        let page = try #require(document.site.pages.first { $0.id == first.pageID })
        #expect(page.isDeveloperPlayground && !page.includeInNavigation && !page.includeInSitemap)
        // The page holds only the control being looked at.
        #expect(page.parts.map(\.type) == [slider])
        #expect(page.parts.first?.id == second.partID)

        // Scratch means scratch: not listed, not undoable, not saved, not exported.
        #expect(document.site.authoredPages == authored)
        #expect(!undoManager.canUndo)
        let wrapper = try FoundryDocument.makeFileWrapper(snapshot: document.snapshot(contentType: .foundryProject), existingFile: nil)
        let saved = try #require(wrapper.fileWrappers?["project.json"]?.regularFileContents)
        #expect(!String(decoding: saved, as: UTF8.self).contains("foundry.showcase."))
        let bundle = StaticSiteRenderer().render(site: document.site)
        #expect(!bundle.files.contains { $0.path.contains(page.slug) })
        #expect(!bundle.files.map(\.contents).joined().contains("foundry-showcase"))

        // Editing the shown control is scratch work too; moving on discards the page.
        editor.setProperty(id: second.partID, key: .init(rawValue: "amount"), value: .number(70))
        #expect(!undoManager.canUndo)
        editor.discardControlPlayground()
        #expect(document.site.pages == authored)
        #expect(!undoManager.canUndo)
    }
}
