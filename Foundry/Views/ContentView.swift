import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct HTMLSourceEditRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let componentID: UUID
    let propertyKey: ComponentProperty.Key
    let propertyPath: [Int]
    let source: HTMLComponentSource
}

private struct PageTextEditRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let componentID: UUID
    let propertyKey: ComponentProperty.Key
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
    @State private var selectedAssetLibraryNodeID: UUID?
    @State private var selectedComponentIDs: Set<UUID> = []
    @State private var selectedComponentID: UUID?
    @State private var selectedPrimitive: CanvasPrimitiveSelection?
    @State private var selectedLibraryComponentType: ComponentType?
    @State private var copiedComponents: [ComponentNode] = []
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
    @State private var componentCatalog = ComponentPackageCatalog.shared
    @State private var canvasViewportWidth = 390.0
    @State private var htmlSourceEditRequest: HTMLSourceEditRequest?
    @State private var pageTextEditRequest: PageTextEditRequest?
    @State private var pageDeletionRequest: PageDeletionRequest?
    @State private var canvasReusableComponentName: String?
    @State private var canvasGlobalComponentName: String?
    @AppStorage(AppPreferenceKey.appearance)
    private var appearance: AppAppearance = .system
    @AppStorage(AppPreferenceKey.externalPreviewAutoReload)
    private var externalPreviewAutoReload = false
    @AppStorage(AppPreferenceKey.previewApplication)
    private var previewApplicationIdentifier = PreviewApplicationSelection.systemDefault
    @AppStorage(AppPreferenceKey.automaticallyChecksComponentUpdates)
    private var automaticallyChecksComponentUpdates = false

    private var renderer: any PageRendering { HTMLPageRenderer(site: document.site) }

    var body: some View {
        let _ = componentCatalog.revision
        DockingWorkspaceView(
            layout: $workspaceLayout,
            canvasEditorOptions: $canvasEditorOptions,
            canvasViewportWidth: $canvasViewportWidth,
            canvasScreens: document.site.theme.screens,
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
            showComponentUpdates: {
                openWindow(id: "available-component-updates")
            }
        ) { panel in
            workspacePanel(panel)
        }
        .frame(
            minWidth: EditorWindowSize.minimumWidth,
            idealWidth: EditorWindowSize.idealWidth,
            maxWidth: .infinity,
            minHeight: EditorWindowSize.minimumHeight,
            idealHeight: EditorWindowSize.idealHeight,
            maxHeight: .infinity
        )
        .task {
            guard automaticallyChecksComponentUpdates else { return }
            _ = await ComponentUpdateManager.shared.automaticCheckIfNeeded()
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
            selectedComponentID = nil
        }
        .onChange(of: selectedComponentID) { _, componentID in
            editsSharedReusableDefinition = false
            if selectedPrimitive?.componentID != componentID {
                selectedPrimitive = nil
            }
            guard let componentID else {
                selectedComponentIDs = []
                return
            }
            if !selectedComponentIDs.contains(componentID) {
                selectedComponentIDs = [componentID]
            }
            selectedLibraryComponentType = nil
            inspectedPageID = nil
            selectedPageFolderID = nil
            selectedPageAssetID = nil
            selectedAssetLibraryNodeID = nil
        }
        .onChange(of: selectedComponentIDs) { _, componentIDs in
            if componentIDs.count != 1 || selectedPrimitive.map({ !componentIDs.contains($0.componentID) }) == true {
                selectedPrimitive = nil
            }
            if let selectedComponentID, !componentIDs.contains(selectedComponentID) {
                self.selectedComponentID = componentIDs.first
            } else if selectedComponentID == nil {
                selectedComponentID = componentIDs.first
            }
            guard !componentIDs.isEmpty else { return }
            selectedLibraryComponentType = nil
            inspectedPageID = nil
            selectedPageFolderID = nil
            selectedPageAssetID = nil
            selectedAssetLibraryNodeID = nil
        }
        .onDeleteCommand {
            if selectedPrimitive != nil { return }
            guard !selectedComponentIDs.isEmpty else { return }
            deleteComponent()
        }
        .focusedSceneValue(\.publishingCommandDispatcher, publishingCommandDispatcher)
        .onChange(of: publishingCommandDispatcher.request?.id) {
            guard let command = publishingCommandDispatcher.request?.command else { return }
            handlePublishingCommand(command)
        }
        .onChange(of: document.mutationEvent.revision) {
            handleMutationImpact(document.mutationEvent.impact)
        }
        .onChange(of: componentCatalog.revision) {
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
        .alert("Save Reusable Component", isPresented: canvasReusableAlertBinding) {
            TextField("Name", text: canvasReusableNameBinding)
            Button("Cancel", role: .cancel) { canvasReusableComponentName = nil }
            Button("Save") {
                guard let name = canvasReusableComponentName else { return }
                saveReusableComponent(name)
                canvasReusableComponentName = nil
            }
            .disabled(canvasReusableComponentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        } message: {
            Text("The selected component and its children will be available in the Project library.")
        }
        .alert("Save Global Component", isPresented: canvasGlobalAlertBinding) {
            TextField("Name", text: canvasGlobalNameBinding)
            Button("Cancel", role: .cancel) { canvasGlobalComponentName = nil }
            Button("Save") {
                guard let name = canvasGlobalComponentName else { return }
                saveGlobalComponent(name)
                canvasGlobalComponentName = nil
            }
            .disabled(canvasGlobalComponentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        } message: {
            Text("Every linked instance will update when this global component is edited.")
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
                addPage: addPage,
                addFolder: { _ = editor.addPageFolder(named: $0) },
                duplicatePage: duplicatePage,
                renamePage: { editor.renamePageFromOutline(id: $0, title: $1) },
                deletePage: deletePage,
                movePage: movePage,
                setHomePage: setHomePage,
                moveTreeItem: { editor.movePageTreeItem($0, to: $1) },
                importURLs: importPageTreeURLs
            )
        case .components:
            ComponentLibraryPanel(
                selectedType: inspectableLibraryComponentSelection,
                addToPageEnd: addComponentToPageEnd
            )
        case .reusableComponents:
            ReusableComponentLibraryPanel(
                definitions: document.site.reusableComponents,
                renameDefinition: renameReusableComponent,
                deleteDefinition: deleteReusableComponent
            )
        case .globalComponents:
            GlobalComponentLibraryPanel(
                definitions: document.site.globalComponents,
                renameDefinition: renameGlobalComponent,
                deleteDefinition: deleteGlobalComponent,
                saveDraggedComponents: saveDraggedComponentsAsGlobals
            )
        case .structure:
            StructurePanel(
                page: selectedPage,
                selectedComponentIDs: $selectedComponentIDs,
                selectedComponentID: inspectableComponentSelection,
                renameComponent: { editor.renameComponent(id: $0, name: $1) },
                moveComponentsToPlacement: moveComponentsFromStructure,
                insertComponent: insertComponentFromLibrary,
                insertReusableComponent: insertReusableComponentFromLibrary,
                insertGlobalComponent: insertGlobalComponentFromLibrary,
                duplicateComponent: duplicateComponent,
                copyComponent: copyComponent,
                pasteComponent: pasteComponent,
                moveComponent: moveComponent,
                outdentComponent: outdentComponent,
                deleteComponent: deleteComponent,
                canPasteComponent: !copiedComponents.isEmpty,
                saveReusableComponent: saveReusableComponent,
                saveGlobalComponent: saveGlobalComponent
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
                selectedComponentID = nil
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
                componentPackageRevision: componentCatalog.revision,
                isComponentCatalogReady: !componentCatalog.isInitialLoading,
                selectedComponentIDs: selectedComponentIDs,
                selectedPrimitive: selectedPrimitive,
                editorOptions: canvasEditorOptions,
                renderer: renderer,
                canPasteComponent: !copiedComponents.isEmpty,
                canClearImage: canClearCanvasImage,
                handleMessage: handleCanvasMessage,
                handleContextMenuAction: handleCanvasContextMenuAction,
                viewportWidth: $canvasViewportWidth
            )
        case .inspector:
            if componentCatalog.isInitialLoading,
               selectedComponent != nil || selectedLibraryComponentType != nil {
                ComponentCatalogLoadingView()
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
                    component: selectedComponent,
                    componentSelectionCount: selectedComponentIDs.count,
                    libraryComponentType: selectedLibraryComponentType,
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
        case .componentProperty(let componentID, _):
            if let page = document.site.pages.first(where: { $0.components.node(withID: componentID) != nil }) {
                markModified(page.id)
            } else {
                markAllPages()
            }
        case .componentStructure(let ownerID):
            if let ownerID,
               let page = document.site.pages.first(where: { $0.components.node(withID: ownerID) != nil }) {
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
            get: { inspectedPageID },
            set: { pageID in
                inspectedPageID = pageID
                guard pageID != nil else { return }
                selectedPageID = pageID
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedComponentID = nil
                selectedLibraryComponentType = nil
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
                selectedComponentID = nil
                selectedLibraryComponentType = nil
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
                selectedComponentID = nil
                selectedLibraryComponentType = nil
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
                selectedComponentID = nil
                selectedLibraryComponentType = nil
            }
        )
    }

    private var inspectableComponentSelection: Binding<UUID?> {
        Binding(
            get: { selectedComponentID },
            set: { componentID in
                selectedPrimitive = nil
                selectedComponentID = componentID
                guard componentID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedLibraryComponentType = nil
            }
        )
    }

    private var inspectableLibraryComponentSelection: Binding<ComponentType?> {
        Binding(
            get: { selectedLibraryComponentType },
            set: { type in
                selectedLibraryComponentType = type
                guard type != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedComponentID = nil
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

    private var selectedComponent: ComponentNode? {
        guard let selectedComponentID else {
            return nil
        }
        return selectedPage?.components.node(withID: selectedComponentID)
    }

    private var topLevelSelectedComponentIDs: [UUID] {
        topLevelComponentIDs(from: selectedComponentIDs)
    }

    private func topLevelComponentIDs(from requestedIDs: Set<UUID>) -> [UUID] {
        guard let selectedPage else { return [] }
        func flattenedIDs(_ nodes: [ComponentNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        return flattenedIDs(selectedPage.components).filter { id in
            guard requestedIDs.contains(id) else { return false }
            return Set(selectedPage.components.ancestorIDs(of: id)).isDisjoint(with: requestedIDs)
        }
    }

    private var selectedReusableDefinition: ReusableComponentDefinition? {
        guard let definitionID = selectedGlobalContext?.definitionID else { return nil }
        return document.site.globalComponents.first(where: { $0.id == definitionID })
    }

    private var selectedGlobalContext: (definitionID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        guard let selectedComponentID else { return nil }
        return document.site.globalComponentContext(containing: selectedComponentID)
    }

    private func setSelectedGlobalOverride(_ isOverridden: Bool) {
        guard let selectedComponentID else { return }
        editor.setGlobalComponentLinked(componentID: selectedComponentID, isLinked: !isOverridden)
    }

    private func handleCanvasMessage(_ message: CanvasMessage) {
        guard let page = selectedPage else { return }

        switch message.event {
        case .selectComponent:
            selectedPrimitive = nil
            guard let componentID = message.componentID,
                  page.components.node(withID: componentID) != nil else { return }
            selectedLibraryComponentType = nil
            if message.extendsSelection == true {
                if selectedComponentIDs.contains(componentID) {
                    selectedComponentIDs.remove(componentID)
                } else {
                    selectedComponentIDs.insert(componentID)
                    selectedComponentID = componentID
                }
            } else {
                selectedComponentIDs = [componentID]
                selectedComponentID = componentID
            }
            workspaceLayout.activate(.structure)
        case .selectPrimitive:
            guard let componentID = message.componentID,
                  let propertyKey = message.propertyKey,
                  let component = page.components.node(withID: componentID),
                  component.type.definition.properties.contains(where: { $0.key == propertyKey }) else { return }
            selectedComponentIDs = [componentID]
            selectedComponentID = componentID
            selectedPrimitive = .init(
                componentID: componentID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? []
            )
            workspaceLayout.activate(.structure)
        case .deleteComponents:
            deleteComponents(message.componentIDs ?? [])
        case .insertComponent:
            guard let type = message.componentType,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertComponent(type: type, on: page.id, placement: placement) else { return }
            selectedComponentID = id
        case .insertReusableComponent:
            guard let definitionID = message.reusableDefinitionID,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertReusableComponent(
                    definitionID: definitionID,
                    on: page.id,
                    placement: placement
                  ) else { return }
            selectedComponentID = id
        case .insertGlobalComponent:
            guard let definitionID = message.globalDefinitionID,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertGlobalComponent(
                    definitionID: definitionID,
                    on: page.id,
                    placement: placement
                  ) else { return }
            selectedComponentID = id
        case .setGlobalLink:
            guard let componentID = message.componentID,
                  let isLinked = message.isGlobalLinked,
                  document.site.globalComponentContext(containing: componentID) != nil else { return }
            editor.setGlobalComponentLinked(componentID: componentID, isLinked: isLinked)
            selectedComponentID = componentID
        case .moveComponent:
            let componentIDs = message.componentIDs ?? message.componentID.map { [$0] } ?? []
            guard componentIDs.allSatisfy({ page.components.node(withID: $0) != nil }),
                  let placement = validatedPlacement(message.placement, on: page),
                  moveComponentsFromStructure(componentIDs, placement) else { return }
            workspaceLayout.activate(.structure)
        case .editHTMLComponent:
            guard let componentID = message.componentID,
                  let propertyKey = message.propertyKey,
                  let source = message.propertyValue,
                  let component = page.components.node(withID: componentID),
                  let package = component.type.definition.package,
                  ComponentTemplateRenderer.htmlPrimitives(
                      in: package.htmlTemplate,
                      repeatMaximums: package.repeatMaximums
                  ).contains(where: {
                      $0.key == propertyKey.rawValue
                  }) else { return }
            selectedComponentIDs = [componentID]
            selectedComponentID = componentID
            selectedPrimitive = .init(componentID: componentID, propertyKey: propertyKey)
            htmlSourceEditRequest = HTMLSourceEditRequest(
                pageID: page.id,
                componentID: componentID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? [],
                source: .init(
                    html: source,
                    css: component.propertyValue(.init(rawValue: propertyKey.rawValue + "CSS"))
                        .value(at: message.propertyPath ?? [])?.stringValue ?? "",
                    javaScript: component.propertyValue(.init(rawValue: propertyKey.rawValue + "JavaScript"))
                        .value(at: message.propertyPath ?? [])?.stringValue ?? ""
                )
            )
        case .editComponent:
            guard let componentID = message.componentID,
                  let propertyKey = message.propertyKey,
                  let component = page.components.node(withID: componentID),
                  component.type.definition.properties.contains(where: { definition in
                      guard definition.key == propertyKey else { return false }
                      switch definition.control {
                      case .singleLineText, .multilineText: return true
                      default: return false
                      }
                  }),
                  let value = message.propertyValue else { return }
            selectedComponentIDs = [componentID]
            selectedComponentID = componentID
            if component.type.definition.properties.contains(where: {
                $0.key == propertyKey && !$0.isInspectorVisible
            }) {
                selectedPrimitive = .init(
                    componentID: componentID,
                    propertyKey: propertyKey,
                    propertyPath: message.propertyPath ?? []
                )
            }
            pageTextEditRequest = PageTextEditRequest(
                pageID: page.id,
                componentID: componentID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? [],
                value: value
            )
        case .importImageAsset:
            guard let propertyKey = message.propertyKey,
                  let componentID = message.componentID,
                  let component = page.components.node(withID: componentID),
                  component.type.definition.properties.contains(where: {
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
                componentID: componentID,
                key: propertyKey,
                value: .url(asset.reference),
                at: message.propertyPath ?? [],
                defaultLeafValue: .url("")
            )
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Import Image")
            selectedComponentID = componentID
            selectedPrimitive = nil
            workspaceLayout.activate(.structure)
        case .insertImageComponent:
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
            guard let componentID = editor.insertComponent(type: .image, on: page.id, placement: placement) else {
                undoManager?.endUndoGrouping()
                return
            }
            guard let imageProperty = ComponentType.image.definition.properties.first(where: {
                      if case .image = $0.control { return true }
                      return false
                  }) else {
                undoManager?.endUndoGrouping()
                return
            }
            editor.setProperty(id: componentID, key: imageProperty.key, value: .url(asset.reference))
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Add Image")
            selectedComponentIDs = [componentID]
            selectedComponentID = componentID
            workspaceLayout.activate(.structure)
        }
    }

    private func handleCanvasContextMenuAction(
        _ action: CanvasContextMenuAction,
        componentID: UUID,
        imageProperty: ComponentProperty.Key?,
        imagePropertyPath: [Int]
    ) {
        guard let component = selectedPage?.components.node(withID: componentID) else { return }
        selectedPrimitive = nil
        selectedLibraryComponentType = nil
        if !selectedComponentIDs.contains(componentID) {
            selectedComponentIDs = [componentID]
        }
        selectedComponentID = componentID

        switch action {
        case .clearImage:
            guard let imageProperty,
                  let definition = component.type.definition.properties.first(where: {
                      guard $0.key == imageProperty else { return false }
                      if case .image = $0.control { return true }
                      return false
                  }) else { return }
            undoManager?.beginUndoGrouping()
            let defaultLeafValue: ComponentProperty.Value = definition.defaultValue.arrayValue == nil
                ? definition.defaultValue
                : .url("")
            setCanvasProperty(
                componentID: componentID,
                key: imageProperty,
                value: defaultLeafValue,
                at: imagePropertyPath,
                defaultLeafValue: defaultLeafValue
            )
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Clear Image")
        case .duplicate:
            duplicateComponent()
        case .copy:
            copyComponent()
        case .paste:
            pasteComponent()
        case .saveReusable:
            canvasReusableComponentName = component.name
        case .saveGlobal:
            canvasGlobalComponentName = component.name
        case .moveUp:
            moveComponent(-1)
        case .moveDown:
            moveComponent(1)
        case .outdent:
            outdentComponent()
        case .delete:
            deleteComponent()
        }
    }

    private func canClearCanvasImage(
        componentID: UUID,
        imageProperty: ComponentProperty.Key,
        imagePropertyPath: [Int]
    ) -> Bool {
        guard let component = selectedPage?.components.node(withID: componentID),
              let definition = component.type.definition.properties.first(where: {
                  guard $0.key == imageProperty else { return false }
                  if case .image = $0.control { return true }
                  return false
              }) else { return false }
        let currentValue = component.propertyValue(imageProperty).value(at: imagePropertyPath)
        let defaultLeafValue: ComponentProperty.Value = definition.defaultValue.arrayValue == nil
            ? definition.defaultValue
            : .url("")
        return currentValue != nil && currentValue != defaultLeafValue
    }

    private var canvasReusableAlertBinding: Binding<Bool> {
        Binding(
            get: { canvasReusableComponentName != nil },
            set: { if !$0 { canvasReusableComponentName = nil } }
        )
    }

    private var canvasGlobalAlertBinding: Binding<Bool> {
        Binding(
            get: { canvasGlobalComponentName != nil },
            set: { if !$0 { canvasGlobalComponentName = nil } }
        )
    }

    private var canvasReusableNameBinding: Binding<String> {
        Binding(
            get: { canvasReusableComponentName ?? "" },
            set: { canvasReusableComponentName = $0 }
        )
    }

    private var canvasGlobalNameBinding: Binding<String> {
        Binding(
            get: { canvasGlobalComponentName ?? "" },
            set: { canvasGlobalComponentName = $0 }
        )
    }

    private func saveHTMLSource(_ source: HTMLComponentSource, request: HTMLSourceEditRequest) {
        guard let page = document.site.pages.first(where: { $0.id == request.pageID }),
              let component = page.components.node(withID: request.componentID),
              let package = component.type.definition.package,
              ComponentTemplateRenderer.htmlPrimitives(
                  in: package.htmlTemplate,
                  repeatMaximums: package.repeatMaximums
              ).contains(where: {
                  $0.key == request.propertyKey.rawValue
              }) else { return }
        let values: [(ComponentProperty.Key, String)] = [
            (request.propertyKey, source.html),
            (.init(rawValue: request.propertyKey.rawValue + "CSS"), source.css),
            (.init(rawValue: request.propertyKey.rawValue + "JavaScript"), source.javaScript)
        ]
        undoManager?.beginUndoGrouping()
        for (key, value) in values {
            let defaultLeafValue: ComponentProperty.Value
            if key == request.propertyKey,
               let primitive = ComponentTemplateRenderer.htmlPrimitives(
                   in: package.htmlTemplate,
                   repeatMaximums: package.repeatMaximums
               ).first(where: { $0.key == key.rawValue }) {
                defaultLeafValue = .string(primitive.defaultValue)
            } else {
                defaultLeafValue = .string("")
            }
            setCanvasProperty(
                componentID: request.componentID,
                key: key,
                value: .string(value),
                at: request.propertyPath,
                defaultLeafValue: defaultLeafValue
            )
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Edit HTML Component")
    }

    private func savePageText(_ value: String, request: PageTextEditRequest) {
        guard let page = document.site.pages.first(where: { $0.id == request.pageID }),
              let component = page.components.node(withID: request.componentID),
              component.type.definition.properties.contains(where: { definition in
                  guard definition.key == request.propertyKey else { return false }
                  switch definition.control {
                  case .singleLineText, .multilineText: return true
                  default: return false
                  }
              }) else { return }
        undoManager?.beginUndoGrouping()
        let defaultLeafValue = component.type.definition.package.flatMap { package in
            ComponentTemplateRenderer.textPrimitives(
                in: package.htmlTemplate,
                repeatMaximums: package.repeatMaximums
            ).first(where: { $0.key == request.propertyKey.rawValue })?.defaultValue
        } ?? ""
        setCanvasProperty(
            componentID: request.componentID,
            key: request.propertyKey,
            value: .string(value),
            at: request.propertyPath,
            defaultLeafValue: .string(defaultLeafValue)
        )
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Edit Text")
    }

    private func setCanvasProperty(
        componentID: UUID,
        key: ComponentProperty.Key,
        value: ComponentProperty.Value,
        at indexPath: [Int],
        defaultLeafValue: ComponentProperty.Value
    ) {
        guard let component = selectedPage?.components.node(withID: componentID) else { return }
        let rootValue = indexPath.isEmpty
            ? value
            : component.propertyValue(key).settingValue(
                value,
                at: indexPath,
                defaultLeafValue: defaultLeafValue
            )
        if let context = document.site.globalComponentContext(containing: componentID), !context.isOverridden {
            editor.setSharedReusableProperty(componentID: componentID, key: key, value: rootValue)
        } else {
            editor.setProperty(id: componentID, key: key, value: rootValue)
        }
    }

    private func imageType(filename: String, mediaType: String) -> UTType? {
        UTType(mimeType: mediaType) ?? UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
    }

    private func validatedPlacement(_ value: CanvasMessage.Placement?, on page: Page) -> ComponentPlacement? {
        guard let value, let placement = value.componentPlacement else { return nil }
        if let targetID = value.targetID,
           page.components.node(withID: targetID) == nil {
            return nil
        }
        return placement
    }

    private func addPage() {
        let pageID = editor.addPage()
        selectedPageID = pageID
        inspectedPageID = pageID
        selectedComponentID = nil
    }

    private func duplicatePage(_ pageID: UUID) {
        let duplicatedPageID = editor.duplicatePage(id: pageID)
        selectedPageID = duplicatedPageID
        inspectedPageID = duplicatedPageID
        selectedComponentID = nil
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
        selectedComponentID = nil
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

    private func addComponentToPageEnd(_ type: ComponentType) {
        guard insertComponentFromLibrary(type, .end) else { return }
        workspaceLayout.activate(.structure)
    }

    private func insertComponentFromLibrary(_ type: ComponentType, _ placement: ComponentPlacement) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertComponent(type: type, on: pageID, placement: placement) else { return false }
        selectedComponentID = id
        return true
    }

    private func insertReusableComponentFromLibrary(
        _ definitionID: UUID,
        _ placement: ComponentPlacement
    ) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertReusableComponent(
                definitionID: definitionID,
                on: pageID,
                placement: placement
              ) else { return false }
        selectedComponentID = id
        return true
    }

    private func insertGlobalComponentFromLibrary(
        _ definitionID: UUID,
        _ placement: ComponentPlacement
    ) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertGlobalComponent(
                definitionID: definitionID,
                on: pageID,
                placement: placement
              ) else { return false }
        selectedComponentID = id
        return true
    }

    private func saveReusableComponent(_ name: String) {
        guard let componentID = selectedComponentID else { return }
        _ = editor.saveReusableComponent(
            componentID: componentID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        workspaceLayout.activate(.reusableComponents)
    }

    private func saveGlobalComponent(_ name: String) {
        guard let componentID = selectedComponentID else { return }
        _ = editor.saveGlobalComponent(
            componentID: componentID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        editsSharedReusableDefinition = true
        workspaceLayout.activate(.globalComponents)
    }

    private func saveDraggedComponentsAsGlobals(_ componentIDs: [UUID]) -> Bool {
        guard let selectedPage else { return false }
        let requestedIDs = Set(componentIDs)
        func flattenedIDs(_ nodes: [ComponentNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        let orderedTopLevelIDs = flattenedIDs(selectedPage.components).filter { id in
            guard requestedIDs.contains(id) else { return false }
            return Set(selectedPage.components.ancestorIDs(of: id)).isDisjoint(with: requestedIDs)
        }
        guard !orderedTopLevelIDs.isEmpty else { return false }
        let createdIDs = editor.saveGlobalComponents(componentIDs: orderedTopLevelIDs)
        if !createdIDs.isEmpty {
            editsSharedReusableDefinition = true
        }
        return createdIDs.count == orderedTopLevelIDs.count
    }

    private func renameGlobalComponent(_ definitionID: UUID, _ name: String) {
        editor.renameGlobalComponent(definitionID: definitionID, name: name)
    }

    private func deleteGlobalComponent(_ definitionID: UUID) {
        editor.removeGlobalComponent(definitionID: definitionID)
        if selectedComponent?.reusableDefinitionID == nil {
            editsSharedReusableDefinition = false
        }
    }

    private func renameReusableComponent(_ definitionID: UUID, _ name: String) {
        editor.renameReusableComponent(definitionID: definitionID, name: name)
    }

    private func deleteReusableComponent(_ definitionID: UUID) {
        editor.removeReusableComponent(definitionID: definitionID)
        if selectedComponent?.reusableDefinitionID == nil {
            editsSharedReusableDefinition = false
        }
    }

    private func updateReusableComponent() {
        guard let componentID = selectedComponentID else { return }
        _ = editor.updateReusableComponent(from: componentID)
    }

    private func detachReusableComponent() {
        guard let componentID = selectedComponentID else { return }
        editor.detachReusableComponent(componentID: componentID)
    }

    private func duplicateComponent() {
        guard let pageID = selectedPage?.id else { return }
        let duplicateIDs = editor.duplicateComponents(
            ids: topLevelSelectedComponentIDs,
            on: pageID
        )
        selectedComponentIDs = Set(duplicateIDs)
        selectedComponentID = duplicateIDs.last
    }

    private func copyComponent() {
        guard let selectedPage else {
            copiedComponents = []
            return
        }
        copiedComponents = topLevelSelectedComponentIDs.compactMap {
            selectedPage.components.node(withID: $0)
        }
    }

    private func pasteComponent() {
        guard let pageID = selectedPage?.id, !copiedComponents.isEmpty else { return }
        let placement: ComponentPlacement
        if let selectedComponent {
            placement = selectedComponent.type.definition.allowsChildren
                ? .inside(selectedComponent.id)
                : .after(selectedComponent.id)
        } else {
            placement = .end
        }
        let pastedIDs = editor.pasteComponents(
            copiedComponents,
            on: pageID,
            placement: placement
        )
        selectedComponentIDs = Set(pastedIDs)
        selectedComponentID = pastedIDs.last
    }

    private func moveComponent(_ offset: Int) {
        guard let pageID = selectedPage?.id,
              let componentID = selectedComponentID else {
            return
        }
        editor.moveComponentBySiblingOffset(
            id: componentID,
            on: pageID,
            offset: offset
        )
    }

    private func outdentComponent() {
        guard let pageID = selectedPage?.id,
              let componentID = selectedComponentID else {
            return
        }
        editor.outdentComponent(id: componentID, on: pageID)
    }

    private func moveComponentsFromStructure(_ sourceIDs: [UUID], _ placement: ComponentPlacement) -> Bool {
        guard let pageID = selectedPage?.id else { return false }
        let requestedIDs = Set(sourceIDs)
        let orderedIDs = topLevelSelectedComponentIDs.filter { requestedIDs.contains($0) }
        let componentIDs = orderedIDs.isEmpty ? sourceIDs : orderedIDs
        guard !componentIDs.isEmpty else { return false }
        if let targetID = placement.targetID {
            let targetAncestors = Set(selectedPage?.components.ancestorIDs(of: targetID) ?? [])
            guard !componentIDs.contains(targetID),
                  targetAncestors.isDisjoint(with: componentIDs) else { return false }
        }
        if editor.moveComponents(ids: componentIDs, on: pageID, to: placement) {
            selectedComponentIDs = Set(componentIDs)
            selectedComponentID = componentIDs.last
            return true
        }
        return false
    }

    private func deleteComponent() {
        deleteComponents(Array(selectedComponentIDs))
    }

    private func deleteComponents(_ requestedIDs: [UUID]) {
        let componentIDs = topLevelComponentIDs(from: Set(requestedIDs))
        guard !componentIDs.isEmpty else { return }
        editor.removeComponents(ids: componentIDs)
        selectedComponentIDs = []
        selectedComponentID = nil
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
        outputPath.split(separator: "/").reduce(serverURL) { url, component in
            url.appending(path: String(component))
        }
    }

    private func previewURL(_ pageURL: URL, sessionID: UUID) -> URL {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return pageURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == foundryPreviewSessionQueryName }
        queryItems.append(URLQueryItem(name: foundryPreviewSessionQueryName, value: sessionID.uuidString))
        components.queryItems = queryItems
        return components.url ?? pageURL
    }

    private func previewTarget(for previewURL: URL) -> String {
        guard let components = URLComponents(url: previewURL, resolvingAgainstBaseURL: false) else {
            return previewURL.path
        }
        return components.percentEncodedQuery.map { "\(components.percentEncodedPath)?\($0)" }
            ?? components.percentEncodedPath
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
            total + page.components.reduce(0) { $0 + assetUsageCount(id, in: $1) }
        }
    }

    private func assetUsageCount(_ id: UUID, in node: ComponentNode) -> Int {
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
