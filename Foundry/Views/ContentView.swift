import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct HTMLSourceEditRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let blockID: UUID
    let propertyKey: BlockProperty.Key
    let propertyPath: [Int]
    let source: HTMLBlockSource
}

private struct PageTextEditRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let blockID: UUID
    let propertyKey: BlockProperty.Key
    let propertyPath: [Int]
    let value: String
}

private struct PageDeletionRequest {
    let pageID: UUID
    let title: String
    let subpageCount: Int
}

struct ContentView: View {
    @ObservedObject var document: FoundryDocument
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedPageID: UUID?
    @State private var inspectedPageID: UUID?
    @State private var selectedPageFolderID: UUID?
    @State private var selectedPageAssetID: UUID?
    @State private var expandedPageTreeItemIDs: Set<UUID> = []
    @State private var selectedAssetLibraryNodeID: UUID?
    @State private var selectedBlockIDs: Set<UUID> = []
    @State private var selectedBlockID: UUID?
    @State private var expandedStructureBlockIDs: Set<UUID> = []
    @State private var selectedPrimitive: CanvasPrimitiveSelection?
    @State private var selectedLibraryBlockType: BlockType?
    @State private var copiedBlocks: [BlockNode] = []
    @State private var editsSharedReusableDefinition = false
    @State private var workspaceLayout = WorkspacePresetStore.initialLayoutForNewDocument()
    @State private var detachedPanelWindows = DetachedPanelWindowCoordinator()
    @State private var themeWindowID = UUID()
    @State private var exportErrorMessage: String?
    @State private var showsProjectSettings = false
    @State private var projectSettingsSection: ProjectSettingsSection? = .general
    @State private var publishingCommandDispatcher = PublishingCommandDispatcher()
    @State private var showsPublishingProgress = false
    @State private var publishingState: PublishingModalState = .preparing
    @State private var publishingTask: Task<Void, Never>?
    @State private var publishingChangeTask: Task<Void, Never>?
    @State private var publishingChangesByTreeItem: [UUID: PublishingChange] = [:]
    @State private var previewSessionID = UUID()
    @State private var previewSessionApplicationIdentifier: String?
    @State private var isPreviewSessionOpen = false
    @State private var previewRefreshTask: Task<Void, Never>?
    @State private var canvasEditorOptions = CanvasEditorOptions()
    @State private var blockCatalog = BlockPackageCatalog.shared
    @State private var canvasViewportWidth = 390.0
    @State private var selectedAppearance = SiteAppearance.light
    private var canvasAppearance: SiteAppearance {
        document.site.appearanceMode.permits(selectedAppearance) ? selectedAppearance :
            (document.site.appearanceMode == .dark ? .dark : .light)
    }
    @State private var htmlSourceEditRequest: HTMLSourceEditRequest?
    @State private var pageTextEditRequest: PageTextEditRequest?
    @State private var pageDeletionRequest: PageDeletionRequest?
    @State private var canvasReusableBlockName: String?
    @State private var canvasGlobalBlockName: String?
    @AppStorage(AppPreferenceKey.appearance)
    private var appearance: AppAppearance = .system
    @AppStorage(AppPreferenceKey.externalPreviewAutoReload)
    private var externalPreviewAutoReload = false
    @AppStorage(AppPreferenceKey.previewApplication)
    private var previewApplicationIdentifier = PreviewApplicationSelection.systemDefault
    @AppStorage(AppPreferenceKey.automaticallyChecksBlockUpdates)
    private var automaticallyChecksBlockUpdates = false

    private var renderer: any PageRendering { HTMLPageRenderer(site: document.site, appearance: canvasAppearance) }

