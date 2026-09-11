import Foundation

nonisolated struct StaticSiteRenderer: SiteRendering {
    let environment: ComponentTemplateEnvironment

    init(environment: ComponentTemplateEnvironment = .published) {
        self.environment = environment
    }

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
            let pageStylesPackageAssetPrefix = ""
            let documentPackageAssetPrefix = "files"
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
            let pagePackages = ComponentArtifactPlan(page: page).packages
            pageFiles.append(contentsOf: componentAssetFiles(
                for: pagePackages,
                scope: .page,
                destinationDirectory: pageFilesDirectory
            ))
            return pageFiles
        }
        files.append(.init(path: "files/site.css", contents: stylesheet(for: site, assets: assets)))
        let sitePackages = ComponentArtifactPlan.sitePackages(in: site)
        files.append(contentsOf: FoundryWebLibraryRegistry.exportFiles(for: sitePackages))
        files.append(contentsOf: componentAssetFiles(
            for: sitePackages,
            scope: .site,
            destinationDirectory: "assets"
        ))
        let managedAssetPaths = site.assetLibrary.managedExportPaths()
        files.append(contentsOf: site.assets.compactMap { asset in
            assets[asset.id].map {
                SiteExportFile(
                    path: site.publishedPath(for: asset, managedAssetPaths: managedAssetPaths),
                    data: $0.data,
                    contentFingerprint: $0.digest?.map { String(format: "%02x", $0) }.joined()
                )
            }
        })
        files.append(contentsOf: imageRenditionFiles(site: site, assets: assets))
        if site.generatesSitemap, let baseURL = validPublicURL(site.publicURL) {
            files.append(.init(path: "sitemap.xml", contents: sitemap(for: site, baseURL: baseURL)))
        }
        if site.generatesRobotsTXT {
            files.append(.init(path: "robots.txt", contents: robotsTXT(for: site)))
        }
        let normalized = normalizedExportFiles(files)
        return SiteExportBundle(files: normalized.files, errors: normalized.errors)
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

    static func requiresPHP(_ page: Page) -> Bool {
        ComponentArtifactPlan(page: page).nodes.contains {
            ComponentRegistry.definition(for: $0.type).package?.manifest.requiresPHP == true
        }
    }

    static func outputPath(for page: Page, in site: Site) -> String {
        let pageExtension = requiresPHP(page) ? "php" : "html"
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
        let body = page.components.map { render($0, page: page, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site) }.joined(separator: "\n")
        let pageTitle = page.metadata.browserTitle.isEmpty ? page.title : page.metadata.browserTitle
        let browserTitle = pageTitle + site.titleSuffix
        let metadata = metadataHTML(for: page, browserTitle: browserTitle, assetPrefix: assetPrefix, assets: assets, site: site)
        let headStart = placedHTML(for: page, placement: .headStart, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, site: site)
        let headEnd = placedHTML(for: page, placement: .headEnd, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, site: site)
        let bodyStart = placedHTML(for: page, placement: .bodyStart, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, site: site)
        let bodyEnd = placedHTML(for: page, placement: .bodyEnd, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, site: site)
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
                    templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page),
                    slots: [:],
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment
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
                    templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page),
                    slots: [:],
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment
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
                context: .init(instanceID: node.id, packageIdentifier: package.manifest.identifier, properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site), templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page), slots: [:], assetBasePath: packageAssetPrefix, assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix), siteBaseURL: siteBaseURL(for: site), pageURL: pageURL(for: page, in: site), siteRootPath: siteRootPath(for: assetPrefix), siteAssetsPath: assetPrefix, environment: environment)
            )
        }
        var seenPackages: Set<String> = []
        let sharedScripts = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = package.pageJavaScript
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(source, context: .init(instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), packageIdentifier: package.manifest.identifier, properties: [:], templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page), slots: [:], assetBasePath: packageAssetPrefix, assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix), siteBaseURL: siteBaseURL(for: site), pageURL: pageURL(for: page, in: site), siteRootPath: siteRootPath(for: assetPrefix), siteAssetsPath: assetPrefix, environment: environment))
        }
        let source = (instanceScripts + sharedScripts).joined(separator: "\n")
        return source
    }

    private func placedHTML(for page: Page, placement: ComponentPackageTemplateFile.Placement, assetPrefix: String, packageAssetPrefix: String, site: Site) -> String {
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
                templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page),
                slots: [:],
                assetBasePath: packageAssetPrefix,
                assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                siteBaseURL: siteBaseURL(for: site),
                pageURL: pageURL(for: page, in: site),
                siteRootPath: siteRootPath(for: assetPrefix),
                siteAssetsPath: assetPrefix,
                environment: environment
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

    private func render(_ node: ComponentNode, page: Page, theme: Theme, assetPrefix: String, packageAssetPrefix: String, assets: [UUID: ProjectAssetContent], site: Site, parentComponentID: UUID? = nil) -> String {
        switch node.type.definition.renderKind {
        case .package:
            guard let package = node.type.definition.package else {
                return missingPackageHTML(
                    node,
                    page: page,
                    theme: theme,
                    assetPrefix: assetPrefix,
                    packageAssetPrefix: packageAssetPrefix,
                    assets: assets,
                    site: site
                )
            }
            guard (try? package.preparePayload()) != nil else {
                return missingPackageHTML(
                    node,
                    page: page,
                    theme: theme,
                    assetPrefix: assetPrefix,
                    packageAssetPrefix: packageAssetPrefix,
                    assets: assets,
                    site: site
                )
            }
            let slots = Dictionary(uniqueKeysWithValues: package.manifest.slots.map { slot in
                let children = node.children.filter {
                    ($0.slotID ?? (package.hasDropZone ? nil : package.manifest.slots.first?.id)) == slot.id
                }
                return (slot.id, children.map { render($0, page: page, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site, parentComponentID: node.id) }.joined())
            })
            let dropZones = Dictionary(uniqueKeysWithValues: package.dropZoneNames.enumerated().map { index, name in
                let slotID = package.dropZoneSlotID(for: name)
                let children = node.children.filter { $0.slotID == slotID || (index == 0 && $0.slotID == nil) }
                return (name, children.map {
                    render($0, page: page, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site, parentComponentID: node.id)
                }.joined())
            })
            let anchor = ComponentAnchorValidator.validated(node.anchor)
            let anchorAttribute = anchor.map { " id=\"\(escapeAttribute($0))\"" } ?? ""
            let customAttributes = ComponentRootAttributeValidator.validAttributes(node.rootAttributes ?? []).map {
                " \($0.name)=\"\(escapeAttribute($0.value))\""
            }.joined()
            let relationshipAttributes = "data-foundry-component data-foundry-package=\"\(escapeAttribute(package.manifest.identifier))\"" +
                (parentComponentID.map { " data-foundry-parent=\"\($0.uuidString)\"" } ?? "")
            let rendered = ComponentTemplateRenderer.render(
                package.htmlTemplate,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site),
                    templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page),
                    slots: slots,
                    dropZones: dropZones,
                    componentClass: componentClass(node) + " " +
                        ComponentTemplateRenderer.packageClass(for: package.manifest.identifier),
                    componentAttributes: "data-foundry-id=\"\(node.id.uuidString)\" \(relationshipAttributes)\(anchorAttribute)\(customAttributes)",
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment,
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
            return "<div data-foundry-id=\"\(node.id.uuidString)\" \(relationshipAttributes) class=\"\(componentClass(node)) \(ComponentTemplateRenderer.packageClass(for: package.manifest.identifier))\">\(rendered)</div>"
        case .unavailable:
            return missingPackageHTML(
                node,
                page: page,
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
        :root{font-size:16px;--foundry-color-background:\(theme.colors.background);--foundry-color-surface:\(theme.colors.surface);--foundry-color-text:\(theme.colors.text);--foundry-color-accent:\(theme.colors.accent);--foundry-color-links:\(theme.colors.links);--foundry-font-body:\(theme.typography.bodyFont.cssFamily);--foundry-font-heading:\(theme.typography.headingFont.cssFamily);--foundry-font-monospace:\(theme.typography.monospacedFont.cssFamily);\(theme.customFontCSSVariables)\(theme.fontSizeCSSVariables)\(theme.spacingCSSVariables)\(theme.shadowCSSVariables)\(theme.borderCSSVariables)}
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

    private func componentAssetFiles(
        for packages: [LoadedComponentPackage],
        scope: ComponentPackageAsset.Scope,
        destinationDirectory: String
    ) -> [SiteExportFile] {
        packages.flatMap { package in
            package.manifest.assets
                .filter { $0.scope == scope }
                .flatMap { declaration in
                    expandedAssetFiles(
                        declaration,
                        from: package.resourceRootURL,
                        destinationDirectory: destinationDirectory
                    )
                }
        }
    }

    private func normalizedExportFiles(_ files: [SiteExportFile]) -> (files: [SiteExportFile], errors: [String]) {
        var filesByPath: [String: SiteExportFile] = [:]
        var errors: [String] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            if let existing = filesByPath[file.path] {
                if existing.data != file.data {
                    errors.append("Two assets publish to '\(file.path)' with different contents.")
                }
            } else {
                filesByPath[file.path] = file
            }
        }
        return (filesByPath.values.sorted(by: { $0.path < $1.path }), errors)
    }

    private func expandedAssetFiles(
        _ declaration: ComponentPackageAsset,
        from resourceRootURL: URL,
        destinationDirectory: String
    ) -> [SiteExportFile] {
        guard isSafeRelativePath(declaration.path) else { return [] }
        let sourceURL = resourceRootURL.appending(path: declaration.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else { return [] }

        if !isDirectory.boolValue {
            guard let data = try? Data(contentsOf: sourceURL) else { return [] }
            let destinationName = declaration.scope == .page
                ? sourceURL.lastPathComponent
                : declaration.path
            return [.init(path: Self.joinedPath(destinationDirectory, destinationName), data: data)]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { item -> SiteExportFile? in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: fileURL) else { return nil }
            let sourceComponents = sourceURL.standardizedFileURL.pathComponents
            let fileComponents = fileURL.standardizedFileURL.pathComponents
            guard fileComponents.starts(with: sourceComponents) else { return nil }
            let relativePath = fileComponents.dropFirst(sourceComponents.count).joined(separator: "/")
            let outputPath = Self.joinedPath(destinationDirectory, declaration.path, relativePath)
            return .init(path: outputPath, data: data)
        }
    }

    private func templateAssetPaths(
        for package: LoadedComponentPackage,
        pageAssetPrefix: String,
        siteAssetPrefix: String
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: package.manifest.assets.map { declaration in
            let destination: String
            switch declaration.scope {
            case .page:
                let sourceURL = package.resourceRootURL.appending(path: declaration.path)
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                let name = exists && isDirectory.boolValue
                    ? declaration.path
                    : sourceURL.lastPathComponent
                destination = joinedPath(pageAssetPrefix, name)
            case .site:
                destination = joinedPath(siteAssetPrefix, declaration.path)
            }
            return (declaration.path, destination)
        })
    }

    private func siteBaseURL(for site: Site) -> String {
        validPublicURL(site.publicURL) ?? ""
    }

    private func pageURL(for page: Page, in site: Site) -> String {
        guard let baseURL = validPublicURL(site.publicURL) else { return "" }
        return absoluteURL(for: page, in: site, baseURL: baseURL)
    }

    private func siteRootPath(for siteAssetsPath: String) -> String {
        let prefix = siteRootPrefix(from: siteAssetsPath)
        guard !prefix.isEmpty else { return "." }
        return String(prefix.dropLast())
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
                            templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page),
                            slots: [:],
                            componentClass: componentClass(resolved),
                            assetBasePath: packageAssetPrefix,
                            assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                            siteBaseURL: siteBaseURL(for: site),
                            pageURL: pageURL(for: page, in: site),
                            siteRootPath: siteRootPath(for: assetPrefix),
                            siteAssetsPath: assetPrefix,
                            environment: environment
                        )
                    )
                    let scopedCSS = ComponentTemplateRenderer.scopedCSS(
                        css,
                        packageIdentifier: package.manifest.identifier,
                        instanceID: resolved.id
                    )
                    return scopedCSS
                }
                return nil
            }.joined()
            return rules.isEmpty ? nil : "@media(min-width:\(minimumWidth)px){\(rules)}"
        }.joined(separator: "\n")
    }

    private func componentClass(_ node: ComponentNode) -> String {
        ["c-" + node.id.uuidString.lowercased(), ComponentRootAttributeValidator.normalizedClasses(node.customClasses)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
                    templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page),
                    slots: [:],
                    componentClass: componentClass(node),
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment
                )
            )
            return ComponentTemplateRenderer.scopedCSS(
                css,
                packageIdentifier: package.manifest.identifier,
                instanceID: node.id
            )
        }.joined(separator: "\n")
        let pagePackageStyles = ComponentArtifactPlan(page: page).packages.compactMap { package -> String? in
            guard !package.pageCSS.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                package.pageCSS,
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    templateValues: ComponentNavigationTemplateValues.values(site: site, currentPage: page),
                    slots: [:],
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment
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
                    assetBasePath: "",
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: "", siteAssetPrefix: "../assets"),
                    siteBaseURL: siteBaseURL(for: site),
                    siteRootPath: "..",
                    siteAssetsPath: "../assets",
                    environment: environment
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
        case .packageShadow(let value): .string(value.source)
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
            if case .image = definition.control {
                return (
                    definition.key.rawValue,
                    resolvedImageValue(value, assetPrefix: assetPrefix, assets: assets, site: site)
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
            if case .themeFontSize = definition.control {
                return (definition.key.rawValue, .string(theme.fontSizeCSSVariable(for: node.property(definition.key))))
            }
            if case .packageFontSize(let themeValues) = definition.control,
               case .packageFontSize(let fontSizeValue) = value {
                let resolved = !themeValues || ComponentThemeValueSelection.isManualCustom(fontSizeValue.source)
                    ? fontSizeValue.customValue : theme.fontSizeCSSVariable(for: fontSizeValue.source)
                return (definition.key.rawValue, .string(resolved))
            }
            if case .packageShadow = definition.control,
               case .packageShadow(let shadowValue) = value {
                return (
                    definition.key.rawValue,
                    .string(ComponentPackageShadowResolver.resolve(shadowValue, theme: theme))
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
                    let suffix = ".rendition.\(rendition.id)"
                    let href: String
                    if let assetID = source.foundryAssetID, let content = assets[assetID],
                       max(content.asset.pixelWidth ?? 0, content.asset.pixelHeight ?? 0) > rendition.effectiveMaximumDimension {
                        href = siteRootPrefix(from: assetPrefix) + imageRenditionPath(
                            assetID: assetID,
                            maximumDimension: rendition.effectiveMaximumDimension,
                            fileExtension: ComponentImageProcessor.renditionFileExtension(
                                data: content.data,
                                fallback: content.asset.imageMetadata.fileExtension
                            )
                        )
                    } else {
                        href = values[property.id]?.stringValue ?? ""
                    }
                    values[property.id + suffix] = .string(href)
                    values[property.id + suffix + ".href"] = .string(href)
                }
            }
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

    private func resolvedImageValue(
        _ value: ComponentProperty.Value,
        assetPrefix: String,
        assets: [UUID: ProjectAssetContent],
        site: Site
    ) -> ComponentPackageValue {
        switch value {
        case .url(let source):
            .string(exportSource(source, assetPrefix: assetPrefix, assets: assets, site: site))
        case .array(let values):
            .array(values.map {
                resolvedImageValue($0, assetPrefix: assetPrefix, assets: assets, site: site)
            })
        default:
            packageValue(value)
        }
    }

    private func imageRenditionFiles(
        site: Site,
        assets: [UUID: ProjectAssetContent]
    ) -> [SiteExportFile] {
        var requests = Set<ImageRenditionRequest>()
        for page in site.pages {
            for node in page.components.flatMap(\.flattened) {
                guard let package = node.type.definition.package else { continue }
                for property in package.manifest.properties where property.control.type == .image {
                    guard case .url(let source) = node.propertyValue(.init(rawValue: property.id)),
                          let assetID = source.foundryAssetID else { continue }
                    for rendition in property.renditions {
                        requests.insert(.init(assetID: assetID, maximumDimension: rendition.effectiveMaximumDimension))
                    }
                }
            }
        }
        return requests.compactMap { request in
            guard let content = assets[request.assetID],
                  let output = ComponentImageProcessor.rendition(
                    data: content.data,
                    filename: content.asset.filename,
                    mimeType: content.asset.mediaType,
                    maximumDimension: request.maximumDimension
                  ) else { return nil }
            return SiteExportFile(
                path: imageRenditionPath(
                    assetID: request.assetID,
                    maximumDimension: request.maximumDimension,
                    fileExtension: output.metadata.fileExtension
                ),
                data: output.data
            )
        }
    }

    private func imageRenditionPath(assetID: UUID, maximumDimension: Int, fileExtension: String) -> String {
        "assets/renditions/\(assetID.uuidString.lowercased())-\(maximumDimension).\(fileExtension)"
    }

    private struct ImageRenditionRequest: Hashable {
        let assetID: UUID
        let maximumDimension: Int
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
        case .packageShadow(let value):
            raw = value.source
        }
        return raw.filter { !";{}<>".contains($0) }
    }

    private func missingPackageHTML(
        _ node: ComponentNode,
        page: Page,
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
                page: page,
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
