import Foundation

nonisolated struct StaticSiteRenderer: SiteRendering {
    func render(site: Site) -> SiteExportBundle {
        render(site: site, assets: [:])
    }

    func render(site: Site, assets: [UUID: ProjectAssetContent]) -> SiteExportBundle {
        var files = site.pages.flatMap { page -> [SiteExportFile] in
            let isHome = page.slug == "index"
            let directory = isHome
                ? ""
                : PageRouteResolver.pathSegments(
                    for: page,
                    pages: site.pages,
                    folders: site.pageFolders
                ).joined(separator: "/")
            let rootPrefix = directory.isEmpty
                ? ""
                : String(repeating: "../", count: directory.split(separator: "/").count)
            let includesPageJavaScript = pageRequiresJavaScript(page)
            let pageFilesDirectory = Self.joinedPath(directory, "files")
            let pageStylesAssetPrefix = String(
                repeating: "../",
                count: directory.split(separator: "/").count + 1
            ) + "assets"
            let pageStylesPackageAssetPrefix: String
            if directory.isEmpty {
                pageStylesPackageAssetPrefix = "components"
            } else {
                pageStylesPackageAssetPrefix = String(
                    repeating: "../",
                    count: directory.split(separator: "/").count + 1
                ) + "files/components"
            }
            let documentPackageAssetPrefix = rootPrefix + "files/components"
            var pageFiles = [SiteExportFile(
                path: Self.outputPath(for: page, in: site),
                contents: render(
                    page: page,
                    language: site.language,
                    theme: site.theme,
                    stylesheetPaths: [rootPrefix + "files/site.css", "files/page.css"],
                    scriptPaths: includesPageJavaScript ? ["files/page.js"] : [],
                    assetPrefix: rootPrefix + "assets",
                    packageAssetPrefix: documentPackageAssetPrefix,
                    assets: assets,
                    site: site
                )
            ), SiteExportFile(
                path: Self.joinedPath(pageFilesDirectory, "page.css"),
                contents: pageStyles(
                    for: page,
                    site: site,
                    assetPrefix: pageStylesAssetPrefix,
                    packageAssetPrefix: pageStylesPackageAssetPrefix,
                    assets: assets
                )
            )]
            if includesPageJavaScript {
                pageFiles.append(SiteExportFile(
                    path: Self.joinedPath(pageFilesDirectory, "page.js"),
                    contents: pageScripts(
                        for: page,
                        theme: site.theme,
                        assetPrefix: rootPrefix + "assets",
                        packageAssetPrefix: documentPackageAssetPrefix,
                        assets: assets,
                        site: site
                    )
                ))
            }
            return pageFiles
        }
        files.append(.init(path: "files/site.css", contents: stylesheet(for: site, assets: assets)))
        let sitePackages = ComponentArtifactPlan.sitePackages(in: site)
        files.append(contentsOf: FoundryWebLibraryRegistry.exportFiles(for: sitePackages))
        files.append(contentsOf: componentAssetFiles(for: sitePackages))
        files.append(contentsOf: site.assets.compactMap { asset in
            assets[asset.id].map { SiteExportFile(path: site.publishedPath(for: asset), data: $0.data) }
        })
        if site.generatesSitemap, let baseURL = validPublicURL(site.publicURL) {
            files.append(.init(path: "sitemap.xml", contents: sitemap(for: site, baseURL: baseURL)))
        }
        if site.generatesRobotsTXT {
            files.append(.init(path: "robots.txt", contents: robotsTXT(for: site)))
        }
        return SiteExportBundle(files: files.sorted { $0.path < $1.path })
    }

    private func pageRequiresJavaScript(_ page: Page) -> Bool {
        page.components.flatMap(\.flattened).contains { node in
            if !ComponentArtifactPlan.htmlArtifact(for: node, suffix: "JavaScript")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return node.type.definition.package?.declaresJavaScript(in: .instance, .page) == true
        }
    }

    static func requiresPhp(_ page: Page) -> Bool {
        ComponentArtifactPlan(page: page).nodes.contains {
            ComponentRegistry.definition(for: $0.type).package?.manifest.requiresPhp == true
        }
    }

    static func outputPath(for page: Page, in site: Site) -> String {
        let pageExtension = requiresPhp(page) ? "php" : "html"
        guard page.slug != "index" else { return "index.\(pageExtension)" }
        let directory = PageRouteResolver.pathSegments(
            for: page,
            pages: site.pages,
            folders: site.pageFolders
        ).joined(separator: "/")
        return joinedPath(directory, "index.\(pageExtension)")
    }

    static func customExportPath(for asset: ProjectAsset, in site: Site) -> String? {
        asset.exportDirectory == nil ? nil : site.publishedPath(for: asset)
    }

    private static func joinedPath(_ components: String...) -> String {
        components.filter { !$0.isEmpty }.joined(separator: "/")
    }

    private func joinedPath(_ prefix: String, _ suffix: String) -> String {
        prefix.isEmpty ? suffix : prefix + "/" + suffix
    }

    private func render(page: Page, language: String, theme: Theme, stylesheetPaths: [String], scriptPaths: [String], assetPrefix: String, packageAssetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        let body = page.components.map { render($0, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site) }.joined(separator: "\n")
        let pageTitle = page.metadata.browserTitle.isEmpty ? page.title : page.metadata.browserTitle
        let browserTitle = pageTitle + site.titleSuffix
        let metadata = metadataHTML(for: page, browserTitle: browserTitle, assetPrefix: assetPrefix, assets: assets, site: site)
        let headStart = placedHTML(for: page, placement: .headStart, packageAssetPrefix: packageAssetPrefix)
        let headEnd = placedHTML(for: page, placement: .headEnd, packageAssetPrefix: packageAssetPrefix)
        let bodyStart = placedHTML(for: page, placement: .bodyStart, packageAssetPrefix: packageAssetPrefix)
        let bodyEnd = placedHTML(for: page, placement: .bodyEnd, packageAssetPrefix: packageAssetPrefix)
        let scripts = scriptPaths.map { "<script src=\"\($0)\"></script>" }.joined(separator: "\n")
        let php = packagePHP(for: page, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site)
        let customHeadCode = site.customCodeEnabled ? site.headCode : ""
        let customBodyStartCode = site.customCodeEnabled ? site.bodyStartCode : ""
        let customBodyEndCode = site.customCodeEnabled ? site.bodyEndCode : ""
        let analyticsCode = site.customCodeEnabled ? site.analyticsCode : ""
        let documentLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = """
        <!doctype html>
        <html lang="\(escapeAttribute(documentLanguage.isEmpty ? "en" : documentLanguage))">
        <head>
        \(headStart)
        \(customHeadCode)
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(browserTitle))</title>
        \(metadata)
        \(stylesheetPaths.map { "  <link rel=\"stylesheet\" href=\"\($0)\">" }.joined(separator: "\n"))
        \(analyticsCode)
        \(headEnd)
        </head>
        <body>
        \(customBodyStartCode)\(bodyStart)\(body)\(bodyEnd)\(scripts)\(customBodyEndCode)
        </body>
        </html>
        """
        return php.isEmpty ? document : php + "\n" + document
    }

    private func packagePHP(for page: Page, theme: Theme, assetPrefix: String, packageAssetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        let nodes = page.components.flatMap(\.flattened)
        let instancePHP = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package else { return nil }
            let source = package.instancePHP
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                source,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site),
                    slots: [:],
                    assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier)
                )
            )
        }
        var seenPackages: Set<String> = []
        let sharedPHP = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = package.pagePHP
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                source,
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    slots: [:],
                    assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier)
                )
            )
        }
        return (instancePHP + sharedPHP).joined(separator: "\n")
    }

    private func pageScripts(for page: Page, theme: Theme, assetPrefix: String, packageAssetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        let nodes = page.components.flatMap(\.flattened)
        let instanceScripts = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package else { return nil }
            let source = [package.instanceJavaScript, ComponentArtifactPlan.htmlArtifact(for: node, suffix: "JavaScript")]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                source,
                context: .init(instanceID: node.id, packageIdentifier: package.manifest.identifier, properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site), slots: [:], assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier))
            )
        }
        var seenPackages: Set<String> = []
        let sharedScripts = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = package.pageJavaScript
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(source, context: .init(instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), packageIdentifier: package.manifest.identifier, properties: [:], slots: [:], assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier)))
        }
        let source = (instanceScripts + sharedScripts).joined(separator: "\n")
        return source
    }

    private func placedHTML(for page: Page, placement: ComponentPackageTemplateFile.Placement, packageAssetPrefix: String) -> String {
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
                slots: [:],
                assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier)
            )
            return templates.map { ComponentTemplateRenderer.render($0.contents, context: context) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func metadataHTML(
        for page: Page,
        browserTitle: String,
        assetPrefix: String,
        assets: [UUID: ProjectAssetContent],
        site: Site
    ) -> String {
        var tags: [String] = []
        let description = page.metadata.description.isEmpty ? site.defaultDescription : page.metadata.description
        if !description.isEmpty {
            tags.append("<meta name=\"description\" content=\"\(escapeAttribute(description))\">")
        }

        let socialTitle = page.metadata.socialTitle.isEmpty ? browserTitle : page.metadata.socialTitle
        tags.append("<meta property=\"og:title\" content=\"\(escapeAttribute(socialTitle))\">")

        if !site.allowsSearchIndexing {
            tags.append("<meta name=\"robots\" content=\"noindex, nofollow\">")
        }

        if site.generatesCanonicalURLs,
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
        let socialImage = page.metadata.socialImage.isEmpty ? site.defaultSocialImage : page.metadata.socialImage
        if !socialImage.isEmpty {
            let source = exportSource(socialImage, assetPrefix: assetPrefix, assets: assets, site: site)
            if !source.isEmpty {
                tags.append("<meta property=\"og:image\" content=\"\(escapeAttribute(source))\">")
            }
        }
        if !site.favicon.isEmpty {
            let source = exportSource(site.favicon, assetPrefix: assetPrefix, assets: assets, site: site)
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
        let path = PageRouteResolver.pathSegments(
            for: page,
            pages: site.pages,
            folders: site.pageFolders
        ).joined(separator: "/")
        return baseURL + "/" + path + "/"
    }

    private func sitemap(for site: Site, baseURL: String) -> String {
        let entries = site.pages.map { page in
            "  <url><loc>\(escape(absoluteURL(for: page, in: site, baseURL: baseURL)))</loc></url>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        \(entries)
        </urlset>
        """
    }

    private func robotsTXT(for site: Site) -> String {
        var lines = ["User-agent: *", site.allowsSearchIndexing ? "Allow: /" : "Disallow: /"]
        if site.generatesSitemap, let baseURL = validPublicURL(site.publicURL) {
            lines.append("Sitemap: \(baseURL)/sitemap.xml")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(_ node: ComponentNode, theme: Theme, assetPrefix: String, packageAssetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site) -> String {
        switch node.type.definition.renderKind {
        case .package:
            guard let package = node.type.definition.package else {
                return missingPackageHTML(
                    node,
                    theme: theme,
                    assetPrefix: assetPrefix,
                    packageAssetPrefix: packageAssetPrefix,
                    assets: assets,
                    site: site
                )
            }
            let slots = Dictionary(uniqueKeysWithValues: package.manifest.slots.map { slot in
                let children = node.children.filter { ($0.slotID ?? package.manifest.slots.first?.id) == slot.id }
                return (slot.id, children.map { render($0, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site) }.joined())
            })
            let rendered = ComponentTemplateRenderer.render(
                package.htmlTemplate,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site),
                    slots: slots,
                    componentClass: componentClass(node) + " " +
                        ComponentTemplateRenderer.packageClass(for: package.manifest.identifier),
                    componentAttributes: "id=\"foundry-\(node.id.uuidString.lowercased())\"",
                    assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier),
                    richTextLinkContext: .init(
                        pages: site.pages,
                        folders: site.pageFolders,
                        assets: site.assets,
                        assetLibrary: site.assetLibrary,
                        publicURL: site.publicURL,
                        absoluteURL: false
                    )
                )
            )
            if package.htmlTemplate.contains("{{ component.attributes }}") ||
                package.htmlTemplate.contains("{{component.attributes}}") {
                return rendered
            }
            return "<div id=\"foundry-\(node.id.uuidString.lowercased())\" class=\"\(componentClass(node)) \(ComponentTemplateRenderer.packageClass(for: package.manifest.identifier))\">\(rendered)</div>"
        case .unavailable:
            return missingPackageHTML(
                node,
                theme: theme,
                assetPrefix: assetPrefix,
                packageAssetPrefix: packageAssetPrefix,
                assets: assets,
                site: site
            )
        }
    }

    private func exportSource(
        _ source: String,
        assetPrefix: String,
        assets: [UUID: ProjectAssetContent],
        site: Site
    ) -> String {
        guard let id = source.foundryAssetID else { return source }
        guard let content = assets[id] else { return "" }
        return siteRootPrefix(from: assetPrefix) + site.publishedPath(for: content.asset)
    }

    private func siteRootPrefix(from assetPrefix: String) -> String {
        let managedAssetsPath = "assets"
        guard assetPrefix.hasSuffix(managedAssetsPath) else { return "" }
        return String(assetPrefix.dropLast(managedAssetsPath.count))
    }

    private func stylesheet(for site: Site, assets: [UUID: ProjectAssetContent]) -> String {
        let theme = site.theme
        let sitePackages = ComponentArtifactPlan.sitePackages(in: site)
        return """
        \(theme.fontSourceCSS(
            assets: assets,
            destination: .export,
            exportedSource: { "../" + site.publishedPath(for: $0) }
        ))
        :root{font-size:16px;--foundry-color-background:\(theme.colors.background);--foundry-color-surface:\(theme.colors.surface);--foundry-color-text:\(theme.colors.text);--foundry-color-accent:\(theme.colors.accent);--foundry-color-links:\(theme.colors.links);--foundry-font-body:\(theme.typography.bodyFont.cssFamily);--foundry-font-heading:\(theme.typography.headingFont.cssFamily);--foundry-font-monospace:\(theme.typography.monospacedFont.cssFamily);\(theme.customFontCSSVariables)\(theme.fontSizeCSSVariables)\(theme.spacingCSSVariables)}
        \(theme.screens.containerCSS)
        *,*::before,*::after{box-sizing:border-box}
        html,body{min-height:100%}
        body{margin:0;background:var(--foundry-color-background);color:var(--foundry-color-text);font-family:var(--foundry-font-body);font-size:var(--foundry-font-size-base);line-height:var(--foundry-font-size-base-line-height);display:flex;flex-direction:column;align-items:stretch}
        a{color:var(--foundry-color-links)}
        h1,h2,h3,h4,h5,h6,.foundry-heading{font-family:var(--foundry-font-heading)}code,pre,kbd,samp{font-family:var(--foundry-font-monospace)}
        .foundry-container{width:100%;max-width:var(--foundry-container-width)!important}.foundry-button{display:block;width:fit-content;text-decoration:none;font-weight:600}.foundry-columns{display:grid}.foundry-image{display:block;width:100%;height:auto}.foundry-spacer{min-height:8px}
        \(FoundryWebLibraryRegistry.exportCSS(for: sitePackages))
        \(sitePackageStyles(for: site))
        """
    }

    private func componentAssetFiles(for packages: [LoadedComponentPackage]) -> [SiteExportFile] {
        packages.flatMap { package in
            package.manifest.assets.compactMap { path in
                guard isSafeRelativePath(path),
                      let data = try? Data(contentsOf: package.resourceRootURL.appending(path: path)) else {
                    return nil
                }
                return SiteExportFile(
                    path: "files/components/\(package.manifest.identifier)/\(path)",
                    data: data
                )
            }
        }
    }

    private func responsiveStyles(
        for page: Page,
        in site: Site,
        assetPrefix: String,
        packageAssetPrefix: String,
        assets: [UUID: ProjectAssetContent]
    ) -> String {
        let nodes = page.components.flatMap(\.flattened)
        return ResponsiveBreakpoint.allCases.dropFirst().compactMap { breakpoint in
            guard let minimumWidth = breakpoint.minimumWidth(in: site.theme.screens) else { return nil }
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
                                assetPrefix: assetPrefix,
                                assets: assets,
                                site: site
                            ),
                            slots: [:],
                            componentClass: componentClass(resolved),
                            assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier)
                        )
                    )
                    let scopedCSS = ComponentTemplateRenderer.scopedCSS(
                        css,
                        packageIdentifier: package.manifest.identifier
                    )
                    return scopedCSS
                }
                return nil
            }.joined()
            return rules.isEmpty ? nil : "@media(min-width:\(minimumWidth)px){\(rules)}"
        }.joined(separator: "\n")
    }

    private func componentClass(_ node: ComponentNode) -> String {
        "c-" + node.id.uuidString.lowercased()
    }

    private func pageStyles(
        for page: Page,
        site: Site,
        assetPrefix: String,
        packageAssetPrefix: String,
        assets: [UUID: ProjectAssetContent]
    ) -> String {
        let nodes = ComponentArtifactPlan(page: page).nodes
        let instanceStyles = nodes.compactMap { node in
            guard let package = node.type.definition.package else { return nil }
            let css = ComponentTemplateRenderer.render(
                [package.css, ComponentArtifactPlan.htmlArtifact(for: node, suffix: "CSS")].filter { !$0.isEmpty }.joined(separator: "\n"),
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(
                        node,
                        theme: site.theme,
                        assetPrefix: assetPrefix,
                        assets: assets,
                        site: site
                    ),
                    slots: [:],
                    componentClass: componentClass(node),
                    assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier)
                )
            )
            return ComponentTemplateRenderer.scopedCSS(css, packageIdentifier: package.manifest.identifier)
        }.joined(separator: "\n")
        let pagePackageStyles = ComponentArtifactPlan(page: page).packages.compactMap { package -> String? in
            guard !package.pageCSS.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                package.pageCSS,
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    slots: [:],
                    assetBasePath: joinedPath(packageAssetPrefix, package.manifest.identifier)
                )
            )
        }.joined(separator: "\n")
        let responsiveStyles = responsiveStyles(
            for: page,
            in: site,
            assetPrefix: assetPrefix,
            packageAssetPrefix: packageAssetPrefix,
            assets: assets
        )
        return [instanceStyles, pagePackageStyles, responsiveStyles]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func sitePackageStyles(for site: Site) -> String {
        ComponentArtifactPlan.sitePackages(in: site).compactMap { package -> String? in
            guard !package.siteCSS.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                package.siteCSS,
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    slots: [:],
                    assetBasePath: "components/\(package.manifest.identifier)"
                )
            )
        }.joined(separator: "\n")
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

    private func packageProperties(
        _ node: ComponentNode,
        theme: Theme,
        assetPrefix: String,
        assets: [UUID: ProjectAssetContent],
        site: Site
    ) -> [String: ComponentPackageValue] {
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
            if case .asset = definition.control,
               case .url(let source) = value {
                return (
                    definition.key.rawValue,
                    .string(exportSource(source, assetPrefix: assetPrefix, assets: assets, site: site))
                )
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
            if case .themeFontFamily = definition.control {
                return (definition.key.rawValue, .string(theme.fontCSSVariable(for: node.property(definition.key))))
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
        for definition in node.type.definition.properties {
            guard case .link(let absoluteURL) = definition.control,
                  case .link(let link) = node.propertyValue(definition.key) else { continue }
            let resolved = ComponentLinkResolver.resolve(
                link, pages: site.pages, folders: site.pageFolders, assets: site.assets,
                assetLibrary: site.assetLibrary,
                publicURL: site.publicURL, absoluteURL: absoluteURL
            )
            values[definition.key.rawValue] = .string(resolved.href)
            values[definition.key.rawValue + ".target"] = .string(resolved.target)
            values[definition.key.rawValue + ".attributes"] = .string(resolved.attributes)
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
        case .packageColor(let value):
            raw = value.source
        case .packageFontSize(let value):
            raw = value.source
        case .packageSpacing(let value):
            raw = value.sources.joined(separator: " ")
        }
        return raw.filter { !";{}<>".contains($0) }
    }

    private func missingPackageHTML(
        _ node: ComponentNode,
        theme: Theme,
        assetPrefix: String,
        packageAssetPrefix: String,
        assets: [UUID: ProjectAssetContent],
        site: Site
    ) -> String {
        if let preview = node.missingPackageSnapshot?.previewHTML { return preview }
        return node.children.map {
            render(
                $0,
                theme: theme,
                assetPrefix: assetPrefix,
                packageAssetPrefix: packageAssetPrefix,
                assets: assets,
                site: site
            )
        }.joined()
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty
            && !path.hasPrefix("/")
            && !components.contains("")
            && !components.contains(".")
            && !components.contains("..")
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

nonisolated extension ComponentNode {
    var flattened: [ComponentNode] {
        [self] + children.flatMap(\.flattened)
    }
}
