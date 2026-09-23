import Foundation
import Testing
@testable import Foundry

@MainActor
struct ReusablePartLibraryTests {
    private func temporaryLibrary() -> ReusablePartLibrary {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FoundryReusableLibrary-\(UUID().uuidString)", directoryHint: .isDirectory)
        return ReusablePartLibrary(directoryURL: directory)
    }

    private func documentWithAsset() -> (FoundryDocument, UUID) {
        let document = FoundryDocument(site: Site.starter())
        let assetID = document.importAsset(
            data: Data([9, 9, 9, 1]),
            filename: "banner.bin",
            mediaType: "application/octet-stream",
            undoManager: nil
        )
        return (document, assetID)
    }

    @Test
    func savingWritesASelfContainedBundleAndLatestSaveWins() throws {
        let library = temporaryLibrary()
        let (document, assetID) = documentWithAsset()
        var root = PartNode.make(.container)
        root.setProperty(.init(rawValue: "image"), value: .url("foundry-asset:\(assetID.uuidString)"))
        let definition = ReusablePartDefinition(name: "Hero", root: root)

        #expect(ReusablePartLibrary.referencedAssetIDs(in: definition) == [assetID])

        library.save(definition: definition, assetContents: document.assetContents)
        #expect(library.entries.map(\.name) == ["Hero"])
        #expect(library.entries.first?.assets.map(\.id) == [assetID])

        var renamed = definition
        renamed.name = "Hero Banner"
        library.save(definition: renamed, assetContents: document.assetContents)
        #expect(library.entries.map(\.name) == ["Hero Banner"])

        // A fresh instance over the same directory sees the same entries.
        let reloaded = ReusablePartLibrary(directoryURL: library.bundleURL(forID: definition.id).deletingLastPathComponent())
        #expect(reloaded.entries.map(\.name) == ["Hero Banner"])
        #expect(reloaded.entry(withID: definition.id)?.definition.root.id == root.id)
    }

    @Test
    func renameAndDeleteManageBundles() throws {
        let library = temporaryLibrary()
        let (document, _) = documentWithAsset()
        let definition = ReusablePartDefinition(name: "Footer", root: PartNode.make(.section))
        library.save(definition: definition, assetContents: document.assetContents)

        library.rename(id: definition.id, to: "Site Footer")
        #expect(library.entries.map(\.name) == ["Site Footer"])

        library.delete(id: definition.id)
        #expect(library.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.bundleURL(forID: definition.id).path))
    }

    @Test
    func importingRemapsAssetsAndReusesIdenticalContent() throws {
        let library = temporaryLibrary()
        let (sourceDocument, sourceAssetID) = documentWithAsset()
        var root = PartNode.make(.container)
        root.setProperty(.init(rawValue: "image"), value: .url("foundry-asset:\(sourceAssetID.uuidString)"))
        let definition = ReusablePartDefinition(name: "Hero", root: root)
        library.save(definition: definition, assetContents: sourceDocument.assetContents)
        let entry = try #require(library.entry(withID: definition.id))

        let targetDocument = FoundryDocument(site: Site.starter())
        let imported = try #require(
            library.importedDefinition(for: entry, into: targetDocument, undoManager: nil)
        )
        let importedAssets = targetDocument.site.assets
        #expect(importedAssets.count == 1)
        let importedAssetID = try #require(importedAssets.first?.id)
        #expect(importedAssetID != sourceAssetID)
        #expect(ReusablePartLibrary.referencedAssetIDs(in: imported) == [importedAssetID])
        // The definition keeps its identity so repeated inserts reuse it.
        #expect(imported.id == definition.id)

