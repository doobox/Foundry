import Foundation
#if DEBUG
import OSLog
#endif

nonisolated enum ProjectMutationImpact: Equatable, Sendable {
    case componentProperty(componentID: UUID, propertyKey: ComponentProperty.Key)
    case componentStructure(ownerID: UUID?)
    case page
    case theme
    case assets
    case package
    case publishingOnly

    var affectsRenderedOutput: Bool {
        self != .publishingOnly
    }
}

nonisolated struct ProjectMutationEvent: Equatable, Sendable {
    let revision: UInt64
    let impact: ProjectMutationImpact
}

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

    func setSitePublicURL(_ publicURL: String) {
        let normalizedURL: String
        if publicURL.hasSuffix("/"),
           let url = URL(string: publicURL),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            normalizedURL = String(publicURL.dropLast())
        } else {
            normalizedURL = publicURL
        }
        mutate(actionName: "Edit Site URL") { $0.publicURL = normalizedURL }
    }

    func setSiteTitleSuffix(_ titleSuffix: String) {
        mutate(actionName: "Edit Site Title Suffix") { $0.titleSuffix = titleSuffix }
    }

    func setSiteDefaultDescription(_ description: String) {
        mutate(actionName: "Edit Site Description") { $0.defaultDescription = description }
    }

    func setSiteFavicon(_ favicon: String) {
        mutate(actionName: "Set Site Icon") { $0.favicon = favicon }
    }

    func setSiteDefaultSocialImage(_ image: String) {
        mutate(actionName: "Set Default Social Image") { $0.defaultSocialImage = image }
    }

    func setGeneratesCanonicalURLs(_ isEnabled: Bool) {
        mutate(actionName: "Change Canonical URL Generation") { $0.generatesCanonicalURLs = isEnabled }
    }

    func setGeneratesSitemap(_ isEnabled: Bool) {
        mutate(actionName: "Change Sitemap Generation") { $0.generatesSitemap = isEnabled }
    }

    func setGeneratesRobotsTXT(_ isEnabled: Bool) {
        mutate(actionName: "Change Robots File Generation") { $0.generatesRobotsTXT = isEnabled }
    }

    func setAllowsSearchIndexing(_ isEnabled: Bool) {
        mutate(actionName: "Change Search Indexing") { $0.allowsSearchIndexing = isEnabled }
    }

    func setCustomCodeEnabled(_ isEnabled: Bool) {
        mutate(actionName: "Change Custom Code") { $0.customCodeEnabled = isEnabled }
    }

    func setSiteHeadCode(_ code: String) {
        mutate(actionName: "Edit Head Code") { $0.headCode = code }
    }

    func setSiteBodyStartCode(_ code: String) {
        mutate(actionName: "Edit Body Start Code") { $0.bodyStartCode = code }
    }

    func setSiteBodyEndCode(_ code: String) {
        mutate(actionName: "Edit Body End Code") { $0.bodyEndCode = code }
    }

    func setSiteAnalyticsCode(_ code: String) {
        mutate(actionName: "Edit Analytics Code") { $0.analyticsCode = code }
    }

    func setPublishingDestination(_ destination: PublishingDestinationKind) {
        mutate(actionName: "Change Publishing Destination", impact: .publishingOnly) {
            let previousDefaultPort = $0.publishingDestination.defaultPort
            $0.publishingDestination = destination
            if $0.publishingPort == 0 || $0.publishingPort == previousDefaultPort {
                $0.publishingPort = destination.defaultPort
            }
        }
    }

    func setPublishingHost(_ host: String) {
        mutate(actionName: "Edit Publishing Host", impact: .publishingOnly) { $0.publishingHost = host }
    }

    func setPublishingPort(_ port: Int) {
        mutate(actionName: "Edit Publishing Port", impact: .publishingOnly) { $0.publishingPort = max(0, min(port, 65_535)) }
    }

    func setPublishingUsername(_ username: String) {
        mutate(actionName: "Edit Publishing Username", impact: .publishingOnly) { $0.publishingUsername = username }
    }

    func setPublishingRemotePath(_ path: String) {
        mutate(actionName: "Edit Publishing Path", impact: .publishingOnly) { $0.publishingRemotePath = path }
    }

    func setPublishingS3Bucket(_ bucket: String) {
        mutate(actionName: "Edit S3 Bucket", impact: .publishingOnly) { $0.publishingS3Bucket = bucket }
    }

    func setPublishingS3Region(_ region: String) {
        mutate(actionName: "Edit S3 Region", impact: .publishingOnly) { $0.publishingS3Region = region }
    }

    func setCleansObsoleteExportFiles(_ isEnabled: Bool) {
        mutate(actionName: "Change Export Cleanup", impact: .publishingOnly) { $0.cleansObsoleteExportFiles = isEnabled }
    }

    func renameComponent(id: UUID, name: String) {
        mutate(actionName: "Rename Component", impact: .componentProperty(componentID: id, propertyKey: .init(rawValue: "name"))) { site in
            site.updateComponent(id: id) { $0.name = name }
        }
    }

    func setComponentAnchor(id: UUID, anchor: String) {
        mutate(actionName: "Edit Component Anchor", impact: .componentProperty(componentID: id, propertyKey: .init(rawValue: "anchor"))) { site in
            site.updateComponent(id: id) {
                let value = anchor.trimmingCharacters(in: .whitespacesAndNewlines)
                $0.anchor = value.isEmpty ? nil : value
            }
        }
    }

    func setComponentClasses(id: UUID, classes: String) {
        mutate(actionName: "Edit Component Classes", impact: .componentProperty(componentID: id, propertyKey: .init(rawValue: "classes"))) { site in
            site.updateComponent(id: id) {
                $0.customClasses = classes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : classes
            }
        }
    }

    func setComponentRootAttributes(id: UUID, attributes: [ComponentHTMLAttribute]) {
        mutate(actionName: "Edit Component Attributes", impact: .componentProperty(componentID: id, propertyKey: .init(rawValue: "attributes"))) { site in
            site.updateComponent(id: id) {
                $0.rootAttributes = attributes.isEmpty ? nil : attributes
            }
        }
    }

    func setProperty(
        id: UUID,
        key: ComponentProperty.Key,
        value: ComponentProperty.Value
    ) {
        mutate(actionName: "Edit Component", impact: .componentProperty(componentID: id, propertyKey: key)) { site in
            site.updateComponent(id: id) { $0.setProperty(key, value: value) }
        }
    }

    func setProperty(id: UUID, key: ComponentProperty.Key, value: String) {
        let propertyValue: ComponentProperty.Value = key == .destination
            ? .link(.init(destination: value.isEmpty ? .none : .url(value)))
            : .string(value)
        setProperty(id: id, key: key, value: propertyValue)
    }

    func setResponsiveProperty(
        id: UUID,
        key: ComponentProperty.Key,
        value: ComponentProperty.Value,
        breakpoint: ResponsiveBreakpoint
    ) {
        mutate(actionName: "Edit \(breakpoint.displayName) Component", impact: .componentProperty(componentID: id, propertyKey: key)) { site in
            site.updateComponent(id: id) {
                $0.setResponsiveProperty(key, value: value, at: breakpoint)
            }
        }
    }

    func removeResponsiveOverride(id: UUID, key: ComponentProperty.Key, breakpoint: ResponsiveBreakpoint) {
        mutate(actionName: "Reset \(breakpoint.displayName) Component", impact: .componentProperty(componentID: id, propertyKey: key)) { site in
            site.updateComponent(id: id) { $0.removeResponsiveOverride(key, at: breakpoint) }
        }
    }

    func setThemeColor(_ token: DesignToken, value: String) {
        mutate(actionName: "Edit Theme Color", impact: .theme) { site in
            switch token {
            case .backgroundColor: site.theme.colors.background = value
            case .surfaceColor: site.theme.colors.surface = value
            case .textColor: site.theme.colors.text = value
            case .accentColor: site.theme.colors.accent = value
            case .linksColor: site.theme.colors.links = value
            case .threeExtraSmallSpacing, .doubleExtraSmallSpacing, .extraSmallSpacing,
                 .smallSpacing, .mediumSpacing, .largeSpacing, .extraLargeSpacing,
                 .doubleExtraLargeSpacing, .threeExtraLargeSpacing: break
            }
        }
    }

    func setThemeScreenEnabled(_ id: ThemeScreenID, value: Bool) {
        mutate(actionName: "Enable Theme Screen", impact: .theme) { site in
            site.theme.screens.update(id) { $0.isEnabled = value }
        }
    }

    func setThemeScreenMinimumWidth(_ id: ThemeScreenID, value: Double) {
        guard value.isFinite else { return }
        mutate(actionName: "Edit Theme Screen Width", impact: .theme) { site in
            site.theme.screens.update(id) { $0.minimumWidth = value }
        }
    }

    func setThemeScreenContainerUnit(_ id: ThemeScreenID, value: ThemeContainerUnit) {
        mutate(actionName: "Edit Theme Container Unit", impact: .theme) { site in
            site.theme.screens.update(id) { screen in
                screen.container.unit = value
                if value == .auto {
                    screen.container.value = screen.minimumWidth
                }
            }
        }
    }

    func setThemeScreenContainerWidth(_ id: ThemeScreenID, value: Double) {
        guard value.isFinite else { return }
        mutate(actionName: "Edit Theme Container Width", impact: .theme) { site in
            site.theme.screens.update(id) { $0.container.value = value }
        }
    }

    func setThemeSpacing(_ token: DesignToken, value: Double) {
        guard value.isFinite, value >= 0 else { return }
        mutate(actionName: "Edit Theme Spacing", impact: .theme) { site in
            switch token {
            case .threeExtraSmallSpacing: site.theme.spacing.threeExtraSmall = value
            case .doubleExtraSmallSpacing: site.theme.spacing.doubleExtraSmall = value
            case .extraSmallSpacing: site.theme.spacing.extraSmall = value
            case .smallSpacing: site.theme.spacing.small = value
            case .mediumSpacing: site.theme.spacing.medium = value
            case .largeSpacing: site.theme.spacing.large = value
            case .extraLargeSpacing: site.theme.spacing.extraLarge = value
            case .doubleExtraLargeSpacing: site.theme.spacing.doubleExtraLarge = value
            case .threeExtraLargeSpacing: site.theme.spacing.threeExtraLarge = value
            case .backgroundColor, .surfaceColor, .textColor, .accentColor, .linksColor: break
            }
        }
    }

    func resetThemeSpacingScale() {
        mutate(actionName: "Reset Theme Spacing Scale", impact: .theme) { site in
            guard let source = ThemeLibrary.shared.themes.first(where: { $0.id == site.themeSourceID }) else { return }
            let defaults = source.theme.spacing
            site.theme.spacing.threeExtraSmall = defaults.threeExtraSmall
            site.theme.spacing.doubleExtraSmall = defaults.doubleExtraSmall
            site.theme.spacing.extraSmall = defaults.extraSmall
            site.theme.spacing.small = defaults.small
            site.theme.spacing.medium = defaults.medium
            site.theme.spacing.large = defaults.large
            site.theme.spacing.extraLarge = defaults.extraLarge
            site.theme.spacing.doubleExtraLarge = defaults.doubleExtraLarge
            site.theme.spacing.threeExtraLarge = defaults.threeExtraLarge
        }
    }

    @discardableResult
    func addThemeSpacing() -> UUID {
        let spacing = ThemeSpacing(name: "Custom Spacing", value: 5)
        mutate(actionName: "Add Theme Spacing", impact: .theme) { $0.theme.spacing.custom.append(spacing) }
        return spacing.id
    }

    func setThemeSpacingName(id: UUID, value: String) {
        mutate(actionName: "Rename Theme Spacing", impact: .theme) { site in
            guard let index = site.theme.spacing.custom.firstIndex(where: { $0.id == id }) else { return }
            site.theme.spacing.custom[index].name = value
        }
    }

    func setThemeSpacingValue(id: UUID, value: Double) {
        guard value.isFinite, value >= 0 else { return }
        mutate(actionName: "Edit Theme Spacing", impact: .theme) { site in
            guard let index = site.theme.spacing.custom.firstIndex(where: { $0.id == id }) else { return }
            site.theme.spacing.custom[index].value = value
        }
    }

    func removeThemeSpacing(id: UUID) {
        mutate(actionName: "Delete Theme Spacing", impact: .theme) {
            $0.theme.spacing.custom.removeAll(where: { $0.id == id })
        }
    }

    @discardableResult
    func addThemeShadow() -> String {
        let id = "user-\(UUID().uuidString.lowercased())"
        let shadow = ThemeShadow(
            id: id,
            title: "Custom Shadow",
            layers: [.init(x: 0, y: 4, blur: 8, opacity: 0.15)]
        )
        mutate(actionName: "Add Theme Shadow", impact: .theme) { $0.theme.shadows.custom.insert(shadow, at: 0) }
        return id
    }

    func removeThemeShadow(id: String) {
        mutate(actionName: "Delete Theme Shadow", impact: .theme) {
            $0.theme.shadows.custom.removeAll { $0.id == id }
        }
    }

    func setThemeShadowTitle(id: String, value: String) {
        mutateThemeShadow(id: id, actionName: "Rename Theme Shadow") { $0.title = value }
    }

    func setThemeShadowLayer(shadowID: String, layer: ThemeShadowLayer) {
        mutateThemeShadow(id: shadowID, actionName: "Edit Theme Shadow") { shadow in
            guard let index = shadow.layers.firstIndex(where: { $0.id == layer.id }) else { return }
            shadow.layers[index] = layer
        }
    }

    func setThemeShadowLayers(shadowID: String, layers: [ThemeShadowLayer]) {
        mutateThemeShadow(id: shadowID, actionName: "Edit Theme Shadow") { $0.layers = layers }
    }

    @discardableResult
    func addThemeShadowLayer(shadowID: String) -> UUID {
        let layer = ThemeShadowLayer(x: 0, y: 4, blur: 8, opacity: 0.15)
        mutateThemeShadow(id: shadowID, actionName: "Add Shadow Layer") { $0.layers.append(layer) }
        return layer.id
    }

    func removeThemeShadowLayer(shadowID: String, layerID: UUID) {
        mutateThemeShadow(id: shadowID, actionName: "Delete Shadow Layer") {
            $0.layers.removeAll { $0.id == layerID }
        }
    }

    func resetThemeShadowScale() {
        mutate(actionName: "Reset Theme Shadow Scale", impact: .theme) { site in
            let defaults = ThemeLibrary.shared.themes
                .first(where: { $0.id == site.themeSourceID })?
                .theme.shadows.predefined ?? ShadowTokens.standard.predefined
            site.theme.shadows.predefined = defaults
        }
    }

    private func mutateThemeShadow(
        id: String,
        actionName: String,
        update: (inout ThemeShadow) -> Void
    ) {
        mutate(actionName: actionName, impact: .theme) { site in
            if let index = site.theme.shadows.custom.firstIndex(where: { $0.id == id }) {
                update(&site.theme.shadows.custom[index])
            } else if let index = site.theme.shadows.predefined.firstIndex(where: { $0.id == id }) {
                update(&site.theme.shadows.predefined[index])
            }
        }
    }

    func setThemeBodyFont(_ value: String) {
        setThemeFont(value, for: .body)
    }

    func setThemeFont(_ value: String, for role: ThemeFontRole) {
        mutate(actionName: "Edit Theme Font Family", impact: .theme) { site in
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
        mutate(actionName: "Add Theme Font", impact: .theme) { $0.theme.typography.customFonts.append(font) }
        return font.id
    }

    func setThemeCustomFontName(id: UUID, value: String) {
        mutate(actionName: "Rename Theme Font", impact: .theme) { site in
            guard let index = site.theme.typography.customFonts.firstIndex(where: { $0.id == id }) else { return }
            site.theme.typography.customFonts[index].name = value
        }
    }

    func setThemeCustomFontFamily(id: UUID, value: String) {
        mutate(actionName: "Edit Theme Font", impact: .theme) { site in
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
        updateThemeFont(reference: reference, actionName: "Edit Theme Font Source") {
            if case .system = $0.source {
                $0.systemFontNames = [$0.family] + $0.fallbacks
            }
            $0.source = source
        }
    }

    func restoreThemeFontNames(reference: ThemeFontReference) {
        updateThemeFont(reference: reference, actionName: "Use Font Names") { definition in
            let names = definition.systemFontNames ?? defaultSystemFontNames(for: reference)
            definition.family = names.first ?? "system-ui"
            definition.fallbacks = Array(names.dropFirst())
            definition.source = .system
            definition.systemFontNames = names
        }
    }

    func setThemeFontFamily(_ value: String, reference: ThemeFontReference) {
        updateThemeFont(reference: reference, actionName: "Edit Theme Font Family") {
            $0.family = value
        }
    }

    func setThemeFontNames(_ value: String, reference: ThemeFontReference) {
        let names = value.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let family = names.first else { return }
        updateThemeFont(reference: reference, actionName: "Edit Theme Font Names") {
            $0.family = family
            $0.fallbacks = Array(names.dropFirst())
            $0.source = .system
            $0.systemFontNames = names
        }
    }

    func setThemeGoogleFont(_ family: String, reference: ThemeFontReference) {
        let normalizedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFamily.isEmpty,
              let url = ThemeFontDefinition.googleStylesheetURL(for: normalizedFamily) else { return }
        updateThemeFont(reference: reference, actionName: "Choose Google Font") {
            if case .system = $0.source {
                $0.systemFontNames = [$0.family] + $0.fallbacks
            }
            $0.family = normalizedFamily
            $0.fallbacks = []
            $0.source = .remote(stylesheetURL: url)
        }
    }

    func setThemeFontDefinition(
        _ definition: ThemeFontDefinition,
        reference: ThemeFontReference,
        actionName: String
    ) {
        updateThemeFont(reference: reference, actionName: actionName) {
            $0 = definition
        }
    }

    func setThemeFontResources(_ files: [String], reference: ThemeFontReference) {
        let uniqueFiles = files.reduce(into: [String]()) { result, file in
            if !result.contains(file) { result.append(file) }
        }
        updateThemeFont(reference: reference, actionName: "Edit Font Resources") {
            $0.source = .bundled(files: uniqueFiles)
        }
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
        mutate(actionName: "Delete Theme Font", impact: .theme) {
            $0.theme.typography.customFonts.removeAll(where: { $0.id == id })
        }
    }

    private func updateThemeFont(
        reference: ThemeFontReference,
        actionName: String,
        update: (inout ThemeFontDefinition) -> Void
    ) {
        mutate(actionName: actionName, impact: .theme) { site in
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

    private func defaultSystemFontNames(for reference: ThemeFontReference) -> [String] {
        let definition = switch reference {
        case .role(.body): ThemeBundleStore.systemTheme.typography.bodyFont
        case .role(.heading): ThemeBundleStore.systemTheme.typography.headingFont
        case .role(.monospaced): ThemeBundleStore.systemTheme.typography.monospacedFont
        case .custom: ThemeFontDefinition.system(family: "system-ui", weights: [400, 700])
        }
        return [definition.family] + definition.fallbacks
    }

    func setThemeFontSize(id: String, value: Double) {
        guard value.isFinite, value > 0 else { return }
        mutate(actionName: "Edit Theme Font Size", impact: .theme) { site in
            if let index = site.theme.typography.predefinedFontSizes.firstIndex(where: { $0.id == id }) {
                site.theme.typography.predefinedFontSizes[index].size = value
            } else if let index = site.theme.typography.customFontSizes.firstIndex(where: { $0.id == id }) {
                site.theme.typography.customFontSizes[index].size = value
            }
        }
    }

    func setThemeFontSizeLineHeight(id: String, value: Double) {
        guard value.isFinite, value > 0 else { return }
        mutate(actionName: "Edit Theme Line Height", impact: .theme) { site in
            if let index = site.theme.typography.predefinedFontSizes.firstIndex(where: { $0.id == id }) {
                site.theme.typography.predefinedFontSizes[index].lineHeight = value
            } else if let index = site.theme.typography.customFontSizes.firstIndex(where: { $0.id == id }) {
                site.theme.typography.customFontSizes[index].lineHeight = value
            }
        }
    }

    func setThemeFontSizeTitle(id: String, value: String) {
        mutate(actionName: "Rename Theme Font Size", impact: .theme) { site in
            guard let index = site.theme.typography.customFontSizes.firstIndex(where: { $0.id == id }) else { return }
            site.theme.typography.customFontSizes[index].title = value
        }
    }

    func resetThemeFontSizeScale() {
        mutate(actionName: "Reset Theme Font Size Scale", impact: .theme) { site in
            guard let source = ThemeLibrary.shared.themes.first(where: { $0.id == site.themeSourceID }) else { return }
            site.theme.typography.predefinedFontSizes = source.theme.typography.predefinedFontSizes
        }
    }

    @discardableResult
    func addThemeFontSize() -> String {
        let newID = "user-\(UUID().uuidString.lowercased())"
        mutate(actionName: "Add Theme Font Size", impact: .theme) { site in
            site.theme.typography.customFontSizes.insert(
                .init(id: newID, title: "Custom", size: 1, lineHeight: 1.5),
                at: 0
            )
        }
        return newID
    }

    func removeThemeFontSize(id: String) {
        mutate(actionName: "Delete Theme Font Size", impact: .theme) {
            $0.theme.typography.customFontSizes.removeAll { $0.id == id }
        }
    }

    func moveThemeFontSize(id: String, before targetID: String) {
        guard id != targetID else { return }
        mutate(actionName: "Reorder Theme Font Sizes", impact: .theme) { site in
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
        mutate(actionName: "Reorder Theme Font Sizes", impact: .theme) { site in
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

    func selectTheme(_ theme: Theme, sourceID: UUID) {
        mutate(actionName: "Select Theme", impact: .theme) { site in
            guard site.themeSourceID != sourceID else { return }
            site.projectThemeValues.absorb(site.theme)
            site.saveActiveThemeState()
            site.projectThemeValues.include(theme)
            let selected = site.themeStates.first(where: { $0.sourceID == sourceID })?.theme ?? theme
            site.theme = site.projectThemeValues.applied(to: selected)
            site.themeSourceID = sourceID
        }
    }

    func resetTheme(_ theme: Theme, sourceID: UUID) {
        mutate(actionName: "Reset Theme", impact: .theme) { site in
            site.projectThemeValues.absorb(site.theme)
            site.themeStates.removeAll { $0.sourceID == sourceID }
            site.theme = site.projectThemeValues.applied(to: theme)
            site.themeSourceID = sourceID
        }
    }

    func commitTheme(_ theme: Theme, sourceID: UUID) {
        mutate(actionName: "Update Theme Defaults", impact: .theme) { site in
            site.themeStates.removeAll { $0.sourceID == sourceID }
            site.projectThemeValues.absorb(theme)
            site.theme = site.projectThemeValues.applied(to: theme)
            site.themeSourceID = sourceID
        }
    }

    @discardableResult
    func addComponent(
        type: ComponentType,
        to pageID: UUID,
        parentID: UUID?
    ) -> UUID {
        let node = ComponentNode.make(type)
        mutate(actionName: "Add \(type.displayName)", impact: .componentStructure(ownerID: parentID)) { site in
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
        mutate(actionName: ids.count == 1 ? "Delete Component" : "Delete Components", impact: .componentStructure(ownerID: nil)) { site in
            for id in ids {
                for pageIndex in site.pages.indices {
                    if site.pages[pageIndex].components.removeNode(withID: id) {
                        break
                    }
                }
            }
        }
    }

    func mutate(
        actionName: String,
        impact: ProjectMutationImpact = .page,
        mutation: (inout Site) -> Void
    ) {
#if DEBUG
        let receivedAt = ContinuousClock.now
        Logger.foundryPerformance.debug("Inspector mutation received: \(actionName, privacy: .public)")
#endif
        var updatedSite = document.site
        mutation(&updatedSite)
#if DEBUG
        let mutationCompletedAt = ContinuousClock.now
#endif
        document.replaceSite(
            with: updatedSite,
            undoManager: undoManager,
            actionName: actionName,
            impact: impact
        )
#if DEBUG
        let completedAt = ContinuousClock.now
        Logger.foundryPerformance.debug(
            "Document mutation completed: \(actionName, privacy: .public), mutate=\(receivedAt.milliseconds(to: mutationCompletedAt), format: .fixed(precision: 3))ms, replace=\(mutationCompletedAt.milliseconds(to: completedAt), format: .fixed(precision: 3))ms, total=\(receivedAt.milliseconds(to: completedAt), format: .fixed(precision: 3))ms"
        )
#endif
    }
}

#if DEBUG
extension Logger {
    static let foundryPerformance = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Foundry",
        category: "InspectorCanvasPerformance"
    )
}

extension ContinuousClock.Instant {
    func milliseconds(to later: Self) -> Double {
        let duration = duration(to: later)
        return Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
#endif

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
