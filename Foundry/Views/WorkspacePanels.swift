import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PagesPanel: View {
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let publishingChanges: [UUID: PublishingChange]
    @Binding var selectedPageID: UUID?
    @Binding var selectedFolderID: UUID?
    @Binding var selectedAssetID: UUID?
    @Binding var expandedItemIDs: Set<UUID>
    let addPage: (PageTreePlacement?) -> Void
    let addFolder: (String, PageTreePlacement?) -> Void
    let renameFolder: (UUID, String) -> Void
    let deleteFolder: (UUID, Bool) -> Void
    let duplicatePage: (UUID) -> Void
    let renamePage: (UUID, String) -> Void
    let deletePage: (UUID) -> Void
    let movePage: (UUID, Int) -> Void
    let setHomePage: (UUID) -> Void
    let moveTreeItem: (PageTreeItem, PageTreePlacement) -> Bool
    let importURLs: ([URL], PageTreePlacement) -> Void
    @State private var isNamingFolder = false
    @State private var folderName = ""
    @State private var folderPlacement: PageTreePlacement?
    @State private var folderPendingDeletion: UUID?

    var body: some View {
        VStack(spacing: 0) {
            PagesPanelHeader(
                addPage: {
                    addPage(selectedFolderID.map(PageTreePlacement.insideFolder))
                },
                addFolder: {
                    folderName = ""
                    folderPlacement = selectedFolderID.map(PageTreePlacement.insideFolder)
                    isNamingFolder = true
                }
            )
            Divider()

            PagesOutlineView(
                pages: pages,
                folders: folders,
                assets: assets,
                publishingChanges: publishingChanges,
                selectedPageID: $selectedPageID,
                selectedFolderID: $selectedFolderID,
                selectedAssetID: $selectedAssetID,
                expandedItemIDs: $expandedItemIDs,
                addPage: addPage,
                requestAddFolder: { placement in
                    folderName = ""
                    folderPlacement = placement
                    isNamingFolder = true
                },
                renameFolder: renameFolder,
                requestDeleteFolder: { folderID in
                    if isFolderEmpty(folderID) {
                        deleteFolderAndClearSelection(folderID)
                    } else {
                        folderPendingDeletion = folderID
                    }
                },
                duplicatePage: duplicatePage,
                renamePage: renamePage,
                deletePage: deletePage,
                movePage: movePage,
                setHomePage: setHomePage,
                moveItem: moveTreeItem,
                importURLs: importURLs
            )
            .padding(.top, 12)
            .overlay {
                if pages.isEmpty && folders.isEmpty {
                    ContentUnavailableView("No Pages", systemImage: "doc")
                        .allowsHitTesting(false)
                }
            }

        }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                addFolder(
                    folderName.trimmingCharacters(in: .whitespacesAndNewlines),
                    folderPlacement
                )
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            "Delete Folder?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { folderPendingDeletion = nil }
            Button("Move Contents Up") {
                guard let folderID = folderPendingDeletion else { return }
                deleteFolderAndClearSelection(folderID, includingContents: false)
                folderPendingDeletion = nil
            }
            Button("Delete All", role: .destructive) {
                guard let folderID = folderPendingDeletion else { return }
                deleteFolderAndClearSelection(folderID, includingContents: true)
                folderPendingDeletion = nil
            }
        } message: {
            Text("Move the folder’s contents up one level, or delete the folder and everything inside it.")
        }
    }

    private func isFolderEmpty(_ folderID: UUID) -> Bool {
        let containsPage = pages.contains { $0.folderID == folderID }
        let containsFolder = folders.contains { $0.parentID == folderID }
        let containsPublishedAsset = assets.contains { $0.exportDirectory == .folder(folderID) }
        return !containsPage && !containsFolder && !containsPublishedAsset
    }

    private func deleteFolderAndClearSelection(_ folderID: UUID, includingContents: Bool = false) {
        deleteFolder(folderID, includingContents)
        expandedItemIDs.remove(folderID)
        if selectedFolderID == folderID {
            selectedFolderID = nil
        }
    }
}

private struct PagesPanelHeader: View {
    let addPage: () -> Void
    let addFolder: () -> Void

