import Foundation

nonisolated struct HTMLPageRenderer: PageRendering {
    let site: Site?
    let appearance: SiteAppearance

    init(site: Site? = nil, appearance: SiteAppearance = .light) { self.site = site; self.appearance = appearance }
    func render(page: Page, theme: Theme) -> String {
        render(page: page, language: "en", theme: theme, assets: [:], breakpoint: .extraLarge)
    }

    func render(page: Page, language: String, theme: Theme, assets: ProjectAssetContents, breakpoint: ResponsiveBreakpoint) -> String {
        let body = page.parts.isEmpty
            ? rootDropZone
            : page.parts.map { render($0, page: page, theme: theme, assets: assets, globalDefinitionID: $0.reusableDefinitionID, breakpoint: breakpoint) }.joined(separator: "\n")
        let pageTitle = page.metadata.browserTitle.isEmpty ? page.title : page.metadata.browserTitle
        let browserTitle = pageTitle + (site?.titleSuffix ?? "")
        let metadata = metadataHTML(for: page, browserTitle: browserTitle, site: site, assets: assets)
        let headStart = placedHTML(for: page, placement: .headStart)
        let headEnd = placedHTML(for: page, placement: .headEnd)
        let bodyStart = placedHTML(for: page, placement: .bodyStart)
        let bodyEnd = placedHTML(for: page, placement: .bodyEnd)
        let scripts = packageScripts(for: page, theme: theme, assets: assets, breakpoint: breakpoint)
        let customHeadCode = site?.customCodeEnabled == true ? site?.headCode ?? "" : ""
        let customBodyStartCode = site?.customCodeEnabled == true ? site?.bodyStartCode ?? "" : ""
        let customBodyEndCode = site?.customCodeEnabled == true ? site?.bodyEndCode ?? "" : ""
        let analyticsCode = site?.customCodeEnabled == true ? site?.analyticsCode ?? "" : ""
        let documentLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        <!doctype html>
        <html lang="\(escapeAttribute(documentLanguage.isEmpty ? "en" : documentLanguage))">
        <head>
        \(headStart)
        \(customHeadCode)
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="\(appearance.rawValue)">
          <title>\(escape(browserTitle))</title>
        \(metadata)
          <style data-foundry-font-sources>
            \(theme.fontSourceCSS(assets: assets, destination: .canvas))
          </style>
          <style>
            :root {
              font-size: 16px;
              color-scheme: \(appearance.rawValue);
              --foundry-color-page: \(theme.color(for: .page, appearance: appearance));
              --foundry-color-background: \(theme.color(for: .background, appearance: appearance));
              --foundry-color-surface: \(theme.color(for: .surface, appearance: appearance));
              --foundry-color-text: \(theme.color(for: .text, appearance: appearance));
              --foundry-color-accent: \(theme.color(for: .accent, appearance: appearance));
              --foundry-color-links: \(theme.color(for: .links, appearance: appearance));
              --foundry-color-muted-text: \(theme.color(for: .mutedText, appearance: appearance));
              --foundry-font-body: \(theme.typography.bodyFont.cssFamily);
              --foundry-font-heading: \(theme.typography.headingFont.cssFamily);
              --foundry-font-monospace: \(theme.typography.monospacedFont.cssFamily);
              \(theme.customFontCSSVariables)
              \(theme.fontSizeCSSVariables)
              --foundry-editor-part: #007BFF;
              --foundry-editor-global: #30D158;
              --foundry-editor-primitive: #007BFF;
              \(theme.spacingCSSVariables)
              \(theme.shadowCSSVariables)
              \(theme.borderCSSVariables)
              \(theme.zIndexCSSVariables)
            }
            *, *::before, *::after { box-sizing: border-box; }
            a { color: var(--foundry-color-links); }
            \(theme.screens.containerCSS)
            .foundry-container { width: 100%; max-width: var(--foundry-container-width) !important; }
            [data-foundry-id] {
              --foundry-editor-chrome: var(--foundry-editor-part);
              cursor: default;
            }
            [data-foundry-global] { --foundry-editor-chrome: var(--foundry-editor-global); }
            [data-foundry-global]:not([data-foundry-global-override="true"]) [data-foundry-id] {
              --foundry-editor-chrome: var(--foundry-editor-global);
            }
            [data-foundry-global][data-foundry-global-override="true"],
            [data-foundry-global][data-foundry-global-override="true"] [data-foundry-id] {
              --foundry-editor-chrome: var(--foundry-editor-part);
            }
            .foundry-multi-drag-image {
              position: fixed; left: -1000px; top: -1000px; z-index: 2000;
              min-width: 132px; padding: 9px 13px; border: 2px solid var(--foundry-drag-color);
              border-radius: 8px; background: rgba(255,255,255,.96); color: #171719;
              box-shadow: 4px 4px 0 color-mix(in srgb, var(--foundry-drag-color) 35%, white),
                          8px 8px 0 color-mix(in srgb, var(--foundry-drag-color) 18%, white),
                          0 8px 24px rgba(0,0,0,.2);
              font: 600 12px system-ui; text-align: center;
            }
            [contenteditable="true"]:focus {
              outline: none !important;
            }
            .foundry-drag-source { opacity: 0.4 !important; }
            .foundry-empty-drop-zone {
              display: grid; place-items: center; min-height: 64px; padding: 16px;
              border: 2px dashed color-mix(in srgb, var(--foundry-editor-chrome) 42%, transparent) !important;
              border-radius: 6px; color: color-mix(in srgb, var(--foundry-color-text) 58%, transparent);
              background: color-mix(in srgb, var(--foundry-color-surface) 72%, transparent);
              font: 600 13px system-ui; text-align: center;
            }
            .foundry-empty-page { min-height: 100vh; }
            .foundry-contentless-drop-zone { min-height: 32px; padding: 6px 12px; }
            .foundry-grid > .foundry-empty-drop-zone { grid-column: 1 / -1; }
            [data-foundry-global].foundry-empty-drop-zone {
              border-color: color-mix(in srgb, var(--foundry-editor-chrome) 42%, transparent) !important;
            }
            [data-foundry-global].foundry-editing { outline-color: var(--foundry-editor-chrome) !important; }
            html, body { min-height: 100%; }
            body {
              margin: 0; background: \(page.backgroundColour(theme: theme, appearance: appearance));
              color: var(--foundry-color-text); font-family: var(--foundry-font-body);
              font-size: var(--foundry-font-size-base); line-height: var(--foundry-font-size-base-line-height);
              display: flex; flex-direction: column; align-items: stretch;
            }
            h1, h2, h3, h4, h5, h6, .foundry-heading { font-family: var(--foundry-font-heading); }
            code, pre, kbd, samp { font-family: var(--foundry-font-monospace); }
            .foundry-button {
              display: block; width: fit-content; text-decoration: none; font-weight: 600;
            }
            .foundry-grid { display: grid; }
            .foundry-image { display: block; width: 100%; height: auto; }
            .foundry-image-drop-zone {
              display: grid; width: 100%; min-height: 64px; padding: 16px; place-items: center;
              border: 2px dashed color-mix(in srgb, var(--foundry-editor-chrome) 42%, transparent) !important;
              border-radius: 6px; color: color-mix(in srgb, var(--foundry-color-text) 58%, transparent);
              background: color-mix(in srgb, var(--foundry-color-surface) 72%, transparent);
              font: 600 13px system-ui; text-align: center;
            }
            .unavailable { padding: 16px; border: 2px dashed #C33; color: #922; background: #FFF5F5; }
            \(FoundryWebLibraryRegistry.canvasCSS(for: PartArtifactPlan(page: page).packages))
            \(packageStyles(for: page, theme: theme, assets: assets, breakpoint: breakpoint))
          </style>
        \(analyticsCode)
        \(headEnd)
        </head>
        <body>\(customBodyStartCode)\(bodyStart)\(body)\(bodyEnd)\(scripts)\(customBodyEndCode)</body>
        </html>
        """
    }

    func renderSubtree(
        partID: UUID,
        page: Page,
        theme: Theme,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedPartSubtree? {
        guard let target = subtreeTarget(partID: partID, in: page.parts) else { return nil }
        return RenderedPartSubtree(
            partID: partID,
            html: render(
                target.node,
                page: page,
                theme: theme,
                assets: assets,
                globalDefinitionID: target.inheritedGlobalDefinitionID,
                breakpoint: breakpoint,
                parentPartID: target.parentPartID,
                parentSlot: target.parentSlot,
                parentDropZoneSlotID: target.parentDropZoneSlotID
            ),
            instanceCSS: partStyles(
                for: flattened(target.node),
                page: page,
                theme: theme,
                assets: assets,
                breakpoint: breakpoint
            )
        )
    }

    private func packageScripts(
        for page: Page,
        theme: Theme,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> String {
        let nodes = page.parts.flatMap(flattened)
        let instanceScripts = nodes.compactMap { sourceNode -> String? in
            let node = sourceNode.resolved(at: breakpoint, screens: theme.screens)
            guard let package = node.type.definition.package, !package.instanceJavaScript.isEmpty else { return nil }
            return PartTemplateRenderer.render(
                package.instanceJavaScript,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assets: assets),
                    templateValues: site.map { PartNavigationTemplateValues.values(site: $0, currentPage: page) } ?? [:],
                    slots: [:],
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    environment: .canvas,
                    loopMaximums: package.loopMaximums
                )
            )
        }
        var seenPackages: Set<String> = []
        let sharedScripts = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = package.pageJavaScript
            guard !source.isEmpty else { return nil }
            return PartTemplateRenderer.render(
                source,
                context: .init(instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), packageIdentifier: package.manifest.identifier, properties: [:], templateValues: site.map { PartNavigationTemplateValues.values(site: $0, currentPage: page) } ?? [:], slots: [:], assetBasePath: canvasAssetBasePath(for: package), assetPaths: canvasAssetPaths(for: package), environment: .canvas, loopMaximums: package.loopMaximums)
            )
        }
        let htmlScripts = nodes.map {
            PartArtifactPlan.htmlArtifact(for: $0.resolved(at: breakpoint, screens: theme.screens), suffix: "JavaScript")
        }
            .filter { !$0.isEmpty }
        let source = (instanceScripts + htmlScripts + sharedScripts).joined(separator: "\n")
        return source.isEmpty ? "" : "<script>\n\(source)\n</script>"
    }

    private func placedHTML(for page: Page, placement: PartPackageTemplateFile.Placement) -> String {
        var seenPackages: Set<String> = []
        return page.parts.flatMap(flattened).compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let templates = package.placedHTML.filter { $0.placement == placement }
            guard !templates.isEmpty else { return nil }
            let context = PartTemplateContext(
                instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                packageIdentifier: package.manifest.identifier,
                properties: [:],
                templateValues: site.map { PartNavigationTemplateValues.values(site: $0, currentPage: page) } ?? [:],
                slots: [:],
                assetBasePath: canvasAssetBasePath(for: package),
                assetPaths: canvasAssetPaths(for: package),
                environment: .canvas,
                loopMaximums: package.loopMaximums
            )
            return templates.map { PartTemplateRenderer.render($0.contents, context: context) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func metadataHTML(
        for page: Page,
        browserTitle: String,
        site: Site?,
        assets: ProjectAssetContents
    ) -> String {
        var tags: [String] = []
        let description = page.metadata.description.isEmpty
            ? site?.defaultDescription ?? ""
            : page.metadata.description
        if !description.isEmpty {
            tags.append("<meta name=\"description\" content=\"\(escapeAttribute(description))\">")
        }
        let socialTitle = page.metadata.socialTitle.isEmpty ? browserTitle : page.metadata.socialTitle
        tags.append("<meta property=\"og:title\" content=\"\(escapeAttribute(socialTitle))\">")

        if site?.allowsSearchIndexing == false {
            tags.append("<meta name=\"robots\" content=\"noindex, nofollow\">")
        }

        if let site,
           site.generatesCanonicalURLs,
           let baseURL = validPublicURL(site.publicURL) {
            let canonicalURL = absoluteURL(for: page, in: site, baseURL: baseURL)
            tags.append("<link rel=\"canonical\" href=\"\(escapeAttribute(canonicalURL))\">")
        }

        let socialDescription = page.metadata.socialDescription.isEmpty
            ? description
            : page.metadata.socialDescription
        if !socialDescription.isEmpty {
            tags.append("<meta property=\"og:description\" content=\"\(escapeAttribute(socialDescription))\">")
        }
        let socialImage = page.metadata.socialImage.isEmpty
            ? site?.defaultSocialImage ?? ""
            : page.metadata.socialImage
        if !socialImage.isEmpty {
            let source = canvasSource(socialImage, assets: assets)
            if !source.isEmpty {
                tags.append("<meta property=\"og:image\" content=\"\(escapeAttribute(source))\">")
            }
        }
        if let favicon = site?.favicon, !favicon.isEmpty {
            let source = canvasSource(favicon, assets: assets)
            if !source.isEmpty {
                tags.append("<link rel=\"icon\" href=\"\(escapeAttribute(source))\">")
            }
        }
        return tags.map { "  " + $0 }.joined(separator: "\n")
    }

    private func validPublicURL(_ value: String) -> String? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else { return nil }
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    private func absoluteURL(for page: Page, in site: Site, baseURL: String) -> String {
        guard page.slug != "index" else { return baseURL + "/" }
        let slugs = PageRouteResolver.pathSegments(
            for: page,
            pages: site.pages,
            folders: site.pageFolders
        )
        return baseURL + "/" + slugs.joined(separator: "/") + "/"
    }

    private func render(_ sourceNode: PartNode, page: Page, theme: Theme, assets: ProjectAssetContents, globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint, parentPartID: UUID? = nil, parentSlot: PartPackageSlot? = nil, parentDropZoneSlotID: String? = nil) -> String {
        let node = sourceNode.resolved(at: breakpoint, screens: theme.screens)
        let globalDefinitionID = node.reusableDefinitionID ?? globalDefinitionID
        switch node.type.definition.renderKind {
        case .package:
            guard let package = node.type.definition.package else {
                return unavailablePart(node, page: page, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: parentPartID)
            }
            do {
                try package.preparePayload()
            } catch {
                return failedPart(node, page: page, package: package, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: parentPartID)
            }
            let slots = Dictionary(uniqueKeysWithValues: package.manifest.slots.map { slot in
                let children = node.children.filter {
                    ($0.slotID ?? (package.hasDropZone ? nil : package.manifest.slots.first?.id)) == slot.id
                }
                let html = children.map {
                    render($0, page: page, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: node.id, parentSlot: slot)
                }.joined()
                return (slot.id, html.isEmpty ? "<div class=\"foundry-empty-drop-zone\" data-foundry-empty-parent=\"\(node.id.uuidString)\" data-foundry-slot-id=\"\(escapeAttribute(slot.id))\">Drop part here</div>" : html)
            })
            let dropZones = Dictionary(uniqueKeysWithValues: package.dropZoneNames.enumerated().map { index, name in
                let slotID = package.dropZoneSlotID(for: name)
                let children = node.children.filter { $0.slotID == slotID || (index == 0 && $0.slotID == nil) }
                let html = children.map {
                    render($0, page: page, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: node.id, parentDropZoneSlotID: slotID)
                }.joined()
                let output = html.isEmpty
                    ? "<div class=\"foundry-empty-drop-zone\" data-foundry-empty-parent=\"\(node.id.uuidString)\" data-foundry-slot-id=\"\(escapeAttribute(slotID))\">Drop part here</div>"
                    : html
                return (name, output)
            })
            let adjacentDropAttribute = !package.hasDropZone && package.manifest.slots.isEmpty
                ? " data-foundry-adjacent-target=\"\(node.id.uuidString)\""
                : ""
            let defaultSlotID = package.dropZoneNames.first.map(package.dropZoneSlotID(for:))
                ?? package.manifest.slots.first?.id
            let canvasAttributes = attributes(for: node, globalDefinitionID: globalDefinitionID, parentPartID: parentPartID, parentSlot: parentSlot, parentDropZoneSlotID: parentDropZoneSlotID) +
                (defaultSlotID.map { " data-foundry-default-slot=\"\(escapeAttribute($0))\"" } ?? "") +
                adjacentDropAttribute
            let renderedProperties = packageProperties(node, theme: theme, assets: assets)
            let templateContext = PartTemplateContext(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: renderedProperties,
                    templateValues: site.map { PartNavigationTemplateValues.values(site: $0, currentPage: page) } ?? [:],
                    slots: slots,
                    dropZones: dropZones,
                    partClass: partClass(node) + " " +
                        PartTemplateRenderer.packageClass(for: package.manifest.identifier),
                    partAttributes: canvasAttributes,
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    enablesEditorMarkup: true,
                    environment: .canvas,
                    richTextLinkContext: richTextLinkContext,
                    loopMaximums: package.loopMaximums
                )
            let rendered = PartTemplateRenderer.render(package.htmlTemplate, context: templateContext)
            let decorated = PartPackageHTMLContributionRenderer.decorate(
                rendered,
                contributions: package.manifest.htmlContributions,
                context: templateContext
            )
            if package.htmlTemplate.contains("{{ part.attributes }}") ||
                package.htmlTemplate.contains("{{part.attributes}}") {
                return decorated
            }
            return "<div \(canvasAttributes)>\(decorated)</div>"
        case .unavailable:
            return unavailablePart(node, page: page, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: parentPartID)
        }
    }

    private var richTextLinkContext: FoundryRichTextCodec.LinkContext {
        .init(
            pages: site?.pages ?? [],
            folders: site?.pageFolders ?? [],
            assets: site?.assets ?? [],
            assetLibrary: site?.assetLibrary,
            publicURL: site?.publicURL ?? "",
            absoluteURL: false
        )
    }

    private func packageStyles(
        for page: Page,
        theme: Theme,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> String {
        let nodes = page.parts.flatMap(flattened)
        let partStyles = partStyles(
            for: nodes,
            page: page,
            theme: theme,
            assets: assets,
            breakpoint: breakpoint
        )
        var seenPackages: Set<String> = []
        let pageStyles = page.parts.flatMap(flattened).compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  (!package.pageCSS.isEmpty || !package.siteCSS.isEmpty),
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            return PartTemplateRenderer.render(
                [package.pageCSS, package.siteCSS].filter { !$0.isEmpty }.joined(separator: "\n"),
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    templateValues: site.map { PartNavigationTemplateValues.values(site: $0, currentPage: page) } ?? [:],
                    slots: [:],
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    environment: .canvas,
                    loopMaximums: package.loopMaximums
                )
            )
        }.joined(separator: "\n")
        return [partStyles, pageStyles].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func partStyles(
        for nodes: [PartNode],
        page: Page,
        theme: Theme,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> String {
        let instanceStyles = nodes.compactMap { sourceNode in
            let node = sourceNode.resolved(at: breakpoint, screens: theme.screens)
            guard let package = node.type.definition.package else { return nil }
            let css = PartTemplateRenderer.render(
                [package.css, package.editorCSS, package.manifest.controlGroupCSS]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n"),
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assets: assets),
                    templateValues: site.map { PartNavigationTemplateValues.values(site: $0, currentPage: page) } ?? [:],
                    slots: [:],
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    environment: .canvas,
                    loopMaximums: package.loopMaximums
                )
            )
            return PartTemplateRenderer.scopedCSS(
                css,
                packageIdentifier: package.manifest.identifier,
                instanceID: node.id
            )
        }.joined(separator: "\n")
        let htmlStyles = nodes.map {
            PartArtifactPlan.htmlArtifact(for: $0.resolved(at: breakpoint, screens: theme.screens), suffix: "CSS")
        }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return [instanceStyles, htmlStyles].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func subtreeTarget(
        partID: UUID,
        in nodes: [PartNode],
        inheritedGlobalDefinitionID: UUID? = nil,
        parentPartID: UUID? = nil,
        parentSlot: PartPackageSlot? = nil,
        parentDropZoneSlotID: String? = nil
    ) -> (
        node: PartNode,
        inheritedGlobalDefinitionID: UUID?,
        parentPartID: UUID?,
        parentSlot: PartPackageSlot?,
        parentDropZoneSlotID: String?
    )? {
        for node in nodes {
            if node.id == partID {
                return (
                    node,
                    inheritedGlobalDefinitionID,
                    parentPartID,
                    parentSlot,
                    parentDropZoneSlotID
                )
            }
            let globalDefinitionID = node.reusableDefinitionID ?? inheritedGlobalDefinitionID
            let package = node.type.definition.package
            for child in node.children {
                let slot = package.flatMap { package in
                    if let slotID = child.slotID {
                        return package.manifest.slots.first { $0.id == slotID }
                    }
                    return package.hasDropZone ? nil : package.manifest.slots.first
                }
                let dropZoneSlotID: String? = package.flatMap { package -> String? in
                    guard slot == nil else { return nil }
                    return package.dropZoneNames.enumerated().first { index, name in
                        let slotID = package.dropZoneSlotID(for: name)
                        return child.slotID == slotID || (index == 0 && child.slotID == nil)
                    }.map { package.dropZoneSlotID(for: $0.element) }
                }
                if let target = subtreeTarget(
                    partID: partID,
                    in: [child],
                    inheritedGlobalDefinitionID: globalDefinitionID,
                    parentPartID: node.id,
                    parentSlot: slot,
                    parentDropZoneSlotID: dropZoneSlotID
                ) {
                    return target
                }
            }
        }
        return nil
    }

    private func canvasAssetBasePath(for package: LoadedPartPackage) -> String {
        "\(CanvasAssetSchemeHandler.packageScheme)://\(package.manifest.identifier)"
    }

    private func canvasAssetPaths(for package: LoadedPartPackage) -> [String: String] {
        let basePath = canvasAssetBasePath(for: package)
        return Dictionary(uniqueKeysWithValues: package.manifest.assets.map { asset in
            (asset.path, basePath + "/" + asset.path)
        })
    }

    private func packageProperties(_ node: PartNode, theme: Theme, assets: ProjectAssetContents) -> [String: PartPackageValue] {
        var values: [String: PartPackageValue] = Dictionary(uniqueKeysWithValues: node.type.definition.properties.map { definition in
            let value = node.propertyValue(definition.key)
            if case .themeBorderWidth(let width) = value {
                return (definition.key.rawValue, PartPackageThemeBorderWidthControl.resolved(width, theme: theme))
            }
            if case .themeRadius(let radius) = value {
                return (definition.key.rawValue, PartPackageThemeRadiusControl.resolved(radius, theme: theme))
            }
            if case .themeMargin(let margin) = value {
                return (definition.key.rawValue, PartPackageThemeMarginControl.resolved(margin, theme: theme))
            }
            if case .themeSpacing(let spacing) = value {
                return (definition.key.rawValue, PartPackageSingleSpacingControl.resolved(spacing, theme: theme))
            }
            if case .themePadding(let padding) = value {
                return (definition.key.rawValue, PartPackageThemePaddingControl.resolved(padding, theme: theme))
            }
            if case .themeFont = definition.control {
                return (definition.key.rawValue, PartPackageFontControl.resolved(definition.key.rawValue, node: node, theme: theme))
            }
            if case .video = definition.control {
                // Preserve selection state for template conditions while keeping
                // the canvas video href empty below so WebKit never loads it.
                return (definition.key.rawValue, packageValue(value))
            }
            if case .url(let source) = value,
               case .image = definition.control {
                return (definition.key.rawValue, .string(canvasSource(source, assets: assets)))
            }
            if case .color = definition.control {
                return (definition.key.rawValue, .string(node.colorProperty(definition.key, theme: theme)))
            }
            if case .packageColor(_, let opacity, _, _) = definition.control,
               case .packageColor(let colorValue) = value {
                return (
                    definition.key.rawValue,
                    .string(PartPackageColorResolver.resolve(
                        colorValue, theme: theme,
                        opacity: opacity, appearance: appearance
                    ))
                )
            }
            if case .themeFontSize = definition.control {
                return (definition.key.rawValue, .string(theme.fontSizeCSSVariable(for: node.property(definition.key))))
            }
            if case .packageShadow = definition.control,
               case .packageShadow(let shadowValue) = value {
                return (
                    definition.key.rawValue,
                    .string(PartPackageShadowResolver.resolve(shadowValue, theme: theme))
                )
            }
            if case .number = definition.control {
                return (definition.key.rawValue, .number(node.numberProperty(definition.key, theme: theme)))
            }
            return (definition.key.rawValue, packageValue(value))
        })
        for definition in node.type.definition.properties {
            if definition.control.isThemeSpacing,
               case .object(let fields) = values[definition.key.rawValue] {
                for (field, value) in fields {
                    let key = definition.key.rawValue + "." + field
                    values[key] = value
                    if case .object(let edges) = value {
                        for (edge, resolved) in edges { values[key + "." + edge] = resolved }
                    }
                }
                // Direct interpolation is the shorthand; qualified fields remain available above.
                values[definition.key.rawValue] = fields["css"]
            }
            if case .themeFont = definition.control,
               case .object(let fields) = values[definition.key.rawValue] {
                for (field, value) in fields { values[definition.key.rawValue + "." + field] = value }
            }
            if case .packageColor(_, let opacity, _, _) = definition.control,
               case .packageColor(let colorValue) = node.propertyValue(definition.key) {
                // The canvas renders one appearance at a time, so unqualified
                // colour outputs resolve concretely for whichever is on screen.
                let light = PartPackageColorResolver.channels(colorValue, theme: theme, opacity: opacity, appearance: .light)
                let dark = PartPackageColorResolver.channels(colorValue, theme: theme, opacity: opacity, appearance: .dark)
                PartPackageDerivedValueResolver.addThemeColorValues(
                    for: definition.key.rawValue,
                    light: light,
                    dark: dark,
                    primary: appearance,
                    combinesAppearances: false,
                    includesOpacity: opacity,
                    to: &values
                )
                if let format = node.type.definition.package?.manifest.resolvedProperties
                    .first(where: { $0.id == definition.key.rawValue })?.control.outputFormat,
                   let current = appearance == .light ? light : dark {
                    values[definition.key.rawValue] = .string(current.formatted(as: format, includesOpacity: opacity))
                }
            }
        }
        if let package = node.type.definition.package {
            for property in package.manifest.resolvedProperties where property.control.type == .image {
                let key = PartProperty.Key(rawValue: property.id)
                guard case .url(let source) = node.propertyValue(key) else { continue }
                let metadata = source.foundryAssetID.flatMap { assets.asset($0)?.imageMetadata }
                    ?? package.imageMetadata[source]
                let focalPoint = PartImageTemplateValues.focalPoint(
                    from: node.propertyValue(PartPackageAdapter.imageFocalPointKey(for: property.id))
                )
                PartImageTemplateValues.insert(
                    propertyID: property.id,
                    href: values[property.id]?.stringValue ?? "",
                    alt: node.property(PartPackageAdapter.imageAltKey(for: property.id)),
                    focalPointX: focalPoint.x,
                    focalPointY: focalPoint.y,
                    metadata: metadata,
                    into: &values
                )
                for rendition in property.renditions {
                    let key = property.id + ".rendition." + rendition.id
                    let href = values[property.id]?.stringValue ?? ""
                    values[key] = .string(href)
                    values[key + ".href"] = .string(href)
                }
            }
            for property in package.manifest.resolvedProperties where property.control.type == .video {
                let key = PartProperty.Key(rawValue: property.id)
                guard case .url(let source) = node.propertyValue(key) else { continue }
                let asset = source.foundryAssetID.flatMap { assets.asset($0) }
                let customPoster = node.property(
                    PartVideoTemplateValues.posterPropertyKey(for: property.id)
                )
                PartVideoTemplateValues.insert(
                    propertyID: property.id,
                    href: "",
                    poster: customPoster.isEmpty
                        ? asset?.videoMetadata?.posterDataURL ?? ""
                        : canvasSource(customPoster, assets: assets),
                    asset: asset,
                    playback: PartVideoTemplateValues.playbackOptions(propertyID: property.id, node: node),
                    enablesEditorMarkup: true,
                    into: &values
                )
            }
        }
        if let site {
            for definition in node.type.definition.properties {
                guard case .link(let absoluteURL) = definition.control,
                      case .link(let link) = node.propertyValue(definition.key) else { continue }
                let resolved = PartLinkResolver.resolve(
                    link, pages: site.pages, folders: site.pageFolders, assets: site.assets,
                    publicURL: site.publicURL, absoluteURL: absoluteURL
                )
                values[definition.key.rawValue] = .string(resolved.href)
                values[definition.key.rawValue + ".target"] = .string(resolved.target)
                values[definition.key.rawValue + ".attributes"] = .string(resolved.attributes)
            }
        }
        return PartPackageDerivedValueResolver.resolve(
            values,
            properties: node.type.definition.package?.manifest.resolvedProperties ?? []
        )
    }

    private func flattened(_ node: PartNode) -> [PartNode] {
        [node] + node.children.flatMap(flattened)
    }

    private func packageValue(_ value: PartProperty.Value) -> PartPackageValue {
        switch value {
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .string(let value), .url(let value), .color(let value), .choice(let value): .string(value)
        case .token(let value): .string(value.rawValue)
        case .array(let values): .array(values.map(packageValue))
        case .link: .string("")
        case .packageColor(let value): .string(value.source)
        case .packageFontSize(let value): .string(value.source)
        case .packageShadow(let value): .string(value.source)
        case .themeSpacing, .themePadding, .themeMargin, .themeBorderWidth, .themeRadius: .string("")
        }
    }

    private func unavailablePart(_ node: PartNode, page: Page, theme: Theme, assets: ProjectAssetContents, globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint, parentPartID: UUID?) -> String {
        let children = node.children.map { render($0, page: page, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: node.id) }.joined()
        let name = node.missingPackageSnapshot?.name ?? node.type.rawValue
        return "<div class=\"unavailable\" \(attributes(for: node, globalDefinitionID: globalDefinitionID, parentPartID: parentPartID))>Missing part: \(escape(name))\(children)</div>"
    }

    private func failedPart(_ node: PartNode, page: Page, package: LoadedPartPackage, theme: Theme, assets: ProjectAssetContents, globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint, parentPartID: UUID?) -> String {
        let children = node.children.map { render($0, page: page, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: node.id) }.joined()
        return "<div class=\"unavailable\" \(attributes(for: node, globalDefinitionID: globalDefinitionID, parentPartID: parentPartID))>Part files could not be loaded: \(escape(package.manifest.name))\(children)</div>"
    }

    private var rootDropZone: String {
        "<div class=\"foundry-empty-drop-zone foundry-empty-page\" data-foundry-root-drop-zone>Drop part here</div>"
    }

    private func canvasSource(_ source: String, assets: ProjectAssetContents) -> String {
        guard let id = source.foundryAssetID else { return source }
        return assets.hasContent(id) ? source : ""
    }

    private func attributes(for node: PartNode, globalDefinitionID: UUID?, parentPartID: UUID?, parentSlot: PartPackageSlot? = nil, parentDropZoneSlotID: String? = nil) -> String {
        let definition = node.type.definition
        let acceptsChildren = definition.allowsChildren ? "true" : "false"
        let manifest = definition.package?.manifest
        let author = manifest?.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution = author?.isEmpty == false ? author! : "Foundry"
        let version = manifest?.version ?? ""
        let globalAttributes = globalDefinitionID.map {
            " data-foundry-global=\"\($0.uuidString)\" data-foundry-global-override=\"\(node.overridesGlobalDefinition == true)\""
        } ?? ""
        let parentAttribute = parentPartID.map { " data-foundry-parent=\"\($0.uuidString)\"" } ?? ""
        let slotAttributes = parentSlot.map {
            " data-foundry-slot=\"\(escapeAttribute($0.id))\" data-foundry-slot-containment=\"\($0.containment.rawValue)\""
        } ?? parentDropZoneSlotID.map {
            " data-foundry-slot=\"\(escapeAttribute($0))\" data-foundry-slot-containment=\"open\""
        } ?? ""
        let anchorAttribute = validAnchor(for: node).map { " id=\"\(escapeAttribute($0))\"" } ?? ""
        let userFacingName = node.reusableDefinitionID.flatMap { definitionID in
            site?.globalParts.first(where: { $0.id == definitionID })?.name
        } ?? node.name
        return "data-foundry-id=\"\(node.id.uuidString)\" data-foundry-part data-foundry-package=\"\(escapeAttribute(node.type.rawValue))\"\(parentAttribute)\(slotAttributes)\(anchorAttribute)\(customAttributes(for: node)) data-foundry-part-type=\"\(escapeAttribute(node.type.rawValue))\" data-foundry-type=\"\(escapeAttribute(node.type.displayName))\" data-foundry-name=\"\(escapeAttribute(userFacingName))\" data-foundry-author=\"\(escapeAttribute(attribution))\" data-foundry-version=\"\(escapeAttribute(version))\" data-foundry-accepts-children=\"\(acceptsChildren)\"\(globalAttributes)"
    }

    private func validAnchor(for node: PartNode) -> String? {
        PartAnchorValidator.validated(node.anchor)
    }

    private func customAttributes(for node: PartNode) -> String {
        PartRootAttributeValidator.validAttributes(node.rootAttributes ?? []).map {
            " \($0.name)=\"\(escapeAttribute($0.value))\""
        }.joined()
    }

    private func partClass(_ node: PartNode) -> String {
        ["c-" + node.id.uuidString.lowercased(), PartRootAttributeValidator.normalizedClasses(node.customClasses)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
