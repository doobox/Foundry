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

struct PartLibraryPanel: View {
    @Binding var selectedType: PartType?
    let addToPageEnd: (PartType) -> Void
    @State private var catalog = PartPackageCatalog.shared
    @State private var partSource = PartLibrarySource.parts
    @AppStorage(AppPreferenceKey.partLibraryIconSize)
    private var iconSizeValue = PartLibraryIconSize.small.rawValue
    @AppStorage(AppPreferenceKey.partLibraryArrangement)
    private var arrangementValue = PartLibraryArrangement.group.rawValue
    @AppStorage(AppPreferenceKey.showsHiddenParts)
    private var showsHiddenParts = false

    var body: some View {
        let _ = catalog.revision
        VStack(spacing: 0) {
            PartLibraryPanelHeader(
                iconSize: iconSize,
                setIconSize: { iconSizeValue = $0.rawValue },
                arrangement: arrangement,
                setArrangement: { arrangementValue = $0.rawValue }
            )
            Divider()
            if catalog.isInitialLoading {
                PartCatalogLoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if hasDevelopmentParts {
                    Picker("Part source", selection: $partSource) {
                        ForEach(PartLibrarySource.allCases) { source in
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
                        ForEach(partSections) { section in
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
                                        PartLibraryTile(
                                            type: type,
                                            iconSize: iconSize,
                                            isSelected: selectedType == type,
                                            select: { selectedType = type }
                                        )
                                        .draggable(PartDragPayload.library(type).stringValue) {
                                            PartLibraryIcon(type: type, size: 54)
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
            if !hasDevelopmentParts {
                partSource = .parts
            }
            if let selectedType, availableTypes.contains(selectedType) {
                return
            }
            selectedType = availableTypes.first
        }
        .onChange(of: partSource) {
            selectedType = availableTypes.first
        }
        .onChange(of: showsHiddenParts) {
            if let selectedType, availableTypes.contains(selectedType) {
                return
            }
            selectedType = availableTypes.first
        }
    }

    private var partSections: [PartLibrarySection] {
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

    private func groupSections(for types: [PartType]) -> [PartLibrarySection] {
        let preferredCategories: [PartCategory] = [
            .layout, .content, .media, .navigation, .forms, .interactive, .other
        ]
        let remainingCategories = Set(types.map { $0.definition.category })
            .subtracting(preferredCategories)
            .sorted { $0.rawValue < $1.rawValue }
        return (preferredCategories + remainingCategories).compactMap { category in
            let categoryTypes = types.filter { $0.definition.category == category }
            guard !categoryTypes.isEmpty else { return nil }
            return PartLibrarySection(
                id: "group-\(category.rawValue)",
                title: category.rawValue,
                types: categoryTypes
            )
        }
    }

    private func metadataSections(
        for types: [PartType],
        value: (PartType) -> String?
    ) -> [PartLibrarySection] {
        var grouped: [String: [PartType]] = [:]
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
        types: [PartType]
    ) -> PartLibrarySection {
        PartLibrarySection(
            id: id,
            title: title,
            types: types.sorted {
                let comparison = $0.displayName.localizedStandardCompare($1.displayName)
                if comparison == .orderedSame { return $0.rawValue < $1.rawValue }
                return comparison == .orderedAscending
            }
        )
    }

    private var availableTypes: [PartType] {
        PartType.allCases.filter { type in
            let isDevelopmentPack = type.definition.package?.isDevelopmentPack == true
            let showsInLibrary = type.definition.package?.manifest.showsInPartLibrary ?? true
            return (showsInLibrary || showsHiddenParts)
                && (partSource == .development ? isDevelopmentPack : !isDevelopmentPack)
        }
    }

    private var hasDevelopmentParts: Bool {
        PartType.allCases.contains {
            $0.definition.package?.isDevelopmentPack == true
                && (($0.definition.package?.manifest.showsInPartLibrary ?? true) || showsHiddenParts)
        }
    }

    private var iconSize: PartLibraryIconSize {
        PartLibraryIconSize(rawValue: iconSizeValue) ?? .medium
    }

    private var arrangement: PartLibraryArrangement {
        PartLibraryArrangement(rawValue: arrangementValue) ?? .group
    }
}

nonisolated private enum PartLibrarySource: String, CaseIterable, Identifiable {
    case parts
    case development

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .parts: "Parts"
        case .development: "Dev Parts"
        }
    }
}

private struct PartLibraryPanelHeader: View {
    let iconSize: PartLibraryIconSize
    let setIconSize: (PartLibraryIconSize) -> Void
    let arrangement: PartLibraryArrangement
    let setArrangement: (PartLibraryArrangement) -> Void

    var body: some View {
        HStack {
            Text("Parts")
                .font(.headline)
            Spacer()
            Menu {
                Menu("Icon Size") {
                    ForEach(PartLibraryIconSize.allCases) { size in
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
                    ForEach(PartLibraryArrangement.allCases) { option in
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
            .help("Part view options")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

nonisolated private enum PartLibraryArrangement: String, CaseIterable, Identifiable {
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

nonisolated private enum PartLibraryIconSize: String, CaseIterable, Identifiable {
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
    @State private var catalog = PartPackageCatalog.shared
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
                openWindow(id: "part-updates")
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
        guard !issues.isEmpty else { return "Parts are healthy" }
        return issues.count == 1 ? "1 part needs attention" : "\(issues.count) parts need attention"
    }

    private var summaryDescription: String {
        guard !issues.isEmpty else { return "All discovered part packages loaded successfully." }
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
                Button("Reload Parts", systemImage: "arrow.clockwise", action: reload)
                    .labelStyle(.iconOnly)
                    .help("Reload part packages")
            }
            .padding(12)
            Divider()
            if issues.isEmpty {
                ContentUnavailableView(
                    "No Part Issues",
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
                systemImage: PartDefinition.genericSystemImage,
                description: Text("Convert a part pack to .foundrydevpack before issuing updates.")
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
        let site = PartUpdatePublisherConfiguration.site
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
                try await PartUpdatePublisher.publishSetup(
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
                PartPackageCatalog.shared.reloadAllPacks()
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
        let site = PartUpdatePublisherConfiguration.site
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
                try await PartUpdatePublisher.publish(
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

    private func incrementVersion(_ part: VersionComponent, from fallback: String) {
        let value = SemanticVersion(releaseVersion) == nil ? fallback : releaseVersion
        let core = value.split(separator: "+", maxSplits: 1)[0]
            .split(separator: "-", maxSplits: 1)[0]
            .split(separator: ".")
            .compactMap { Int($0) }
        guard core.count == 3 else { return }

        switch part {
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
        let site = PartUpdatePublisherConfiguration.site
        return [.ftp, .ftps, .sftp].contains(site.publishingDestination)
            && !site.publishingHost.isEmpty
            && !site.publishingUsername.isEmpty
            && !site.publishingRemotePath.isEmpty
            && URL(string: site.publicURL)?.scheme == "https"
    }

    private func publishingURL(for sourceURL: URL?) -> String? {
        guard let sourceURL,
              let identifier = try? FoundryPackLoader.load(from: sourceURL).identifier else { return nil }
        return URL(string: PartUpdatePublisherConfiguration.site.publicURL)?
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
    let diagnostics: [PartPackageDiagnostic]
    let displayName: String
    let identifier: String?

    var id: URL { url }
    var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

    init(url: URL, diagnostics: [PartPackageDiagnostic]) {
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

private struct PartLibrarySection: Identifiable {
    let id: String
    let title: String
    let types: [PartType]
}

struct ReusablePartLibraryPanel: View {
    let definitions: [ReusablePartDefinition]
    let renameDefinition: (UUID, String) -> Void
    let deleteDefinition: (UUID) -> Void
    @State private var definitionToRename: ReusablePartDefinition?
    @State private var definitionToDelete: ReusablePartDefinition?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(definitions) { definition in
                ReusablePartLibraryRow(definition: definition)
                    .draggable(PartDragPayload.reusable(definition.id).stringValue) {
                        PartDragPreview(
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
                    "No Templates",
                    systemImage: WorkspacePanel.reusableParts.systemImage,
                    description: Text("Save a part as a template from Structure to add it here.")
                )
            }
        }
        .alert("Rename Template", isPresented: renameAlertBinding) {
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
            "Delete \(definitionToDelete?.name ?? "Template")?",
            isPresented: deleteAlertBinding
        ) {
            Button("Delete Template", role: .destructive) {
                guard let id = definitionToDelete?.id else { return }
                deleteDefinition(id)
                definitionToDelete = nil
            }
            Button("Cancel", role: .cancel) { definitionToDelete = nil }
        } message: {
            Text("Parts already added from this template are independent and will be unchanged.")
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { definitionToRename != nil }, set: { if !$0 { definitionToRename = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { definitionToDelete != nil }, set: { if !$0 { definitionToDelete = nil } })
    }
}

private struct PartLibraryTile: View {
    let type: PartType
    let iconSize: PartLibraryIconSize
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Group {
                if iconSize == .list {
                    HStack(spacing: 8) {
                        partIcon
                        partTitle
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: iconSize.tileSize, maxHeight: iconSize.tileSize)
                } else {
                    VStack(spacing: 6) {
                        partIcon
                        partTitle
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
        .accessibilityIdentifier("part-library-\(type.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var partIcon: some View {
        PartLibraryIcon(
            type: type,
            size: iconSize.iconSize,
            symbolColor: isSelected ? .white : .accentColor
        )
    }

    private var partTitle: some View {
        Text(type.displayName)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .font(.caption)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
    }
}

struct PartLibraryIcon: View {
    @State private var loadedIcon: NSImage?
    let type: PartType
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
            if let cached = PartIconLoader.cachedIcon(at: url) {
                loadedIcon = cached.image
                return
            }
            loadedIcon = await PartIconLoader.shared.icon(at: url)?.image
        }
    }

    private var displayedIcon: NSImage? {
        loadedIcon ?? (type.definition.package?.iconURL).flatMap {
            PartIconLoader.cachedIcon(at: $0)?.image
        }
    }
}

private struct PartDragPreview: View {
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

private struct ReusablePartLibraryRow: View {
    let definition: ReusablePartDefinition

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: definition.root.type.systemImage)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                Text("Template")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(definition.name), template, drag to add")
    }
}

struct GlobalPartLibraryPanel: View {
    let definitions: [ReusablePartDefinition]
    let renameDefinition: (UUID, String) -> Void
    let deleteDefinition: (UUID) -> Void
    let saveDraggedParts: ([UUID]) -> Bool
    @State private var definitionToRename: ReusablePartDefinition?
    @State private var definitionToDelete: ReusablePartDefinition?
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
                .draggable(PartDragPayload.global(definition.id).stringValue) {
                    PartDragPreview(name: definition.name, systemImage: definition.root.type.systemImage)
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
                  let payload = PartDragPayload(value) else { return false }
            switch payload {
            case .node(let id):
                return saveDraggedParts([id])
            case .nodes(let ids):
                return saveDraggedParts(ids)
            case .library, .reusable, .global:
                return false
            }
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if definitions.isEmpty {
                ContentUnavailableView(
                    "No Global Parts",
                    systemImage: WorkspacePanel.globalParts.systemImage,
                    description: Text("Save a part as global from Structure to add it here.")
                )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: isDropTargeted ? 2 : 0)
                .padding(4)
                .allowsHitTesting(false)
        }
        .alert("Rename Global Part", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { definitionToRename = nil }
            Button("Rename") {
                guard let id = definitionToRename?.id else { return }
                renameDefinition(id, renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                definitionToRename = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Delete \(definitionToDelete?.name ?? "Global Part")?", isPresented: deleteAlertBinding) {
            Button("Delete Global Part", role: .destructive) {
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
    let globalPartNames: [UUID: String]
    @Binding var selectedPartIDs: Set<UUID>
    @Binding var selectedPartID: UUID?
    @Binding var isPageSelected: Bool
    @Binding var expandedPartIDs: Set<UUID>
    let renamePart: (UUID, String) -> Void
    let canMovePartsToPlacement: ([UUID], PartPlacement) -> Bool
    let movePartsToPlacement: ([UUID], PartPlacement) -> Bool
    let insertPart: (PartType, PartPlacement) -> Bool
    let insertReusablePart: (UUID, PartPlacement) -> Bool
    let insertGlobalPart: (UUID, PartPlacement) -> Bool
    let duplicatePart: () -> Void
    let copyPart: () -> Void
    let pastePart: () -> Void
    let movePart: (Int) -> Void
    let outdentPart: () -> Void
    let deletePart: () -> Void
    let canPastePart: Bool
    let saveReusablePart: (String) -> Void
    let saveGlobalPart: (String) -> Void
    let setGlobalPartLinked: (UUID, Bool) -> Void
    @State private var isNamingReusablePart = false
    @State private var reusablePartName = ""
    @State private var isNamingGlobalPart = false
    @State private var globalPartName = ""
    @State private var isPageExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            if let page {
                StructureOutlineView(
                    page: page,
                    globalPartNames: globalPartNames,
                    selectedPartIDs: $selectedPartIDs,
                    primarySelectedPartID: $selectedPartID,
                    isPageSelected: $isPageSelected,
                    isPageExpanded: $isPageExpanded,
                    expandedItemIDs: $expandedPartIDs,
                    renamePart: renamePart,
                    canMoveParts: canMovePartsToPlacement,
                    moveParts: movePartsToPlacement,
                    insertPart: insertPart,
                    insertReusablePart: insertReusablePart,
                    insertGlobalPart: insertGlobalPart,
                    duplicatePart: duplicatePart,
                    copyPart: copyPart,
                    pastePart: pastePart,
                    canPastePart: canPastePart,
                    saveAsReusablePart: {
                        reusablePartName = $0
                        isNamingReusablePart = true
                    },
                    saveAsGlobalPart: {
                        globalPartName = $0
                        isNamingGlobalPart = true
                    },
                    setGlobalPartLinked: setGlobalPartLinked,
                    movePart: movePart,
                    outdentPart: outdentPart,
                    deletePart: deletePart
                )
            } else {
                ContentUnavailableView("No Page", systemImage: "doc")
            }
        }
        .alert("Save Template", isPresented: $isNamingReusablePart) {
            TextField("Name", text: $reusablePartName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveReusablePart(reusablePartName) }
                .disabled(reusablePartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The selected part and its children will be available in the Project library.")
        }
        .alert("Save Global Part", isPresented: $isNamingGlobalPart) {
            TextField("Name", text: $globalPartName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveGlobalPart(globalPartName) }
                .disabled(globalPartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Every linked instance will update when this global part is edited.")
        }
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard let selectedPartID, let page else { return }
        expandedPartIDs.formUnion(page.parts.ancestorIDs(of: selectedPartID))
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(selectedPartID, anchor: .center)
        }
    }

    private func acceptAtEnd(_ payload: PartDragPayload) -> Bool {
        switch payload {
        case .library(let type): insertPart(type, .end)
        case .reusable(let id): insertReusablePart(id, .end)
        case .global(let id): insertGlobalPart(id, .end)
        case .node(let id): movePartsToPlacement([id], .end)
        case .nodes(let ids): movePartsToPlacement(ids, .end)
        }
    }

    private func visibleParts(in page: Page) -> [StructureTreeItem] {
        StructureTreeItem.flatten(page.parts, expandedIDs: expandedPartIDs)
    }

    private func applyReorder(
        _ difference: ReorderDifference<UUID, ReorderableSingleCollectionIdentifier>
    ) {
        let placement: PartPlacement
        switch difference.destination.position {
        case .before(let targetID):
            placement = .before(targetID)
        case .end:
            placement = .end
        }
        for sourceID in difference.sources {
            _ = movePartsToPlacement([sourceID], placement)
        }
    }

}

nonisolated struct StructureTreeItem: Identifiable, Sendable {
    let part: PartNode
    let depth: Int

    var id: UUID { part.id }

    static func flatten(
        _ parts: [PartNode],
        expandedIDs: Set<UUID>,
        depth: Int = 0
    ) -> [StructureTreeItem] {
        parts.flatMap { part in
            var result = [StructureTreeItem(part: part, depth: depth)]
            if expandedIDs.contains(part.id) {
                result += flatten(part.children, expandedIDs: expandedIDs, depth: depth + 1)
            }
            return result
        }
    }
}

private struct StructureEndDropZone: View {
    let isEmpty: Bool
    let accept: (PartDragPayload) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Label(
            isEmpty ? "Drop a part here" : "Drop at page end",
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
            guard let value = values.first, let payload = PartDragPayload(value) else { return false }
            return accept(payload)
        } isTargeted: {
            isTargeted = $0
        }
    }
}
