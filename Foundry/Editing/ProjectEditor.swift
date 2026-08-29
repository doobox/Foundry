import Foundation

@MainActor
struct ProjectEditor {
    let document: FoundryDocument
    let undoManager: UndoManager?

    func setSiteName(_ name: String) {
        mutate(actionName: "Rename Site") { $0.name = name }
    }

    func setSiteLanguage(_ language: String) {
        mutate(actionName: "Edit Site Language") { $0.language = language }
    }

    func renameComponent(id: UUID, name: String) {
        mutate(actionName: "Rename Component") { site in
            site.updateComponent(id: id) { $0.name = name }
        }
    }

    func setProperty(
        id: UUID,
        key: ComponentProperty.Key,
        value: ComponentProperty.Value
    ) {
        mutate(actionName: "Edit Component") { site in
            site.updateComponent(id: id) { $0.setProperty(key, value: value) }
        }
    }

    func setProperty(id: UUID, key: ComponentProperty.Key, value: String) {
        let propertyValue: ComponentProperty.Value =
            key == .destination ? .url(value) : .string(value)
        setProperty(id: id, key: key, value: propertyValue)
    }

    func setResponsiveProperty(
        id: UUID,
        key: ComponentProperty.Key,
        value: ComponentProperty.Value,
        breakpoint: ResponsiveBreakpoint
    ) {
        mutate(actionName: "Edit \(breakpoint.displayName) Component") { site in
            site.updateComponent(id: id) {
                $0.setResponsiveProperty(key, value: value, at: breakpoint)
            }
        }
    }

    func removeResponsiveOverride(id: UUID, key: ComponentProperty.Key, breakpoint: ResponsiveBreakpoint) {
        mutate(actionName: "Reset \(breakpoint.displayName) Component") { site in
            site.updateComponent(id: id) { $0.removeResponsiveOverride(key, at: breakpoint) }
        }
    }

    func setThemeColor(_ token: DesignToken, value: String) {
        mutate(actionName: "Edit Theme Color") { site in
            switch token {
            case .backgroundColor: site.theme.colors.background = value
            case .surfaceColor: site.theme.colors.surface = value
            case .textColor: site.theme.colors.text = value
            case .accentColor: site.theme.colors.accent = value
            case .smallSpacing, .mediumSpacing, .largeSpacing: break
            }
        }
    }

    func setThemeSpacing(_ token: DesignToken, value: Double) {
        mutate(actionName: "Edit Theme Spacing") { site in
            switch token {
            case .smallSpacing: site.theme.spacing.small = value
            case .mediumSpacing: site.theme.spacing.medium = value
            case .largeSpacing: site.theme.spacing.large = value
            case .backgroundColor, .surfaceColor, .textColor, .accentColor: break
            }
        }
    }

    func setThemeBodyFont(_ value: String) {
        setThemeFont(value, for: .body)
    }

    func setThemeFont(_ value: String, for role: ThemeFontRole) {
        mutate(actionName: "Edit Theme Font Family") { site in
            switch role {
            case .body: site.theme.typography.bodyFont.family = value
            case .heading: site.theme.typography.headingFont.family = value
            case .monospaced: site.theme.typography.monospacedFont.family = value
            }
        }
    }

    @discardableResult
    func addThemeCustomFont() -> UUID {
        let font = ThemeCustomFont(
            name: "Custom Font",
            font: .system(family: "system-ui", weights: [400, 700])
        )
        mutate(actionName: "Add Theme Font") { $0.theme.typography.customFonts.append(font) }
        return font.id
    }

    func setThemeCustomFontName(id: UUID, value: String) {
        mutate(actionName: "Rename Theme Font") { site in
            guard let index = site.theme.typography.customFonts.firstIndex(where: { $0.id == id }) else { return }
            site.theme.typography.customFonts[index].name = value
        }
    }

    func setThemeCustomFontFamily(id: UUID, value: String) {
        mutate(actionName: "Edit Theme Font") { site in
            guard let index = site.theme.typography.customFonts.firstIndex(where: { $0.id == id }) else { return }
            site.theme.typography.customFonts[index].font.family = value
        }
    }