    var body: some View {
        HStack {
            Text("Pages")
                .font(.headline)
            Spacer()
            Menu {
                Button("New Page", systemImage: "doc.badge.plus", action: addPage)
                Button("New Folder…", systemImage: "folder.badge.plus", action: addFolder)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Add Page or Folder")
            .help("Add a page or folder")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

struct ComponentLibraryPanel: View {
    @Binding var selectedType: ComponentType?
    let addToPageEnd: (ComponentType) -> Void
    @State private var catalog = ComponentPackageCatalog.shared
    @State private var componentSource = ComponentLibrarySource.components
    @AppStorage(AppPreferenceKey.componentLibraryIconSize)
    private var iconSizeValue = ComponentLibraryIconSize.small.rawValue
    @AppStorage(AppPreferenceKey.componentLibraryArrangement)
    private var arrangementValue = ComponentLibraryArrangement.group.rawValue

    var body: some View {
        let _ = catalog.revision
        VStack(spacing: 0) {
            ComponentLibraryPanelHeader(
                iconSize: iconSize,
                setIconSize: { iconSizeValue = $0.rawValue },
                arrangement: arrangement,
                setArrangement: { arrangementValue = $0.rawValue }
            )
            Divider()
            if catalog.isInitialLoading {
                ComponentCatalogLoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if hasDevelopmentComponents {
                    Picker("Component source", selection: $componentSource) {
                        ForEach(ComponentLibrarySource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .buttonSizing(.flexible)
                    .pickerStyle(.palette)
                    .controlSize(.small)
                    .labelsHidden()
                    .padding(12)

                    Divider()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(componentSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Divider()

                                LazyVGrid(
                                    columns: [GridItem(
                                        .adaptive(
                                            minimum: iconSize.gridMinimumWidth,
                                            maximum: .infinity
                                        ),
                                        spacing: 0,
                                        alignment: .center
                                    )],
                                    alignment: .center,
                                    spacing: 10
                                ) {
                                    ForEach(section.types) { type in
                                        ComponentLibraryTile(
                                            type: type,
                                            iconSize: iconSize,
                                            isSelected: selectedType == type,
                                            select: { selectedType = type }
                                        )
                                        .draggable(ComponentDragPayload.library(type).stringValue) {
                                            ComponentLibraryIcon(type: type, size: 54)
                                        }
                                        .contextMenu {
                                            Button("Add to Page End", systemImage: "plus") {
                                                addToPageEnd(type)
                                            }
                                            if let packageURL = type.definition.package?.rootURL {
                                                Divider()
                                                Button(
                                                    "Show in Finder",
                                                    systemImage: "macwindow.and.pointer.arrow"
                                                ) {
                                                    NSWorkspace.shared.activateFileViewerSelecting([packageURL])
                                                }
                                            }
                                        }
                                        .accessibilityAction(named: "Add to Page End") {
                                            addToPageEnd(type)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: .infinity)
            }

        }
        .onChange(of: catalog.revision, initial: true) {
            if !hasDevelopmentComponents {
                componentSource = .components
            }
            if let selectedType, availableTypes.contains(selectedType) {
                return
            }
            selectedType = availableTypes.first
        }
        .onChange(of: componentSource) {
            selectedType = availableTypes.first
        }
    }

    private var componentSections: [ComponentLibrarySection] {
        let types = availableTypes
        switch arrangement {
        case .group:
            return groupSections(for: types)
        case .author:
            return metadataSections(for: types) { type in
                type.definition.package?.manifest.author
            }
        case .tag:
            return metadataSections(for: types) { type in
                type.definition.package?.manifest.tags.first
            }
        case .title:
            return [
                makeSection(
                    id: "title-foundry",
                    title: "Foundry",
                    types: types.filter { $0.definition.package?.isBuiltIn == true }
                ),
                makeSection(
                    id: "title-third-party",
                    title: "Third Party",
                    types: types.filter { $0.definition.package?.isBuiltIn != true }
                )
            ]
            .filter { !$0.types.isEmpty }
        }
    }

    private func groupSections(for types: [ComponentType]) -> [ComponentLibrarySection] {
        let preferredCategories: [ComponentCategory] = [
            .layout, .content, .media, .navigation, .forms, .interactive, .other
        ]
        let remainingCategories = Set(types.map { $0.definition.category })
            .subtracting(preferredCategories)
            .sorted { $0.rawValue < $1.rawValue }
        return (preferredCategories + remainingCategories).compactMap { category in
            let categoryTypes = types.filter { $0.definition.category == category }
            guard !categoryTypes.isEmpty else { return nil }
            return ComponentLibrarySection(
                id: "group-\(category.rawValue)",
                title: category.rawValue,
                types: categoryTypes
            )
        }
    }

    private func metadataSections(
        for types: [ComponentType],
        value: (ComponentType) -> String?
    ) -> [ComponentLibrarySection] {
        var grouped: [String: [ComponentType]] = [:]
        var titles: [String: String] = [:]
        for type in types {
            let title = normalizedSectionTitle(value(type))
            let key = title.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).lowercased()
            titles[key] = key == "other" ? "Other" : (titles[key] ?? title)
            grouped[key, default: []].append(type)
        }
        return grouped.map { key, groupedTypes in
            let title = titles[key] ?? "Other"
            return makeSection(
                id: "metadata-\(key)",
                title: title,
                types: groupedTypes
            )
        }
        .sorted { left, right in
            if left.title == "Other" { return false }
            if right.title == "Other" { return true }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    private func normalizedSectionTitle(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Other" : trimmed
    }

    private func makeSection(
        id: String,
        title: String,
        types: [ComponentType]
    ) -> ComponentLibrarySection {
        ComponentLibrarySection(
            id: id,
            title: title,
            types: types.sorted {
                let comparison = $0.displayName.localizedStandardCompare($1.displayName)
                if comparison == .orderedSame { return $0.rawValue < $1.rawValue }
                return comparison == .orderedAscending
            }
        )
    }

    private var availableTypes: [ComponentType] {
        ComponentType.allCases.filter { type in
            let isDevelopmentPack = type.definition.package?.isDevelopmentPack == true
            return componentSource == .development ? isDevelopmentPack : !isDevelopmentPack
        }
    }

    private var hasDevelopmentComponents: Bool {
        ComponentType.allCases.contains { $0.definition.package?.isDevelopmentPack == true }
    }

    private var iconSize: ComponentLibraryIconSize {
        ComponentLibraryIconSize(rawValue: iconSizeValue) ?? .medium
    }

    private var arrangement: ComponentLibraryArrangement {
        ComponentLibraryArrangement(rawValue: arrangementValue) ?? .group
    }
}

nonisolated private enum ComponentLibrarySource: String, CaseIterable, Identifiable {
    case components
    case development

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .components: "Components"
        case .development: "Dev Components"
        }
    }
}

private struct ComponentLibraryPanelHeader: View {
    let iconSize: ComponentLibraryIconSize
    let setIconSize: (ComponentLibraryIconSize) -> Void
    let arrangement: ComponentLibraryArrangement
    let setArrangement: (ComponentLibraryArrangement) -> Void

    var body: some View {
        HStack {
            Text("Components")
                .font(.headline)
            Spacer()
            Menu {
                Menu("Icon Size") {
                    ForEach(ComponentLibraryIconSize.allCases) { size in
                        Toggle(
                            size.title,
                            isOn: Binding(
                                get: { iconSize == size },
                                set: { isSelected in
                                    if isSelected {
                                        setIconSize(size)
                                    }
                                }
                            )
                        )
                    }
                }
                Menu("Arrange By") {
                    ForEach(ComponentLibraryArrangement.allCases) { option in
                        Toggle(
                            option.title,
                            isOn: Binding(
                                get: { arrangement == option },
                                set: { isSelected in
                                    if isSelected {
                                        setArrangement(option)
                                    }
                                }
                            )
                        )
                    }
                }
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Component view options")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

nonisolated private enum ComponentLibraryArrangement: String, CaseIterable, Identifiable {
    case group
    case author
    case tag
    case title

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .group: "Group"
        case .author: "Author"
        case .tag: "Tag"
        case .title: "Title"
        }
    }
}

nonisolated private enum ComponentLibraryIconSize: String, CaseIterable, Identifiable {
    case list
    case small
    case medium

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .list: "List"
        case .small: "Default"
        case .medium: "Large"
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .list: 28
        case .small: 42
        case .medium: 60
        }
    }

    var tileSize: CGFloat {
        switch self {
        case .list: 44
        case .small: 72
        case .medium: 90
        }
    }

    var gridMinimumWidth: CGFloat {
        switch self {
        case .list: 140
        case .small, .medium: tileSize
        }
    }
}

struct DeveloperPanel: View {
    @State private var catalog = ComponentPackageCatalog.shared
    @State private var selection = DeveloperPanelSection.issues
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = catalog.revision
        VStack(spacing: 0) {
            Picker("Developer tools", selection: $selection) {
                ForEach(DeveloperPanelSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .buttonSizing(.flexible)
            .pickerStyle(.palette)
            .controlSize(.small)
            .labelsHidden()
            .padding(12)
            .onChange(of: selection) { _, newSelection in
                guard newSelection == .updater else { return }
                openWindow(id: "component-updates")
                selection = .issues
            }

            Divider()

            DeveloperIssuesView(
                issues: issues,
                summaryTitle: summaryTitle,
                summaryDescription: summaryDescription,
                reload: catalog.reloadAllPacks
            )
        }
    }

    private var issues: [DeveloperPackageIssue] {
        catalog.diagnostics.compactMap { url, diagnostics in
            guard !diagnostics.isEmpty else { return nil }
            return DeveloperPackageIssue(url: url, diagnostics: diagnostics)
        }
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private var errorCount: Int {
        issues.reduce(into: 0) { count, issue in
            count += issue.diagnostics.count { $0.severity == .error }
        }
    }

    private var warningCount: Int {
        issues.reduce(into: 0) { count, issue in
            count += issue.diagnostics.count { $0.severity == .warning }
        }
    }

    private var summaryTitle: String {
        guard !issues.isEmpty else { return "Components are healthy" }
        return issues.count == 1 ? "1 component needs attention" : "\(issues.count) components need attention"
    }

    private var summaryDescription: String {
        guard !issues.isEmpty else { return "All discovered component packages loaded successfully." }
        var parts: [String] = []
        if errorCount > 0 {
            parts.append(errorCount == 1 ? "1 error" : "\(errorCount) errors")
        }
        if warningCount > 0 {
            parts.append(warningCount == 1 ? "1 warning" : "\(warningCount) warnings")
        }
        return parts.joined(separator: ", ")
    }
}

private enum DeveloperPanelSection: String, CaseIterable, Identifiable {
    case issues
    case updater

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

private struct DeveloperIssuesView: View {
    let issues: [DeveloperPackageIssue]
    let summaryTitle: String
    let summaryDescription: String
    let reload: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryTitle)
                        .font(.headline)
                    Text(summaryDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Reload Components", systemImage: "arrow.clockwise", action: reload)
                    .labelStyle(.iconOnly)
                    .help("Reload component packages")
            }
            .padding(12)
            Divider()
            if issues.isEmpty {
                ContentUnavailableView(
                    "No Component Issues",
                    systemImage: "checkmark.circle",
                    description: Text("Package validation and loading issues will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(issues) { issue in
                            DeveloperPackageIssueCard(issue: issue)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

private struct ReleaseNoteDraft: Identifiable {
    let id = UUID()
    var text = ""
}

struct DeveloperReleasesView: View {
    let developmentPacks: [URL]
    @State private var selectedPackURL: URL?
    @State private var publishingDirectoryURL = ""
    @State private var releaseVersion = ""
    @State private var releaseNotes = [ReleaseNoteDraft()]
    @State private var isWorking = false
    @State private var operationProgress = 0.0
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var workingTask: Task<Void, Never>?

    var body: some View {
        content
            .onAppear {
                if selectedPackURL == nil { selectedPackURL = developmentPacks.first }
                resetReleaseVersion(for: selectedPack)
            }
            .onChange(of: developmentPacks) { _, packs in
                if selectedPackURL.map({ packs.contains($0) }) != true {
                    selectedPackURL = packs.first
                }
            }
            .onChange(of: selectedPackURL) {
                workingTask?.cancel()
                publishingDirectoryURL = publishingURL(for: selectedPackURL) ?? ""
                resetReleaseVersion(for: selectedPack)
                releaseNotes = [ReleaseNoteDraft()]
                resultMessage = nil
                errorMessage = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        if developmentPacks.isEmpty {
            ContentUnavailableView(
                "No Development Pack",
                systemImage: "shippingbox",
                description: Text("Convert a component pack to .foundrydevpack before issuing updates.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    Picker("Development Pack", selection: $selectedPackURL) {
                        ForEach(developmentPacks, id: \.self) { url in
                            Text(url.deletingPathExtension().lastPathComponent).tag(Optional(url))
                        }
                    }
                }

                if let selectedPackURL {
                    if let configuration = selectedPack?.metadata.updates,
                       configuration.appcastURL.lastPathComponent == "appcast.php" {
                        issueUpdateView(
                            sourceURL: selectedPackURL,
                            configuration: configuration
                        )
                    } else {
                        prepareForUpdatesView(sourceURL: selectedPackURL)
                    }
                }

                if isWorking || resultMessage != nil || errorMessage != nil {
                    Section {
                        DeveloperReleaseStatus(
                            isWorking: isWorking,
                            progress: operationProgress,
                            resultMessage: resultMessage,
                            errorMessage: errorMessage
                        )
                        if isWorking {
                            Button("Cancel", role: .cancel) { workingTask?.cancel() }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var selectedPack: FoundryPack? {
        selectedPackURL.flatMap { try? FoundryPackLoader.load(from: $0) }
    }

    private func prepareForUpdatesView(sourceURL: URL) -> some View {
        Section("Prepare for Updates") {
            Text("Foundry uses the publishing settings to derive the appcast and archive URLs and creates a signing identity in Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Publishing URL", value: publishingDirectoryURL.isEmpty ? "Configure Publishing Settings" : publishingDirectoryURL)
            Button("Prepare and Publish Endpoint", systemImage: "checkmark.seal") {
                prepareForUpdates(sourceURL: sourceURL)
            }
            .disabled(!isValidPublishingDirectoryURL(publishingDirectoryURL) || !publisherIsConfigured || isWorking)
        }
    }

    @ViewBuilder
    private func issueUpdateView(
        sourceURL: URL,
        configuration: FoundryPackUpdateConfiguration
    ) -> some View {
        Section {
            if let currentVersion = selectedPack?.metadata.version {
                LabeledContent("Current Version", value: currentVersion)
                LabeledContent("Release Version") {
                    HStack(spacing: 10) {
                        TextField("Release Version", text: $releaseVersion, prompt: Text("1.0.1"))
                            .labelsHidden()
                            .frame(width: 110)
                            .textFieldStyle(.roundedBorder)
                        ControlGroup {
                            Button("Major") { incrementVersion(.major, from: currentVersion) }
                            Button("Minor") { incrementVersion(.minor, from: currentVersion) }
                            Button("Patch") { incrementVersion(.patch, from: currentVersion) }
                        }
                    }
                }
                if !releaseVersion.isEmpty && !isValidReleaseVersion {
                    Label("Enter a semantic version greater than \(currentVersion).", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Publishing Directory")
                    .font(.subheadline.weight(.semibold))
                Text(configuration.appcastURL.deletingLastPathComponent().absoluteString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            Text("Release")
        }

        Section {
            ForEach($releaseNotes) { $note in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                    TextField(
                        "Describe a change",
                        text: $note.text,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    if releaseNotes.count > 1 {
                        Button("Remove Note", systemImage: "minus.circle") {
                            releaseNotes.removeAll { $0.id == note.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button("Add Another Note", systemImage: "plus") {
                releaseNotes.append(ReleaseNoteDraft())
            }
        } header: {
            Text("Release Notes")
        }

        Section {
            Button("Publish Update") {
                issueUpdate(sourceURL: sourceURL)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                isWorking
                    || !isValidReleaseVersion
                    || releaseNotes.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
        }
    }

    private func prepareForUpdates(sourceURL: URL) {
        guard let url = URL(string: publishingDirectoryURL),
              let packID = try? FoundryPackLoader.load(from: sourceURL).identifier else { return }
        let site = ComponentUpdatePublisherConfiguration.site
        let credential = PublishingCredentialStore.credential(site: site)
        let outputDirectoryURL = FileManager.default.temporaryDirectory.appending(
            path: "Foundry-Update-Setup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        isWorking = true
        operationProgress = 0
        resultMessage = nil
        errorMessage = nil
        workingTask?.cancel()
        workingTask = Task {
            defer { try? FileManager.default.removeItem(at: outputDirectoryURL) }
            do {
                let setupDirectory = try FoundryPackReleaseBuilder.prepareForUpdates(
                    sourceURL: sourceURL,
                    publishingDirectoryURL: url,
                    outputDirectoryURL: outputDirectoryURL
                )
                try Task.checkCancellation()
                try await ComponentUpdatePublisher.publishSetup(
                    directory: setupDirectory,
                    packID: packID,
                    site: site,
                    credential: credential,
                    progress: { progress in
                        Task { @MainActor in
                            operationProgress = progress
                        }
                    }
                )
                try await verifyPublishedEndpoint(appcastURL: url.appending(path: "appcast.php"))
                try Task.checkCancellation()
                try FoundryPackReleaseBuilder.finalizeUpdatePreparation(
                    sourceURL: sourceURL,
                    publishingDirectoryURL: url
                )
                ComponentPackageCatalog.shared.reloadAllPacks()
                resetReleaseVersion(for: try? FoundryPackLoader.load(from: sourceURL))
                resultMessage = "Published the update endpoint successfully."
            } catch is CancellationError {
                errorMessage = "Preparation was cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func issueUpdate(sourceURL: URL) {
        guard let pack = try? FoundryPackLoader.load(from: sourceURL),
              let packID = pack.identifier else { return }
        let version = releaseVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let site = ComponentUpdatePublisherConfiguration.site
        let credential = PublishingCredentialStore.credential(site: site)
        let outputDirectoryURL = FileManager.default.temporaryDirectory.appending(
            path: "Foundry-Release-Output-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let notes = releaseNotes.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let request = FoundryPackReleaseBuilder.Request(
            sourceURL: sourceURL,
            outputDirectoryURL: outputDirectoryURL,
            version: version,
            releaseNotes: notes
        )
        isWorking = true
        operationProgress = 0
        resultMessage = nil
        errorMessage = nil
        workingTask?.cancel()
        workingTask = Task {
            defer { try? FileManager.default.removeItem(at: outputDirectoryURL) }
            do {
                guard let configuration = pack.metadata.updates else {
                    throw FoundryPackUpdateError.invalidMetadata("Prepare this pack for updates before issuing a release.")
                }
                try validatePublishingDestination(site: site, configuration: configuration, packID: packID)
                let result = try await FoundryPackReleaseBuilder.create(request)
                try Task.checkCancellation()
                try await ComponentUpdatePublisher.publish(
                    directory: result.outputDirectoryURL,
                    packID: packID,
                    site: site,
                    credential: credential,
                    progress: { progress in
                        Task { @MainActor in
                            operationProgress = progress
                        }
                    }
                )
                try await verifyPublishedRelease(
                    appcastURL: configuration.appcastURL,
                    packID: packID,
                    version: version
                )
                resultMessage = "Published and verified version \(version)."
                releaseNotes = [ReleaseNoteDraft()]
                releaseVersion = version
                incrementVersion(.patch, from: version)
            } catch is CancellationError {
                errorMessage = "Publishing was cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private enum VersionComponent {
        case major
        case minor
        case patch
    }

    private var isValidReleaseVersion: Bool {
        guard let source = selectedPack?.metadata.version.flatMap(SemanticVersion.init),
              let release = SemanticVersion(releaseVersion.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return release > source
    }

    private func incrementVersion(_ component: VersionComponent, from fallback: String) {
        let value = SemanticVersion(releaseVersion) == nil ? fallback : releaseVersion
        let core = value.split(separator: "+", maxSplits: 1)[0]
            .split(separator: "-", maxSplits: 1)[0]
            .split(separator: ".")
            .compactMap { Int($0) }
        guard core.count == 3 else { return }

        switch component {
        case .major:
            releaseVersion = "\(core[0] + 1).0.0"
        case .minor:
            releaseVersion = "\(core[0]).\(core[1] + 1).0"
        case .patch:
            releaseVersion = "\(core[0]).\(core[1]).\(core[2] + 1)"
        }
    }

    private func resetReleaseVersion(for pack: FoundryPack?) {
        guard let currentVersion = pack?.metadata.version else {
            releaseVersion = ""
            return
        }
        releaseVersion = currentVersion
        if pack?.metadata.updates != nil {
            incrementVersion(.patch, from: currentVersion)
        }
    }

    private var publisherIsConfigured: Bool {
        let site = ComponentUpdatePublisherConfiguration.site
        return [.ftp, .ftps, .sftp].contains(site.publishingDestination)
            && !site.publishingHost.isEmpty
            && !site.publishingUsername.isEmpty
            && !site.publishingRemotePath.isEmpty
            && URL(string: site.publicURL)?.scheme == "https"
    }

    private func publishingURL(for sourceURL: URL?) -> String? {
        guard let sourceURL,
              let identifier = try? FoundryPackLoader.load(from: sourceURL).identifier else { return nil }
        return URL(string: ComponentUpdatePublisherConfiguration.site.publicURL)?
            .appending(path: identifier)
            .absoluteString
    }

    private func verifyPublishedRelease(appcastURL: URL, packID: String, version: String) async throws {
        var request = URLRequest(url: appcastURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw FoundryPackUpdateError.invalidMetadata("The published appcast could not be reached.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let appcast = try decoder.decode(FoundryPackAppcast.self, from: data)
        guard appcast.packID == packID else {
            throw FoundryPackUpdateError.wrongPack(appcast.packID)
        }
        let matches = appcast.releases.filter { $0.version == version }
        guard matches.count == 1 else {
            throw FoundryPackUpdateError.invalidMetadata("The published appcast does not contain version \(version).")
        }
        let releaseDirectoryURL = appcastURL
            .deletingLastPathComponent()
            .appending(path: "\(packID) \(version)", directoryHint: .isDirectory)
        let expectedDownloadURL = releaseDirectoryURL
            .appending(path: "\(packID) \(version).foundrypack.zip")
        let expectedReleaseNotesURL = releaseDirectoryURL.appending(path: "release-notes.html")
        guard matches[0].downloadURL == expectedDownloadURL,
              matches[0].releaseNotesURL == expectedReleaseNotesURL else {
            throw FoundryPackUpdateError.invalidMetadata(
                "The published release URLs do not match the configured publishing directory."
            )
        }
    }

    private func verifyPublishedEndpoint(appcastURL: URL) async throws {
        var request = URLRequest(url: appcastURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw FoundryPackUpdateError.invalidMetadata("The published update endpoint could not be reached.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let appcast = try decoder.decode(FoundryPackAppcast.self, from: data)
        guard appcast.formatVersion == FoundryPackAppcast.currentFormatVersion else {
            throw FoundryPackUpdateError.unsupportedAppcast(appcast.formatVersion)
        }
    }

    private func validatePublishingDestination(
        site: Site,
        configuration: FoundryPackUpdateConfiguration,
        packID: String
    ) throws {
        guard let configuredAppcastURL = URL(string: site.publicURL)?
            .appending(path: packID)
            .appending(path: "appcast.php"),
              configuredAppcastURL == configuration.appcastURL else {
            throw FoundryPackUpdateError.invalidMetadata(
                "Publishing settings have changed since this pack was prepared. Restore those settings or prepare the pack again before publishing."
            )
        }
    }

    private func isValidPublishingDirectoryURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme?.lowercased() == "https"
            && url.host != nil
            && url.query == nil
            && url.fragment == nil
    }
}

private struct DeveloperReleaseStatus: View {
    let isWorking: Bool
    let progress: Double
    let resultMessage: String?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isWorking {
                ProgressView("Uploading…", value: progress, total: 1)
            }
            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
        }
    }
}

private struct DeveloperPackageIssue: Identifiable {
    let url: URL
    let diagnostics: [ComponentPackageDiagnostic]
    let displayName: String
    let identifier: String?

    var id: URL { url }
    var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

    init(url: URL, diagnostics: [ComponentPackageDiagnostic]) {
        self.url = url
        self.diagnostics = diagnostics

        let manifestURL = url.appending(path: "Contents/Info.plist")
        let manifest: [String: Any]?
        if let data = try? Data(contentsOf: manifestURL),
           let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            manifest = propertyList as? [String: Any]
        } else {
            manifest = nil
        }
        let title = manifest?["title"] as? String
        let identifier = manifest?["id"] as? String
        displayName = title.flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        self.identifier = identifier?.isEmpty == false ? identifier : nil
    }
}

private struct DeveloperPackageIssueCard: View {
    let issue: DeveloperPackageIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: issue.hasErrors ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.hasErrors ? .red : .orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.displayName)
                        .font(.headline)
                    Text(issue.hasErrors ? "Failed to load" : "Loaded with warnings")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(issue.hasErrors ? .red : .orange)
                    if let identifier = issue.identifier {
                        Text(identifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 8)

                Button("Show in Finder", systemImage: "macwindow.and.pointer.arrow") {
                    NSWorkspace.shared.activateFileViewerSelecting([issue.url])
                }
                .labelStyle(.iconOnly)
                .help("Show package in Finder")
            }

            Divider()

            ForEach(Array(issue.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: diagnostic.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnostic.message)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text(diagnostic.location)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Text(issue.url.path(percentEncoded: false))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ComponentLibrarySection: Identifiable {
    let id: String
    let title: String
    let types: [ComponentType]
}

struct ReusableComponentLibraryPanel: View {
    let definitions: [ReusableComponentDefinition]
    let renameDefinition: (UUID, String) -> Void
    let deleteDefinition: (UUID) -> Void
    @State private var definitionToRename: ReusableComponentDefinition?
    @State private var definitionToDelete: ReusableComponentDefinition?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(definitions) { definition in
                ReusableComponentLibraryRow(definition: definition)
                    .draggable(ComponentDragPayload.reusable(definition.id).stringValue) {
                        ComponentDragPreview(
                            name: definition.name,
                            systemImage: definition.root.type.systemImage
                        )
                    }
                    .contextMenu {
                        Button("Rename…") {
                            renameText = definition.name
                            definitionToRename = definition
                        }
                        Button("Delete…", role: .destructive) {
                            definitionToDelete = definition
                        }
                    }
            }
        }
        .overlay {
            if definitions.isEmpty {
                ContentUnavailableView(
                    "No Reusable Components",
                    systemImage: "square.stack.3d.up",
                    description: Text("Save a component from Structure to add it here.")
                )
            }
        }
        .alert("Rename Reusable Component", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { definitionToRename = nil }
            Button("Rename") {
                guard let id = definitionToRename?.id else { return }
                renameDefinition(id, renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                definitionToRename = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Delete \(definitionToDelete?.name ?? "Reusable Component")?",
            isPresented: deleteAlertBinding
        ) {
            Button("Delete Reusable Component", role: .destructive) {
                guard let id = definitionToDelete?.id else { return }
                deleteDefinition(id)
                definitionToDelete = nil
            }
            Button("Cancel", role: .cancel) { definitionToDelete = nil }
        } message: {
            Text("Components already added from this reusable item are independent and will be unchanged.")
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { definitionToRename != nil }, set: { if !$0 { definitionToRename = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { definitionToDelete != nil }, set: { if !$0 { definitionToDelete = nil } })
    }
}

private struct ComponentLibraryTile: View {
    let type: ComponentType
    let iconSize: ComponentLibraryIconSize
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Group {
                if iconSize == .list {
                    HStack(spacing: 8) {
                        componentIcon
                        componentTitle
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: iconSize.tileSize, maxHeight: iconSize.tileSize)
                } else {
                    VStack(spacing: 6) {
                        componentIcon
                        componentTitle
                            .frame(maxWidth: .infinity)
                    }
                    .padding(6)
                    .frame(width: iconSize.tileSize, height: iconSize.tileSize)
                }
            }
            .background(
                isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName), drag to add")
        .accessibilityIdentifier("component-library-\(type.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var componentIcon: some View {
        ComponentLibraryIcon(
            type: type,
            size: iconSize.iconSize,
            symbolColor: isSelected ? .white : .accentColor
        )
    }

    private var componentTitle: some View {
        Text(type.displayName)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .font(.caption)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
    }
}

struct ComponentLibraryIcon: View {
    @State private var loadedIcon: NSImage?
    let type: ComponentType
    let size: CGFloat
    var symbolColor: Color = .accentColor

    var body: some View {
        Group {
            if let image = displayedIcon {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: type.systemImage)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(symbolColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16))
        .accessibilityHidden(true)
        .task(id: type.definition.package?.iconURL) {
            guard let url = type.definition.package?.iconURL else {
                loadedIcon = nil
                return
            }
            if let cached = ComponentIconLoader.cachedIcon(at: url) {
                loadedIcon = cached.image
                return
            }
            loadedIcon = await ComponentIconLoader.shared.icon(at: url)?.image
        }
    }

    private var displayedIcon: NSImage? {
        loadedIcon ?? (type.definition.package?.iconURL).flatMap {
            ComponentIconLoader.cachedIcon(at: $0)?.image
        }
    }
}

private struct ComponentDragPreview: View {
    let name: String
    let systemImage: String

    var body: some View {
        Label(name, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 150, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

private struct ReusableComponentLibraryRow: View {
    let definition: ReusableComponentDefinition

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: definition.root.type.systemImage)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                Text("Reusable component")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(definition.name), reusable component, drag to add")
    }
}

struct GlobalComponentLibraryPanel: View {
    let definitions: [ReusableComponentDefinition]
    let renameDefinition: (UUID, String) -> Void
    let deleteDefinition: (UUID) -> Void
    let saveDraggedComponents: ([UUID]) -> Bool
    @State private var definitionToRename: ReusableComponentDefinition?
    @State private var definitionToDelete: ReusableComponentDefinition?
    @State private var renameText = ""
    @State private var isDropTargeted = false

    var body: some View {
        List {
            ForEach(definitions) { definition in
                HStack(spacing: 10) {
                    Image(systemName: definition.root.type.systemImage)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(definition.name)
                        Text("Updates everywhere")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "link")
                        .foregroundStyle(.tertiary)
                }
                .draggable(ComponentDragPayload.global(definition.id).stringValue) {
                    ComponentDragPreview(name: definition.name, systemImage: definition.root.type.systemImage)
                }
                .contextMenu {
                    Button("Rename…") {
                        renameText = definition.name
                        definitionToRename = definition
                    }
                    Button("Delete…", role: .destructive) { definitionToDelete = definition }
                }
            }
        }
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first,
                  let payload = ComponentDragPayload(value) else { return false }
            switch payload {
            case .node(let id):
                return saveDraggedComponents([id])
            case .nodes(let ids):
                return saveDraggedComponents(ids)
            case .library, .reusable, .global:
                return false
            }
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if definitions.isEmpty {
                ContentUnavailableView(
                    "No Global Components",
                    systemImage: "globe",
                    description: Text("Save a component as global from Structure to add it here.")
                )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: isDropTargeted ? 2 : 0)
                .padding(4)
                .allowsHitTesting(false)
        }
        .alert("Rename Global Component", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { definitionToRename = nil }
            Button("Rename") {
                guard let id = definitionToRename?.id else { return }
                renameDefinition(id, renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                definitionToRename = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Delete \(definitionToDelete?.name ?? "Global Component")?", isPresented: deleteAlertBinding) {
            Button("Delete Global Component", role: .destructive) {
                guard let id = definitionToDelete?.id else { return }
                deleteDefinition(id)
                definitionToDelete = nil
            }
            Button("Cancel", role: .cancel) { definitionToDelete = nil }
        } message: {
            Text("Existing instances will be detached and keep their current content.")
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { definitionToRename != nil }, set: { if !$0 { definitionToRename = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { definitionToDelete != nil }, set: { if !$0 { definitionToDelete = nil } })
    }
}

struct StructurePanel: View {
    let page: Page?
    let globalComponentNames: [UUID: String]
    @Binding var selectedComponentIDs: Set<UUID>
    @Binding var selectedComponentID: UUID?
    @Binding var expandedComponentIDs: Set<UUID>
    let renameComponent: (UUID, String) -> Void
    let canMoveComponentsToPlacement: ([UUID], ComponentPlacement) -> Bool
    let moveComponentsToPlacement: ([UUID], ComponentPlacement) -> Bool
    let insertComponent: (ComponentType, ComponentPlacement) -> Bool
    let insertReusableComponent: (UUID, ComponentPlacement) -> Bool
    let insertGlobalComponent: (UUID, ComponentPlacement) -> Bool
    let duplicateComponent: () -> Void
    let copyComponent: () -> Void
    let pasteComponent: () -> Void
    let moveComponent: (Int) -> Void
    let outdentComponent: () -> Void
    let deleteComponent: () -> Void
    let canPasteComponent: Bool
    let saveReusableComponent: (String) -> Void
    let saveGlobalComponent: (String) -> Void
    let setGlobalComponentLinked: (UUID, Bool) -> Void
    @State private var isNamingReusableComponent = false
    @State private var reusableComponentName = ""
    @State private var isNamingGlobalComponent = false
    @State private var globalComponentName = ""

    var body: some View {
        VStack(spacing: 0) {
            if let page {
                StructureOutlineView(
                    components: page.components,
                    globalComponentNames: globalComponentNames,
                    selectedComponentIDs: $selectedComponentIDs,
                    primarySelectedComponentID: $selectedComponentID,
                    expandedItemIDs: $expandedComponentIDs,
                    renameComponent: renameComponent,
                    canMoveComponents: canMoveComponentsToPlacement,
                    moveComponents: moveComponentsToPlacement,
                    insertComponent: insertComponent,
                    insertReusableComponent: insertReusableComponent,
                    insertGlobalComponent: insertGlobalComponent,
                    duplicateComponent: duplicateComponent,
                    copyComponent: copyComponent,
                    pasteComponent: pasteComponent,
                    canPasteComponent: canPasteComponent,
                    saveAsReusableComponent: {
                        reusableComponentName = $0
                        isNamingReusableComponent = true
                    },
                    saveAsGlobalComponent: {
                        globalComponentName = $0
                        isNamingGlobalComponent = true
                    },
                    setGlobalComponentLinked: setGlobalComponentLinked,
                    moveComponent: moveComponent,
                    outdentComponent: outdentComponent,
                    deleteComponent: deleteComponent
                )
            } else {
                ContentUnavailableView("No Page", systemImage: "doc")
            }
        }
        .alert("Save Reusable Component", isPresented: $isNamingReusableComponent) {
            TextField("Name", text: $reusableComponentName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveReusableComponent(reusableComponentName) }
                .disabled(reusableComponentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The selected component and its children will be available in the Project library.")
        }
        .alert("Save Global Component", isPresented: $isNamingGlobalComponent) {
            TextField("Name", text: $globalComponentName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveGlobalComponent(globalComponentName) }
                .disabled(globalComponentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Every linked instance will update when this global component is edited.")
        }
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard let selectedComponentID, let page else { return }
        expandedComponentIDs.formUnion(page.components.ancestorIDs(of: selectedComponentID))
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(selectedComponentID, anchor: .center)
        }
    }

    private func acceptAtEnd(_ payload: ComponentDragPayload) -> Bool {
        switch payload {
        case .library(let type): insertComponent(type, .end)
        case .reusable(let id): insertReusableComponent(id, .end)
        case .global(let id): insertGlobalComponent(id, .end)
        case .node(let id): moveComponentsToPlacement([id], .end)
        case .nodes(let ids): moveComponentsToPlacement(ids, .end)
        }
    }

    private func visibleComponents(in page: Page) -> [StructureTreeItem] {
        StructureTreeItem.flatten(page.components, expandedIDs: expandedComponentIDs)
    }

    private func applyReorder(
        _ difference: ReorderDifference<UUID, ReorderableSingleCollectionIdentifier>
    ) {
        let placement: ComponentPlacement
        switch difference.destination.position {
        case .before(let targetID):
            placement = .before(targetID)
        case .end:
            placement = .end
        }
        for sourceID in difference.sources {
            _ = moveComponentsToPlacement([sourceID], placement)
        }
    }

}

nonisolated struct StructureTreeItem: Identifiable, Sendable {
    let component: ComponentNode
    let depth: Int

    var id: UUID { component.id }

    static func flatten(
        _ components: [ComponentNode],
        expandedIDs: Set<UUID>,
        depth: Int = 0
    ) -> [StructureTreeItem] {
        components.flatMap { component in
            var result = [StructureTreeItem(component: component, depth: depth)]
            if expandedIDs.contains(component.id) {
                result += flatten(component.children, expandedIDs: expandedIDs, depth: depth + 1)
            }
            return result
        }
    }
}

private struct StructureEndDropZone: View {
    let isEmpty: Bool
    let accept: (ComponentDragPayload) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Label(
            isEmpty ? "Drop a component here" : "Drop at page end",
            systemImage: isEmpty ? "square.and.arrow.down" : "arrow.down.to.line"
        )
        .font(.caption)
        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: isEmpty ? 64 : 28)
        .background(
            isTargeted ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(isEmpty ? 0.35 : 0),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let payload = ComponentDragPayload(value) else { return false }
            return accept(payload)
        } isTargeted: {
            isTargeted = $0
        }
    }
}
