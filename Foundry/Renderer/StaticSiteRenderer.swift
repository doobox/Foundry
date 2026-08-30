import Foundation

nonisolated struct StaticSiteRenderer: SiteRendering {
    func render(site: Site) -> SiteExportBundle {
        render(site: site, assets: [:])
    }

    func render(site: Site, assets: [UUID: ProjectAssetContent]) -> SiteExportBundle {
        var files = site.pages.map { page in
            let isHome = page.slug == "index"
            let directory = isHome ? "" : joinedPath(folderPath(for: page.folderID, in: site), page.slug)
            let pageExtension = Self.requiresPhp(page) ? "php" : "html"
            let rootPrefix = directory.isEmpty
                ? ""
                : String(repeating: "../", count: directory.split(separator: "/").count)
            return SiteExportFile(
                path: isHome ? "index.\(pageExtension)" : joinedPath(directory, "index.\(pageExtension)"),
                contents: render(
                    page: page,
                    language: site.language,
                    theme: site.theme,
                    stylesheetPath: rootPrefix + "assets/site.css",
                    assetPrefix: rootPrefix + "assets/images",
                    assets: assets,
                    site: site
                )
            )
        }
        files.append(.init(path: "assets/site.css", contents: stylesheet(for: site, assets: assets)))
        files.append(contentsOf: site.assets.compactMap { asset in
            assets[asset.id].map { SiteExportFile(path: asset.exportPath, data: $0.data) }
        })
        files.append(contentsOf: site.assets.compactMap { asset in
            guard let content = assets[asset.id],
                  let exportPath = customExportPath(for: asset, in: site) else { return nil }
            return SiteExportFile(path: exportPath, data: content.data)
        })
        return SiteExportBundle(files: files.sorted { $0.path < $1.path })
    }

    static func requiresPhp(_ page: Page) -> Bool {
        page.components
            .flatMap(\.flattened)
            .contains { ComponentRegistry.definition(for: $0.type).package?.manifest.requiresPhp == true }
    }

    private func customExportPath(for asset: ProjectAsset, in site: Site) -> String? {
        let filename = (asset.filename as NSString).lastPathComponent
        let safeFilename = filename.isEmpty ? asset.storageFilename : filename
        switch asset.exportDirectory {
        case .root:
            return safeFilename
        case .folder(let folderID):
            return joinedPath(folderPath(for: folderID, in: site), safeFilename)
        case nil:
            return nil
        }
    }

    private func folderPath(for folderID: UUID?, in site: Site) -> String {
        var currentID = folderID
        var slugs: [String] = []
        var visited = Set<UUID>()
        while let id = currentID,
              visited.insert(id).inserted,
              let folder = site.pageFolders.first(where: { $0.id == id }) {
            slugs.insert(folder.slug, at: 0)
            currentID = folder.parentID
        }
        return slugs.joined(separator: "/")
    }

    private func joinedPath(_ prefix: String, _ suffix: String) -> String {
        prefix.isEmpty ? suffix : prefix + "/" + suffix
    }

    private func render(page: Page, language: String, theme: Theme, stylesheetPath: String, assetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        let body = page.components.map { render($0, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site) }.joined(separator: "\n")
        let browserTitle = page.metadata.browserTitle.isEmpty ? page.title : page.metadata.browserTitle
        let metadata = metadataHTML(for: page, browserTitle: browserTitle, assetPrefix: assetPrefix, assets: assets)
        let headStart = placedHTML(for: page, placement: .headStart)
        let headEnd = placedHTML(for: page, placement: .headEnd)
        let bodyStart = placedHTML(for: page, placement: .bodyStart)
        let bodyEnd = placedHTML(for: page, placement: .bodyEnd)
        let scripts = packageScripts(for: page, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site)
        let php = packagePHP(for: page, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site)
        let documentLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = """
        <!doctype html>
        <html lang="\(escapeAttribute(documentLanguage.isEmpty ? "en" : documentLanguage))">
        <head>
        \(headStart)
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(browserTitle))</title>
        \(metadata)
          <link rel="stylesheet" href="\(stylesheetPath)">
        \(headEnd)
        </head>
        <body>
        \(bodyStart)\(body)\(bodyEnd)\(scripts)
        </body>
        </html>
        """
        return php.isEmpty ? document : php + "\n" + document
    }

    private func packagePHP(for page: Page, theme: Theme, assetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        let nodes = page.components.flatMap(\.flattened)
        let instancePHP = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package, !package.instancePHP.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                package.instancePHP,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site),
                    slots: [:]
                )
            )
        }
        var seenPackages: Set<String> = []
        let sharedPHP = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = [package.pagePHP, package.sitePHP].filter { !$0.isEmpty }.joined(separator: "\n")
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                source,
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    slots: [:]
                )
            )
        }
        return (instancePHP + sharedPHP).joined(separator: "\n")
    }

    private func packageScripts(for page: Page, theme: Theme, assetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        let nodes = page.components.flatMap(\.flattened)
        let instanceScripts = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package, !package.instanceJavaScript.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                package.instanceJavaScript,
                context: .init(instanceID: node.id, packageIdentifier: package.manifest.identifier, properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site), slots: [:])
            )
        }
        var seenPackages: Set<String> = []
        let sharedScripts = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = [package.pageJavaScript, package.siteJavaScript].filter { !$0.isEmpty }.joined(separator: "\n")
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(source, context: .init(instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), packageIdentifier: package.manifest.identifier, properties: [:], slots: [:]))
        }
        let source = (instanceScripts + sharedScripts).joined(separator: "\n")
        return source.isEmpty ? "" : "<script>\n\(source)\n</script>"
    }

    private func placedHTML(for page: Page, placement: ComponentPackageTemplateFile.Placement) -> String {
        var seenPackages: Set<String> = []
        return page.components.flatMap(\.flattened).compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let templates = package.placedHTML.filter { $0.placement == placement }
            guard !templates.isEmpty else { return nil }
            let context = ComponentTemplateContext(
                instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                packageIdentifier: package.manifest.identifier,
                properties: [:],
                slots: [:]
            )
            return templates.map { ComponentTemplateRenderer.render($0.contents, context: context) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func metadataHTML(
        for page: Page,
        browserTitle: String,
        assetPrefix: String,
        assets: [UUID: ProjectAssetContent]
    ) -> String {
        var tags: [String] = []
        if !page.metadata.description.isEmpty {
            tags.append("<meta name=\"description\" content=\"\(escapeAttribute(page.metadata.description))\">")
        }

        let socialTitle = page.metadata.socialTitle.isEmpty ? browserTitle : page.metadata.socialTitle
        tags.append("<meta property=\"og:title\" content=\"\(escapeAttribute(socialTitle))\">")

        let socialDescription = page.metadata.socialDescription.isEmpty
            ? page.metadata.description
            : page.metadata.socialDescription
        if !socialDescription.isEmpty {
            tags.append("<meta property=\"og:description\" content=\"\(escapeAttribute(socialDescription))\">")
        }
        if !page.metadata.socialImage.isEmpty {
            let source = exportSource(page.metadata.socialImage, assetPrefix: assetPrefix, assets: assets)
            if !source.isEmpty {
                tags.append("<meta property=\"og:image\" content=\"\(escapeAttribute(source))\">")
            }
        }
        return tags.map { "  " + $0 }.joined(separator: "\n")
    }

    private func render(_ node: ComponentNode, theme: Theme, assetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        let style = sharedStyles(for: node, theme: theme)
        switch node.type.definition.renderKind {
        case .section:
            return element("section", "section", node, style, children(of: node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site))
        case .columns:
            let columns = clamped(node.numberProperty(.columnCount), to: 1...6)
            let gap = clamped(node.numberProperty(.gap), to: 0...120)
            return element("section", "columns", node, style + "grid-template-columns:repeat(\(columns),minmax(0,1fr));gap:\(gap)px;", children(of: node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site))
        case .text:
            return element("div", "text", node, style + textStyles(node, theme: theme), escape(node.property(.text)))
        case .heading:
            let level = min(max(Int(node.property(.headingLevel)) ?? 2, 1), 6)
            return element("h\(level)", "heading", node, style + textStyles(node, theme: theme), escape(node.property(.text)))
        case .button:
            let label = escapeAttribute(node.property(.accessibilityLabel))
            let aria = label.isEmpty ? "" : " aria-label=\"\(label)\""
            let link = resolvedLink(for: node, site: site)
            let target = link.target.isEmpty ? "" : " target=\"\(escapeAttribute(link.target))\""
            let customAttributes = link.attributes.isEmpty ? "" : " \(link.attributes)"
            return "<a class=\"button \(componentClass(node))\" style=\"\(style + textStyles(node, theme: theme))\" href=\"\(escapeAttribute(link.href))\"\(target)\(aria)\(customAttributes)>\(escape(node.property(.text)))</a>"
        case .image:
            let source = exportSource(node.property(.source), assetPrefix: assetPrefix, assets: assets)
            return "<img class=\"image \(componentClass(node))\" style=\"\(style)\" src=\"\(escapeAttribute(source))\" alt=\"\(escapeAttribute(node.property(.altText)))\">"
        case .divider:
            let color = safeHex(node.colorProperty(.borderColor, theme: theme), fallback: "#D9D9DE")
            return "<hr class=\"divider \(componentClass(node))\" style=\"\(style)border:0;border-top:\(clamped(node.numberProperty(.borderWidth), to: 1...24))px solid \(color);\">"
        case .spacer:
            return "<div class=\"spacer \(componentClass(node))\" style=\"\(style)min-height:\(clamped(node.numberProperty(.height), to: 0...600))px;\"></div>"
        case .package:
            guard let package = node.type.definition.package else {
                return missingPackageHTML(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site)
            }
            let slots = Dictionary(uniqueKeysWithValues: package.manifest.slots.map { slot in
                let children = node.children.filter { ($0.slotID ?? package.manifest.slots.first?.id) == slot.id }
                return (slot.id, children.map { render($0, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site) }.joined())
            })
            let rendered = ComponentTemplateRenderer.render(
                package.htmlTemplate,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site),
                    slots: slots,
                    componentClass: componentClass(node) + " " +
                        ComponentTemplateRenderer.packageClass(for: package.manifest.identifier)
                )
            )
            if package.htmlTemplate.contains("{{ component.attributes }}") ||
                package.htmlTemplate.contains("{{component.attributes}}") {
                return rendered
            }
            return "<div class=\"\(componentClass(node))\" data-foundry-package=\"\(escapeAttribute(package.manifest.identifier))\">\(rendered)</div>"
        case .unavailable:
            return missingPackageHTML(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site)
        }
    }

    private func resolvedLink(for node: ComponentNode, site: Site) -> ComponentLinkResolver.Result {
        guard case .link(let link) = node.propertyValue(.destination) else {
            return .init(href: "", target: "", attributes: "")
        }
        return ComponentLinkResolver.resolve(
            link,
            pages: site.pages,
            folders: site.pageFolders,
            assets: site.assets,
            publicURL: site.publicURL,
            absoluteURL: false
        )
    }

    private func children(of node: ComponentNode, theme: Theme, assetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        node.children.map { render($0, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site) }.joined()
    }

    private func exportSource(_ source: String, assetPrefix: String, assets: [UUID: ProjectAssetContent]) -> String {
        guard let id = source.foundryAssetID else { return source }
        guard let content = assets[id] else { return "" }
        return assetPrefix + "/" + content.asset.storageFilename
    }

    private func element(_ tag: String, _ className: String, _ node: ComponentNode, _ style: String, _ contents: String) -> String {
        "<\(tag) class=\"\(className) \(componentClass(node))\" style=\"\(style)\">\(contents)</\(tag)>"
    }

    private func textStyles(_ node: ComponentNode, theme: Theme) -> String {
        let color = safeHex(node.colorProperty(.textColor, theme: theme), fallback: "#171719")
        return "color:\(color);font-size:\(clamped(node.numberProperty(.fontSize), to: 10...120))px;text-align:\(alignment(node.property(.alignment)));"
    }

    private func sharedStyles(for node: ComponentNode, theme: Theme) -> String {
        var styles = "padding:\(clamped(node.numberProperty(.padding, theme: theme), to: 0...160))px;"
        styles += "margin-top:\(clamped(node.numberProperty(.marginTop, theme: theme), to: 0...240))px;"
        styles += "margin-bottom:\(clamped(node.numberProperty(.marginBottom, theme: theme), to: 0...240))px;"
        if node.type.definition.properties.contains(where: { $0.key == .backgroundColor }) {
            styles += "background-color:\(safeHex(node.colorProperty(.backgroundColor, theme: theme), fallback: "#FFFFFF"));"
        }
        if node.type.definition.properties.contains(where: { $0.key == .borderColor }) {
            styles += "border:\(clamped(node.numberProperty(.borderWidth, theme: theme), to: 0...24))px solid \(safeHex(node.colorProperty(.borderColor, theme: theme), fallback: "#D9D9DE"));"
            styles += "border-radius:\(clamped(node.numberProperty(.cornerRadius), to: 0...160))px;"
        }
        let maxWidth = min(max(node.numberProperty(.maxWidth), 0), 1600)
        if maxWidth > 0 { styles += "max-width:\(clamped(maxWidth, to: 0...1600))px;" }
        switch node.property(.horizontalAlignment) {
        case "center": styles += "margin-left:auto;margin-right:auto;"
        case "trailing": styles += "margin-left:auto;margin-right:0;"
        default: styles += "margin-left:0;margin-right:auto;"
        }
        return styles
    }

    private func stylesheet(for site: Site, assets: [UUID: ProjectAssetContent]) -> String {
        let theme = site.theme
        return """
        \(theme.remoteFontImports)
        :root{font-size:\(theme.typography.baseSize)px;--background:\(theme.colors.background);--surface:\(theme.colors.surface);--text:\(theme.colors.text);--accent:\(theme.colors.accent);--font-body:\(theme.typography.bodyFont.cssFamily);--font-heading:\(theme.typography.headingFont.cssFamily);--font-monospace:\(theme.typography.monospacedFont.cssFamily);\(theme.customFontCSSVariables)\(theme.fontSizeCSSVariables)--space-s:\(theme.spacing.small)px;--space-m:\(theme.spacing.medium)px;--space-l:\(theme.spacing.large)px}
        *,*::before,*::after{box-sizing:border-box}
        html,body{min-height:100%}
        body{margin:0;background:var(--background);color:var(--text);font-family:var(--font-body);font-size:var(--font-size-base);line-height:var(--font-size-base-line-height)}
        h1,h2,h3,h4,h5,h6,.heading{font-family:var(--font-heading)}code,pre,kbd,samp{font-family:var(--font-monospace)}
        .button{display:block;width:fit-content;text-decoration:none;font-weight:600}.columns{display:grid}.image{display:block;width:100%;height:auto}.spacer{min-height:8px}
        \(packageStyles(for: site, assets: assets))
        \(themeControlStyles(for: site))
        \(responsiveStyles(for: site, assets: assets))
        """
    }

    private func responsiveStyles(
        for site: Site,
        assets: [UUID: ProjectAssetContent]
    ) -> String {
        let nodes = site.pages.flatMap { $0.components.flatMap(\.flattened) }
        return [ResponsiveBreakpoint.tabletPortrait, .tabletLandscape, .desktop].compactMap { breakpoint in
            guard let minimumWidth = breakpoint.minimumWidth else { return nil }
            let rules = nodes.compactMap { node -> String? in
                guard node.responsiveOverrides?.contains(where: { $0.breakpoint == breakpoint }) == true else { return nil }
                let resolved = node.resolved(at: breakpoint)
                if let package = resolved.type.definition.package {
                    let css = ComponentTemplateRenderer.render(
                        package.css,
                        context: .init(
                            instanceID: resolved.id,
                            packageIdentifier: package.manifest.identifier,
                            properties: packageProperties(
                                resolved,
                                theme: site.theme,
                                assetPrefix: "",
                                assets: assets,
                                site: site
                            ),
                            slots: [:],
                            componentClass: componentClass(resolved)
                        )
                    )
                    let scopedCSS = ComponentTemplateRenderer.scopedCSS(
                        css,
                        packageIdentifier: package.manifest.identifier
                    )
                    let themeCSS = themeControlDeclarations(for: resolved, theme: site.theme)
                    return scopedCSS + (themeCSS.isEmpty ? "" : ".\(componentClass(resolved)){\(themeCSS)}")
                }
                var declarations = sharedStyles(for: resolved, theme: site.theme)
                switch resolved.type.definition.renderKind {
                case .text, .heading, .button:
                    declarations += textStyles(resolved, theme: site.theme)
                case .columns:
                    declarations += "grid-template-columns:repeat(\(clamped(resolved.numberProperty(.columnCount), to: 1...6)),minmax(0,1fr));gap:\(clamped(resolved.numberProperty(.gap), to: 0...120))px;"
                case .spacer:
                    declarations += "min-height:\(clamped(resolved.numberProperty(.height), to: 0...600))px;"
                default:
                    break
                }
                return ".\(componentClass(node)){\(declarations.replacingOccurrences(of: ";", with: "!important;"))}"
            }.joined()
            return rules.isEmpty ? nil : "@media(min-width:\(minimumWidth)px){\(rules)}"
        }.joined(separator: "\n")
    }

    private func componentClass(_ node: ComponentNode) -> String {
        "c-" + node.id.uuidString.lowercased()
    }

    private func packageStyles(
        for site: Site,
        assets: [UUID: ProjectAssetContent]
    ) -> String {
        let nodes = site.pages.flatMap { $0.components.flatMap(\.flattened) }
        let instanceStyles = nodes.compactMap { node in
            guard let package = node.type.definition.package else { return nil }
            let css = ComponentTemplateRenderer.render(
                package.css,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: site.theme, assetPrefix: "", assets: assets, site: site),
                    slots: [:],
                    componentClass: componentClass(node)
                )
            )
            return ComponentTemplateRenderer.scopedCSS(css, packageIdentifier: package.manifest.identifier)
        }.joined(separator: "\n")
        var seenPackages: Set<String> = []
        let pageStyles = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  (!package.pageCSS.isEmpty || !package.siteCSS.isEmpty),
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            return ComponentTemplateRenderer.render(
                [package.pageCSS, package.siteCSS].filter { !$0.isEmpty }.joined(separator: "\n"),
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    slots: [:]
                )
            )
        }.joined(separator: "\n")
        return [instanceStyles, pageStyles].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func themeControlStyles(for site: Site) -> String {
        site.pages.flatMap { $0.components.flatMap(\.flattened) }.compactMap { node in
            let declarations = themeControlDeclarations(for: node, theme: site.theme)
            return declarations.isEmpty ? nil : ".\(componentClass(node)){\(declarations)}"
        }.joined(separator: "\n")
    }

    private func themeControlDeclarations(for node: ComponentNode, theme: Theme) -> String {
        guard node.type.definition.package == nil else { return "" }
        var declarations = ""
        if node.type.definition.properties.contains(where: { $0.control.isThemeFontFamily }) {
            declarations += "font-family:\(theme.fontCSSVariable(for: node.property(.themeFontFamily)));"
        }
        if node.type.definition.properties.contains(where: { $0.control.isThemeFontSize }) {
            declarations += ThemeTypographyControlCSS.declarations(for: node, theme: theme)
                .joined(separator: ";") + ";"
        }
        return declarations
    }

    private func packageValue(_ value: ComponentProperty.Value) -> ComponentPackageValue {
        switch value {
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .string(let value), .url(let value), .color(let value), .choice(let value): .string(value)
        case .token(let value): .string(value.rawValue)
        case .array(let values): .array(values.map(packageValue))
        case .link: .string("")
        }
    }

    private func packageProperties(
        _ node: ComponentNode,
        theme: Theme,
        assetPrefix: String,
        assets: [UUID: ProjectAssetContent],
        site: Site? = nil
    ) -> [String: ComponentPackageValue] {
        let transformedImageInputs = Set(
            node.type.definition.package?.manifest.properties.compactMap { property in
                property.control.type == .imageTransform ? property.control.input : nil
            } ?? []
        )
        var values: [String: ComponentPackageValue] = Dictionary(uniqueKeysWithValues: node.type.definition.properties.map { definition in
            let value = node.propertyValue(definition.key)
            if case .asset = definition.control,
               case .url(let source) = value {
                if transformedImageInputs.contains(definition.key.rawValue),
                   let id = source.foundryAssetID,
                   let content = assets[id] {
                    return (
                        definition.key.rawValue,
                        .string("data:\(content.asset.mediaType);base64,\(content.data.base64EncodedString())")
                    )
                }
                return (
                    definition.key.rawValue,
                    .string(exportSource(source, assetPrefix: assetPrefix, assets: assets))
                )
            }
            if case .color = definition.control {
                return (definition.key.rawValue, .string(node.colorProperty(definition.key, theme: theme)))
            }
            if case .packageColor(_, let customColorKey, let colorMathKey, let opacityKey) = definition.control {
                return (
                    definition.key.rawValue,
                    .string(ComponentPackageColorResolver.resolve(
                        node: node, key: definition.key, theme: theme,
                        customColorKey: customColorKey,
                        colorMathKey: colorMathKey, opacityKey: opacityKey
                    ))
                )
            }
            if case .themeFontFamily = definition.control {
                return (definition.key.rawValue, .string(theme.fontCSSVariable(for: node.property(definition.key))))
            }
            if case .themeFontSize = definition.control {
                return (definition.key.rawValue, .string(theme.fontSizeCSSVariable(for: node.property(definition.key))))
            }
            if case .packageFontFamily(let themeValues, let customValueKey) = definition.control {
                let source = node.property(definition.key)
                let resolved = !themeValues || source == "custom"
                    ? node.property(customValueKey) : theme.fontCSSVariable(for: source)
                return (definition.key.rawValue, .string(resolved))
            }
            if case .packageFontSize(let themeValues, let customValueKey) = definition.control {
                let source = node.property(definition.key)
                let resolved = !themeValues || source == "custom"
                    ? node.property(customValueKey) : theme.fontSizeCSSVariable(for: source)
                return (definition.key.rawValue, .string(resolved))
            }
            if case .lineHeight(let fontSizeKey) = definition.control {
                return (
                    definition.key.rawValue,
                    .string(ComponentPackageLineHeightResolver.resolve(
                        node.property(definition.key),
                        fontSizeKey: fontSizeKey,
                        node: node,
                        theme: theme
                    ))
                )
            }
            if case .number = definition.control {
                return (definition.key.rawValue, .number(node.numberProperty(definition.key, theme: theme)))
            }
            return (definition.key.rawValue, packageValue(value))
        })
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

    private func safeCSSValue(_ value: ComponentProperty.Value) -> String {
        let raw: String
        switch value {
        case .number(let value):
            return clamped(value, to: -10_000...10_000)
        case .boolean(let value):
            return value ? "true" : "false"
        case .string(let value), .url(let value), .color(let value), .choice(let value):
            raw = value
        case .token(let value):
            raw = value.rawValue
        case .array(let values):
            raw = values.map(\.stringValue).joined(separator: " ")
        case .link:
            raw = ""
        }
        return raw.filter { !";{}<>".contains($0) }
    }

    private func missingPackageHTML(_ node: ComponentNode, theme: Theme, assetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        if let preview = node.missingPackageSnapshot?.previewHTML { return preview }
        return children(of: node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site)
    }

    private func alignment(_ value: String) -> String {
        value == "center" ? "center" : value == "trailing" ? "right" : "left"
    }

    private func safeHex(_ value: String, fallback: String) -> String {
        let digits = value.hasPrefix("#") ? value.dropFirst() : Substring()
        return digits.count == 6 && digits.allSatisfy(\.isHexDigit) ? "#\(digits)" : fallback
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>) -> String {
        min(max(value, range.lowerBound), range.upperBound).formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...2)))
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "\"", with: "&quot;")
    }
}

nonisolated private extension ComponentNode {
    var flattened: [ComponentNode] {
        [self] + children.flatMap(\.flattened)
    }
}