    func setThemeFontFallbacks(_ value: String, reference: ThemeFontReference) {
        updateThemeFont(reference: reference, actionName: "Edit Theme Font Fallbacks") {
            $0.fallbacks = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    func setThemeFontSource(_ source: ThemeFontSource, reference: ThemeFontReference) {
        updateThemeFont(reference: reference, actionName: "Edit Theme Font Source") { $0.source = source }
    }

    func setThemeFontWeights(_ weights: [Int], reference: ThemeFontReference) {
        updateThemeFont(reference: reference, actionName: "Edit Theme Font Weights") {
            let normalized = Array(Set(weights)).sorted()
            $0.weights = normalized.isEmpty ? [400] : normalized
        }
    }

    func setThemeFontStyles(_ styles: [ThemeFontStyle], reference: ThemeFontReference) {
        updateThemeFont(reference: reference, actionName: "Edit Theme Font Styles") {
            $0.styles = styles.isEmpty ? [.normal] : styles
        }
    }

    func removeThemeCustomFont(id: UUID) {
        mutate(actionName: "Delete Theme Font") {
            $0.theme.typography.customFonts.removeAll(where: { $0.id == id })
        }
    }

    private func updateThemeFont(
        reference: ThemeFontReference,
        actionName: String,
        update: (inout ThemeFontDefinition) -> Void
    ) {
        mutate(actionName: actionName) { site in
            switch reference {
            case .role(.body): update(&site.theme.typography.bodyFont)
            case .role(.heading): update(&site.theme.typography.headingFont)
            case .role(.monospaced): update(&site.theme.typography.monospacedFont)
            case .custom(let id):
                guard let index = site.theme.typography.customFonts.firstIndex(where: { $0.id == id }) else { return }
                update(&site.theme.typography.customFonts[index].font)
            }
        }
    }

    func setThemeFontSize(id: String, value: Double) {
        guard value.isFinite, value > 0 else { return }
        mutate(actionName: "Edit Theme Font Size") { site in
            guard let index = site.theme.typography.customFontSizes.firstIndex(where: { $0.id == id }) else { return }
            site.theme.typography.customFontSizes[index].size = value
        }
    }

    func setThemeBaseSize(_ value: Double) {
        guard value.isFinite, value > 0 else { return }
        mutate(actionName: "Edit Theme Base Size") { $0.theme.typography.baseSize = value }
    }

    func setThemeFontSizeLineHeight(id: String, value: ThemeLineHeight) {
        mutate(actionName: "Edit Theme Line Height") { site in
            guard let index = site.theme.typography.customFontSizes.firstIndex(where: { $0.id == id }) else { return }
            site.theme.typography.customFontSizes[index].lineHeight = value
        }
    }

    func setThemeFontSizeTitle(id: String, value: String) {
        mutate(actionName: "Rename Theme Font Size") { site in
            guard let index = site.theme.typography.customFontSizes.firstIndex(where: { $0.id == id }) else { return }
            site.theme.typography.customFontSizes[index].title = value
        }
    }

    @discardableResult
    func addThemeFontSize() -> String {
        var newID = ""
        mutate(actionName: "Add Theme Font Size") { site in
            let existingIDs = Set(site.theme.typography.fontSizes.map(\.id))
            var suffix = 1
            repeat {
                newID = suffix == 1 ? "custom" : "custom-\(suffix)"
                suffix += 1
            } while existingIDs.contains(newID)
            site.theme.typography.customFontSizes.insert(
                .init(id: newID, title: "Custom", size: 1, lineHeight: .normal),
                at: 0
            )
        }
        return newID
    }

    func removeThemeFontSize(id: String) {
        mutate(actionName: "Delete Theme Font Size") {
            $0.theme.typography.customFontSizes.removeAll { $0.id == id }
        }
    }

    func moveThemeFontSize(id: String, before targetID: String) {
        guard id != targetID else { return }
        mutate(actionName: "Reorder Theme Font Sizes") { site in
            guard let source = site.theme.typography.customFontSizes.firstIndex(where: { $0.id == id }) else { return }
            let item = site.theme.typography.customFontSizes.remove(at: source)
            guard let destination = site.theme.typography.customFontSizes.firstIndex(where: { $0.id == targetID }) else {
                site.theme.typography.customFontSizes.insert(item, at: source)
                return
            }
            site.theme.typography.customFontSizes.insert(item, at: destination)
        }
    }

    func moveThemeFontSizes(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        mutate(actionName: "Reorder Theme Font Sizes") { site in
            var sizes = site.theme.typography.customFontSizes
            let moving = offsets.sorted().map { sizes[$0] }
            for index in offsets.sorted(by: >) {
                sizes.remove(at: index)
            }
            let removedBeforeDestination = offsets.filter { $0 < destination }.count
            let insertionIndex = max(0, min(destination - removedBeforeDestination, sizes.count))
            sizes.insert(contentsOf: moving, at: insertionIndex)
            site.theme.typography.customFontSizes = sizes
        }
    }

    func applyThemePackage(_ package: LoadedThemePackage) {
        mutate(actionName: "Apply Theme") { site in
            site.theme = package.manifest.theme
            site.themePackage = package.lock
        }
    }

    @discardableResult
    func addComponent(
        type: ComponentType,
        to pageID: UUID,
        parentID: UUID?
    ) -> UUID {
        let node = ComponentNode.make(type)
        mutate(actionName: "Add \(type.displayName)") { site in
            guard let pageIndex = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            site.pages[pageIndex].components.append(node, to: parentID)
        }
        return node.id
    }

    func removeComponent(id: UUID) {
        removeComponents(ids: [id])
    }

    func removeComponents(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        mutate(actionName: ids.count == 1 ? "Delete Component" : "Delete Components") { site in
            for id in ids {
                for pageIndex in site.pages.indices {
                    if site.pages[pageIndex].components.removeNode(withID: id) {
                        break
                    }
                }
            }
        }
    }

    func mutate(actionName: String, mutation: (inout Site) -> Void) {
        var updatedSite = document.site
        mutation(&updatedSite)
        document.replaceSite(
            with: updatedSite,
            undoManager: undoManager,
            actionName: actionName
        )
    }
}

nonisolated extension Site {
    func component(withID id: UUID) -> ComponentNode? {
        for page in pages {
            if let component = page.components.node(withID: id) {
                return component
            }
        }
        return nil
    }

    mutating func updateComponent(
        id: UUID,
        transform: (inout ComponentNode) -> Void
    ) {
        for pageIndex in pages.indices {
            if pages[pageIndex].components.updateNode(withID: id, transform: transform) {
                return
            }
        }
    }
}
