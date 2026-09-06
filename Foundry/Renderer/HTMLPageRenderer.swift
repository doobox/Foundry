import Foundation

@MainActor
struct HTMLPageRenderer: PageRendering {
    let site: Site?

    init(site: Site? = nil) { self.site = site }
    func render(page: Page, theme: Theme) -> String {
        render(page: page, language: "en", theme: theme, assets: [:], breakpoint: .extraLarge)
    }

    func render(page: Page, language: String, theme: Theme, assets: [UUID: ProjectAssetContent], breakpoint: ResponsiveBreakpoint) -> String {
        let body = page.components.isEmpty
            ? rootDropZone
            : page.components.map { render($0, theme: theme, assets: assets, globalDefinitionID: $0.reusableDefinitionID, breakpoint: breakpoint) }.joined(separator: "\n")
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
          <title>\(escape(browserTitle))</title>
        \(metadata)
          <style>
            \(theme.fontSourceCSS(assets: assets, destination: .canvas))
            :root {
              font-size: 16px;
              --foundry-color-background: \(theme.colors.background);
              --foundry-color-surface: \(theme.colors.surface);
              --foundry-color-text: \(theme.colors.text);
              --foundry-color-accent: \(theme.colors.accent);
              --foundry-color-links: \(theme.colors.links);
              --foundry-font-body: \(theme.typography.bodyFont.cssFamily);
              --foundry-font-heading: \(theme.typography.headingFont.cssFamily);
              --foundry-font-monospace: \(theme.typography.monospacedFont.cssFamily);
              \(theme.customFontCSSVariables)
              \(theme.fontSizeCSSVariables)
              --foundry-editor-component: #0A84FF;
              --foundry-editor-global: #0A84FF;
              --foundry-editor-primitive: #0A84FF;
              \(theme.spacingCSSVariables)
            }
            *, *::before, *::after { box-sizing: border-box; }
            a { color: var(--foundry-color-links); }
            \(theme.screens.containerCSS)
            .foundry-container { width: 100%; max-width: var(--foundry-container-width) !important; }
            [data-foundry-id] {
              --foundry-editor-chrome: var(--foundry-editor-component);
              position: relative; cursor: default;
            }
            [data-foundry-global] { --foundry-editor-chrome: var(--foundry-editor-global); }
            [data-foundry-global-override="true"],
            [data-foundry-global-override="true"] [data-foundry-global] {
              --foundry-editor-chrome: var(--foundry-editor-component);
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
            .foundry-global-menu {
              display: none; position: fixed; z-index: 1002; min-width: 190px; padding: 5px;
              border: 1px solid rgba(0,0,0,.12); border-radius: 9px; background: rgba(255,255,255,.98);
              box-shadow: 0 10px 30px rgba(0,0,0,.2); color: #171719;
            }
            .foundry-global-menu.is-visible { display: block; }
            .foundry-global-menu button {
              display: block; width: 100%; padding: 7px 10px; border: 0; border-radius: 6px;
              background: transparent; color: inherit; font: 13px system-ui; text-align: left; cursor: default;
            }
            .foundry-global-menu button:hover { background: rgba(0,0,0,.08); }
            [contenteditable="true"]:focus {
              outline: none !important;
            }
            .foundry-drag-source { opacity: 0.4 !important; }
            .foundry-drop-before { box-shadow: inset 0 4px 0 var(--foundry-editor-chrome) !important; }
            .foundry-drop-after { box-shadow: inset 0 -4px 0 var(--foundry-editor-chrome) !important; }
            .foundry-drop-inside { outline: 4px dashed var(--foundry-editor-chrome) !important; outline-offset: -8px; }
            .foundry-drop-end { border-color: var(--foundry-editor-chrome) !important; background: color-mix(in srgb, var(--foundry-editor-chrome) 12%, transparent) !important; }
            [data-foundry-global].foundry-drop-before { box-shadow: inset 0 4px 0 var(--foundry-editor-chrome) !important; }
            [data-foundry-global].foundry-drop-after { box-shadow: inset 0 -4px 0 var(--foundry-editor-chrome) !important; }
            [data-foundry-global].foundry-drop-inside { outline-color: var(--foundry-editor-chrome) !important; }
            [data-foundry-global].foundry-drop-end {
              border-color: var(--foundry-editor-chrome) !important;
              background: color-mix(in srgb, var(--foundry-editor-chrome) 12%, transparent) !important;
            }
            .foundry-empty-drop-zone {
              display: grid; place-items: center; min-height: 64px; padding: 16px;
              border: 2px dashed color-mix(in srgb, var(--foundry-editor-component) 42%, transparent) !important;
              border-radius: 6px; color: color-mix(in srgb, var(--foundry-color-text) 58%, transparent);
              background: color-mix(in srgb, var(--foundry-color-surface) 72%, transparent);
              font: 600 13px system-ui; text-align: center;
            }
            .foundry-empty-drop-zone.foundry-drop-inside {
              border-color: transparent !important;
              outline-offset: -4px;
            }
            .foundry-empty-page { min-height: 100vh; }
            .foundry-contentless-drop-zone { min-height: 32px; padding: 6px 12px; }
            .foundry-columns > .foundry-empty-drop-zone { grid-column: 1 / -1; }
            [data-foundry-global].foundry-empty-drop-zone {
              border-color: color-mix(in srgb, var(--foundry-editor-component) 42%, transparent) !important;
            }
            [data-foundry-global].foundry-editing { outline-color: var(--foundry-editor-chrome) !important; }
            html, body { min-height: 100%; }
            body {
              margin: 0; background: var(--foundry-color-background);
              color: var(--foundry-color-text); font-family: var(--foundry-font-body);
              font-size: var(--foundry-font-size-base); line-height: var(--foundry-font-size-base-line-height);
              display: flex; flex-direction: column; align-items: stretch;
            }
            h1, h2, h3, h4, h5, h6, .foundry-heading { font-family: var(--foundry-font-heading); }
            code, pre, kbd, samp { font-family: var(--foundry-font-monospace); }
            .foundry-button {
              display: block; width: fit-content; text-decoration: none; font-weight: 600;
            }
            .foundry-columns { display: grid; }
            .foundry-image { display: block; width: 100%; height: auto; }
            .foundry-image-drop-zone {
              display: grid; width: 100%; min-height: 64px; padding: 16px; place-items: center;
              border: 2px dashed color-mix(in srgb, var(--foundry-editor-component) 42%, transparent) !important;
              border-radius: 6px; color: color-mix(in srgb, var(--foundry-color-text) 58%, transparent);
              background: color-mix(in srgb, var(--foundry-color-surface) 72%, transparent);
              font: 600 13px system-ui; text-align: center;
            }
            .foundry-image-drop-zone.foundry-drop-inside {
              border-color: transparent !important;
              outline-offset: -4px;
            }
            [data-foundry-image-drop-zone].foundry-image.foundry-drop-inside {
              outline-offset: -4px;
            }
            [data-foundry-image-drop-zone][data-foundry-primitive-property].foundry-drop-inside {
              outline-color: var(--foundry-editor-primitive) !important;
            }
            .foundry-spacer { min-height: 8px; }
            .unavailable { padding: 16px; border: 2px dashed #C33; color: #922; background: #FFF5F5; }
            \(FoundryWebLibraryRegistry.canvasCSS(for: ComponentArtifactPlan(page: page).packages))
            \(packageStyles(for: page, theme: theme, assets: assets, breakpoint: breakpoint))
          </style>
        \(analyticsCode)
        \(headEnd)
        </head>
        <body>\(customBodyStartCode)\(bodyStart)\(body)\(bodyEnd)\(scripts)\(customBodyEndCode)</body>
        </html>
        """
    }

    private func packageScripts(
        for page: Page,
        theme: Theme,
        assets: [UUID: ProjectAssetContent],
        breakpoint: ResponsiveBreakpoint
    ) -> String {
        let nodes = page.components.flatMap(flattened)
        let instanceScripts = nodes.compactMap { sourceNode -> String? in
            let node = sourceNode.resolved(at: breakpoint)
            guard let package = node.type.definition.package, !package.instanceJavaScript.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                package.instanceJavaScript,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assets: assets),
                    slots: [:],
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    environment: .canvas,
                    repeatMaximums: package.repeatMaximums
                )
            )
        }
        var seenPackages: Set<String> = []
        let sharedScripts = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = package.pageJavaScript
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                source,
                context: .init(instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), packageIdentifier: package.manifest.identifier, properties: [:], slots: [:], assetBasePath: canvasAssetBasePath(for: package), assetPaths: canvasAssetPaths(for: package), environment: .canvas, repeatMaximums: package.repeatMaximums)
            )
        }
        let htmlScripts = nodes.map {
            ComponentArtifactPlan.htmlArtifact(for: $0.resolved(at: breakpoint), suffix: "JavaScript")
        }
            .filter { !$0.isEmpty }
        let source = (instanceScripts + htmlScripts + sharedScripts).joined(separator: "\n")
        return source.isEmpty ? "" : "<script>\n\(source)\n</script>"
    }

    private func placedHTML(for page: Page, placement: ComponentPackageTemplateFile.Placement) -> String {
        var seenPackages: Set<String> = []
        return page.components.flatMap(flattened).compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let templates = package.placedHTML.filter { $0.placement == placement }
            guard !templates.isEmpty else { return nil }
            let context = ComponentTemplateContext(
                instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                packageIdentifier: package.manifest.identifier,
                properties: [:],
                slots: [:],
                assetBasePath: canvasAssetBasePath(for: package),
                assetPaths: canvasAssetPaths(for: package),
                environment: .canvas,
                repeatMaximums: package.repeatMaximums
            )
            return templates.map { ComponentTemplateRenderer.render($0.contents, context: context) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func metadataHTML(
        for page: Page,
        browserTitle: String,
        site: Site?,
        assets: [UUID: ProjectAssetContent]
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

    private func render(_ sourceNode: ComponentNode, theme: Theme, assets: [UUID: ProjectAssetContent], globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint) -> String {
        let node = sourceNode.resolved(at: breakpoint)
        let globalDefinitionID = node.reusableDefinitionID ?? globalDefinitionID
        switch node.type.definition.renderKind {
        case .package:
            guard let package = node.type.definition.package else {
                return unavailableComponent(node, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
            }
            do {
                try package.preparePayload()
            } catch {
                return failedComponent(node, package: package, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
            }
            let slots = Dictionary(uniqueKeysWithValues: package.manifest.slots.map { slot in
                let children = node.children.filter { ($0.slotID ?? package.manifest.slots.first?.id) == slot.id }
                let html = children.map {
                    render($0, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
                }.joined()
                return (slot.id, html.isEmpty ? "<div class=\"foundry-empty-drop-zone\" data-foundry-empty-parent=\"\(node.id.uuidString)\" data-foundry-slot-id=\"\(escapeAttribute(slot.id))\">Drop component here</div>" : html)
            })
            let adjacentDropAttribute = package.manifest.slots.isEmpty
                ? " data-foundry-adjacent-target=\"\(node.id.uuidString)\""
                : ""
            let canvasAttributes = attributes(for: node, globalDefinitionID: globalDefinitionID) +
                " data-foundry-package=\"\(escapeAttribute(package.manifest.identifier))\"" +
                adjacentDropAttribute
            let rendered = ComponentTemplateRenderer.render(
                package.htmlTemplate,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assets: assets),
                    slots: slots,
                    componentAttributes: canvasAttributes,
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    enablesEditorMarkup: true,
                    environment: .canvas,
                    richTextLinkContext: richTextLinkContext,
                    repeatMaximums: package.repeatMaximums
                )
            )
            if package.htmlTemplate.contains("{{ component.attributes }}") ||
                package.htmlTemplate.contains("{{component.attributes}}") {
                return rendered
            }
            return "<div \(canvasAttributes)>\(rendered)</div>"
        case .unavailable:
            return unavailableComponent(node, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
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
        assets: [UUID: ProjectAssetContent],
        breakpoint: ResponsiveBreakpoint
    ) -> String {
        let nodes = page.components.flatMap(flattened)
        let instanceStyles = nodes.compactMap { sourceNode in
            let node = sourceNode.resolved(at: breakpoint)
            guard let package = node.type.definition.package else { return nil }
            let css = ComponentTemplateRenderer.render(
                package.css + "\n" + package.editorCSS,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assets: assets),
                    slots: [:],
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    environment: .canvas,
                    repeatMaximums: package.repeatMaximums
                )
            )
            return ComponentTemplateRenderer.scopedCSS(css, packageIdentifier: package.manifest.identifier)
        }.joined(separator: "\n")
        let htmlStyles = nodes.map {
            ComponentArtifactPlan.htmlArtifact(for: $0.resolved(at: breakpoint), suffix: "CSS")
        }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        var seenPackages: Set<String> = []
        let pageStyles = page.components.flatMap(flattened).compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  (!package.pageCSS.isEmpty || !package.siteCSS.isEmpty),
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            return ComponentTemplateRenderer.render(
                [package.pageCSS, package.siteCSS].filter { !$0.isEmpty }.joined(separator: "\n"),
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    slots: [:],
                    assetBasePath: canvasAssetBasePath(for: package),
                    assetPaths: canvasAssetPaths(for: package),
                    environment: .canvas,
                    repeatMaximums: package.repeatMaximums
                )
            )
        }.joined(separator: "\n")
        return [instanceStyles, htmlStyles, pageStyles].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func canvasAssetBasePath(for package: LoadedComponentPackage) -> String {
        "\(CanvasAssetSchemeHandler.packageScheme)://\(package.manifest.identifier)"
    }

    private func canvasAssetPaths(for package: LoadedComponentPackage) -> [String: String] {
        let basePath = canvasAssetBasePath(for: package)
        return Dictionary(uniqueKeysWithValues: package.manifest.assets.map { asset in
            (asset.path, basePath + "/" + asset.path)
        })
    }

    private func packageProperties(_ node: ComponentNode, theme: Theme, assets: [UUID: ProjectAssetContent]) -> [String: ComponentPackageValue] {
        var values: [String: ComponentPackageValue] = Dictionary(uniqueKeysWithValues: node.type.definition.properties.map { definition in
            let value = node.propertyValue(definition.key)
            if let source = definition.themeValueSource,
               case .choice(let reference) = value,
               let resolved = ComponentPackageThemeValueResolver.resolve(reference, from: source, theme: theme) {
                return (definition.key.rawValue, .string(resolved))
            }
            if let source = definition.themeValueSource,
               case .array(let items) = value {
                return (definition.key.rawValue, .array(items.map { item in
                    let reference: String
                    switch item {
                    case .choice(let value), .string(let value): reference = value
                    default: return packageValue(item)
                    }
                    guard
                          let resolved = ComponentPackageThemeValueResolver.resolve(reference, from: source, theme: theme) else {
                        return packageValue(item)
                    }
                    return .string(resolved)
                }))
            }
            if case .image = definition.control,
               case .url(let source) = value {
                return (definition.key.rawValue, .string(canvasSource(source, assets: assets)))
            }
            if case .color = definition.control {
                return (definition.key.rawValue, .string(node.colorProperty(definition.key, theme: theme)))
            }
            if case .packageColor(_, let colorMath, let opacity) = definition.control,
               case .packageColor(let colorValue) = value {
                return (
                    definition.key.rawValue,
                    .string(ComponentPackageColorResolver.resolve(
                        colorValue, theme: theme,
                        colorMath: colorMath, opacity: opacity
                    ))
                )
            }
            if case .themeFontSize = definition.control {
                return (definition.key.rawValue, .string(theme.fontSizeCSSVariable(for: node.property(definition.key))))
            }
            if case .packageFontSize(let themeValues) = definition.control,
               case .packageFontSize(let fontSizeValue) = value {
                let resolved = !themeValues || ComponentThemeValueSelection.isManualCustom(fontSizeValue.source)
                    ? fontSizeValue.customValue : theme.fontSizeCSSVariable(for: fontSizeValue.source)
                return (definition.key.rawValue, .string(resolved))
            }
            if case .packageSpacing(let kind, _, _) = definition.control,
               case .packageSpacing(let spacingValue) = value {
                return (
                    definition.key.rawValue,
                    .string(ComponentPackageSpacingResolver.resolve(
                        spacingValue,
                        theme: theme,
                        kind: kind
                    ))
                )
            }
            if case .number = definition.control {
                return (definition.key.rawValue, .number(node.numberProperty(definition.key, theme: theme)))
            }
            return (definition.key.rawValue, packageValue(value))
        })
        for definition in node.type.definition.properties {
            guard case .packageFontSize(let usesThemeValues) = definition.control,
                  case .packageFontSize(let fontSizeValue) = node.propertyValue(definition.key) else { continue }
            values[definition.key.rawValue + ".lineHeight"] = .string(
                ComponentPackageThemeValueResolver.resolveFontSizeLineHeight(
                    fontSizeValue,
                    usesThemeValues: usesThemeValues,
                    theme: theme
                )
            )
        }
        if let package = node.type.definition.package {
            for property in package.manifest.properties where property.control.type == .image {
                let key = ComponentProperty.Key(rawValue: property.id)
                guard case .url(let source) = node.propertyValue(key) else { continue }
                let metadata = source.foundryAssetID.flatMap { assets[$0]?.asset.imageMetadata }
                    ?? package.imageMetadata[source]
                let focalPoint = ComponentImageTemplateValues.focalPoint(
                    from: node.propertyValue(ComponentPackageAdapter.imageFocalPointKey(for: property.id))
                )
                ComponentImageTemplateValues.insert(
                    propertyID: property.id,
                    href: values[property.id]?.stringValue ?? "",
                    alt: node.property(ComponentPackageAdapter.imageAltKey(for: property.id)),
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
        }
        if let site {
            for definition in node.type.definition.properties {
                guard case .link(let absoluteURL) = definition.control,
                      case .link(let link) = node.propertyValue(definition.key) else { continue }
                let resolved = ComponentLinkResolver.resolve(
                    link, pages: site.pages, folders: site.pageFolders, assets: site.assets,
                    publicURL: site.publicURL, absoluteURL: absoluteURL
                )
                values[definition.key.rawValue] = .string(resolved.href)
                values[definition.key.rawValue + ".target"] = .string(resolved.target)
                values[definition.key.rawValue + ".attributes"] = .string(resolved.attributes)
            }
        }
        return ComponentPackageDerivedValueResolver.resolve(
            values,
            properties: node.type.definition.package?.manifest.properties ?? []
        )
    }

    private func flattened(_ node: ComponentNode) -> [ComponentNode] {
        [node] + node.children.flatMap(flattened)
    }

    private func packageValue(_ value: ComponentProperty.Value) -> ComponentPackageValue {
        switch value {
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .string(let value), .url(let value), .color(let value), .choice(let value): .string(value)
        case .token(let value): .string(value.rawValue)
        case .array(let values): .array(values.map(packageValue))
        case .link: .string("")
        case .packageColor(let value): .string(value.source)
        case .packageFontSize(let value): .string(value.source)
        case .packageSpacing(let value): .array(value.sources.map(ComponentPackageValue.string))
        }
    }

    private func unavailableComponent(_ node: ComponentNode, theme: Theme, assets: [UUID: ProjectAssetContent], globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint) -> String {
        let children = node.children.map { render($0, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint) }.joined()
        let name = node.missingPackageSnapshot?.name ?? node.type.rawValue
        return "<div class=\"unavailable\" \(attributes(for: node, globalDefinitionID: globalDefinitionID))>Missing component: \(escape(name))\(children)</div>"
    }

    private func failedComponent(_ node: ComponentNode, package: LoadedComponentPackage, theme: Theme, assets: [UUID: ProjectAssetContent], globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint) -> String {
        let children = node.children.map { render($0, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint) }.joined()
        return "<div class=\"unavailable\" \(attributes(for: node, globalDefinitionID: globalDefinitionID))>Component files could not be loaded: \(escape(package.manifest.name))\(children)</div>"
    }

    private var rootDropZone: String {
        "<div class=\"foundry-empty-drop-zone foundry-empty-page\" data-foundry-root-drop-zone>Drop component here</div>"
    }

    private func renderedChildren(of node: ComponentNode, theme: Theme, assets: [UUID: ProjectAssetContent], globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint) -> String {
        guard node.children.isEmpty else {
            return node.children.map { render($0, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint) }.joined()
        }
        return "<div class=\"foundry-empty-drop-zone\" data-foundry-empty-parent=\"\(node.id.uuidString)\">Drop component here</div>"
    }

    private func canvasSource(_ source: String, assets: [UUID: ProjectAssetContent]) -> String {
        guard let id = source.foundryAssetID else { return source }
        return assets[id] == nil ? "" : source
    }

    private func attributes(for node: ComponentNode, globalDefinitionID: UUID?) -> String {
        let definition = node.type.definition
        let acceptsChildren = definition.allowsChildren ? "true" : "false"
        let manifest = definition.package?.manifest
        let author = manifest?.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution = author?.isEmpty == false ? author! : "Foundry"
        let version = manifest?.version ?? ""
        let globalAttributes = globalDefinitionID.map {
            " data-foundry-global=\"\($0.uuidString)\" data-foundry-global-override=\"\(node.overridesGlobalDefinition == true)\""
        } ?? ""
        return "id=\"foundry-\(node.id.uuidString.lowercased())\" data-foundry-id=\"\(node.id.uuidString)\" data-foundry-component-type=\"\(escapeAttribute(node.type.rawValue))\" data-foundry-type=\"\(escapeAttribute(node.type.displayName))\" data-foundry-name=\"\(escapeAttribute(node.name))\" data-foundry-author=\"\(escapeAttribute(attribution))\" data-foundry-version=\"\(escapeAttribute(version))\" data-foundry-accepts-children=\"\(acceptsChildren)\"\(globalAttributes)"
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
