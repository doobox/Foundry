import Foundation

nonisolated struct HTMLPageRenderer: PageRendering {
    let site: Site?
    let appearance: SiteAppearance
    private let templateValuesCache = PartTemplateValuesCache()
    private let artifactCache: CanvasRenderCache?
    private let packageRevision: Int
    private var cacheSession: CanvasRenderCache.Session?
    private var shellRootID: UUID?
    private var sceneArtifacts: [UUID: CanvasSceneArtifact]?

    init(site: Site? = nil, appearance: SiteAppearance = .light, artifactCache: CanvasRenderCache? = nil, packageRevision: Int = 0) {
        self.site = site
        self.appearance = appearance
        self.artifactCache = artifactCache
        self.packageRevision = packageRevision
    }

    private func prepared(page: Page, framework: Framework, assets: ProjectAssetContents, breakpoint: ResponsiveBreakpoint) -> Self {
        var copy = self
        copy.cacheSession = artifactCache?.session(environment: .init(site: site, page: page, framework: framework,
            assets: assets, breakpoint: breakpoint, appearance: appearance, packageRevision: packageRevision),
            liveIDs: Set(page.parts.flatMap(flattened).map(\.id)))
        return copy
    }

    /// A renderer whose shell renders share one cache session. Instance CSS and
    /// resolved properties are keyed on a part's own values, so a part keeps
    /// them when only the tree around it changed — which is exactly what an
    /// insertion does to the parent it lands in.
    func preparedForShells(environment: CanvasRenderCache.Environment, liveIDs: Set<UUID>) -> Self {
        guard let artifactCache else { return self }
        var copy = self
        copy.cacheSession = artifactCache.session(environment: environment, liveIDs: liveIDs)
        return copy
    }

    private func cachedText(_ kind: CanvasRenderCache.Kind, key: CanvasRenderCache.Key, compute: () -> String) -> String {
        guard let cacheSession else { return compute() }
        if case .text(let text) = cacheSession.value(kind, key: key, compute: { .text(compute()) }) { return text }
        return compute()
    }

    private func ownValues(_ node: PartNode) -> PartNode {
        var own = node
        own.children = []
        return own
    }
    func render(page: Page, framework: Framework) -> String {
        render(page: page, language: "en", framework: framework, assets: [:], breakpoint: .extraLarge)
    }

    func render(page: Page, language: String, framework: Framework, assets: ProjectAssetContents, breakpoint: ResponsiveBreakpoint) -> String {
        guard !Task.isCancelled else { return "" }
        if artifactCache != nil, cacheSession == nil {
            return prepared(page: page, framework: framework, assets: assets, breakpoint: breakpoint)
                .render(page: page, language: language, framework: framework, assets: assets, breakpoint: breakpoint)
        }
        let body = page.parts.isEmpty
            ? rootDropZone
            : page.parts.map { render($0, page: page, framework: framework, assets: assets, globalDefinitionID: $0.reusableDefinitionID, breakpoint: breakpoint) }.joined(separator: "\n")
        let pageTitle = page.metadata.browserTitle.isEmpty ? page.title : page.metadata.browserTitle
        let browserTitle = pageTitle + (site?.titleSuffix ?? "")
        let metadata = metadataHTML(for: page, browserTitle: browserTitle, site: site, assets: assets)
        let headStart = placedHTML(for: page, framework: framework, placement: .headStart)
        let headEnd = placedHTML(for: page, framework: framework, placement: .headEnd)
        let bodyStart = placedHTML(for: page, framework: framework, placement: .bodyStart)
        let bodyEnd = placedHTML(for: page, framework: framework, placement: .bodyEnd)
        let customHeadCode = site?.customCodeEnabled == true ? site?.headCode ?? "" : ""
        let customBodyStartCode = site?.customCodeEnabled == true ? site?.bodyStartCode ?? "" : ""
        let customBodyEndCode = site?.customCodeEnabled == true ? site?.bodyEndCode ?? "" : ""
        let analyticsCode = site?.customCodeEnabled == true ? site?.analyticsCode ?? "" : ""
        let documentLanguage = (page.language ?? language).trimmingCharacters(in: .whitespacesAndNewlines)
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
            \(framework.fontSourceCSS(assets: assets, destination: .canvas))
          </style>
          <style>
            :root {
              --foundry-editor-part: #007BFF;
              --foundry-editor-global: #30D158;
              --foundry-editor-primitive: #007BFF;
            }
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
              position: relative;
              overflow: hidden;

              display: grid;
              place-items: center;
              box-sizing: border-box;

              width: 100%;
              align-self: stretch;
              justify-self: stretch;
              min-height: 64px;
              padding: 16px;

              background: #e9e9e9;
              border: 1px solid #cdcdcd !important;
              border-radius: 4px;

              font: 400 12px system-ui;
              text-align: center;
            }

            .foundry-drop-label {
              color: #898989;
            }
            .foundry-drop-label svg { display: block; }
            .foundry-empty-page { min-height: 100vh; }
            .foundry-contentless-drop-zone { min-height: 32px; padding: 6px 12px; }
            [data-foundry-global].foundry-editing { outline-color: var(--foundry-editor-chrome) !important; }
            body { background: \(page.backgroundColour(framework: framework, appearance: appearance)); }
            .foundry-image-drop-zone, .foundry-video-drop-zone {
              /* The zone span inherits the replaced media element's own
                 classes so part CSS keeps positioning it — which means part
                 rules like .fd-image { display: block } can reach it. The
                 centring is chrome and must win. */
              position: relative; overflow: hidden;
              display: grid !important; place-items: center !important;
              box-sizing: border-box;
              width: 100%; min-height: 64px; padding: 16px;
              background: #e9e9e9;
              border: 1px solid #cdcdcd !important;
              border-radius: 4px;
              font: 400 12px system-ui; text-align: center;
            }
            .unavailable { padding: 16px; border: 2px dashed #C33; color: #922; background: #FFF5F5; }
            \(FoundryWebLibraryRegistry.canvasCSS(for: PartArtifactPlan(page: page).packages))
          </style>
          <style data-foundry-framework-styles>
            \(BootstrapThemeCSS.render(framework: framework))
            \(BootstrapColorCSS.canvas(framework: framework, appearance: appearance))
          </style>
        \(instanceStyleElements(for: page, framework: framework, assets: assets, breakpoint: breakpoint))
          <style data-foundry-shared-styles>
            \(packageStyles(for: page, framework: framework, assets: assets, breakpoint: breakpoint))
          </style>
        \(analyticsCode)
        \(headEnd)
        </head>
        <body>\(customBodyStartCode)\(bodyStart)<!--foundry-roots-start-->\(body)<!--foundry-roots-end-->\(bodyEnd)\(customBodyEndCode)</body>
        </html>
        """
    }

    func renderSubtree(
        partID: UUID,
        page: Page,
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedPartSubtree? {
        guard !Task.isCancelled else { return nil }
        if artifactCache != nil, cacheSession == nil {
            return prepared(page: page, framework: framework, assets: assets, breakpoint: breakpoint)
                .renderSubtree(partID: partID, page: page, framework: framework, assets: assets, breakpoint: breakpoint)
        }
        guard let target = subtreeTarget(partID: partID, in: page.parts) else { return nil }
        return RenderedPartSubtree(
            partID: partID,
            html: render(
                target.node,
                page: page,
                framework: framework,
                assets: assets,
                globalDefinitionID: target.inheritedGlobalDefinitionID,
                breakpoint: breakpoint,
                parentPartID: target.parentPartID,
                parentSlot: target.parentSlot,
                parentDropZoneSlotID: target.parentDropZoneSlotID
            ),
            instanceStyles: Dictionary(
                instanceStyles(
                    for: flattened(target.node),
                    page: page,
                    framework: framework,
                    assets: assets,
                    breakpoint: breakpoint
                ).map { ($0.partID.uuidString, $0.css) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    private func placedHTML(for page: Page, framework: Framework, placement: PartPackageTemplateFile.Placement) -> String {
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
                templateValues: templateValues(for: page, framework: framework),
                slots: [:],
                assetBasePath: canvasAssetBasePath(for: package),
                assetPaths: canvasAssetPaths(for: package),
                environment: .canvas,
                loopMaximums: package.loopMaximums
            )
            return templates.map { PartTemplateRenderer.render($0.contents, context: context) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func templateValues(for page: Page, framework: Framework) -> [String: PartPackageValue] {
        templateValuesCache.values(for: page.id) {
            let breakpointValues = PartBreakpointTemplateValues.values(screens: framework.screens)
            guard let site else { return breakpointValues }
            return PartNavigationTemplateValues.values(site: site, currentPage: page)
                .merging(breakpointValues) { current, _ in current }
        }
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
        baseURL + StaticSiteRenderer.urlPath(for: page, pages: site.pages, folders: site.pageFolders)
    }

    private func render(_ sourceNode: PartNode, page: Page, framework: Framework, assets: ProjectAssetContents, globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint, parentPartID: UUID? = nil, parentSlot: PartPackageSlot? = nil, parentDropZoneSlotID: String? = nil) -> String {
        guard !Task.isCancelled else { return "" }
        if var html = sceneArtifacts?[sourceNode.id]?.html {
            for child in sourceNode.children {
                let marker = "<!--foundry-child:\(child.id.uuidString)-->"
                if html.contains(marker) {
                    html = html.replacingOccurrences(of: marker, with: render(child, page: page,
                        framework: framework, assets: assets, globalDefinitionID: nil, breakpoint: breakpoint))
                }
            }
            return html
        }
        if let shellRootID, sourceNode.id != shellRootID {
            return "<!--foundry-child:\(sourceNode.id.uuidString)-->"
        }
        return cachedText(.html, key: .init(node: sourceNode, globalID: globalDefinitionID, parentID: parentPartID, slot: parentSlot, dropZone: parentDropZoneSlotID)) {
            renderUncached(sourceNode, page: page, framework: framework, assets: assets, globalDefinitionID: globalDefinitionID,
                breakpoint: breakpoint, parentPartID: parentPartID, parentSlot: parentSlot, parentDropZoneSlotID: parentDropZoneSlotID)
        }
    }

    /// Renders one instance only. Child content is represented by stable identities,
    /// never copied into the parent's artifact. Published rendering is unchanged.
    func renderShell(_ input: CanvasSceneInput, page: Page, framework: Framework,
                     assets: ProjectAssetContents) -> CanvasSceneArtifact {
        var renderer = self
        renderer.shellRootID = input.node.id
        let html = renderer.render(input.node, page: page, framework: framework, assets: assets,
            globalDefinitionID: input.globalID, breakpoint: .mobile, parentPartID: input.parentID,
            parentSlot: input.slot, parentDropZoneSlotID: input.dropZone)
        let css = renderer.instanceStyles(for: [input.node], page: page, framework: framework,
            assets: assets, breakpoint: .mobile).first?.css ?? ""
        return .init(html: html, css: css)
    }

    func renderSceneDocument(artifacts: [UUID: CanvasSceneArtifact], page: Page, language: String,
                             framework: Framework, assets: ProjectAssetContents,
                             breakpoint: ResponsiveBreakpoint) -> String {
        var renderer = self
        renderer.sceneArtifacts = artifacts
        return renderer.render(page: page, language: language, framework: framework,
                               assets: assets, breakpoint: breakpoint)
    }

    private func renderUncached(_ sourceNode: PartNode, page: Page, framework: Framework, assets: ProjectAssetContents, globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint, parentPartID: UUID?, parentSlot: PartPackageSlot?, parentDropZoneSlotID: String?) -> String {
        let node = sourceNode.resolved(at: breakpoint, screens: framework.screens)
        let globalDefinitionID = node.reusableDefinitionID ?? globalDefinitionID
        switch node.type.definition.renderKind {
        case .package:
            guard let package = node.type.definition.package else {
                return unavailablePart(node, page: page, framework: framework, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: parentPartID)
            }
            do {
                try package.preparePayload()
            } catch {
                return failedPart(node, page: page, package: package, framework: framework, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: parentPartID)
            }
            let slots = Dictionary(uniqueKeysWithValues: package.renderDefinition.slots.map { slot in
                let children = node.children.filter {
                    ($0.slotID ?? (package.hasDropZone ? nil : package.renderDefinition.slots.first?.id)) == slot.id
                }
                let html = children.map {
                    render($0, page: page, framework: framework, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: node.id, parentSlot: slot)
                }.joined()
                return (slot.id, html.isEmpty ? "<div class=\"foundry-empty-drop-zone\" data-foundry-empty-parent=\"\(node.id.uuidString)\" data-foundry-slot-id=\"\(escapeAttribute(slot.id))\"><span class=\"foundry-drop-label\">\(FoundryDropZoneGlyphs.part)</span></div>" : html)
            })
            let dropZones = Dictionary(uniqueKeysWithValues: package.dropZoneNames.enumerated().map { index, name in
                let slotID = package.dropZoneSlotID(for: name)
                let children = node.children.filter { $0.slotID == slotID || (index == 0 && $0.slotID == nil) }
                let html = children.map {
                    render($0, page: page, framework: framework, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: node.id, parentDropZoneSlotID: slotID)
                }.joined()
                let output = html.isEmpty
                    ? "<div class=\"foundry-empty-drop-zone\" data-foundry-empty-parent=\"\(node.id.uuidString)\" data-foundry-slot-id=\"\(escapeAttribute(slotID))\"><span class=\"foundry-drop-label\">\(FoundryDropZoneGlyphs.part)</span></div>"
                    : html
                return (name, output)
            })
            let adjacentDropAttribute = !package.hasDropZone && package.renderDefinition.slots.isEmpty
                ? " data-foundry-adjacent-target=\"\(node.id.uuidString)\""
                : ""
            let defaultSlotID = package.dropZoneNames.first.map(package.dropZoneSlotID(for:))
                ?? package.renderDefinition.slots.first?.id
            let canvasAttributes = attributes(for: node, globalDefinitionID: globalDefinitionID, parentPartID: parentPartID, parentSlot: parentSlot, parentDropZoneSlotID: parentDropZoneSlotID) +
                (defaultSlotID.map { " data-foundry-default-slot=\"\(escapeAttribute($0))\"" } ?? "") +
                adjacentDropAttribute
            let renderedProperties = packageProperties(node, framework: framework, assets: assets, breakpoint: breakpoint)
            let templateContext = PartTemplateContext(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: renderedProperties,
                    templateValues: templateValues(for: page, framework: framework),
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
                    richTextColourContext: .init(
                        palettes: framework.colourPalettes,
                        mode: appearance == .light ? .light : .dark
                    ),
                    loopMaximums: package.loopMaximums
                )
            let rendered = PartTemplateRenderer.render(package.htmlTemplate, context: templateContext)
            let decorated = PartPackageHTMLContributionRenderer.decorate(
                rendered,
                contributions: package.renderDefinition.htmlContributions,
                context: templateContext
            )
            if package.htmlTemplate.contains("{{ part.attributes }}") ||
                package.htmlTemplate.contains("{{part.attributes}}") {
                return decorated
            }
            return "<div \(canvasAttributes)>\(decorated)</div>"
        case .unavailable:
            return unavailablePart(node, page: page, framework: framework, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: parentPartID)
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
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> String {
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
                    templateValues: templateValues(for: page, framework: framework),
                    slots: [:],
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    environment: .canvas,
                    loopMaximums: package.loopMaximums
                )
            )
        }.joined(separator: "\n")
        return pageStyles
    }

    /// One `<style>` per part instance, keyed by part ID. Subtree patches
    /// replace these elements by key, so a declaration a part no longer emits
    /// disappears — bundling them into the shared sheet would leave the
    /// original rules in place for a patch to fight with.
    private func instanceStyleElements(
        for page: Page,
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> String {
        instanceStyles(
            for: page.parts.flatMap(flattened),
            page: page,
            framework: framework,
            assets: assets,
            breakpoint: breakpoint
        ).map { instance in
            """
              <style data-foundry-instance-style="\(instance.partID.uuidString)">
                \(instance.css)
              </style>
            """
        }.joined(separator: "\n")
    }

    /// One scoped stylesheet per part instance. The patch path stores each
    /// under its own `<style>` element in the canvas: a patched parent must
    /// never leave a trailing copy of a descendant's rules that would shadow
    /// the descendant's own later patches.
    private func instanceStyles(
        for nodes: [PartNode],
        page: Page,
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> [(partID: UUID, css: String)] {
        nodes.compactMap { sourceNode in
            guard !Task.isCancelled else { return nil }
            if let artifact = sceneArtifacts?[sourceNode.id] {
                return artifact.css.isEmpty ? nil : (sourceNode.id, artifact.css)
            }
            let node = sourceNode.resolved(at: breakpoint, screens: framework.screens)
            let text = cachedText(.css, key: .init(node: ownValues(node))) {
            var pieces: [String] = [BootstrapPartUtilityCSS.render(node: node, framework: framework)]
            if sourceNode.type.definition.package?.manifest.controlGroups.contains(where: { $0.type == .background }) == true {
                pieces.append(PartPackageBackgroundResolver.stylesheet(packageProperties(sourceNode, framework: framework, assets: assets, breakpoint: .mobile)))
                for level in ResponsiveBreakpoint.allCases.dropFirst() {
                    guard let width = level.minimumWidth(in: framework.screens),
                          sourceNode.responsiveOverrides?.contains(where: { $0.breakpoint == level }) == true else { continue }
                    let resolved = sourceNode.resolved(at: level, screens: framework.screens)
                    let css = PartPackageBackgroundResolver.stylesheet(packageProperties(resolved, framework: framework, assets: assets, breakpoint: level))
                    if !css.isEmpty { pieces.append("@media(min-width:\(width)px){\(css)}") }
                }
            }
            if let package = node.type.definition.package {
                let css = PartTemplateRenderer.render(
                    [package.css, package.editorCSS, package.renderDefinition.controlGroupCSS]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n"),
                    context: .init(
                        instanceID: node.id,
                        packageIdentifier: package.manifest.identifier,
                        properties: packageProperties(node, framework: framework, assets: assets, breakpoint: breakpoint),
                        templateValues: templateValues(for: page, framework: framework),
                        slots: [:],
                        assetBasePath: canvasAssetBasePath(for: package),
                        assetPaths: canvasAssetPaths(for: package),
                        environment: .canvas,
                        loopMaximums: package.loopMaximums
                    )
                )
                let scoped = PartTemplateRenderer.scopedCSS(
                    css,
                    packageIdentifier: package.manifest.identifier,
                    instanceID: node.id
                )
                if !scoped.isEmpty { pieces.append(scoped) }
            }
            let artifact = PartArtifactPlan.htmlArtifact(for: node, suffix: "CSS")
            if !artifact.isEmpty { pieces.append(artifact) }
            let custom = PartTemplateRenderer.scopedCustomCSS(node.customCSS, instanceID: node.id)
            if !custom.isEmpty { pieces.append(custom) }
            return pieces.joined(separator: "\n")
            }
            return text.isEmpty ? nil : (sourceNode.id, text)
        }
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
                        return package.renderDefinition.slots.first { $0.id == slotID }
                    }
                    return package.hasDropZone ? nil : package.renderDefinition.slots.first
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

    private func packageProperties(_ node: PartNode, framework: Framework, assets: ProjectAssetContents, breakpoint: ResponsiveBreakpoint) -> [String: PartPackageValue] {
        if node.type.definition.properties.contains(where: { $0.control.isCollection }) {
            return uncachedPackageProperties(node, framework: framework, assets: assets, breakpoint: breakpoint)
        }
        guard let cacheSession else { return uncachedPackageProperties(node, framework: framework, assets: assets) }
        if case .properties(let values) = cacheSession.value(.properties, key: .init(node: ownValues(node)), compute: {
            .properties(uncachedPackageProperties(node, framework: framework, assets: assets))
        }) { return values }
        return uncachedPackageProperties(node, framework: framework, assets: assets)
    }

    private func uncachedPackageProperties(_ node: PartNode, framework: Framework, assets: ProjectAssetContents, breakpoint: ResponsiveBreakpoint = .mobile) -> [String: PartPackageValue] {
        // One definition fetch, one stored-value index and one manifest
        // property expansion for the whole pass; repeating any of them per
        // key dominates page-render profiles.
        let partDefinition = node.type.definition
        let definitions = partDefinition.properties
        let manifestProperties = partDefinition.package?.renderDefinition.properties ?? []
        let manifestPropertiesByID = partDefinition.package?.renderDefinition.propertiesByID ?? [:]
        var values: [String: PartPackageValue] = Dictionary(uniqueKeysWithValues: definitions.map { definition in
            let value = node.storedPropertyValue(definition.key) ?? definition.defaultValue
            if let classes = BootstrapControlGroupClasses.resolve(node: node, key: definition.key, framework: framework) {
                return (definition.key.rawValue, .string(classes))
            }
            if case .frameworkBorderWidth(let width) = value {
                return (definition.key.rawValue, PartPackageFrameworkBorderWidthControl.resolved(width, framework: framework))
            }
            if case .frameworkRadius(let radius) = value {
                return (definition.key.rawValue, PartPackageFrameworkRadiusControl.resolved(radius, framework: framework))
            }
            if case .frameworkMargin(let margin) = value {
                return (definition.key.rawValue, PartPackageFrameworkMarginControl.resolved(margin, framework: framework))
            }
            if case .frameworkSpacing(let spacing) = value {
                return (definition.key.rawValue, PartPackageSingleSpacingControl.resolved(
                    spacing,
                    framework: framework,
                    noneValue: manifestPropertiesByID[definition.key.rawValue]?.noneValue
                ))
            }
            if case .frameworkPadding(let padding) = value {
                return (definition.key.rawValue, PartPackageFrameworkPaddingControl.resolved(padding, framework: framework))
            }
            if case .frameworkFont = definition.control {
                return (definition.key.rawValue, PartPackageFontControl.resolved(definition.key.rawValue, node: node, framework: framework))
            }
            if case .collection(_, let fields) = definition.control {
                let records = value.arrayValue ?? []
                return (
                    definition.key.rawValue,
                    .array(records.map { record in
                        PartCollectionRenderResolver.resolve(
                            record,
                            fields: fields,
                            breakpoint: breakpoint,
                            framework: framework,
                            source: { source, control in
                                if case .video = control { return YouTubeVideo.id(from: source) == nil ? "" : source }
                                return canvasSource(source, assets: assets)
                            },
                            link: { destination, absoluteURL in
                                site.map {
                                    PartLinkResolver.resolve(
                                        destination,
                                        pages: $0.pages,
                                        folders: $0.pageFolders,
                                        assets: $0.assets,
                                        publicURL: $0.publicURL,
                                        absoluteURL: absoluteURL
                                    )
                                }
                            },
                            packageColor: { color, opacity in
                                PartPackageColorResolver.resolve(
                                    color,
                                    framework: framework,
                                    opacity: opacity,
                                    appearance: appearance
                                )
                            }
                        )
                    })
                )
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
                return (definition.key.rawValue, .string(node.colorProperty(definition.key, framework: framework)))
            }
            if case .packageColor(_, let opacity, _, _) = definition.control,
               case .packageColor(let colorValue) = value {
                return (
                    definition.key.rawValue,
                    .string(PartPackageColorResolver.resolve(
                        colorValue, framework: framework,
                        opacity: opacity, appearance: appearance
                    ))
                )
            }
            if case .themeColor = definition.control {
                return (definition.key.rawValue, .string(BootstrapPaletteTheme.resolve(node.property(definition.key), framework: framework)))
            }
            if node.type == .container && definition.key.rawValue == "width" {
                return (definition.key.rawValue, .string(BootstrapLayout.containerClass(node.property(definition.key), screens: framework.screens)))
            }
            if case .frameworkFontSize = definition.control {

                return (definition.key.rawValue, .string(framework.fontSizeCSSVariable(for: node.property(definition.key))))
            }
            if case .frameworkStackingOrder = definition.control {
                if case .packageStackingOrder(let selected) = value, selected.isCustom {
                    return (definition.key.rawValue, .string(String(Int(selected.customValue))))
                }
                return (definition.key.rawValue, .string(framework.zIndexCSSVariable(for: node.property(definition.key))))
            }
            if case .packageShadow = definition.control,
               case .packageShadow(let shadowValue) = value {
                if manifestPropertiesByID[definition.key.rawValue]?.controlGroupSource?.type == .filters {
                    return (definition.key.rawValue, .string(PartPackageShadowResolver.filter(shadowValue, framework: framework)))
                }
                return (
                    definition.key.rawValue,
                    .string(PartPackageShadowResolver.resolve(shadowValue, framework: framework))
                )
            }
            if case .number = definition.control {
                return (definition.key.rawValue, .number(node.numberProperty(definition.key, framework: framework)))
            }
            return (definition.key.rawValue, packageValue(value))
        })
        for definition in definitions {
            if case .collection(let itemLabel, _) = definition.control {
                values["__foundry_collection_label." + definition.key.rawValue] = .string(itemLabel)
            }
        }
        for definition in definitions {
            if definition.control.isFrameworkSpacing,
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
            if case .frameworkFont = definition.control,
               case .object(let fields) = values[definition.key.rawValue] {
                for (field, value) in fields { values[definition.key.rawValue + "." + field] = value }
            }
            if case .frameworkFontSize = definition.control {
                // The size's paired leading travels with it in the framework.
                values[definition.key.rawValue + ".lineHeight"] = .string(
                    framework.lineHeightCSSVariable(for: node.property(definition.key))
                )
            }
            if case .packageColor(_, let opacity, _, _) = definition.control,
               case .packageColor(let colorValue) = node.propertyValue(definition.key) {
                // The canvas renders one appearance at a time, so unqualified
                // colour outputs resolve concretely for whichever is on screen.
                let light = PartPackageColorResolver.channels(colorValue, framework: framework, opacity: opacity, appearance: .light)
                let dark = PartPackageColorResolver.channels(colorValue, framework: framework, opacity: opacity, appearance: .dark)
                PartPackageDerivedValueResolver.addFrameworkColorValues(
                    for: definition.key.rawValue,
                    light: light,
                    dark: dark,
                    primary: appearance,
                    combinesAppearances: false,
                    includesOpacity: opacity,
                    to: &values
                )
                if let format = manifestPropertiesByID[definition.key.rawValue]?.control.outputFormat,
                   let current = appearance == .light ? light : dark {
                    values[definition.key.rawValue] = .string(current.formatted(as: format, includesOpacity: opacity))
                }
            }
        }
        if let package = partDefinition.package {
            PartSVGRenderer.insert(node: node, package: package, assets: assets, canvas: true, into: &values)
            for property in manifestProperties where property.control.type == .image {
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
                    // The canvas shows the full-size image, but reports the
                    // rendition's size so `srcset` descriptors match export.
                    PartImageTemplateValues.insertRendition(
                        propertyID: property.id,
                        renditionID: rendition.id,
                        href: values[property.id]?.stringValue ?? "",
                        maximumDimension: rendition.effectiveMaximumDimension,
                        metadata: metadata,
                        into: &values
                    )
                }
            }
            for property in manifestProperties where property.control.type == .video {
                let key = PartProperty.Key(rawValue: property.id)
                guard case .url(let source) = node.propertyValue(key) else { continue }
                let asset = source.foundryAssetID.flatMap { assets.asset($0) }
                let customPoster = node.property(
                    PartVideoTemplateValues.posterPropertyKey(for: property.id)
                )
                PartVideoTemplateValues.insert(
                    propertyID: property.id,
                    href: YouTubeVideo.id(from: source) == nil ? "" : source,
                    poster: property.usesAutomaticVideoPoster || customPoster.isEmpty
                        ? asset?.videoMetadata?.posterDataURL ?? ""
                        : canvasSource(customPoster, assets: assets),
                    asset: asset,
                    playback: PartVideoTemplateValues.playbackOptions(propertyID: property.id, node: node),
                    into: &values
                )
            }
            // Implicit video primitives have no manifest property, so the
            // canvas poster frame is supplied directly from asset metadata.
            let manifestVideoIDs = Set(
                manifestProperties.filter { $0.control.type == .video }.map(\.id)
            )
            for definition in definitions {
                guard case .video = definition.control,
                      !manifestVideoIDs.contains(definition.key.rawValue),
                      case .url(let source) = node.propertyValue(definition.key) else { continue }
                let asset = source.foundryAssetID.flatMap { assets.asset($0) }
                values[definition.key.rawValue + ".poster"] = .string(
                    asset?.videoMetadata?.posterDataURL ?? ""
                )
            }
        }
        if let site {
            for definition in definitions {
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
        PartPackageBackgroundResolver.resolve(
            &values,
            properties: manifestProperties,
            enablesEditorMarkup: true,
            instanceID: node.id
        )
        PartPackageControlGroupCSSResolver.resolve(&values, properties: manifestProperties)
        let resolved = PartPackageDerivedValueResolver.resolve(
            values,
            properties: manifestProperties
        )
        guard partDefinition.package != nil else {
            return resolved
        }
        return PartPackageVisibilityEvaluator.availableTemplateValues(
            resolved,
            properties: manifestProperties,
            for: node,
            screens: framework.screens
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
        case .object(let values): .object(values.mapValues(packageValue))
        case .link: .string("")
        case .packageColor(let value): .string(value.source)
        case .packageFontSize(let value): .string(value.source)
        case .packageShadow(let value): .string(value.source)
        case .packageStackingOrder(let value): .string(value.source)
        case .frameworkSpacing, .frameworkPadding, .frameworkMargin, .frameworkBorderWidth, .frameworkRadius: .string("")
        }
    }

    private func unavailablePart(_ node: PartNode, page: Page, framework: Framework, assets: ProjectAssetContents, globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint, parentPartID: UUID?) -> String {
        let children = node.children.map { render($0, page: page, framework: framework, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: node.id) }.joined()
        let name = node.missingPackageSnapshot?.name ?? node.type.rawValue
        // The snapshot travels in the document, so the title and the pack's
        // help address show even on a machine that never had the pack.
        let help = node.missingPackageSnapshot?.helpURL
            .map { " — help: \(escape($0.absoluteString))" } ?? ""
        return "<div class=\"unavailable\" \(attributes(for: node, globalDefinitionID: globalDefinitionID, parentPartID: parentPartID))>Missing part: \(escape(name))\(help)\(children)</div>"
    }

    private func failedPart(_ node: PartNode, page: Page, package: LoadedPartPackage, framework: Framework, assets: ProjectAssetContents, globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint, parentPartID: UUID?) -> String {
        let children = node.children.map { render($0, page: page, framework: framework, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint, parentPartID: node.id) }.joined()
        return "<div class=\"unavailable\" \(attributes(for: node, globalDefinitionID: globalDefinitionID, parentPartID: parentPartID))>Part files could not be loaded: \(escape(package.manifest.name))\(children)</div>"
    }

    private var rootDropZone: String {
        "<div class=\"foundry-empty-drop-zone foundry-empty-page\" data-foundry-root-drop-zone><span class=\"foundry-drop-label\">\(FoundryDropZoneGlyphs.part)</span></div>"
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
                + (node.reusableDefinitionID != nil ? " data-foundry-global-root=\"true\"" : "")
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
