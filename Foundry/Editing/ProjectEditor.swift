import Foundation

nonisolated enum ProjectMutationImpact: Equatable, Sendable {
    case partProperty(partID: UUID, propertyKey: PartProperty.Key)
    case partProperties(partIDs: [UUID], propertyKey: PartProperty.Key)
    case partStructure(ownerID: UUID?)
    case page
    case framework
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
        let source = favicon.foundryAssetID.flatMap { document.assetContents[$0] }
        document.setFaviconSource(source, undoManager: undoManager)
    }

    func importSiteFavicon(data: Data, filename: String, mediaType: String) {
        let processed = PartImageProcessor.canonicalize(
            data: data,
            filename: filename,
            mimeType: mediaType
        )
        let metadata = processed.metadata
        let source = ProjectAsset(
            filename: metadata.filename,
            mediaType: metadata.mimeType,
            byteCount: processed.data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: processed.data),
            pixelWidth: metadata.width,
            pixelHeight: metadata.height
        )
        document.setFaviconSource(
            ProjectAssetContent(asset: source, data: processed.data),
            undoManager: undoManager
        )
    }

    func setSiteDefaultSocialImage(_ image: String) {
        mutate(actionName: "Set Default Social Image") { $0.defaultSocialImage = image }
    }

    func setSiteSocialImageAlt(_ alt: String) {
        mutate(actionName: "Edit Social Image Description") { $0.socialImageAlt = alt }
    }

    /// Stores the site's social handle, adding the leading @ when omitted.
    func setSiteSocialAccount(_ account: String) {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty || trimmed.hasPrefix("@") ? trimmed : "@" + trimmed
        mutate(actionName: "Edit Social Account") { $0.socialAccount = normalized }
    }

    func setSiteLogo(_ logo: String) {
        let source = logo.foundryAssetID.flatMap { document.assetContents[$0] }
        document.setSiteLogoSource(source, undoManager: undoManager)
    }

    func importSiteLogo(data: Data, filename: String, mediaType: String) {
        let processed = PartImageProcessor.canonicalize(
            data: data,
            filename: filename,
            mimeType: mediaType
        )
        let metadata = processed.metadata
        let source = ProjectAsset(
            filename: metadata.filename,
            mediaType: metadata.mimeType,
            byteCount: processed.data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: processed.data),
            pixelWidth: metadata.width,
            pixelHeight: metadata.height
        )
        document.setSiteLogoSource(
            ProjectAssetContent(asset: source, data: processed.data),
            undoManager: undoManager
        )
    }

    func setSiteLogoAlt(_ alt: String) {
        mutate(actionName: "Edit Site Logo Alt Text") { $0.logoAlt = alt }
    }

    func setSiteAllowsDarkMode(_ isEnabled: Bool) {
        mutate(actionName: "Change Site Appearance", impact: .framework) {
            $0.appearanceMode = isEnabled ? .both : .light
        }
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

    func setGeneratesCacheBustingLinks(_ isEnabled: Bool) {
        mutate(actionName: "Change Cache Busting") { $0.generatesCacheBustingLinks = isEnabled }
    }

    func setDefaultPageExtension(_ preference: PageExtensionPreference) {
        mutate(actionName: "Change Default Page Extension") { $0.defaultPageExtension = preference }
    }

    func setPreviewServerPort(_ port: Int?) {
        mutate(actionName: "Change Preview Server Port", impact: .publishingOnly) {
            $0.previewServerPort = port.map { max(1_024, min($0, 65_535)) }
        }
    }

    func setMinifiesGeneratedOutput(_ isEnabled: Bool) {
        mutate(actionName: "Change Output Minification") { $0.minifiesGeneratedOutput = isEnabled }
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

    func addPublishingDestination(kind: PublishingDestinationKind, name: String? = nil) -> UUID {
        let destination = PublishingDestination(name: name ?? kind.title, kind: kind)
        mutate(actionName: "Add Publishing Destination", impact: .publishingOnly) { site in
            site.publishingDestinations.append(destination)
            if site.publishingDestinations.count == 1
                || !site.publishingDestinations.contains(where: { $0.id == site.defaultPublishingDestinationID }) {
                site.defaultPublishingDestinationID = destination.id
                site.synchronizeLegacyPublishingFields()
            }
        }
        return destination.id
    }

    func updatePublishingDestination(_ destination: PublishingDestination) {
        mutate(actionName: "Edit Publishing Destination", impact: .publishingOnly) { site in
            guard let index = site.publishingDestinations.firstIndex(where: { $0.id == destination.id }) else { return }
            site.publishingDestinations[index] = destination
            if site.publishingDestinations.count == 1 {
                site.defaultPublishingDestinationID = destination.id
            }
            if site.defaultPublishingDestinationID == destination.id {
                site.synchronizeLegacyPublishingFields()
            }
        }
    }

    func duplicatePublishingDestination(id: UUID) -> UUID? {
        guard let source = document.site.publishingDestinations.first(where: { $0.id == id }) else { return nil }
        let duplicate = PublishingDestination(
            name: source.name + " Copy",
            kind: source.kind,
            host: source.host,
            port: source.port,
            username: source.username,
            remotePath: source.remotePath,
            s3Bucket: source.s3Bucket,
            s3Region: source.s3Region,
            cleansObsoleteFiles: source.cleansObsoleteFiles
        )
        mutate(actionName: "Duplicate Publishing Destination", impact: .publishingOnly) {
            $0.publishingDestinations.append(duplicate)
        }
        return duplicate.id
    }

    func removePublishingDestination(id: UUID) {
        mutate(actionName: "Remove Publishing Destination", impact: .publishingOnly) { site in
            site.publishingDestinations.removeAll { $0.id == id }
            if site.publishingDestinations.count == 1
                || !site.publishingDestinations.contains(where: { $0.id == site.defaultPublishingDestinationID }) {
                site.defaultPublishingDestinationID = site.publishingDestinations.first?.id
                site.synchronizeLegacyPublishingFields()
            }
        }
    }

    func setDefaultPublishingDestination(id: UUID) {
        mutate(actionName: "Set Default Publishing Destination", impact: .publishingOnly) { site in
            guard site.publishingDestinations.contains(where: { $0.id == id }) else { return }
            site.defaultPublishingDestinationID = id
            site.synchronizeLegacyPublishingFields()
        }
    }

    func renamePart(id: UUID, name: String) {
        if let context = document.site.globalPartContext(containing: id), !context.isOverridden {
            renameSharedReusablePartInstance(partID: id, name: name)
            return
        }
        mutate(actionName: "Rename Part", impact: .partProperty(partID: id, propertyKey: .init(rawValue: "name"))) { site in
            site.updatePart(id: id) { $0.name = name }
        }
    }

    func setPartAnchor(id: UUID, anchor: String) {
        mutate(actionName: "Edit Part Anchor", impact: .partProperty(partID: id, propertyKey: .init(rawValue: "anchor"))) { site in
            site.updatePart(id: id) {
                let value = anchor.trimmingCharacters(in: .whitespacesAndNewlines)
                $0.anchor = value.isEmpty ? nil : value
            }
        }
    }

    func setPartClasses(id: UUID, classes: String) {
        if let context = document.site.globalPartContext(containing: id), !context.isOverridden {
            editSharedReusablePart(partID: id, actionName: "Edit Part Classes") {
                $0.customClasses = classes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : classes
            }
            return
        }
        mutate(actionName: "Edit Part Classes", impact: .partProperty(partID: id, propertyKey: .init(rawValue: "classes"))) { site in
            site.updatePart(id: id) {
                $0.customClasses = classes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : classes
            }
        }
    }

    func setPartCustomCSS(id: UUID, css: String) {
        let value = css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : css
        if let context = document.site.globalPartContext(containing: id), !context.isOverridden {
            editSharedReusablePart(partID: id, actionName: "Edit Part CSS") { $0.customCSS = value }
            return
        }
        mutate(actionName: "Edit Part CSS", impact: .partProperty(partID: id, propertyKey: .init(rawValue: "customCSS"))) { site in
            site.updatePart(id: id) { $0.customCSS = value }
        }
    }

    func setPartRootAttributes(id: UUID, attributes: [PartHTMLAttribute]) {
        if let context = document.site.globalPartContext(containing: id), !context.isOverridden {
            editSharedReusablePart(partID: id, actionName: "Edit Part Attributes") {
                $0.rootAttributes = attributes.isEmpty ? nil : attributes
            }
            return
        }
        mutate(actionName: "Edit Part Attributes", impact: .partProperty(partID: id, propertyKey: .init(rawValue: "attributes"))) { site in
            site.updatePart(id: id) {
                $0.rootAttributes = attributes.isEmpty ? nil : attributes
            }
        }
    }

    func setProperty(
        id: UUID,
        key: PartProperty.Key,
        value: PartProperty.Value
    ) {
        if let context = document.site.globalPartContext(containing: id), !context.isOverridden {
            setSharedReusableProperty(partID: id, key: key, value: value)
            return
        }
        mutate(actionName: "Edit Part", impact: .partProperty(partID: id, propertyKey: key)) { site in
            site.updatePart(id: id) { $0.setProperty(key, value: value) }
        }
    }

    func setProperties(
        ids: [UUID],
        key: PartProperty.Key,
        value: PartProperty.Value
    ) {
        var seen = Set<UUID>()
        let ids = ids.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first {
            setProperty(id: id, key: key, value: value)
            return
        }
        mutate(
            actionName: "Edit \(ids.count) Parts",
            impact: .partProperties(partIDs: ids, propertyKey: key)
        ) { site in
            for id in ids {
                site.updatePart(id: id) { $0.setProperty(key, value: value) }
            }
        }
    }

    func setProperty(id: UUID, key: PartProperty.Key, value: String) {
        let propertyValue: PartProperty.Value = key == .destination || key.rawValue == "link.destination"
            ? .link(.init(destination: value.isEmpty ? .none : .url(value)))
            : .string(value)
        setProperty(id: id, key: key, value: propertyValue)
    }

    func setResponsiveProperty(
        id: UUID,
        key: PartProperty.Key,
        value: PartProperty.Value,
        breakpoint: ResponsiveBreakpoint
    ) {
        if let context = document.site.globalPartContext(containing: id), !context.isOverridden {
            setSharedReusableResponsiveProperty(partID: id, key: key, value: value, breakpoint: breakpoint)
            return
        }
        mutate(actionName: "Edit \(breakpoint.displayName) Part", impact: .partProperty(partID: id, propertyKey: key)) { site in
            site.updatePart(id: id) {
                $0.setResponsiveProperty(key, value: value, at: breakpoint)
            }
        }
    }

    func setResponsiveProperties(
        ids: [UUID],
        key: PartProperty.Key,
        value: PartProperty.Value,
        breakpoint: ResponsiveBreakpoint
    ) {
        var seen = Set<UUID>()
        let ids = ids.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first {
            setResponsiveProperty(id: id, key: key, value: value, breakpoint: breakpoint)
            return
        }
        mutate(
            actionName: "Edit \(breakpoint.displayName) on \(ids.count) Parts",
            impact: .partProperties(partIDs: ids, propertyKey: key)
        ) { site in
            for id in ids {
                site.updatePart(id: id) {
                    $0.setResponsiveProperty(key, value: value, at: breakpoint)
                }
            }
        }
    }

    func removeResponsiveOverride(id: UUID, key: PartProperty.Key, breakpoint: ResponsiveBreakpoint) {
        if let context = document.site.globalPartContext(containing: id), !context.isOverridden {
            removeSharedReusableResponsiveOverride(partID: id, key: key, breakpoint: breakpoint)
            return
        }
        mutate(actionName: "Reset \(breakpoint.displayName) Part", impact: .partProperty(partID: id, propertyKey: key)) { site in
            site.updatePart(id: id) { $0.removeResponsiveOverride(key, at: breakpoint) }
        }
    }

    func removeResponsiveOverrides(
        ids: [UUID],
        key: PartProperty.Key,
        breakpoint: ResponsiveBreakpoint
    ) {
        var seen = Set<UUID>()
        let ids = ids.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first {
            removeResponsiveOverride(id: id, key: key, breakpoint: breakpoint)
            return
        }
        mutate(
            actionName: "Reset \(breakpoint.displayName) on \(ids.count) Parts",
            impact: .partProperties(partIDs: ids, propertyKey: key)
        ) { site in
            for id in ids {
                site.updatePart(id: id) { $0.removeResponsiveOverride(key, at: breakpoint) }
            }
        }
    }

    func setFrameworkColor(_ token: DesignToken, value: String) {
        mutate(actionName: "Edit Framework Color", impact: .framework) { site in
            switch token {
            case .backgroundColor: site.framework.colors.background = value
            case .surfaceColor: site.framework.colors.surface = value
            case .textColor: site.framework.colors.text = value
            case .accentColor: site.framework.colors.accent = value
            case .linksColor: site.framework.colors.links = value
            }
        }
    }

    func addCustomSpacing() {
        let used = Set(document.site.framework.spacing.custom.map(\.name))
        var number = 13
        while used.contains(String(number)) { number += 1 }
        mutate(actionName: "Add Spacing Size", impact: .framework) { site in
            site.framework.spacing.custom.append(.init(name: String(number), value: 4))
        }
    }

    @discardableResult
    func renameCustomSpacing(_ id: UUID, name: String) -> Bool {
        let tokens = document.site.framework.spacing.custom
        guard SpacingTokens.validName(name),
              !tokens.contains(where: { $0.id != id && $0.name == name }),
              let token = tokens.first(where: { $0.id == id }) else { return false }
        guard token.name != name else { return true }
        mutate(actionName: "Rename Spacing Size", impact: .framework) { site in
            guard let index = site.framework.spacing.custom.firstIndex(where: { $0.id == id }) else { return }
            site.replacePartSpacingReference(token.name, with: name)
            site.framework.spacing.custom[index].name = name
        }
        return true
    }

    func setCustomSpacing(_ id: UUID, value: Double) {
        guard value.isFinite, value >= 0,
              let token = document.site.framework.spacing.custom.first(where: { $0.id == id }),
              token.value != value else { return }
        mutate(actionName: "Edit Bootstrap Spacing", impact: .framework) { site in
            guard let index = site.framework.spacing.custom.firstIndex(where: { $0.id == id }) else { return }
            site.framework.spacing.custom[index].value = value
        }
    }

    func setBootstrapSpacing(_ step: Int, value: Double) {
        guard value.isFinite, value >= 0, document.site.framework.spacing.values.indices.contains(step),
              document.site.framework.spacing.values[step] != value else { return }
        mutate(actionName: "Edit Bootstrap Spacing", impact: .framework) {
            $0.framework.spacing.values[step] = value
        }
    }

    func resetBootstrapSpacing() {
        guard document.site.framework.spacing.values != SpacingTokens.multipliers else { return }
        mutate(actionName: "Reset Bootstrap Spacing", impact: .framework) {
            $0.framework.spacing.values = SpacingTokens.multipliers
        }
    }

    func removeCustomSpacing(_ id: UUID, replacingWith replacement: String) {
        guard let token = document.site.framework.spacing.custom.first(where: { $0.id == id }),
              replacement != token.name,
              document.site.framework.spacing.choices.contains(where: { $0.id == replacement }) else { return }
        mutate(actionName: "Remove Spacing Size", impact: .framework) { site in
            site.replacePartSpacingReference(token.name, with: replacement)
            site.framework.spacing.custom.removeAll { $0.id == id }
        }
    }

    func setFrameworkScreenEnabled(_ id: FrameworkScreenID, value: Bool) {
        mutate(actionName: "Enable Framework Screen", impact: .framework) { site in
            site.framework.screens.update(id) { $0.isEnabled = value }
        }
    }

    func setFrameworkScreenMinimumWidth(_ id: FrameworkScreenID, value: Double) {
        guard value.isFinite else { return }
        mutate(actionName: "Edit Framework Screen Width", impact: .framework) { site in
            site.framework.screens.update(id) { $0.minimumWidth = value }
        }
    }

    func setFrameworkScreenContainerUnit(_ id: FrameworkScreenID, value: FrameworkContainerUnit) {
        mutate(actionName: "Edit Framework Container Unit", impact: .framework) { site in
            site.framework.screens.update(id) { screen in
                screen.container.unit = value
                if value == .auto {
                    screen.container.value = screen.minimumWidth
                }
            }
        }
    }

    func setFrameworkScreenContainerWidth(_ id: FrameworkScreenID, value: Double) {
        guard value.isFinite else { return }
        mutate(actionName: "Edit Framework Container Width", impact: .framework) { site in
            site.framework.screens.update(id) { $0.container.value = value }
        }
    }

    func setFrameworkBorderWidth(id: String, value: Double) {
        setFrameworkDimension(
            id: id,
            value: value,
            actionName: "Edit Framework Border Width",
            keyPath: \Framework.borderWidths
        )
    }

    func setFrameworkBorderRadius(id: String, value: Double) {
        setFrameworkDimension(
            id: id,
            value: value,
            actionName: "Edit Framework Border Radius",
            keyPath: \Framework.borderRadii
        )
    }

    func resetFrameworkBorderWidths() {
        resetFrameworkDimensionScale(\.borderWidths, actionName: "Reset Framework Border Widths")
    }

    func resetFrameworkBorderRadii() {
        resetFrameworkDimensionScale(\.borderRadii, actionName: "Reset Framework Border Radii")
    }

    func setFrameworkZIndex(id: String, value: Double) {
        setFrameworkDimension(
            id: id,
            value: value,
            actionName: "Edit Framework Z-Index",
            keyPath: \Framework.zIndexes
        )
    }

    func resetFrameworkZIndexes() {
        resetFrameworkDimensionScale(\.zIndexes, actionName: "Reset Framework Z-Indexes")
    }

    /// Reset restores the source framework's saved predefined scale; custom
    /// values are the user's own and survive untouched.
    private func resetFrameworkDimensionScale(
        _ scale: WritableKeyPath<Framework, FrameworkDimensionTokens>,
        actionName: String
    ) {
        mutate(actionName: actionName, impact: .framework) { site in
            guard let source = FrameworkLibrary.shared.frameworks.first(where: { $0.id == site.frameworkSourceID }) else { return }
            site.framework[keyPath: scale].predefined = source.framework[keyPath: scale].predefined
        }
    }

    @discardableResult
    func addFrameworkBorderWidth() -> UUID {
        addFrameworkCustomDimension(\.borderWidths, value: 3, actionName: "Add Framework Border Width")
    }

    func setFrameworkBorderWidthName(id: UUID, value: String) {
        setFrameworkCustomDimensionName(\.borderWidths, id: id, value: value, actionName: "Rename Framework Border Width")
    }

    func setFrameworkBorderWidthValue(id: UUID, value: Double) {
        setFrameworkCustomDimensionValue(\.borderWidths, id: id, value: value, actionName: "Edit Framework Border Width")
    }

    func removeFrameworkBorderWidth(id: UUID) {
        removeFrameworkCustomDimension(
            \.borderWidths, projectValues: \.borderWidths, id: id,
            actionName: "Delete Framework Border Width", bakesAsRadius: false
        )
    }

    @discardableResult
    func addFrameworkBorderRadius() -> UUID {
        addFrameworkCustomDimension(\.borderRadii, value: 10, actionName: "Add Framework Border Radius")
    }

    func setFrameworkBorderRadiusName(id: UUID, value: String) {
        setFrameworkCustomDimensionName(\.borderRadii, id: id, value: value, actionName: "Rename Framework Border Radius")
    }

    func setFrameworkBorderRadiusValue(id: UUID, value: Double) {
        setFrameworkCustomDimensionValue(\.borderRadii, id: id, value: value, actionName: "Edit Framework Border Radius")
    }

    func removeFrameworkBorderRadius(id: UUID) {
        removeFrameworkCustomDimension(
            \.borderRadii, projectValues: \.borderRadii, id: id,
            actionName: "Delete Framework Border Radius", bakesAsRadius: true
        )
    }

    @discardableResult
    func addFrameworkZIndexValue() -> UUID {
        addFrameworkCustomDimension(\.zIndexes, value: 500, actionName: "Add Framework Stacking Order")
    }

    func setFrameworkZIndexName(id: UUID, value: String) {
        setFrameworkCustomDimensionName(\.zIndexes, id: id, value: value, actionName: "Rename Framework Stacking Order")
    }

    func setFrameworkZIndexValue(id: UUID, value: Double) {
        setFrameworkCustomDimensionValue(\.zIndexes, id: id, value: value, actionName: "Edit Framework Stacking Order")
    }

    func removeFrameworkZIndex(id: UUID) {
        // Stacking references live in token-only selections, which cannot
        // hold a raw number — deleting snaps them to the closest predefined
        // token instead of baking a length in.
        removeFrameworkCustomDimension(
            \.zIndexes, projectValues: \.zIndexes, id: id,
            actionName: "Delete Framework Stacking Order", bakesAsRadius: nil
        )
    }

    @discardableResult
    private func addFrameworkCustomDimension(
        _ scale: WritableKeyPath<Framework, FrameworkDimensionTokens>,
        value: Double,
        actionName: String
    ) -> UUID {
        let id = UUID()
        mutate(actionName: actionName, impact: .framework) { site in
            let existing = Set(site.framework[keyPath: scale].custom.map(\.name))
            var name = "new"
            var counter = 1
            while existing.contains(name) {
                name = "new\(counter)"
                counter += 1
            }
            site.framework[keyPath: scale].custom.append(.init(id: id, name: name, value: value))
        }
        return id
    }

    private func setFrameworkCustomDimensionName(
        _ scale: WritableKeyPath<Framework, FrameworkDimensionTokens>,
        id: UUID,
        value: String,
        actionName: String
    ) {
        mutate(actionName: actionName, impact: .framework) { site in
            guard let index = site.framework[keyPath: scale].custom.firstIndex(where: { $0.id == id }) else { return }
            site.framework[keyPath: scale].custom[index].name = value
        }
    }

    private func setFrameworkCustomDimensionValue(
        _ scale: WritableKeyPath<Framework, FrameworkDimensionTokens>,
        id: UUID,
        value: Double,
        actionName: String
    ) {
        guard value.isFinite, value >= 0 else { return }
        mutate(actionName: actionName, impact: .framework) { site in
            guard let index = site.framework[keyPath: scale].custom.firstIndex(where: { $0.id == id }) else { return }
            site.framework[keyPath: scale].custom[index].value = value
        }
    }

    /// Deleting a custom dimension bakes its pixel size into referencing
    /// parts (`bakesAsRadius` picks the value kind; nil skips baking) and
    /// snaps token-only selections to the closest predefined token.
    private func removeFrameworkCustomDimension(
        _ scale: WritableKeyPath<Framework, FrameworkDimensionTokens>,
        projectValues: WritableKeyPath<ProjectFrameworkValues, [FrameworkCustomDimension]>,
        id: UUID,
        actionName: String,
        bakesAsRadius: Bool?
    ) {
        mutate(actionName: actionName, impact: .framework) { site in
            guard let removed = site.framework[keyPath: scale].custom.first(where: { $0.id == id }) else { return }
            let fallbackToken = site.framework[keyPath: scale].predefined
                .min { abs($0.value - removed.value) < abs($1.value - removed.value) }?.id ?? "none"
            if let bakesAsRadius {
                site.bakePartFrameworkDimensionReference(
                    removed.reference,
                    amountPx: removed.value,
                    fallbackToken: fallbackToken,
                    isRadius: bakesAsRadius
                )
            } else {
                site.replacePartFrameworkReference(removed.reference, with: fallbackToken)
            }
            site.framework[keyPath: scale].custom.removeAll(where: { $0.id == id })
            site.projectFrameworkValues[keyPath: projectValues].removeAll(where: { $0.id == id })
            for index in site.frameworkStates.indices {
                site.frameworkStates[index].framework[keyPath: scale].custom.removeAll(where: { $0.id == id })
            }
        }
    }

    private func setFrameworkDimension(
        id: String,
        value: Double,
        actionName: String,
        keyPath: WritableKeyPath<Framework, FrameworkDimensionTokens>
    ) {
        guard value.isFinite, value >= 0 else { return }
        mutate(actionName: actionName, impact: .framework) { site in
            guard let index = site.framework[keyPath: keyPath].predefined.firstIndex(where: { $0.id == id }) else { return }
            site.framework[keyPath: keyPath].predefined[index].value = value
        }
    }

    @discardableResult
    func addFrameworkShadow() -> String {
        let id = "user-\(UUID().uuidString.lowercased())"
        let shadow = FrameworkShadow(
            id: id,
            title: "Custom Shadow",
            layers: [.init(x: 0, y: 4, blur: 8, opacity: 0.15)]
        )
        mutate(actionName: "Add Framework Shadow", impact: .framework) { $0.framework.shadows.custom.insert(shadow, at: 0) }
        return id
    }

    func removeFrameworkShadow(id: String, replacingWith replacement: String) {
        mutate(actionName: "Replace and Delete Framework Shadow", impact: .framework) { site in
            site.replacePartFrameworkReference(id, with: replacement)
            site.framework.shadows.custom.removeAll { $0.id == id }
            site.projectFrameworkValues.shadows.removeAll { $0.id == id }
            for index in site.frameworkStates.indices {
                site.frameworkStates[index].framework.shadows.custom.removeAll { $0.id == id }
            }
        }
    }

    func setFrameworkShadowTitle(id: String, value: String) {
        mutateFrameworkShadow(id: id, actionName: "Rename Framework Shadow") { $0.title = value }
    }

    func setFrameworkShadowLayer(shadowID: String, layer: FrameworkShadowLayer) {
        mutateFrameworkShadow(id: shadowID, actionName: "Edit Framework Shadow") { shadow in
            guard let index = shadow.layers.firstIndex(where: { $0.id == layer.id }) else { return }
            shadow.layers[index] = layer
        }
    }

    func setFrameworkShadowLayers(shadowID: String, layers: [FrameworkShadowLayer]) {
        mutateFrameworkShadow(id: shadowID, actionName: "Edit Framework Shadow") { $0.layers = layers }
    }

    @discardableResult
    func addFrameworkShadowLayer(shadowID: String) -> UUID {
        let layer = FrameworkShadowLayer(x: 0, y: 4, blur: 8, opacity: 0.15)
        mutateFrameworkShadow(id: shadowID, actionName: "Add Shadow Layer") { $0.layers.append(layer) }
        return layer.id
    }

    func removeFrameworkShadowLayer(shadowID: String, layerID: UUID) {
        mutateFrameworkShadow(id: shadowID, actionName: "Delete Shadow Layer") {
            $0.layers.removeAll { $0.id == layerID }
        }
    }

    func resetFrameworkShadowScale() {
        mutate(actionName: "Reset Framework Shadow Scale", impact: .framework) { site in
            let defaults = FrameworkLibrary.shared.frameworks
                .first(where: { $0.id == site.frameworkSourceID })?
                .framework.shadows.predefined ?? ShadowTokens.standard.predefined
            site.framework.shadows.predefined = defaults
        }
    }

    private func mutateFrameworkShadow(
        id: String,
        actionName: String,
        update: (inout FrameworkShadow) -> Void
    ) {
        mutate(actionName: actionName, impact: .framework) { site in
            if let index = site.framework.shadows.custom.firstIndex(where: { $0.id == id }) {
                update(&site.framework.shadows.custom[index])
            } else if let index = site.framework.shadows.predefined.firstIndex(where: { $0.id == id }) {
                update(&site.framework.shadows.predefined[index])
            }
        }
    }

    func setFrameworkBodyFont(_ value: String) {
        setFrameworkFont(value, for: .body)
    }

    func setFrameworkFont(_ value: String, for role: FrameworkFontRole) {
        mutate(actionName: "Edit Framework Font Family", impact: .framework) { site in
            switch role {
            case .body: site.framework.typography.bodyFont.family = value
            case .heading: site.framework.typography.headingFont.family = value
            case .monospaced: site.framework.typography.monospacedFont.family = value
            }
        }
    }

    @discardableResult
    func addFrameworkCustomFont() -> UUID {
        let font = FrameworkCustomFont(
            name: "Custom Font",
            font: .system(family: "system-ui", weights: [400, 700])
        )
        mutate(actionName: "Add Framework Font", impact: .framework) { $0.framework.typography.customFonts.append(font) }
        return font.id
    }

    func setFrameworkCustomFontName(id: UUID, value: String) {
        mutate(actionName: "Rename Framework Font", impact: .framework) { site in
            guard let index = site.framework.typography.customFonts.firstIndex(where: { $0.id == id }) else { return }
            site.framework.typography.customFonts[index].name = value
        }
    }

    func setFrameworkCustomFontFamily(id: UUID, value: String) {
        mutate(actionName: "Edit Framework Font", impact: .framework) { site in
            guard let index = site.framework.typography.customFonts.firstIndex(where: { $0.id == id }) else { return }
            site.framework.typography.customFonts[index].font.family = value
        }
    }

    func setFrameworkFontFallbacks(_ value: String, reference: FrameworkFontReference) {
        updateFrameworkFont(reference: reference, actionName: "Edit Framework Font Fallbacks") {
            $0.fallbacks = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    func setFrameworkFontSource(_ source: FrameworkFontSource, reference: FrameworkFontReference) {
        updateFrameworkFont(reference: reference, actionName: "Edit Framework Font Source") {
            if case .system = $0.source {
                $0.systemFontNames = [$0.family] + $0.fallbacks
            }
            $0.source = source
        }
    }

    func restoreFrameworkFontNames(reference: FrameworkFontReference) {
        updateFrameworkFont(reference: reference, actionName: "Use Font Names") { definition in
            let names = definition.systemFontNames ?? defaultSystemFontNames(for: reference)
            definition.family = names.first ?? "system-ui"
            definition.fallbacks = Array(names.dropFirst())
            definition.source = .system
            definition.systemFontNames = names
        }
    }

    func setFrameworkFontFamily(_ value: String, reference: FrameworkFontReference) {
        updateFrameworkFont(reference: reference, actionName: "Edit Framework Font Family") {
            $0.family = value
        }
    }

    func setFrameworkFontNames(_ value: String, reference: FrameworkFontReference) {
        let names = value.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let family = names.first else { return }
        updateFrameworkFont(reference: reference, actionName: "Edit Framework Font Names") {
            $0.family = family
            $0.fallbacks = Array(names.dropFirst())
            $0.source = .system
            $0.systemFontNames = names
        }
    }

    func setFrameworkGoogleFont(_ family: String, reference: FrameworkFontReference, configuration: GoogleFontConfiguration? = nil) {
        let normalizedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFamily.isEmpty,
              let url = FrameworkFontDefinition.googleStylesheetURL(for: normalizedFamily) else { return }
        updateFrameworkFont(reference: reference, actionName: "Choose Google Font") {
            if case .system = $0.source {
                $0.systemFontNames = [$0.family] + $0.fallbacks
            }
            $0.family = normalizedFamily
            $0.fallbacks = []
            $0.source = .remote(stylesheetURL: url)
            $0.googleConfiguration = nil
            if let configuration { $0.applyGoogleConfiguration(configuration) }
        }
    }

    func setFrameworkFontDefinition(
        _ definition: FrameworkFontDefinition,
        reference: FrameworkFontReference,
        actionName: String
    ) {
        updateFrameworkFont(reference: reference, actionName: actionName) {
            $0 = definition
        }
    }

    func setFrameworkFontResources(_ files: [String], reference: FrameworkFontReference) {
        let uniqueFiles = files.reduce(into: [String]()) { result, file in
            if !result.contains(file) { result.append(file) }
        }
        let contents = document.assetContents
        let metadata = uniqueFiles.compactMap { file -> FontFileMetadata? in
            guard let id = file.foundryAssetID, let content = contents[id] else { return nil }
            return FontFileMetadata.read(content)
        }
        updateFrameworkFont(reference: reference, actionName: "Edit Font Resources") {
            let previous: [String]
            if case .bundled(let files) = $0.source { previous = files } else { previous = [] }
            // Removing a broken attachment must remain possible; adding files must
            // never introduce unreadable data or mix unrelated families.
            if !Set(uniqueFiles).isSubset(of: Set(previous)) {
                guard metadata.count == uniqueFiles.count,
                      let first = metadata.first,
                      metadata.allSatisfy({ $0.belongsToSameFamily(as: first) }) else { return }
            }
            $0.source = .bundled(files: uniqueFiles)
            if let first = metadata.first, metadata.allSatisfy({ $0.belongsToSameFamily(as: first) }) {
                $0.family = first.family
                $0.fallbacks = []
                $0.weights = Array(Set(metadata.flatMap { face in
                    face.weight == face.maximumWeight ? [face.weight] : Array(stride(from: face.weight, through: face.maximumWeight, by: 100))
                })).sorted()
                $0.styles = metadata.contains(where: \.italic) ? (metadata.contains(where: { !$0.italic }) ? [.normal, .italic] : [.italic]) : [.normal]
            }
        }
    }

    func setFrameworkFontWeights(_ weights: [Int], reference: FrameworkFontReference) {
        updateFrameworkFont(reference: reference, actionName: "Edit Framework Font Weights") {
            let normalized = Array(Set(weights)).sorted()
            $0.weights = normalized.isEmpty ? [400] : normalized
        }
    }

    func setFrameworkFontStyles(_ styles: [FrameworkFontStyle], reference: FrameworkFontReference) {
        updateFrameworkFont(reference: reference, actionName: "Edit Framework Font Styles") {
            $0.styles = styles.isEmpty ? [.normal] : styles
        }
    }

    func removeFrameworkCustomFont(id: UUID, replacingWith replacement: String) {
        let reference = "custom:\(id.uuidString.lowercased())"
        mutate(actionName: "Replace and Delete Framework Font", impact: .framework) { site in
            site.replacePartFrameworkReference(reference, with: replacement)
            site.framework.typography.customFonts.removeAll(where: { $0.id == id })
            site.projectFrameworkValues.fonts.removeAll(where: { $0.id == id })
            for index in site.frameworkStates.indices {
                site.frameworkStates[index].framework.typography.customFonts.removeAll(where: { $0.id == id })
            }
        }
    }

    private func updateFrameworkFont(
        reference: FrameworkFontReference,
        actionName: String,
        update: (inout FrameworkFontDefinition) -> Void
    ) {
        mutate(actionName: actionName, impact: .framework) { site in
            switch reference {
            case .role(.body): update(&site.framework.typography.bodyFont)
            case .role(.heading): update(&site.framework.typography.headingFont)
            case .role(.monospaced): update(&site.framework.typography.monospacedFont)
            case .custom(let id):
                guard let index = site.framework.typography.customFonts.firstIndex(where: { $0.id == id }) else { return }
                update(&site.framework.typography.customFonts[index].font)
            }
        }
    }

    private func defaultSystemFontNames(for reference: FrameworkFontReference) -> [String] {
        let definition = switch reference {
        case .role(.body): FrameworkBundleStore.systemFramework.typography.bodyFont
        case .role(.heading): FrameworkBundleStore.systemFramework.typography.headingFont
        case .role(.monospaced): FrameworkBundleStore.systemFramework.typography.monospacedFont
        case .custom: FrameworkFontDefinition.system(family: "system-ui", weights: [400, 700])
        }
        return [definition.family] + definition.fallbacks
    }

    func setFrameworkFontSize(id: String, value: Double) {
        guard value.isFinite, value > 0 else { return }
        mutate(actionName: "Edit Framework Font Size", impact: .framework) { site in
            if let index = site.framework.typography.predefinedFontSizes.firstIndex(where: { $0.id == id }) {
                site.framework.typography.predefinedFontSizes[index].size = value
            } else if let index = site.framework.typography.customFontSizes.firstIndex(where: { $0.id == id }) {
                site.framework.typography.customFontSizes[index].size = value
            }
        }
    }

    func setFrameworkFontSizeLineHeight(id: String, value: Double) {
        guard value.isFinite, value > 0 else { return }
        mutate(actionName: "Edit Framework Line Height", impact: .framework) { site in
            if let index = site.framework.typography.predefinedFontSizes.firstIndex(where: { $0.id == id }) {
                site.framework.typography.predefinedFontSizes[index].lineHeight = value
            } else if let index = site.framework.typography.customFontSizes.firstIndex(where: { $0.id == id }) {
                site.framework.typography.customFontSizes[index].lineHeight = value
            }
        }
    }

    func setFrameworkFontSizeTitle(id: String, value: String) {
        mutate(actionName: "Rename Framework Font Size", impact: .framework) { site in
            guard let index = site.framework.typography.customFontSizes.firstIndex(where: { $0.id == id }) else { return }
            site.framework.typography.customFontSizes[index].title = value
        }
    }

    func resetFrameworkFontSizeScale() {
        mutate(actionName: "Reset Framework Font Size Scale", impact: .framework) { site in
            guard let source = FrameworkLibrary.shared.frameworks.first(where: { $0.id == site.frameworkSourceID }) else { return }
            site.framework.typography.predefinedFontSizes = source.framework.typography.predefinedFontSizes
        }
    }

    @discardableResult
    func addFrameworkFontSize() -> String {
        let newID = "user-\(UUID().uuidString.lowercased())"
        mutate(actionName: "Add Framework Font Size", impact: .framework) { site in
            site.framework.typography.customFontSizes.insert(
                .init(id: newID, title: "Custom", size: 1, lineHeight: 1.5),
                at: 0
            )
        }
        return newID
    }

    func removeFrameworkFontSize(id: String, replacingWith replacement: String) {
        mutate(actionName: "Replace and Delete Framework Type Size", impact: .framework) { site in
            site.replacePartFrameworkReference(id, with: replacement)
            site.framework.typography.customFontSizes.removeAll { $0.id == id }
            site.projectFrameworkValues.fontSizes.removeAll { $0.id == id }
            for index in site.frameworkStates.indices {
                site.frameworkStates[index].framework.typography.customFontSizes.removeAll { $0.id == id }
            }
        }
    }

    func moveFrameworkFontSize(id: String, before targetID: String) {
        guard id != targetID else { return }
        mutate(actionName: "Reorder Framework Font Sizes", impact: .framework) { site in
            guard let source = site.framework.typography.customFontSizes.firstIndex(where: { $0.id == id }) else { return }
            let item = site.framework.typography.customFontSizes.remove(at: source)
            guard let destination = site.framework.typography.customFontSizes.firstIndex(where: { $0.id == targetID }) else {
                site.framework.typography.customFontSizes.insert(item, at: source)
                return
            }
            site.framework.typography.customFontSizes.insert(item, at: destination)
        }
    }

    func moveFrameworkFontSizes(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        mutate(actionName: "Reorder Framework Font Sizes", impact: .framework) { site in
            var sizes = site.framework.typography.customFontSizes
            let moving = offsets.sorted().map { sizes[$0] }
            for index in offsets.sorted(by: >) {
                sizes.remove(at: index)
            }
            let removedBeforeDestination = offsets.filter { $0 < destination }.count
            let insertionIndex = max(0, min(destination - removedBeforeDestination, sizes.count))
            sizes.insert(contentsOf: moving, at: insertionIndex)
            site.framework.typography.customFontSizes = sizes
        }
    }

    func selectFramework(_ framework: Framework, sourceID: UUID) {
        mutate(actionName: "Select Framework", impact: .framework) { site in
            guard site.frameworkSourceID != sourceID else { return }
            site.projectFrameworkValues.absorb(site.framework)
            if site.frameworkSourceID != sourceID { site.saveActiveFrameworkState() }
            site.projectFrameworkValues.include(framework)
            let selected = site.frameworkStates.first(where: { $0.sourceID == sourceID })?.framework ?? framework
            site.framework = site.projectFrameworkValues.applied(to: selected)
            site.frameworkSourceID = sourceID
        }
    }

    func resetFramework(_ framework: Framework, sourceID: UUID) {
        mutate(actionName: "Reset Framework", impact: .framework) { site in
            site.projectFrameworkValues.absorb(site.framework)
            site.frameworkStates.removeAll { $0.sourceID == sourceID }
            site.framework = site.projectFrameworkValues.applied(to: framework)
            site.frameworkSourceID = sourceID
        }
    }

    func didDeleteFramework(sourceID: UUID) {
        mutate(actionName: "Delete Framework", impact: .framework) { site in
            site.frameworkStates.removeAll { $0.sourceID == sourceID }
            guard site.frameworkSourceID == sourceID else { return }
            site.projectFrameworkValues.absorb(site.framework)
            site.frameworkStates.removeAll { $0.sourceID == FrameworkBundleStore.systemFrameworkID }
            site.framework = site.projectFrameworkValues.applied(to: FrameworkBundleStore.systemFramework)
            site.frameworkSourceID = FrameworkBundleStore.systemFrameworkID
        }
    }

    func commitFramework(_ framework: Framework, sourceID: UUID) {
        mutate(actionName: "Update Framework Defaults", impact: .framework) { site in
            let projectColours = site.framework.colourPalettes.filter { $0.origin == .custom }
            site.frameworkStates.removeAll { $0.sourceID == sourceID }
            site.projectFrameworkValues.absorb(framework)
            site.projectFrameworkValues.colours = projectColours
            site.framework = site.projectFrameworkValues.applied(to: framework)
            site.frameworkSourceID = sourceID
        }
    }

    @discardableResult
    func addPart(
        type: PartType,
        to pageID: UUID,
        parentID: UUID?
    ) -> UUID {
        let node = PartNode.make(type, framework: document.site.framework)
        let page = document.site.pages.first(where: { $0.id == pageID })
        let sharedInsertion = page.map {
            document.site.sharedGlobalInsertion(on: $0, at: parentID.map(PartPlacement.inside) ?? .end)
        } ?? SharedGlobalStructureMove(authoritativeInstances: [:])
        mutate(actionName: "Add \(type.displayName)", impact: .partStructure(ownerID: parentID)) { site in
            guard let pageIndex = site.pages.firstIndex(where: { $0.id == pageID }) else {
                return
            }
            site.pages[pageIndex].parts.append(node, to: parentID)
            site.synchronizeGlobalsAfterStructureMove(sharedInsertion)
        }
        return node.id
    }

    func removePart(id: UUID) {
        removeParts(ids: [id])
    }

    func removeParts(ids: [UUID]) {
        guard !ids.isEmpty,
              canRemoveParts(ids: ids),
              let sharedRemoval = document.site.sharedGlobalRemoval(partIDs: ids) else { return }
        mutate(actionName: ids.count == 1 ? "Delete Part" : "Delete Parts", impact: .partStructure(ownerID: nil)) { site in
            for id in ids {
                for pageIndex in site.pages.indices {
                    if site.pages[pageIndex].parts.removeNode(withID: id) {
                        break
                    }
                }
            }
            site.synchronizeGlobalsAfterStructureMove(sharedRemoval)
        }
    }

    func canRemoveParts(ids: [UUID]) -> Bool {
        var pages = document.site.pages
        for id in ids {
            guard let pageIndex = pages.firstIndex(where: { $0.parts.node(withID: id) != nil }),
                  pages[pageIndex].parts.permitsRemoving(id) else {
                return false
            }
            _ = pages[pageIndex].parts.extractNode(withID: id)
        }
        return true
    }

    func mutate(
        actionName: String,
        impact: ProjectMutationImpact = .page,
        mutation: (inout Site) -> Void
    ) {
        var updatedSite = document.site
        mutation(&updatedSite)
        document.replaceSite(
            with: updatedSite,
            undoManager: undoManager,
            actionName: actionName,
            impact: impact
        )
    }
}

nonisolated extension Site {
    func part(withID id: UUID) -> PartNode? {
        for page in pages {
            if let part = page.parts.node(withID: id) {
                return part
            }
        }
        return nil
    }

    mutating func updatePart(
        id: UUID,
        transform: (inout PartNode) -> Void
    ) {
        for pageIndex in pages.indices {
            if pages[pageIndex].parts.updateNode(withID: id, transform: transform) {
                return
            }
        }
    }
}