    var body: some View {
        let _ = blockCatalog.revision
        DockingWorkspaceView(
            layout: $workspaceLayout,
            canvasEditorOptions: $canvasEditorOptions,
            canvasViewportWidth: $canvasViewportWidth,
            canvasScreens: document.site.theme.screens,
            canvasAppearance: $selectedAppearance,
            appearanceMode: document.site.appearanceMode,
            openProjectSettings: {
                projectSettingsSection = .general
                showsProjectSettings = true
            },
            openThemeEditor: {
                ThemeWindowRegistry.shared.register(
                    id: themeWindowID,
                    document: document,
                    undoManager: undoManager
                )
                openWindow(id: "theme-editor", value: themeWindowID)
            },
            previewSite: previewSite,
            publishSite: { publishSite() },
            showBlockUpdates: {
                openWindow(id: "available-block-updates")
            }
        ) { panel in
            workspacePanel(panel)
        }
        .environment(\.canvasAppearance, canvasAppearance)
        .frame(
            minWidth: EditorWindowSize.minimumWidth,
            idealWidth: EditorWindowSize.idealWidth,
            maxWidth: .infinity,
            minHeight: EditorWindowSize.minimumHeight,
            idealHeight: EditorWindowSize.idealHeight,
            maxHeight: .infinity
        )
        .task {
            guard automaticallyChecksBlockUpdates else { return }
            _ = await BlockUpdateManager.shared.automaticCheckIfNeeded()
        }
        .onChange(of: workspaceLayout) {
            workspaceLayout.persist()
        }
        .background {
            DetachedPanelPresenter(
                layout: $workspaceLayout,
                coordinator: detachedPanelWindows,
                content: { panel in AnyView(workspacePanel(panel)) }
            )
            .frame(width: 0, height: 0)
        }
        .onAppear {
            appearance.apply()
            selectedPageID = selectedPageID ?? document.site.pages.first?.id
            inspectedPageID = inspectedPageID ?? selectedPageID
            schedulePublishingChangeRefresh(immediately: true)
        }
        .onDisappear {
            dismissWindow(id: "theme-editor", value: themeWindowID)
            ThemeWindowRegistry.shared.remove(id: themeWindowID)
        }
        .onChange(of: appearance) { _, newValue in
            newValue.apply()
        }
        .onChange(of: externalPreviewAutoReload) { _, isEnabled in
            if !isEnabled {
                previewRefreshTask?.cancel()
            }
        }
        .onChange(of: document.site.pages.map(\.id)) { _, pageIDs in
            if let selectedPageID, pageIDs.contains(selectedPageID) {
                return
            }
            selectedPageID = pageIDs.first
            selectedBlockID = nil
        }
        .onChange(of: selectedBlockID) { _, blockID in
            editsSharedReusableDefinition = false
            if selectedPrimitive?.blockID != blockID {
                selectedPrimitive = nil
            }
            guard let blockID else {
                selectedBlockIDs = []
                return
            }
            if !selectedBlockIDs.contains(blockID) {
                selectedBlockIDs = [blockID]
            }
            selectedLibraryBlockType = nil
            inspectedPageID = nil
            selectedPageFolderID = nil
            selectedPageAssetID = nil
            selectedAssetLibraryNodeID = nil
        }
        .onChange(of: selectedBlockIDs) { _, blockIDs in
            if blockIDs.count != 1 || selectedPrimitive.map({ !blockIDs.contains($0.blockID) }) == true {
                selectedPrimitive = nil
            }
            if let selectedBlockID, !blockIDs.contains(selectedBlockID) {
                self.selectedBlockID = blockIDs.first
            } else if selectedBlockID == nil {
                selectedBlockID = blockIDs.first
            }
            guard !blockIDs.isEmpty else { return }
            selectedLibraryBlockType = nil
            inspectedPageID = nil
            selectedPageFolderID = nil
            selectedPageAssetID = nil
            selectedAssetLibraryNodeID = nil
        }
        .onDeleteCommand {
            if selectedPrimitive != nil { return }
            guard !selectedBlockIDs.isEmpty else { return }
            deleteBlock()
        }
        .focusedSceneValue(\.publishingCommandDispatcher, publishingCommandDispatcher)
        .onChange(of: publishingCommandDispatcher.request?.id) {
            guard let command = publishingCommandDispatcher.request?.command else { return }
            handlePublishingCommand(command)
        }
        .onChange(of: document.mutationEvent.revision) {
            handleMutationImpact(document.mutationEvent.impact)
        }
        .onChange(of: blockCatalog.revision) {
            handleMutationImpact(.package)
        }
        .onDisappear {
            previewRefreshTask?.cancel()
            publishingTask?.cancel()
            publishingChangeTask?.cancel()
        }
        .sheet(isPresented: $showsProjectSettings) {
            ProjectSettingsView(
                selection: $projectSettingsSection,
                site: document.site,
                assetContents: document.assetContents,
                siteName: document.site.name,
                language: document.site.language,
                publicURL: document.site.publicURL,
                titleSuffix: document.site.titleSuffix,
                defaultDescription: document.site.defaultDescription,
                favicon: document.site.favicon,
                defaultSocialImage: document.site.defaultSocialImage,
                assets: document.site.assets,
                pages: document.site.pages,
                pageFolders: document.site.pageFolders,
                generatesCanonicalURLs: document.site.generatesCanonicalURLs,
                generatesSitemap: document.site.generatesSitemap,
                generatesRobotsTXT: document.site.generatesRobotsTXT,
                allowsSearchIndexing: document.site.allowsSearchIndexing,
                customCodeEnabled: document.site.customCodeEnabled,
                headCode: document.site.headCode,
                bodyStartCode: document.site.bodyStartCode,
                bodyEndCode: document.site.bodyEndCode,
                analyticsCode: document.site.analyticsCode,
                editor: editor,
                openPageMetadata: { pageID in
                    showsProjectSettings = false
                    inspectablePageSelection.wrappedValue = pageID
                }
            )
        }
        .sheet(isPresented: $showsPublishingProgress) {
            PublishingProgressView(
                siteName: document.site.name,
                state: publishingState,
                cancel: { publishingTask?.cancel() },
                dismiss: { showsPublishingProgress = false }
            )
            .interactiveDismissDisabled(publishingState.isActive)
        }
        .sheet(item: $htmlSourceEditRequest) { request in
            HTMLSourceEditorView(
                source: request.source,
                cancel: { htmlSourceEditRequest = nil },
                save: { source in
                    saveHTMLSource(source, request: request)
                    htmlSourceEditRequest = nil
                }
            )
        }
        .sheet(item: $pageTextEditRequest) { request in
            PageTextEditorView(
                value: request.value,
                pages: document.site.pages,
                folders: document.site.pageFolders,
                assets: document.site.assets,
                publicURL: document.site.publicURL,
                cancel: { pageTextEditRequest = nil },
                save: { value in
                    savePageText(value, request: request)
                    pageTextEditRequest = nil
                }
            )
        }
        .alert("Site Export Failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "The site could not be generated.")
        }
        .alert(
            "Delete \(pageDeletionRequest.map { "“\($0.title)”" } ?? "Page")?",
            isPresented: pageDeletionAlertBinding
        ) {
            Button("Delete Page Only", role: .destructive) {
                guard let request = pageDeletionRequest else { return }
                performPageDeletion(request.pageID, includingSubpages: false)
                pageDeletionRequest = nil
            }
            Button("Delete Page and Subpages", role: .destructive) {
                guard let request = pageDeletionRequest else { return }
                performPageDeletion(request.pageID, includingSubpages: true)
                pageDeletionRequest = nil
            }
            Button("Cancel", role: .cancel) {
                pageDeletionRequest = nil
            }
        } message: {
            let count = pageDeletionRequest?.subpageCount ?? 0
            Text(
                count == 1
                    ? "This page contains one subpage. Keeping it will move it up one level."
                    : "This page contains \(count) subpages. Keeping them will move its direct subpages up one level."
            )
        }
        .alert("Save Template", isPresented: canvasReusableAlertBinding) {
            TextField("Name", text: canvasReusableNameBinding)
            Button("Cancel", role: .cancel) { canvasReusableBlockName = nil }
            Button("Save") {
                guard let name = canvasReusableBlockName else { return }
                saveReusableBlock(name)
                canvasReusableBlockName = nil
            }
            .disabled(canvasReusableBlockName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        } message: {
            Text("The selected block and its children will be available in the Project library.")
        }
        .alert("Save Global Block", isPresented: canvasGlobalAlertBinding) {
            TextField("Name", text: canvasGlobalNameBinding)
            Button("Cancel", role: .cancel) { canvasGlobalBlockName = nil }
            Button("Save") {
                guard let name = canvasGlobalBlockName else { return }
                saveGlobalBlock(name)
                canvasGlobalBlockName = nil
            }
            .disabled(canvasGlobalBlockName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        } message: {
            Text("Every linked instance will update when this global block is edited.")
        }
    }

    @ViewBuilder
    private func workspacePanel(_ panel: WorkspacePanel) -> some View {
        switch panel {
        case .pages:
            PagesPanel(
                pages: document.site.pages,
                folders: document.site.pageFolders,
                assets: document.site.assets,
                publishingChanges: publishingChangesByTreeItem,
                selectedPageID: inspectablePageSelection,
                selectedFolderID: inspectablePageFolderSelection,
                selectedAssetID: inspectablePageAssetSelection,
                expandedItemIDs: $expandedPageTreeItemIDs,
                addPage: { addPage(at: $0) },
                addFolder: addPageFolder,
                renameFolder: { editor.renamePageFolder(id: $0, name: $1) },
                deleteFolder: { editor.removePageFolder(id: $0, includingContents: $1) },
                duplicatePage: duplicatePage,
                renamePage: { editor.renamePageFromOutline(id: $0, title: $1) },
                deletePage: deletePage,
                movePage: movePage,
                setHomePage: setHomePage,
                moveTreeItem: { editor.movePageTreeItem($0, to: $1) },
                importURLs: importPageTreeURLs
            )
        case .blocks:
            BlockLibraryPanel(
                selectedType: inspectableLibraryBlockSelection,
                addToPageEnd: addBlockToPageEnd
            )
        case .reusableBlocks:
            ReusableBlockLibraryPanel(
                definitions: document.site.reusableBlocks,
                renameDefinition: renameReusableBlock,
                deleteDefinition: deleteReusableBlock
            )
        case .globalBlocks:
            GlobalBlockLibraryPanel(
                definitions: document.site.globalBlocks,
                renameDefinition: renameGlobalBlock,
                deleteDefinition: deleteGlobalBlock,
                saveDraggedBlocks: saveDraggedBlocksAsGlobals
            )
        case .structure:
            StructurePanel(
                page: selectedPage,
                globalBlockNames: Dictionary(
                    uniqueKeysWithValues: document.site.globalBlocks.map { ($0.id, $0.name) }
                ),
                selectedBlockIDs: $selectedBlockIDs,
                selectedBlockID: inspectableBlockSelection,
                expandedBlockIDs: $expandedStructureBlockIDs,
                renameBlock: renameBlock,
                canMoveBlocksToPlacement: canMoveBlocksFromStructure,
                moveBlocksToPlacement: moveBlocksFromStructure,
                insertBlock: insertBlockFromLibrary,
                insertReusableBlock: insertReusableBlockFromLibrary,
                insertGlobalBlock: insertGlobalBlockFromLibrary,
                duplicateBlock: duplicateBlock,
                copyBlock: copyBlock,
                pasteBlock: pasteBlock,
                moveBlock: moveBlock,
                outdentBlock: outdentBlock,
                deleteBlock: deleteBlock,
                canPasteBlock: !copiedBlocks.isEmpty,
                saveReusableBlock: saveReusableBlock,
                saveGlobalBlock: saveGlobalBlock,
                setGlobalBlockLinked: { blockID, isLinked in
                    editor.setGlobalBlockLinked(blockID: blockID, isLinked: isLinked)
                    selectedBlockIDs = [blockID]
                    selectedBlockID = blockID
                }
            )
        case .assets:
            AssetsPanel(
                library: document.site.assetLibrary.resourcesOnly,
                assetContents: document.assetContents,
                selectedNodeID: inspectableAssetLibrarySelection,
                importFiles: importAssets,
                importURLs: importAssetURLs,
                createFolder: { name, placement in
                    _ = document.createAssetFolder(named: name, at: placement, undoManager: undoManager)
                },
                moveNode: { document.moveAssetNodeToResources(id: $0, to: $1, undoManager: undoManager) },
                deleteNode: deleteAssetLibraryNode
            )
            .onChange(of: selectedAssetLibraryNodeID) { _, selectedID in
                guard selectedID != nil else { return }
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedBlockID = nil
            }
        case .developer:
            DeveloperPanel()
        case .canvas:
            CanvasView(
                site: document.site,
                page: selectedPage,
                language: document.site.language,
                theme: document.site.theme,
                assets: document.assetContents,
                assetRevision: document.assetRevision,
                mutationEvent: document.mutationEvent,
                blockPackageRevision: blockCatalog.revision,
                isBlockCatalogReady: !blockCatalog.isInitialLoading,
                selectedBlockIDs: selectedBlockIDs,
                primarySelectedBlockID: selectedBlockID,
                selectedPrimitive: selectedPrimitive,
                editorOptions: canvasEditorOptions,
                renderer: renderer,
                canPasteBlock: !copiedBlocks.isEmpty,
                canClearImage: canClearCanvasImage,
                handleMessage: handleCanvasMessage,
                handleContextMenuAction: handleCanvasContextMenuAction,
                viewportWidth: $canvasViewportWidth
            )
        case .inspector:
            if blockCatalog.isInitialLoading,
               selectedBlock != nil || selectedLibraryBlockType != nil {
                BlockCatalogLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                InspectorView(
                    page: inspectedPage,
                    currentPage: selectedPage,
                    folder: selectedPageFolder,
                    asset: selectedPageAsset,
                    assetLibraryNode: selectedAssetLibraryNode,
                    assetLibrary: document.site.assetLibrary,
                    assetContents: document.assetContents,
                    folders: document.site.pageFolders,
                    pages: document.site.pages,
                    publicURL: document.site.publicURL,
                    block: selectedBlock,
                    blockSelectionCount: selectedBlockIDs.count,
                    libraryBlockType: selectedLibraryBlockType,
                    theme: document.site.theme,
                    assets: document.site.assets,
                    editor: editor,
                    reusableDefinition: selectedReusableDefinition,
                    isGlobalOverride: selectedGlobalContext?.isOverridden == true,
                    setGlobalOverride: setSelectedGlobalOverride,
                    breakpoint: activeCanvasBreakpoint,
                    assetUsageCount: assetUsageCount,
                    renameAsset: { document.renameAsset(id: $0, filename: $1, undoManager: undoManager) },
                    renameAssetFolder: { document.renameAssetFolder(id: $0, name: $1, undoManager: undoManager) },
                    importImage: importImageAsset,
                    editsSharedDefinition: $editsSharedReusableDefinition
                )
            }
        }
    }

    private func schedulePublishingChangeRefresh(immediately: Bool = false) {
        publishingChangeTask?.cancel()
        publishingChangeTask = Task {
            if !immediately {
                try? await Task.sleep(for: .milliseconds(750))
            }
            guard !Task.isCancelled else { return }
            let site = document.site
            let assets = document.assetContents
            let localDirectory = site.publishingDestination == .local
                ? PublishingDestinationStore.url(for: site.id)
                : nil
            let result = await Task.detached {
                let bundle = StaticSiteRenderer().render(site: site, assets: assets)
                let previous = PublishingManifestStore().load(for: site, localDirectory: localDirectory)
                let changesByPath = PublishingPlan.changes(bundle: bundle, previous: previous)
                var changes: [UUID: PublishingChange] = [:]
                for page in site.pages {
                    changes[page.id] = changesByPath[StaticSiteRenderer.outputPath(for: page, in: site)]
                }
                for asset in site.assets {
                    guard let path = StaticSiteRenderer.customExportPath(for: asset, in: site) else { continue }
                    changes[asset.id] = changesByPath[path]
                }
                return changes
            }.value
            guard !Task.isCancelled else { return }
            publishingChangesByTreeItem = result
        }
    }

    private func handleMutationImpact(_ impact: ProjectMutationImpact) {
        guard impact.affectsRenderedOutput else {
            schedulePublishingChangeRefresh()
            return
        }
        markPublishingChangesDirty(for: impact)
        schedulePublishingChangeRefresh()
        schedulePreviewRefresh()
    }

    private func markPublishingChangesDirty(for impact: ProjectMutationImpact) {
        func markModified(_ id: UUID) {
            if publishingChangesByTreeItem[id] != .new {
                publishingChangesByTreeItem[id] = .modified
            }
        }

        func markAllPages() {
            document.site.pages.forEach { markModified($0.id) }
        }

        switch impact {
        case .blockProperty(let blockID, _):
            if let page = document.site.pages.first(where: { $0.blocks.node(withID: blockID) != nil }) {
                markModified(page.id)
            } else {
                markAllPages()
            }
        case .blockStructure(let ownerID):
            if let ownerID,
               let page = document.site.pages.first(where: { $0.blocks.node(withID: ownerID) != nil }) {
                markModified(page.id)
            } else {
                markAllPages()
            }
        case .assets:
            markAllPages()
            document.site.assets.forEach { markModified($0.id) }
        case .page, .theme, .package:
            markAllPages()
        case .publishingOnly:
            break
        }
    }

    private var editor: ProjectEditor {
        ProjectEditor(document: document, undoManager: undoManager)
    }

    private var inspectablePageSelection: Binding<UUID?> {
        Binding(
            get: { inspectedPageID ?? selectedPageID },
            set: { pageID in
                inspectedPageID = pageID
                guard pageID != nil else { return }
                selectedPageID = pageID
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedBlockID = nil
                selectedLibraryBlockType = nil
            }
        )
    }

    private var inspectablePageFolderSelection: Binding<UUID?> {
        Binding(
            get: { selectedPageFolderID },
            set: { folderID in
                selectedPageFolderID = folderID
                guard folderID != nil else { return }
                inspectedPageID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedBlockID = nil
                selectedLibraryBlockType = nil
            }
        )
    }

    private var inspectablePageAssetSelection: Binding<UUID?> {
        Binding(
            get: { selectedPageAssetID },
            set: { assetID in
                selectedPageAssetID = assetID
                guard assetID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedAssetLibraryNodeID = nil
                selectedBlockID = nil
                selectedLibraryBlockType = nil
            }
        )
    }

    private var inspectableAssetLibrarySelection: Binding<UUID?> {
        Binding(
            get: { selectedAssetLibraryNodeID },
            set: { nodeID in
                selectedAssetLibraryNodeID = nodeID
                guard nodeID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedBlockID = nil
                selectedLibraryBlockType = nil
            }
        )
    }

    private var inspectableBlockSelection: Binding<UUID?> {
        Binding(
            get: { selectedBlockID },
            set: { blockID in
                selectedPrimitive = nil
                selectedBlockID = blockID
                guard blockID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedLibraryBlockType = nil
            }
        )
    }

    private var inspectableLibraryBlockSelection: Binding<BlockType?> {
        Binding(
            get: { selectedLibraryBlockType },
            set: { type in
                selectedLibraryBlockType = type
                guard type != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedBlockID = nil
                selectedPrimitive = nil
            }
        )
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )
    }

    private var selectedPage: Page? {
        document.site.pages.first(where: { $0.id == selectedPageID })
            ?? document.site.pages.first
    }

    private var inspectedPage: Page? {
        guard let inspectedPageID else { return nil }
        return document.site.pages.first(where: { $0.id == inspectedPageID })
    }

    private var selectedPageFolder: PageFolder? {
        guard let selectedPageFolderID else { return nil }
        return document.site.pageFolders.first(where: { $0.id == selectedPageFolderID })
    }

    private var selectedPageAsset: ProjectAsset? {
        guard let selectedPageAssetID else { return nil }
        return document.site.assets.first(where: { $0.id == selectedPageAssetID })
    }

    private var selectedAssetLibraryNode: ProjectAssetNode? {
        guard let selectedAssetLibraryNodeID else { return nil }
        return document.site.assetLibrary.node(withID: selectedAssetLibraryNodeID)
    }

    private var activeCanvasBreakpoint: ResponsiveBreakpoint {
        ResponsiveBreakpoint.forViewportWidth(canvasViewportWidth, screens: document.site.theme.screens)
    }

    private var selectedBlock: BlockNode? {
        guard let selectedBlockID else {
            return nil
        }
        return selectedPage?.blocks.node(withID: selectedBlockID)
    }

    private var topLevelSelectedBlockIDs: [UUID] {
        topLevelBlockIDs(from: selectedBlockIDs)
    }

    private func topLevelBlockIDs(from requestedIDs: Set<UUID>) -> [UUID] {
        guard let selectedPage else { return [] }
        func flattenedIDs(_ nodes: [BlockNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        return flattenedIDs(selectedPage.blocks).filter { id in
            guard requestedIDs.contains(id) else { return false }
            return Set(selectedPage.blocks.ancestorIDs(of: id)).isDisjoint(with: requestedIDs)
        }
    }

    private var selectedReusableDefinition: ReusableBlockDefinition? {
        guard let definitionID = selectedGlobalContext?.definitionID else { return nil }
        return document.site.globalBlocks.first(where: { $0.id == definitionID })
    }

    private var selectedGlobalContext: (definitionID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        guard let selectedBlockID else { return nil }
        return document.site.globalBlockContext(containing: selectedBlockID)
    }

    private func setSelectedGlobalOverride(_ isOverridden: Bool) {
        guard let selectedBlockID else { return }
        editor.setGlobalBlockLinked(blockID: selectedBlockID, isLinked: !isOverridden)
    }

    private func handleCanvasMessage(_ message: CanvasMessage) {
        guard let page = selectedPage else { return }

        switch message.event {
        case .selectBlock:
            selectedPrimitive = nil
            guard let blockID = message.blockID,
                  page.blocks.node(withID: blockID) != nil else { return }
            selectedLibraryBlockType = nil
            if message.extendsSelection == true {
                if selectedBlockIDs.contains(blockID) {
                    selectedBlockIDs.remove(blockID)
                } else {
                    selectedBlockIDs.insert(blockID)
                    selectedBlockID = blockID
                }
            } else {
                selectedBlockIDs = [blockID]
                selectedBlockID = blockID
            }
            workspaceLayout.activate(.structure)
        case .selectPrimitive:
            guard let blockID = message.blockID,
                  let propertyKey = message.propertyKey,
                  let block = page.blocks.node(withID: blockID),
                  block.type.definition.properties.contains(where: { $0.key == propertyKey }) else { return }
            selectedBlockIDs = [blockID]
            selectedBlockID = blockID
            selectedPrimitive = .init(
                blockID: blockID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? []
            )
            workspaceLayout.activate(.structure)
        case .deleteBlocks:
            deleteBlocks(message.blockIDs ?? [])
        case .duplicateBlocks:
            guard selectCanvasBlocks(message.blockIDs, on: page) else { return }
            duplicateBlock()
        case .copyBlocks:
            guard selectCanvasBlocks(message.blockIDs, on: page) else { return }
            copyBlock()
        case .pasteBlocks:
            guard selectCanvasBlocks(message.blockIDs, on: page) else { return }
            pasteBlock()
        case .insertBlock:
            guard let type = message.blockType,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertBlock(type: type, on: page.id, placement: placement) else { return }
            selectedBlockID = id
        case .insertReusableBlock:
            guard let definitionID = message.reusableDefinitionID,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertReusableBlock(
                    definitionID: definitionID,
                    on: page.id,
                    placement: placement
                  ) else { return }
            selectedBlockID = id
        case .insertGlobalBlock:
            guard let definitionID = message.globalDefinitionID,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertGlobalBlock(
                    definitionID: definitionID,
                    on: page.id,
                    placement: placement
                  ) else { return }
            selectedBlockID = id
        case .setGlobalLink:
            guard let blockID = message.blockID,
                  let isLinked = message.isGlobalLinked,
                  document.site.globalBlockContext(containing: blockID) != nil else { return }
            editor.setGlobalBlockLinked(blockID: blockID, isLinked: isLinked)
            selectedBlockID = blockID
        case .moveBlock:
            let blockIDs = message.blockIDs ?? message.blockID.map { [$0] } ?? []
            guard blockIDs.allSatisfy({ page.blocks.node(withID: $0) != nil }),
                  let placement = validatedPlacement(message.placement, on: page),
                  moveBlocksFromStructure(blockIDs, placement) else { return }
            workspaceLayout.activate(.structure)
        case .editHTMLBlock:
            guard let blockID = message.blockID,
                  let propertyKey = message.propertyKey,
                  let source = message.propertyValue,
                  let block = page.blocks.node(withID: blockID),
                  let package = block.type.definition.package,
                  BlockTemplateRenderer.htmlPrimitives(
                      in: package.htmlTemplate,
                      loopMaximums: package.loopMaximums
                  ).contains(where: {
                      $0.key == propertyKey.rawValue
                  }) else { return }
            selectedBlockIDs = [blockID]
            selectedBlockID = blockID
            selectedPrimitive = .init(blockID: blockID, propertyKey: propertyKey)
            htmlSourceEditRequest = HTMLSourceEditRequest(
                pageID: page.id,
                blockID: blockID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? [],
                source: .init(
                    html: source,
                    css: block.propertyValue(BlockPackageAdapter.htmlCSSKey(for: propertyKey.rawValue))
                        .value(at: message.propertyPath ?? [])?.stringValue ?? "",
                    javaScript: block.propertyValue(BlockPackageAdapter.htmlJavaScriptKey(for: propertyKey.rawValue))
                        .value(at: message.propertyPath ?? [])?.stringValue ?? ""
                )
            )
        case .editBlock:
            guard let blockID = message.blockID,
                  let propertyKey = message.propertyKey,
                  let block = page.blocks.node(withID: blockID),
                  block.type.definition.properties.contains(where: { definition in
                      guard definition.key == propertyKey else { return false }
                      switch definition.control {
                      case .singleLineText, .multilineText: return true
                      default: return false
                      }
                  }),
                  let value = message.propertyValue else { return }
            selectedBlockIDs = [blockID]
            selectedBlockID = blockID
            if block.type.definition.properties.contains(where: {
                $0.key == propertyKey && !$0.isInspectorVisible
            }) {
                selectedPrimitive = .init(
                    blockID: blockID,
                    propertyKey: propertyKey,
                    propertyPath: message.propertyPath ?? []
                )
            }
            pageTextEditRequest = PageTextEditRequest(
                pageID: page.id,
                blockID: blockID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? [],
                value: value
            )
        case .importImageAsset:
            guard let propertyKey = message.propertyKey,
                  let blockID = message.blockID,
                  let block = page.blocks.node(withID: blockID),
                  block.type.definition.properties.contains(where: {
                      guard $0.key == propertyKey else { return false }
                      if case .image = $0.control { return true }
                      return false
                  }) else { return }
            undoManager?.beginUndoGrouping()
            let asset: ProjectAsset
            if let assetID = message.assetID {
                guard let existingAsset = document.site.assets.first(where: {
                    $0.id == assetID && UTType(mimeType: $0.mediaType)?.conforms(to: .image) == true
                }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = existingAsset
            } else {
                guard let filename = message.assetFilename,
                      let mediaType = message.assetMediaType,
                      let type = imageType(filename: filename, mediaType: mediaType),
                      type.conforms(to: .image),
                      let encoded = message.assetData,
                      let data = Data(base64Encoded: encoded),
                      data.count <= 25_000_000 else {
                    undoManager?.endUndoGrouping()
                    return
                }
                let assetID = document.importAsset(
                    data: data,
                    filename: filename,
                    mediaType: type.preferredMIMEType ?? mediaType,
                    reuseIdenticalContent: true,
                    undoManager: undoManager
                )
                guard let importedAsset = document.site.assets.first(where: { $0.id == assetID }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = importedAsset
            }
            setCanvasProperty(
                blockID: blockID,
                key: propertyKey,
                value: .url(asset.reference),
                at: message.propertyPath ?? [],
                defaultLeafValue: .url("")
            )
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Import Image")
            selectedBlockID = blockID
            selectedPrimitive = nil
            workspaceLayout.activate(.structure)
        case .insertImageBlock:
            guard let placement = validatedPlacement(message.placement, on: page) else { return }
            let asset: ProjectAsset
            undoManager?.beginUndoGrouping()
            if let assetID = message.assetID {
                guard let existingAsset = document.site.assets.first(where: {
                    $0.id == assetID && UTType(mimeType: $0.mediaType)?.conforms(to: .image) == true
                }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = existingAsset
            } else {
                guard let filename = message.assetFilename,
                      let mediaType = message.assetMediaType,
                      let type = imageType(filename: filename, mediaType: mediaType),
                      type.conforms(to: .image),
                      let encoded = message.assetData,
                      let data = Data(base64Encoded: encoded),
                      data.count <= 25_000_000 else {
                    undoManager?.endUndoGrouping()
                    return
                }
                let assetID = document.importAsset(
                    data: data,
                    filename: filename,
                    mediaType: type.preferredMIMEType ?? mediaType,
                    reuseIdenticalContent: true,
                    undoManager: undoManager
                )
                guard let importedAsset = document.site.assets.first(where: { $0.id == assetID }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = importedAsset
            }
            guard let blockID = editor.insertBlock(type: .image, on: page.id, placement: placement) else {
                undoManager?.endUndoGrouping()
                return
            }
            guard let imageProperty = BlockType.image.definition.properties.first(where: {
                      if case .image = $0.control { return true }
                      return false
                  }) else {
                undoManager?.endUndoGrouping()
                return
            }
            editor.setProperty(id: blockID, key: imageProperty.key, value: .url(asset.reference))
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Add Image")
            selectedBlockIDs = [blockID]
            selectedBlockID = blockID
            workspaceLayout.activate(.structure)
        }
    }

    @discardableResult
    private func selectCanvasBlocks(_ blockIDs: [UUID]?, on page: Page) -> Bool {
        guard let blockIDs, !blockIDs.isEmpty,
              blockIDs.allSatisfy({ page.blocks.node(withID: $0) != nil }) else { return false }
        selectedBlockIDs = Set(blockIDs)
        selectedBlockID = blockIDs.last
        return true
    }

    private func handleCanvasContextMenuAction(
        _ action: CanvasContextMenuAction,
        blockID: UUID,
        imageProperty: BlockProperty.Key?,
        imagePropertyPath: [Int]
    ) {
        guard let block = selectedPage?.blocks.node(withID: blockID) else { return }
        selectedPrimitive = nil
        selectedLibraryBlockType = nil
        if !selectedBlockIDs.contains(blockID) {
            selectedBlockIDs = [blockID]
        }
        selectedBlockID = blockID

        switch action {
        case .clearImage:
            guard let imageProperty,
                  let definition = block.type.definition.properties.first(where: {
                      guard $0.key == imageProperty else { return false }
                      if case .image = $0.control { return true }
                      return false
                  }) else { return }
            undoManager?.beginUndoGrouping()
            let defaultLeafValue: BlockProperty.Value = definition.defaultValue.arrayValue == nil
                ? definition.defaultValue
                : .url("")
            setCanvasProperty(
                blockID: blockID,
                key: imageProperty,
                value: defaultLeafValue,
                at: imagePropertyPath,
                defaultLeafValue: defaultLeafValue
            )
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Clear Image")
        case .duplicate:
            duplicateBlock()
        case .copy:
            copyBlock()
        case .paste:
            pasteBlock()
        case .saveReusable:
            canvasReusableBlockName = block.name
        case .saveGlobal:
            canvasGlobalBlockName = block.name
        case .makeLocalOverride:
            editor.setGlobalBlockLinked(blockID: blockID, isLinked: false)
        case .relinkGlobal:
            editor.setGlobalBlockLinked(blockID: blockID, isLinked: true)
        case .moveUp:
            moveBlock(-1)
        case .moveDown:
            moveBlock(1)
        case .outdent:
            outdentBlock()
        case .delete:
            deleteBlock()
        }
    }

    private func canClearCanvasImage(
        blockID: UUID,
        imageProperty: BlockProperty.Key,
        imagePropertyPath: [Int]
    ) -> Bool {
        guard let block = selectedPage?.blocks.node(withID: blockID),
              let definition = block.type.definition.properties.first(where: {
                  guard $0.key == imageProperty else { return false }
                  if case .image = $0.control { return true }
                  return false
              }) else { return false }
        let currentValue = block.propertyValue(imageProperty).value(at: imagePropertyPath)
        let defaultLeafValue: BlockProperty.Value = definition.defaultValue.arrayValue == nil
            ? definition.defaultValue
            : .url("")
        return currentValue != nil && currentValue != defaultLeafValue
    }

    private var canvasReusableAlertBinding: Binding<Bool> {
        Binding(
            get: { canvasReusableBlockName != nil },
            set: { if !$0 { canvasReusableBlockName = nil } }
        )
    }

    private var canvasGlobalAlertBinding: Binding<Bool> {
        Binding(
            get: { canvasGlobalBlockName != nil },
            set: { if !$0 { canvasGlobalBlockName = nil } }
        )
    }

    private var canvasReusableNameBinding: Binding<String> {
        Binding(
            get: { canvasReusableBlockName ?? "" },
            set: { canvasReusableBlockName = $0 }
        )
    }

    private var canvasGlobalNameBinding: Binding<String> {
        Binding(
            get: { canvasGlobalBlockName ?? "" },
            set: { canvasGlobalBlockName = $0 }
        )
    }

    private func saveHTMLSource(_ source: HTMLBlockSource, request: HTMLSourceEditRequest) {
        guard let page = document.site.pages.first(where: { $0.id == request.pageID }),
              let block = page.blocks.node(withID: request.blockID),
              let package = block.type.definition.package,
              BlockTemplateRenderer.htmlPrimitives(
                  in: package.htmlTemplate,
                  loopMaximums: package.loopMaximums
              ).contains(where: {
                  $0.key == request.propertyKey.rawValue
              }) else { return }
        let values: [(BlockProperty.Key, String)] = [
            (request.propertyKey, source.html),
            (BlockPackageAdapter.htmlCSSKey(for: request.propertyKey.rawValue), source.css),
            (BlockPackageAdapter.htmlJavaScriptKey(for: request.propertyKey.rawValue), source.javaScript)
        ]
        undoManager?.beginUndoGrouping()
        for (key, value) in values {
            let defaultLeafValue: BlockProperty.Value
            if key == request.propertyKey,
               let primitive = BlockTemplateRenderer.htmlPrimitives(
                   in: package.htmlTemplate,
                   loopMaximums: package.loopMaximums
               ).first(where: { $0.key == key.rawValue }) {
                defaultLeafValue = .string(primitive.defaultValue)
            } else {
                defaultLeafValue = .string("")
            }
            setCanvasProperty(
                blockID: request.blockID,
                key: key,
                value: .string(value),
                at: request.propertyPath,
                defaultLeafValue: defaultLeafValue
            )
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Edit HTML Block")
    }

    private func savePageText(_ value: String, request: PageTextEditRequest) {
        guard let page = document.site.pages.first(where: { $0.id == request.pageID }),
              let block = page.blocks.node(withID: request.blockID),
              block.type.definition.properties.contains(where: { definition in
                  guard definition.key == request.propertyKey else { return false }
                  switch definition.control {
                  case .singleLineText, .multilineText: return true
                  default: return false
                  }
              }) else { return }
        undoManager?.beginUndoGrouping()
        let defaultLeafValue = block.type.definition.package.flatMap { package in
            BlockTemplateRenderer.textPrimitives(
                in: package.htmlTemplate,
                loopMaximums: package.loopMaximums
            ).first(where: { $0.key == request.propertyKey.rawValue })?.defaultValue
        } ?? ""
        setCanvasProperty(
            blockID: request.blockID,
            key: request.propertyKey,
            value: .string(value),
            at: request.propertyPath,
            defaultLeafValue: .string(defaultLeafValue)
        )
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Edit Text")
    }

    private func setCanvasProperty(
        blockID: UUID,
        key: BlockProperty.Key,
        value: BlockProperty.Value,
        at indexPath: [Int],
        defaultLeafValue: BlockProperty.Value
    ) {
        guard let block = selectedPage?.blocks.node(withID: blockID) else { return }
        let rootValue = indexPath.isEmpty
            ? value
            : block.propertyValue(key).settingValue(
                value,
                at: indexPath,
                defaultLeafValue: defaultLeafValue
            )
        if let context = document.site.globalBlockContext(containing: blockID), !context.isOverridden {
            editor.setSharedReusableProperty(blockID: blockID, key: key, value: rootValue)
        } else {
            editor.setProperty(id: blockID, key: key, value: rootValue)
        }
    }

    private func imageType(filename: String, mediaType: String) -> UTType? {
        UTType(mimeType: mediaType) ?? UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
    }

    private func validatedPlacement(_ value: CanvasMessage.Placement?, on page: Page) -> BlockPlacement? {
        guard let value, let placement = value.blockPlacement else { return nil }
        if let targetID = value.targetID,
           page.blocks.node(withID: targetID) == nil {
            return nil
        }
        return placement
    }

    private func addPage() {
        addPage(at: nil)
    }

    private func addPage(at placement: PageTreePlacement?) {
        let pageID = editor.addPage()
        if let placement {
            _ = editor.movePageTreeItem(.page(pageID), to: placement)
        }
        selectedPageID = pageID
        selectedPageFolderID = nil
        selectedPageAssetID = nil
        inspectedPageID = pageID
        selectedBlockID = nil
    }

    private func addPageFolder(_ name: String, at placement: PageTreePlacement?) {
        let folderID = editor.addPageFolder(named: name)
        if let placement {
            _ = editor.movePageTreeItem(.folder(folderID), to: placement)
        }
        selectedPageFolderID = folderID
        inspectedPageID = nil
        selectedPageAssetID = nil
        expandedPageTreeItemIDs.insert(folderID)
    }

    private func duplicatePage(_ pageID: UUID) {
        let duplicatedPageID = editor.duplicatePage(id: pageID)
        selectedPageID = duplicatedPageID
        inspectedPageID = duplicatedPageID
        selectedBlockID = nil
    }

    private func deletePage(_ pageID: UUID) {
        let subpageCount = descendantPageIDs(of: pageID).count
        if subpageCount > 0,
           let page = document.site.pages.first(where: { $0.id == pageID }) {
            pageDeletionRequest = PageDeletionRequest(
                pageID: pageID,
                title: page.title,
                subpageCount: subpageCount
            )
        } else {
            performPageDeletion(pageID, includingSubpages: false)
        }
    }

    private func performPageDeletion(_ pageID: UUID, includingSubpages: Bool) {
        guard let nextPageID = editor.removePage(
            id: pageID,
            includingSubpages: includingSubpages
        ) else { return }
        selectedPageID = nextPageID
        inspectedPageID = nextPageID
        selectedBlockID = nil
    }

    private func descendantPageIDs(of pageID: UUID) -> Set<UUID> {
        var descendants = Set<UUID>()
        var parents: Set<UUID> = [pageID]
        while !parents.isEmpty {
            let children = Set(document.site.pages.compactMap { page in
                page.parentPageID.map(parents.contains) == true ? page.id : nil
            }).subtracting(descendants)
            guard !children.isEmpty else { break }
            descendants.formUnion(children)
            parents = children
        }
        return descendants
    }

    private var pageDeletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pageDeletionRequest != nil },
            set: { if !$0 { pageDeletionRequest = nil } }
        )
    }

    private func movePage(_ pageID: UUID, _ offset: Int) {
        editor.movePage(id: pageID, offset: offset)
    }

    private func setHomePage(_ pageID: UUID) {
        editor.setHomePage(id: pageID)
        selectedPageID = pageID
        inspectedPageID = pageID
    }

    private func addBlockToPageEnd(_ type: BlockType) {
        guard insertBlockFromLibrary(type, .end) else { return }
        workspaceLayout.activate(.structure)
    }

    private func insertBlockFromLibrary(_ type: BlockType, _ placement: BlockPlacement) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertBlock(type: type, on: pageID, placement: placement) else { return false }
        selectedBlockID = id
        return true
    }

    private func insertReusableBlockFromLibrary(
        _ definitionID: UUID,
        _ placement: BlockPlacement
    ) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertReusableBlock(
                definitionID: definitionID,
                on: pageID,
                placement: placement
              ) else { return false }
        selectedBlockID = id
        return true
    }

    private func insertGlobalBlockFromLibrary(
        _ definitionID: UUID,
        _ placement: BlockPlacement
    ) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertGlobalBlock(
                definitionID: definitionID,
                on: pageID,
                placement: placement
              ) else { return false }
        selectedBlockID = id
        return true
    }

    private func saveReusableBlock(_ name: String) {
        guard let blockID = selectedBlockID else { return }
        _ = editor.saveReusableBlock(
            blockID: blockID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        workspaceLayout.activate(.reusableBlocks)
    }

    private func saveGlobalBlock(_ name: String) {
        guard let blockID = selectedBlockID else { return }
        _ = editor.saveGlobalBlock(
            blockID: blockID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        editsSharedReusableDefinition = true
        workspaceLayout.activate(.globalBlocks)
    }

    private func saveDraggedBlocksAsGlobals(_ blockIDs: [UUID]) -> Bool {
        guard let selectedPage else { return false }
        let requestedIDs = Set(blockIDs)
        func flattenedIDs(_ nodes: [BlockNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        let orderedTopLevelIDs = flattenedIDs(selectedPage.blocks).filter { id in
            guard requestedIDs.contains(id) else { return false }
            return Set(selectedPage.blocks.ancestorIDs(of: id)).isDisjoint(with: requestedIDs)
        }
        guard !orderedTopLevelIDs.isEmpty else { return false }
        let createdIDs = editor.saveGlobalBlocks(blockIDs: orderedTopLevelIDs)
        if !createdIDs.isEmpty {
            editsSharedReusableDefinition = true
        }
        return createdIDs.count == orderedTopLevelIDs.count
    }

    private func renameBlock(_ blockID: UUID, _ name: String) {
        if let definitionID = document.site.block(withID: blockID)?.reusableDefinitionID,
           document.site.globalBlocks.contains(where: { $0.id == definitionID }) {
            editor.renameGlobalBlock(definitionID: definitionID, name: name)
        } else {
            editor.renameBlock(id: blockID, name: name)
        }
    }

    private func renameGlobalBlock(_ definitionID: UUID, _ name: String) {
        editor.renameGlobalBlock(definitionID: definitionID, name: name)
    }

    private func deleteGlobalBlock(_ definitionID: UUID) {
        editor.removeGlobalBlock(definitionID: definitionID)
        if selectedBlock?.reusableDefinitionID == nil {
            editsSharedReusableDefinition = false
        }
    }

    private func renameReusableBlock(_ definitionID: UUID, _ name: String) {
        editor.renameReusableBlock(definitionID: definitionID, name: name)
    }

    private func deleteReusableBlock(_ definitionID: UUID) {
        editor.removeReusableBlock(definitionID: definitionID)
        if selectedBlock?.reusableDefinitionID == nil {
            editsSharedReusableDefinition = false
        }
    }

    private func updateReusableBlock() {
        guard let blockID = selectedBlockID else { return }
        _ = editor.updateReusableBlock(from: blockID)
    }

    private func detachReusableBlock() {
        guard let blockID = selectedBlockID else { return }
        editor.detachReusableBlock(blockID: blockID)
    }

    private func duplicateBlock() {
        guard let pageID = selectedPage?.id else { return }
        let duplicateIDs = editor.duplicateBlocks(
            ids: topLevelSelectedBlockIDs,
            on: pageID
        )
        selectedBlockIDs = Set(duplicateIDs)
        selectedBlockID = duplicateIDs.last
    }

    private func copyBlock() {
        guard let selectedPage else {
            copiedBlocks = []
            return
        }
        copiedBlocks = topLevelSelectedBlockIDs.compactMap {
            selectedPage.blocks.node(withID: $0)
        }
    }

    private func pasteBlock() {
        guard let pageID = selectedPage?.id, !copiedBlocks.isEmpty else { return }
        let placement = topLevelSelectedBlockIDs.last
            .map(BlockPlacement.after)
            ?? .end
        let pastedIDs = editor.pasteBlocks(
            copiedBlocks,
            on: pageID,
            placement: placement
        )
        selectedBlockIDs = Set(pastedIDs)
        selectedBlockID = pastedIDs.last
    }

    private func moveBlock(_ offset: Int) {
        guard let pageID = selectedPage?.id,
              let blockID = selectedBlockID else {
            return
        }
        editor.moveBlockBySiblingOffset(
            id: blockID,
            on: pageID,
            offset: offset
        )
    }

    private func outdentBlock() {
        guard let pageID = selectedPage?.id,
              let blockID = selectedBlockID else {
            return
        }
        editor.outdentBlock(id: blockID, on: pageID)
    }

    private func moveBlocksFromStructure(_ sourceIDs: [UUID], _ placement: BlockPlacement) -> Bool {
        guard let pageID = selectedPage?.id else { return false }
        let requestedIDs = Set(sourceIDs)
        let orderedIDs = topLevelSelectedBlockIDs.filter { requestedIDs.contains($0) }
        let blockIDs = orderedIDs.isEmpty ? sourceIDs : orderedIDs
        guard !blockIDs.isEmpty else { return false }
        if let targetID = placement.targetID {
            let targetAncestors = Set(selectedPage?.blocks.ancestorIDs(of: targetID) ?? [])
            guard !blockIDs.contains(targetID),
                  targetAncestors.isDisjoint(with: blockIDs) else { return false }
        }
        if editor.moveBlocks(ids: blockIDs, on: pageID, to: placement) {
            selectedBlockIDs = Set(blockIDs)
            selectedBlockID = blockIDs.last
            return true
        }
        return false
    }

    private func canMoveBlocksFromStructure(_ sourceIDs: [UUID], _ placement: BlockPlacement) -> Bool {
        guard let pageID = selectedPage?.id else { return false }
        return editor.canMoveBlocks(ids: sourceIDs, on: pageID, to: placement)
    }

    private func deleteBlock() {
        deleteBlocks(Array(selectedBlockIDs))
    }

    private func deleteBlocks(_ requestedIDs: [UUID]) {
        let blockIDs = topLevelBlockIDs(from: Set(requestedIDs))
        guard !blockIDs.isEmpty else { return }
        editor.removeBlocks(ids: blockIDs)
        selectedBlockIDs = []
        selectedBlockID = nil
    }

    private func previewSite() {
        previewRefreshTask?.cancel()
        let site = document.site
        let assets = document.assetContents
        let selectedPageOutputPath = selectedPage.map {
            StaticSiteRenderer.outputPath(for: $0, in: site)
        }
        let applicationIdentifier = selectedPreviewApplicationIdentifier
        let sessionID: UUID
        if let previousApplicationIdentifier = previewSessionApplicationIdentifier,
           previousApplicationIdentifier != applicationIdentifier {
            let replacementSessionID = UUID()
            previewSessionID = replacementSessionID
            sessionID = replacementSessionID
        } else {
            sessionID = previewSessionID
        }
        previewRefreshTask = Task { @MainActor in
            do {
                let bundle = await Task.detached(priority: .userInitiated) {
                    StaticSiteRenderer(environment: .preview).render(site: site, assets: assets)
                }.value
                guard !Task.isCancelled else { return }
                let serverURL = try await PreviewServer.shared.publish(bundle, notifyingClients: false)
                guard !Task.isCancelled else { return }
                let pageURL = selectedPageOutputPath.map {
                    previewURL(for: $0, relativeTo: serverURL)
                } ?? serverURL
                let previewURL = previewURL(pageURL, sessionID: sessionID)
                isPreviewSessionOpen = true
                await presentPreview(
                    previewURL,
                    sessionID: sessionID,
                    applicationIdentifier: applicationIdentifier
                )
            } catch {
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func schedulePreviewRefresh() {
        guard externalPreviewAutoReload, isPreviewSessionOpen else { return }
        previewRefreshTask?.cancel()
        previewRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let site = document.site
            let assets = document.assetContents
            let bundle = await Task.detached(priority: .userInitiated) {
                StaticSiteRenderer(environment: .preview).render(site: site, assets: assets)
            }.value
            guard !Task.isCancelled else { return }
            do {
                _ = try await PreviewServer.shared.publish(bundle)
            } catch {
                guard !Task.isCancelled else { return }
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func presentPreview(
        _ previewURL: URL,
        sessionID: UUID,
        applicationIdentifier: String?
    ) async {
        if previewSessionApplicationIdentifier == applicationIdentifier,
           await PreviewServer.shared.navigatePreview(
            sessionID: sessionID,
            to: previewTarget(for: previewURL)
           ) {
            activatePreviewApplication(applicationIdentifier)
            return
        }
        previewSessionApplicationIdentifier = applicationIdentifier
        openPreview(previewURL)
    }

    private var selectedPreviewApplicationIdentifier: String? {
        if previewApplicationIdentifier == PreviewApplicationSelection.systemDefault {
            return PreviewApplicationCatalog.defaultApplication()?.bundleIdentifier
        }
        return previewApplicationIdentifier
    }

    private func previewURL(for outputPath: String, relativeTo serverURL: URL) -> URL {
        outputPath.split(separator: "/").reduce(serverURL) { url, block in
            url.appending(path: String(block))
        }
    }

    private func previewURL(_ pageURL: URL, sessionID: UUID) -> URL {
        guard var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return pageURL
        }
        var queryItems = parts.queryItems ?? []
        queryItems.removeAll { $0.name == foundryPreviewSessionQueryName }
        queryItems.append(URLQueryItem(name: foundryPreviewSessionQueryName, value: sessionID.uuidString))
        parts.queryItems = queryItems
        return parts.url ?? pageURL
    }

    private func previewTarget(for previewURL: URL) -> String {
        guard let parts = URLComponents(url: previewURL, resolvingAgainstBaseURL: false) else {
            return previewURL.path
        }
        return parts.percentEncodedQuery.map { "\(parts.percentEncodedPath)?\($0)" }
            ?? parts.percentEncodedPath
    }

    private func activatePreviewApplication(_ applicationIdentifier: String?) {
        guard let applicationIdentifier,
              let runningApplication = NSRunningApplication.runningApplications(
                withBundleIdentifier: applicationIdentifier
              ).first else { return }
        NSApp.yieldActivation(to: runningApplication)
        runningApplication.activate()
    }

    private func openPreview(_ previewURL: URL) {
            let defaultApplicationIdentifier = PreviewApplicationCatalog.defaultApplication()?.bundleIdentifier
            if previewApplicationIdentifier == PreviewApplicationSelection.systemDefault ||
                previewApplicationIdentifier == defaultApplicationIdentifier {
                NSWorkspace.shared.open(previewURL)
            } else if let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: previewApplicationIdentifier
            ) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.promptsUserIfNeeded = true
                configuration.addsToRecentItems = false
                NSWorkspace.shared.open(
                    [previewURL],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                ) { _, error in
                    guard let error else { return }
                    Task { @MainActor in exportErrorMessage = error.localizedDescription }
                }
            } else {
                previewApplicationIdentifier = PreviewApplicationSelection.systemDefault
                NSWorkspace.shared.open(previewURL)
            }
    }

    private func handlePublishingCommand(_ command: PublishingCommandDispatcher.Command) {
        switch command {
        case .settings:
            projectSettingsSection = .publishing
            showsProjectSettings = true
        case .publishSite:
            publishSite()
        case .republishAllFiles:
            publishSite(forceAllFiles: true)
        case .markAllChanged:
            markAllPublishingFilesChanged()
        case .markAllUnchanged:
            markAllPublishingFilesUnchanged()
        }
    }

    private func publishSite(forceAllFiles: Bool = false) {
        guard let nativeDocument = NSDocumentController.shared.currentDocument else { return }
        if nativeDocument.fileURL == nil {
            nativeDocument.save(nil)
            return
        }
        nativeDocument.save(nil)
        let site = document.site
        let assets = document.assetContents
        var localDirectory = PublishingDestinationStore.url(for: site.id)
        if site.publishingDestination == .local, localDirectory == nil {
            let panel = NSOpenPanel()
            panel.title = "Choose Publishing Folder"
            panel.message = "Choose the folder that will contain the published website."
            panel.prompt = "Choose"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            PublishingDestinationStore.setURL(directory, for: site.id)
            localDirectory = directory
        }

        let credential = PublishingCredentialStore.credential(site: site)
        publishingState = .preparing
        showsPublishingProgress = true
        publishingTask?.cancel()
        publishingTask = Task {
            await Task.yield()
            do {
                let bundle = await Task.detached {
                    StaticSiteRenderer().render(site: site, assets: assets)
                }.value
                try Task.checkCancellation()
                publishingState = .publishing(nil)
                let result = try await SitePublisher().publish(
                    bundle: bundle,
                    site: site,
                    localDirectory: localDirectory,
                    credential: credential,
                    forceAllFiles: forceAllFiles
                ) { progress in
                    Task { @MainActor in
                        publishingState = .publishing(progress)
                    }
                }
                publishingState = .completed(result)
                schedulePublishingChangeRefresh(immediately: true)
            } catch is CancellationError {
                publishingState = .cancelled
            } catch {
                publishingState = .failed(error.localizedDescription)
            }
            publishingTask = nil
        }
    }

    private func markAllPublishingFilesChanged() {
        let site = document.site
        let localDirectory = site.publishingDestination == .local
            ? PublishingDestinationStore.url(for: site.id)
            : nil
        do {
            try PublishingManifestStore().remove(for: site, localDirectory: localDirectory)
            schedulePublishingChangeRefresh(immediately: true)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func markAllPublishingFilesUnchanged() {
        let site = document.site
        let assets = document.assetContents
        let localDirectory = site.publishingDestination == .local
            ? PublishingDestinationStore.url(for: site.id)
            : nil
        publishingChangeTask?.cancel()
        publishingChangeTask = Task {
            do {
                let manifest = await Task.detached {
                    let bundle = StaticSiteRenderer().render(site: site, assets: assets)
                    return PublishingPlan.make(
                        bundle: bundle,
                        previous: nil,
                        removesObsoleteFiles: false
                    ).nextManifest
                }.value
                try PublishingManifestStore().save(manifest, for: site, localDirectory: localDirectory)
                schedulePublishingChangeRefresh(immediately: true)
            } catch {
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func importAssets() {
        let panel = NSOpenPanel()
        panel.title = "Import Files or Folders"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        importAssetURLs(panel.urls, placement: .end)
    }

    private func importAssetURLs(_ urls: [URL], placement: AssetPlacement) {
        guard !urls.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            importAssetURL(url, placement: placement)
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Import Assets")
    }

    private func importPageTreeURLs(_ urls: [URL], placement: PageTreePlacement) {
        guard !urls.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            importPageTreeURL(url, placement: placement)
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Import Site Files")
    }

    private func importPageTreeURL(_ url: URL, placement: PageTreePlacement) {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey]) else {
            return
        }
        if values.isDirectory == true {
            let folderID = editor.addPageFolder(named: url.lastPathComponent)
            guard editor.movePageTreeItem(.folder(folderID), to: placement) else { return }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                importPageTreeURL(child, placement: .end(parentFolderID: folderID))
            }
            selectedPageFolderID = folderID
            return
        }
        guard values.isRegularFile == true, let data = try? Data(contentsOf: url) else { return }
        let assetID = document.importAsset(
            data: data,
            filename: url.lastPathComponent,
            mediaType: (values.contentType ?? UTType(filenameExtension: url.pathExtension))?.preferredMIMEType
                ?? "application/octet-stream",
            undoManager: undoManager
        )
        guard editor.movePageTreeItem(.asset(assetID), to: placement) else { return }
        selectedPageAssetID = assetID
    }

    private func importAssetURL(_ url: URL, placement: AssetPlacement) {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey]) else {
            return
        }
        if values.isDirectory == true {
            let folderID = document.createAssetFolder(
                named: url.lastPathComponent,
                at: placement,
                undoManager: undoManager
            )
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                importAssetURL(child, placement: .inside(folderID: folderID))
            }
            return
        }
        guard values.isRegularFile == true, let data = try? Data(contentsOf: url) else { return }
        importAsset(
            data: data,
            filename: url.lastPathComponent,
            type: values.contentType ?? UTType(filenameExtension: url.pathExtension),
            placement: placement
        )
    }

    private func importAsset(data: Data, filename: String, type: UTType?, placement: AssetPlacement) {
        _ = document.importAsset(
            data: data,
            filename: filename,
            mediaType: type?.preferredMIMEType ?? "application/octet-stream",
            placement: placement,
            undoManager: undoManager
        )
    }

    private func importImageAsset(_ url: URL) -> ProjectAsset? {
        let filename = url.lastPathComponent
        let dragPrefix = "foundry-image-asset-"
        if filename.hasPrefix(dragPrefix),
           let separator = filename.range(of: "--"),
           let id = UUID(uuidString: String(filename[filename.index(filename.startIndex, offsetBy: dragPrefix.count)..<separator.lowerBound])),
           let asset = document.site.assets.first(where: { $0.id == id && $0.mediaType.hasPrefix("image/") }) {
            return asset
        }

        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
              values.isRegularFile == true,
              let type = values.contentType ?? UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image),
              let data = try? Data(contentsOf: url),
              data.count <= 25_000_000 else { return nil }
        let id = document.importAsset(
            data: data,
            filename: filename,
            mediaType: type.preferredMIMEType ?? "application/octet-stream",
            placement: .end,
            reuseIdenticalContent: true,
            undoManager: undoManager
        )
        return document.site.assets.first(where: { $0.id == id })
    }

    private func deleteAssetLibraryNode(_ id: UUID) {
        guard let node = document.site.assetLibrary.node(withID: id) else { return }
        switch node {
        case .asset:
            document.removeAsset(id: id, undoManager: undoManager)
        case .folder:
            document.removeAssetFolder(id: id, undoManager: undoManager)
        }
        selectedAssetLibraryNodeID = nil
    }

    private func assetUsageCount(_ id: UUID) -> Int {
        document.site.pages.reduce(0) { total, page in
            total + page.blocks.reduce(0) { $0 + assetUsageCount(id, in: $1) }
        }
    }

    private func assetUsageCount(_ id: UUID, in node: BlockNode) -> Int {
        (node.property(.source).foundryAssetID == id ? 1 : 0) + node.children.reduce(0) { $0 + assetUsageCount(id, in: $1) }
    }
}

private enum PublishingModalState {
    case preparing
    case publishing(PublishingProgress?)
    case completed(PublishingResult)
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .publishing: true
        case .completed, .failed, .cancelled: false
        }
    }
}

private struct PublishingProgressView: View {
    let siteName: String
    let state: PublishingModalState
    let cancel: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: statusSymbol)
                .font(.system(size: 36))
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.weight(.semibold))

            statusContent
                .frame(maxWidth: .infinity)

            Divider()

            HStack {
                Spacer()
                if state.isActive {
                    Button("Cancel", role: .cancel, action: cancel)
                } else {
                    Button("Done", action: dismiss)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .frame(minHeight: 240)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .preparing:
            ProgressView()
                .controlSize(.small)
            Text("Preparing the site for publishing…")
                .foregroundStyle(.secondary)
        case .publishing(let progress):
            if let progress {
                ProgressView(value: progress.fractionCompleted)
                Text("\(formattedBytes(progress.uploadedBytes)) of \(formattedBytes(progress.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    ForEach(progress.transfers) { transfer in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(transfer.file)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text("\(Int(transfer.fractionCompleted * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: transfer.fractionCompleted)
                        }
                    }
                }
                .font(.caption)
                Text("\(progress.completedFileCount) of \(progress.fileCount) files complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Starting upload…")
                    .foregroundStyle(.secondary)
            }
        case .completed(let result):
            Text(completionMessage(result))
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        case .cancelled:
            Text("Publishing was cancelled.")
                .foregroundStyle(.secondary)
        }
    }

    private func completionMessage(_ result: PublishingResult) -> String {
        var parts = ["Uploaded \(result.uploadedFileCount)"]
        if result.unchangedFileCount > 0 { parts.append("skipped \(result.unchangedFileCount) unchanged") }
        if result.removedFileCount > 0 { parts.append("removed \(result.removedFileCount) obsolete") }
        return parts.joined(separator: ", ") + "."
    }

    private var title: String {
        switch state {
        case .preparing: "Preparing \(siteName)"
        case .publishing: "Publishing \(siteName)"
        case .completed: "Publishing Complete"
        case .failed: "Publishing Failed"
        case .cancelled: "Publishing Cancelled"
        }
    }

    private var statusSymbol: String {
        switch state {
        case .preparing, .publishing: "icloud.and.arrow.up"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch state {
        case .completed: .green
        case .failed: .orange
        default: .secondary
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    ContentView(document: FoundryDocument())
}
