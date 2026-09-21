import Foundation
import Testing
@testable import Foundry

@MainActor
struct ReusablePartTests {
    @Test
    func insertingATemplateStampsAFreshIndependentTree() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        let definition = try #require(
            editor.templateDefinition(fromPartID: source.id, name: "Hero")
        )
        #expect(definition.root.id != source.id)

        let insertedID = try #require(
            editor.insertTemplate(definition, on: site.pages[0].id, placement: .end)
        )
        let inserted = try #require(document.site.part(withID: insertedID))

        #expect(inserted.reusableDefinitionID == nil)
        #expect(inserted.id != source.id)
        #expect(inserted.id != definition.root.id)
        #expect(inserted.children.map(\.id) != definition.root.children.map(\.id))
    }

    @Test
    func detachKeepsLocalContentAndRemovesOnlyTheLink() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let before = try #require(document.site.part(withID: source.id))

        editor.detachReusablePart(partID: source.id)
        let after = try #require(document.site.part(withID: source.id))

        #expect(after.reusableDefinitionID == nil)
        #expect(after.name == before.name)
        #expect(after.children == before.children)
    }

    @Test
    func stampedTemplateInstancesRemainIndependentOfTheSource() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definition = try #require(
            editor.templateDefinition(fromPartID: source.id, name: "Hero")
        )
        let secondID = try #require(
            editor.insertTemplate(definition, on: site.pages[0].id, placement: .end)
        )
        editor.renamePart(id: source.id, name: "Updated Hero")

        #expect(document.site.part(withID: source.id)?.name == "Updated Hero")
        #expect(document.site.part(withID: secondID)?.name == "Hero")
        #expect(definition.root.name == "Hero")
    }

    @Test
    func globalEditingUpdatesEveryInstanceInOneMutation() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(
            editor.saveGlobalPart(partID: source.id, name: "Hero")
        )
        let secondID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        editor.renameSharedReusablePartInstance(partID: source.id, name: "Shared Hero")

        #expect(document.site.part(withID: source.id)?.name == "Shared Hero")
        #expect(document.site.part(withID: secondID)?.name == "Shared Hero")
        #expect(document.site.globalParts.first?.root.name == "Shared Hero")
    }

    @Test
    func globalsRoundTripThroughProjectJSON() throws {
        var site = Site.starter()
        let global = ReusablePartDefinition(name: "Header", root: PartNode.make(.container))
        site.globalPartLibrary = [.part(global)]

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.globalParts == [global])
    }

    @Test
    func globalPartFoldersOrganizeAndDeletingAFolderDetachesInstances() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let folderID = try #require(editor.createGlobalPartFolder(named: "Sections"))

        #expect(editor.moveGlobalPartNode(id: definitionID, to: .inside(folderID: folderID)))
        guard case .folder(let folder)? = document.site.globalPartLibrary.node(withID: folderID) else {
            Issue.record("Folder missing from the global part library")
            return
        }
        #expect(folder.children.map(\.id) == [definitionID])
        #expect(document.site.globalParts.map(\.id) == [definitionID])

        // A folder can never move inside itself or its own subtree.
        #expect(!editor.moveGlobalPartNode(id: folderID, to: .inside(folderID: folderID)))

        editor.deleteGlobalPartFolder(id: folderID)
        #expect(document.site.globalParts.isEmpty)
        #expect(document.site.part(withID: source.id)?.reusableDefinitionID == nil)
    }

    @Test
    func duplicatingAGlobalPartCreatesAnIndependentCopyBesideTheOriginal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let copyID = try #require(editor.duplicateGlobalPart(definitionID: definitionID))

        #expect(copyID != definitionID)
        #expect(document.site.globalPartLibrary.map(\.id) == [definitionID, copyID])
        let copy = try #require(document.site.globalParts.first { $0.id == copyID })
        #expect(copy.name == "Hero Copy")
        #expect(copy.root.id != document.site.globalParts.first { $0.id == definitionID }?.root.id)

        // Renaming the copy leaves the original untouched.
        editor.renameGlobalPart(definitionID: copyID, name: "Banner")
        #expect(document.site.globalParts.first { $0.id == definitionID }?.name == "Hero")
        #expect(document.site.globalParts.first { $0.id == copyID }?.name == "Banner")
    }

    @Test
    func editingNestedGlobalContentUpdatesEveryInstanceAndPreservesSelectionIdentity() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let sourceText = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )
        let secondTextID = try #require(document.site.part(withID: secondRootID)?.children.first?.id)

        editor.setSharedReusableProperty(partID: sourceText.id, key: .text, value: .string("Global heading"))

        #expect(document.site.part(withID: sourceText.id)?.property(.text) == "Global heading")
        #expect(document.site.part(withID: secondTextID)?.property(.text) == "Global heading")
        #expect(document.site.part(withID: sourceText.id)?.id == sourceText.id)
        #expect(document.site.part(withID: secondTextID)?.id == secondTextID)
    }

    @Test
    func editingGlobalTextUpdatesAnInstanceOnAnotherPage() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let sourceText = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondPageID = editor.addPage()
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: secondPageID, placement: .end)
        )
        let secondTextID = try #require(document.site.part(withID: secondRootID)?.children.first?.id)

        editor.setSharedReusableProperty(partID: sourceText.id, key: .text, value: .string("Across every page"))

        #expect(document.site.part(withID: sourceText.id)?.property(.text) == "Across every page")
        #expect(document.site.part(withID: secondTextID)?.property(.text) == "Across every page")
    }

    @Test
    func unlockedGlobalChildKeepsLocalContentUntilRelinked() throws {
        let site = TestSiteFixtures.populatedSite()
        let firstRoot = try #require(site.pages.first?.parts.first)
        let firstText = try #require(firstRoot.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: firstRoot.id, name: "Hero"))
        let secondPageID = editor.addPage()
        let secondRootID = try #require(editor.insertGlobalPart(definitionID: definitionID, on: secondPageID, placement: .end))
        let secondTextID = try #require(document.site.part(withID: secondRootID)?.children.first?.id)

        editor.setGlobalPartLinked(partID: secondTextID, isLinked: false)
        editor.setProperty(id: secondTextID, key: .text, value: .string("Page-specific heading"))
        editor.setSharedReusableProperty(partID: firstText.id, key: .text, value: .string("Global heading"))

        #expect(document.site.part(withID: firstText.id)?.property(.text) == "Global heading")
        #expect(document.site.part(withID: secondTextID)?.property(.text) == "Page-specific heading")
        #expect(document.site.globalPartContext(containing: secondTextID)?.isOverridden == true)

        editor.setGlobalPartLinked(partID: secondTextID, isLinked: true)

        #expect(document.site.part(withID: secondTextID)?.property(.text) == "Global heading")
        #expect(document.site.globalPartContext(containing: secondTextID)?.isOverridden == false)
    }

    @Test
    func movingLocalPartIntoGlobalUpdatesEveryInstance() throws {
        var site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let local = PartNode(type: .paragraph, name: "Local addition")
        site.pages[0].parts.append(local)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.movePart(id: local.id, on: site.pages[0].id, to: .inside(source.id)))

        #expect(document.site.part(withID: source.id)?.children.last?.id == local.id)
        #expect(document.site.part(withID: secondRootID)?.children.last?.name == "Local addition")
        #expect(document.site.globalParts.first?.root.children.last?.name == "Local addition")
    }

    @Test
    func insertingNewPartIntoGlobalUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let lastChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        let insertedID = try #require(
            editor.insertPart(type: .paragraph, on: site.pages[0].id, placement: .after(lastChild.id))
        )

        #expect(document.site.part(withID: source.id)?.children.last?.id == insertedID)
        #expect(document.site.part(withID: secondRootID)?.children.last?.type == .paragraph)
        #expect(document.site.globalParts.first?.root.children.last?.type == .paragraph)
    }

    @Test
    func deletingAndDuplicatingNestedGlobalPartsUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let firstChild = try #require(source.children.first)
        let secondChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        let duplicateID = try #require(editor.duplicatePart(id: firstChild.id, on: site.pages[0].id))
        #expect(document.site.part(withID: source.id)?.children.count == 3)
        #expect(document.site.part(withID: secondRootID)?.children.count == 3)

        editor.removePart(id: secondChild.id)
        #expect(document.site.part(withID: source.id)?.children.count == 2)
        #expect(document.site.part(withID: secondRootID)?.children.count == 2)
        #expect(document.site.part(withID: duplicateID) != nil)
    }

    @Test
    func linkedGlobalMetadataAndPropertiesSynchronizeButAnchorRemainsLocal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let sourceChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )
        let secondChildID = try #require(document.site.part(withID: secondRootID)?.children.first?.id)

        editor.renamePart(id: sourceChild.id, name: "Shared name")
        editor.setPartClasses(id: sourceChild.id, classes: "shared-class")
        editor.setPartRootAttributes(
            id: sourceChild.id,
            attributes: [PartHTMLAttribute(name: "data-role", value: "hero")]
        )
        editor.setProperty(id: sourceChild.id, key: .text, value: .string("Shared value"))
        editor.setPartAnchor(id: sourceChild.id, anchor: "local-anchor")

        let secondChild = try #require(document.site.part(withID: secondChildID))
        #expect(secondChild.name == "Shared name")
        #expect(secondChild.customClasses == "shared-class")
        #expect(secondChild.rootAttributes?.first?.name == "data-role")
        #expect(secondChild.property(.text) == "Shared value")
        #expect(secondChild.anchor == nil)
        #expect(document.site.part(withID: sourceChild.id)?.anchor == "local-anchor")
    }

    @Test
    func movingPartOutOfGlobalUpdatesEveryInstanceAndKeepsDraggedNodeLocal() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let movedChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.movePart(id: movedChild.id, on: site.pages[0].id, to: .after(source.id)))

        #expect(document.site.part(withID: source.id)?.children.count == 1)
        #expect(document.site.part(withID: secondRootID)?.children.count == 1)
        #expect(document.site.pages[0].parts.contains(where: { $0.id == movedChild.id }))
        #expect(document.site.part(withID: movedChild.id)?.reusableDefinitionID == nil)
    }

    @Test
    func reorderingInsideGlobalUpdatesEveryInstance() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let firstChild = try #require(source.children.first)
        let secondChild = try #require(source.children.last)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(editor.movePart(id: firstChild.id, on: site.pages[0].id, to: .after(secondChild.id)))

        #expect(document.site.part(withID: source.id)?.children.map(\.name) == ["Call to action", "Paragraph"])
        #expect(document.site.part(withID: secondRootID)?.children.map(\.name) == ["Call to action", "Paragraph"])
    }

    @Test
    func movingBetweenInstancesOfSameGlobalIsRejected() throws {
        let site = TestSiteFixtures.populatedSite()
        let source = try #require(site.pages.first?.parts.first)
        let sourceChild = try #require(source.children.first)
        let document = FoundryDocument(site: site)
        let editor = ProjectEditor(document: document, undoManager: nil)
        let definitionID = try #require(editor.saveGlobalPart(partID: source.id, name: "Hero"))
        let secondRootID = try #require(
            editor.insertGlobalPart(definitionID: definitionID, on: site.pages[0].id, placement: .end)
        )

        #expect(!editor.movePart(id: sourceChild.id, on: site.pages[0].id, to: .inside(secondRootID)))
        #expect(document.site.part(withID: source.id)?.children.count == 2)
        #expect(document.site.part(withID: secondRootID)?.children.count == 2)
    }

    @Test
    func folderCannotMoveInsideItsDescendantAndReorderingWorks() throws {
        let inner = ReusablePartFolder(name: "Inner")
        let outer = ReusablePartFolder(name: "Outer", children: [.folder(inner)])
        let hero = ReusablePartDefinition(name: "Hero", root: PartNode.make(.container))
        var nodes: [ReusablePartNode] = [.folder(outer), .part(hero)]

        let movedIntoDescendant = nodes.move(id: outer.id, to: .inside(folderID: inner.id))
        let movedIntoItself = nodes.move(id: outer.id, to: .inside(folderID: outer.id))
        #expect(!movedIntoDescendant)
        #expect(!movedIntoItself)

        let movedIntoInner = nodes.move(id: hero.id, to: .inside(folderID: inner.id))
        #expect(movedIntoInner)
        #expect(nodes.allDefinitions.map(\.name) == ["Hero"])
        guard case .folder(let movedOuter) = nodes.node(withID: outer.id),
              case .folder(let movedInner)? = movedOuter.children.first else {
            Issue.record("expected nested folders")
            return
        }
        #expect(movedInner.children.map(\.id) == [hero.id])

        let movedBeforeOuter = nodes.move(id: hero.id, to: .before(nodeID: outer.id))
        #expect(movedBeforeOuter)
        #expect(nodes.first?.id == hero.id)
    }

    @Test
    func detachingOneGlobalInstanceClearsItsLinkButNotNestedGlobals() throws {
        let nestedDefinitionID = UUID()
        var nestedGlobal = PartNode.make(.container)
        nestedGlobal.reusableDefinitionID = nestedDefinitionID
        var overriddenChild = PartNode.make(.heading)
        overriddenChild.overridesGlobalDefinition = true
        var instance = PartNode.make(.section)
        instance.reusableDefinitionID = UUID()
        instance.overridesGlobalDefinition = true
        instance.children = [overriddenChild, nestedGlobal]
        var untouched = PartNode.make(.section)
        untouched.reusableDefinitionID = instance.reusableDefinitionID

        var parts = [instance, untouched]
        let didDetach = parts.detachGlobalInstance(id: instance.id)
        #expect(didDetach)

        let detached = try #require(parts.first)
        #expect(detached.reusableDefinitionID == nil)
        #expect(detached.overridesGlobalDefinition == nil)
        #expect(detached.children.first?.overridesGlobalDefinition == nil)
        // A nested global inside keeps its own link and any override state.
        #expect(detached.children.last?.reusableDefinitionID == nestedDefinitionID)
        // Other instances of the same definition stay linked.
        #expect(parts.last?.reusableDefinitionID == instance.reusableDefinitionID)
    }

}