        // Importing again adds no duplicate asset bytes.
        _ = library.importedDefinition(for: entry, into: targetDocument, undoManager: nil)
        #expect(targetDocument.site.assets.count == 1)
    }

    @Test
    func savingFromOneProjectStampsIntoAnother() throws {
        let library = temporaryLibrary()
        let site = TestSiteFixtures.populatedSite()
        let sourceDocument = FoundryDocument(site: site)
        let sourceEditor = ProjectEditor(document: sourceDocument, undoManager: nil)
        let sourcePart = try #require(site.pages.first?.parts.first)
        let definition = try #require(
            sourceEditor.templateDefinition(fromPartID: sourcePart.id, name: "Hero")
        )
        library.save(definition: definition, assetContents: sourceDocument.assetContents)

        let targetDocument = FoundryDocument(site: Site.starter())
        let targetEditor = ProjectEditor(document: targetDocument, undoManager: nil)
        let entry = try #require(library.entry(withID: definition.id))
        let imported = try #require(
            library.importedDefinition(for: entry, into: targetDocument, undoManager: nil)
        )
        let insertedID = try #require(
            targetEditor.insertTemplate(
                imported,
                on: targetDocument.site.pages[0].id,
                placement: .end
            )
        )
        let inserted = try #require(targetDocument.site.part(withID: insertedID))
        #expect(inserted.children.count == definition.root.children.count)
        // The target project stores only the stamped copy — templates live on disk.
        #expect(inserted.reusableDefinitionID == nil)
    }

    @Test
    func organizationSupportsFoldersOrderingAndSurvivesReload() throws {
        let library = temporaryLibrary()
        let (document, _) = documentWithAsset()
        let hero = ReusablePartDefinition(name: "Hero", root: PartNode.make(.container))
        let footer = ReusablePartDefinition(name: "Footer", root: PartNode.make(.section))
        library.save(definition: hero, assetContents: document.assetContents)
        library.save(definition: footer, assetContents: document.assetContents)

        let folderID = try #require(library.createFolder(name: "Sections"))
        #expect(library.moveNode(id: hero.id, to: .inside(folderID: folderID)))
        #expect(!library.moveNode(id: folderID, to: .inside(folderID: folderID)))
        library.renameFolder(id: folderID, to: "Hero Sections")

        // The panel tree resolves folders and templates in stored order.
        guard case .folder(let folder)? = library.organizedNodes.last(where: { $0.id == folderID }) else {
            Issue.record("expected folder in organized nodes")
            return
        }
        #expect(folder.name == "Hero Sections")
        #expect(folder.children.map(\.id) == [hero.id])

        // A fresh instance over the same directory sees the same organization.
        let reloaded = ReusablePartLibrary(directoryURL: library.bundleURL(forID: hero.id).deletingLastPathComponent())
        #expect(reloaded.organizedNodes == library.organizedNodes)

        // Deleting the folder removes the bundles it contained.
        library.deleteFolder(id: folderID)
        #expect(library.entry(withID: hero.id) == nil)
        #expect(library.entries.map(\.id) == [footer.id])
    }

    @Test
    func chosenFoldersGainAFoundryDirectoryUnlessAlreadyALibrary() throws {
        let fileManager = FileManager.default
        let plain = fileManager.temporaryDirectory
            .appending(path: "Chosen-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: plain, withIntermediateDirectories: true)
        #expect(FoundryLibraryLocation.resolvedRoot(forChosen: plain).lastPathComponent == "Foundry")

        let named = plain.appending(path: "Foundry", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: named, withIntermediateDirectories: true)
        #expect(FoundryLibraryLocation.resolvedRoot(forChosen: named) == named)

        // A folder already holding library content is used as-is.
        let existing = fileManager.temporaryDirectory
            .appending(path: "Existing-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: existing.appending(path: "Packs", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        #expect(FoundryLibraryLocation.resolvedRoot(forChosen: existing) == existing)
    }

    @Test
    func changingTheLibraryLocationCopiesContentWithoutOverwriting() throws {
        let fileManager = FileManager.default
        let oldRoot = fileManager.temporaryDirectory
            .appending(path: "FoundryLibraryOld-\(UUID().uuidString)", directoryHint: .isDirectory)
        let newRoot = fileManager.temporaryDirectory
            .appending(path: "FoundryLibraryNew-\(UUID().uuidString)", directoryHint: .isDirectory)
        let oldPacks = oldRoot.appending(path: "Packs", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: oldPacks, withIntermediateDirectories: true)
        try Data("pack".utf8).write(to: oldPacks.appending(path: "Gallery.foundrypack"))
        try Data("old".utf8).write(to: oldPacks.appending(path: "Existing.foundrypack"))
        let newPacks = newRoot.appending(path: "Packs", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: newPacks, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: newPacks.appending(path: "Existing.foundrypack"))

        FoundryLibraryLocation.migrateContent(from: oldRoot, to: newRoot)

        // Missing content copies across; the source keeps its files.
        #expect(fileManager.fileExists(atPath: newPacks.appending(path: "Gallery.foundrypack").path))
        #expect(fileManager.fileExists(atPath: oldPacks.appending(path: "Gallery.foundrypack").path))
        // Content already at the destination is never overwritten.
        #expect(try Data(contentsOf: newPacks.appending(path: "Existing.foundrypack")) == Data("keep".utf8))
    }

    @Test
    func projectTemplatesLiveInTheDocumentAndSupportUndo() throws {
        let page = Page(title: "Home", slug: "index", parts: [PartNode.make(.container)])
        let document = FoundryDocument(site: Site(name: "Project", pages: [page]))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let partID = try #require(document.site.pages.first?.parts.first?.id)
        let definition = try #require(editor.templateDefinition(fromPartID: partID, name: "Hero"))

        undoManager.beginUndoGrouping()
        #expect(editor.addProjectTemplate(definition))
        undoManager.endUndoGrouping()
        #expect(document.site.projectTemplateLibrary.allDefinitions.map(\.name) == ["Hero"])

        // Project templates persist inside project.json like any other site data.
        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.projectTemplateLibrary == document.site.projectTemplateLibrary)

        undoManager.beginUndoGrouping()
        editor.renameProjectTemplate(id: definition.id, to: "Header")
        undoManager.endUndoGrouping()
        #expect(document.site.projectTemplateLibrary.allDefinitions.first?.name == "Header")
        undoManager.undo()
        #expect(document.site.projectTemplateLibrary.allDefinitions.first?.name == "Hero")
        undoManager.undo()
        #expect(document.site.projectTemplateLibrary.isEmpty)

        // Folders organize project templates exactly like the pack library.
        func grouped<Result>(_ mutation: () -> Result) -> Result {
            undoManager.beginUndoGrouping()
            defer { undoManager.endUndoGrouping() }
            return mutation()
        }
        _ = grouped { editor.addProjectTemplate(definition) }
        let folderID = try #require(grouped { editor.createProjectTemplateFolder(named: "Sections") })
        #expect(grouped { editor.moveProjectTemplateNode(id: definition.id, to: .inside(folderID: folderID)) })
        guard case .folder(let folder)? = document.site.projectTemplateLibrary.node(withID: folderID) else {
            Issue.record("expected folder in project template library")
            return
        }
        #expect(folder.children.map(\.id) == [definition.id])
    }

    @Test
    func duplicateCreatesAnIndependentBundleAfterTheOriginal() throws {
        let library = temporaryLibrary()
        let (document, _) = documentWithAsset()
        let hero = ReusablePartDefinition(name: "Hero", root: PartNode.make(.container))
        library.save(definition: hero, assetContents: document.assetContents)

        library.duplicate(id: hero.id)

        #expect(library.entries.map(\.name).sorted() == ["Hero", "Hero Copy"])
        let copy = try #require(library.entries.first { $0.name == "Hero Copy" })
        #expect(copy.id != hero.id)
        #expect(copy.definition.root.id != hero.root.id)
        #expect(library.organizedNodes.map(\.id) == [hero.id, copy.id])
    }
}
