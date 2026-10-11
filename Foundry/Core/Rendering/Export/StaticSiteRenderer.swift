import Foundation

nonisolated struct StaticSiteRenderer: SiteRendering {
    let environment: PartTemplateEnvironment
    private let navigationValuesCache = PartTemplateValuesCache()

    init(environment: PartTemplateEnvironment = .published) {
        self.environment = environment
    }

    /// Navigation values walk the whole site; the export path builds a
    /// template context per part instance, so they are memoized per page.
    private func navigationValues(for page: Page, in site: Site) -> [String: PartPackageValue] {
        navigationValuesCache.values(for: page.id) {
            PartNavigationTemplateValues.values(site: site, currentPage: page)
        }
    }

    func render(site: Site) -> SiteExportBundle {
        render(site: site, assets: [:])
    }

    func render(site: Site, assets: ProjectAssetContents) -> SiteExportBundle {
        var files: [SiteExportFile] = []
        // The collecting API remains for export callers; preview uses the same
        // generator with a disk sink instead of retaining the complete bundle.
        do {
            try generate(site: site, assets: assets) { files.append($0) }
            try Task.checkCancellation()
        } catch {
            return SiteExportBundle(files: [], errors: [error.localizedDescription])
        }
        let normalized = normalizedExportFiles(files)
        let outputFiles = environment == .published
            ? PublishedOutputProcessor.process(normalized.files, for: site)
            : normalized.files
        return SiteExportBundle(
            files: outputFiles,
            errors: normalized.errors
        )
    }

    func generate(site: Site, assets: ProjectAssetContents,
                  reusingPages: [UUID: [SiteExportFile]] = [:],
                  pageIDs: Set<UUID>? = nil, includeSharedFiles: Bool = true,
                  stageTiming: (String, Duration) -> Void = { _, _ in },
                  pageOutput: (UUID, [String]) -> Void = { _, _ in },
                  emit: (SiteExportFile) throws -> Void) throws {
        var stageStart = ContinuousClock.now
        let webIconPlan = WebIconGenerator.exportPlan(
            storedAssets: site.webIconAssets,
            contents: assets
        )
        if includeSharedFiles && site.customCodeEnabled {
            if !site.cssCode.isEmpty {
                try emit(SiteExportFile(path: "files/custom-site.css", contents: site.cssCode))
            }
            if !site.javaScriptCode.isEmpty {
                try emit(SiteExportFile(path: "files/custom-site.js", contents: site.javaScriptCode))
            }
        }
        var sitePackages: [LoadedPartPackage] = []
        var sitePackageIdentifiers = Set<String>()
        stageTiming("setup", stageStart.duration(to: .now))
        stageStart = .now
        for page in site.pages {
            try Task.checkCancellation()
            if !includeSharedFiles, let pageIDs, !pageIDs.contains(page.id) { continue }
            let pagePackages = PartArtifactPlan(page: page).packages
            for package in pagePackages where sitePackageIdentifiers.insert(package.manifest.identifier).inserted {
                sitePackages.append(package)
            }
            if let pageIDs, !pageIDs.contains(page.id) { continue }
            if let files = reusingPages[page.id] {
                for file in files { try emit(file) }
                pageOutput(page.id, files.map(\.path))
                continue
            }
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
            let libraryPrefix = rootPrefix + "files/libraries"
            let scriptsBefore = FoundryWebLibraryRegistry.exportScripts(
                for: pagePackages,
                prefix: libraryPrefix,
                placement: .beforePage
            )
            let scriptsAfter = FoundryWebLibraryRegistry.exportScripts(
                for: pagePackages,
                prefix: libraryPrefix,
                placement: .afterPage
            )
            let pageFilesDirectory = Self.joinedPath(directory, "files")
            let pageStylesAssetPrefix = String(
                repeating: "../",
                count: directory.split(separator: "/").count + 1
            ) + "assets"
            let pageStylesPackageAssetPrefix = ""
            let documentPackageAssetPrefix = "files"
            var pageFiles = [SiteExportFile(
                path: Self.outputPath(for: page, in: site),
                contents: HTMLTagWhitespaceCleanup.clean(render(
                    page: page,
                    language: site.language,
                    theme: site.theme,
                    stylesheetPaths: [rootPrefix + "files/site.css", "files/page.css"],
                    scripts: scriptsBefore + (includesPageJavaScript ? [FoundryWebScript(path: "files/page.js")] : []) + scriptsAfter,
                    assetPrefix: rootPrefix + "assets",
                    packageAssetPrefix: documentPackageAssetPrefix,
                    assets: assets,
                    site: site,
                    webIconPlan: webIconPlan
                ))
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
            pageFiles.append(contentsOf: partAssetFiles(
                for: pagePackages,
                scope: .page,
                destinationDirectory: pageFilesDirectory
            ))
            for file in pageFiles { try emit(file) }
            pageOutput(page.id, pageFiles.map(\.path))
        }
        stageTiming("pagesAndDependencies", stageStart.duration(to: .now))
        guard includeSharedFiles else { return }
        stageStart = .now
        try emit(.init(path: "files/site.css", contents: stylesheet(for: site, assets: assets)))
        stageTiming("sharedCSS", stageStart.duration(to: .now))
        stageStart = .now
        for file in FoundryWebLibraryRegistry.exportFiles(for: sitePackages) { try emit(file) }
        for file in partAssetFiles(
            for: sitePackages,
            scope: .site,
            destinationDirectory: "assets"
        ) { try emit(file) }
        stageTiming("bundledAndPackageResources", stageStart.duration(to: .now))
        stageStart = .now
        let managedAssetPaths = site.assetLibrary.managedExportPaths()
        for asset in site.assets {
            try Task.checkCancellation()
            guard assets.hasContent(asset.id) else { continue }
            try emit(SiteExportFile(
                path: site.publishedPath(for: asset, managedAssetPaths: managedAssetPaths),
                fingerprint: assets.digest(asset.id),
                resolve: { assets[asset.id]?.data }
            ))
        }
        for asset in site.siteLogoAssets {
            try Task.checkCancellation()
            guard assets.hasContent(asset.id) else { continue }
            try emit(SiteExportFile(
                path: SiteLogoStorage.exportPath(for: asset),
                fingerprint: assets.digest(asset.id),
                resolve: { assets[asset.id]?.data }
            ))
        }
        stageTiming("projectAssets", stageStart.duration(to: .now))
        stageStart = .now
        try imageRenditionFiles(site: site, assets: assets, emit: emit)
        try backgroundVideoPosterFiles(site: site, assets: assets, emit: emit)
        stageTiming("renditionsAndPosters", stageStart.duration(to: .now))
        stageStart = .now
        for file in webIconPlan.files { try emit(file) }
        if site.generatesSitemap, let baseURL = validPublicURL(site.publicURL) {
            try emit(.init(path: "sitemap.xml", contents: sitemap(for: site, baseURL: baseURL)))
        }
        if site.generatesRobotsTXT {
            try emit(.init(path: "robots.txt", contents: robotsTXT(for: site)))
        }
        stageTiming("iconsAndMetadata", stageStart.duration(to: .now))
    }

    private func pageRequiresJavaScript(_ page: Page) -> Bool {
        page.parts.flatMap(\.flattened).contains { node in
            if !PartArtifactPlan.htmlArtifact(for: node, suffix: "JavaScript")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return node.definition.package?.declaresJavaScript(in: .instance, .page) == true
                || !(node.definition.package?.manifest.controlGroupJavaScript.isEmpty ?? true)
        }
    }

    static func requiresPHP(_ page: Page) -> Bool {
        PartArtifactPlan(page: page).nodes.contains {
            PartRegistry.definition(for: $0.type).package?.manifest.requiresPHP == true
        }
    }

    /// The page's exported file extension: a PHP-requiring part forces `php`;
    /// then an extension the author typed into the filename override applies;
    /// otherwise the extension stamped on the page at creation stands.
    static func fileExtension(for page: Page) -> String {
        if requiresPHP(page) { return "php" }
        if let declared = page.filenameOverride.map({ ($0 as NSString).pathExtension }),
           ["html", "php"].contains(declared) {
            return declared
        }
        return page.preferredExtension == .php ? "php" : "html"
    }

    /// The exported file's name: the author's filename override when present,
    /// completed with the effective extension; `index` otherwise. The home
    /// page is always the root `index` file.
    static func filename(for page: Page) -> String {
        var base = "index"
        if page.slug != "index", let override = page.filenameOverride {
            let stripped = (override as NSString).deletingPathExtension
            if !stripped.isEmpty { base = stripped }
        }
        return "\(base).\(fileExtension(for: page))"
    }

    /// The page's site-relative address the way links write it: the directory
    /// alone for `index` files (pretty URLs), the visible filename otherwise.
    static func urlPath(for page: Page, pages: [Page], folders: [PageFolder]) -> String {
        let segments = PageRouteResolver.pathSegments(for: page, pages: pages, folders: folders)
        let directory = segments.isEmpty ? "/" : "/" + segments.joined(separator: "/") + "/"
        let file = filename(for: page)
        return file.hasPrefix("index.") ? directory : directory + file
    }

    static func outputPath(for page: Page, in site: Site) -> String {
        let directory = PageRouteResolver.pathSegments(
            for: page,
            pages: site.pages,
            folders: site.pageFolders
        ).joined(separator: "/")
        return directory.isEmpty
            ? filename(for: page)
            : directory + "/" + filename(for: page)
    }

    static func customExportPath(for asset: ProjectAsset, in site: Site) -> String? {
        asset.exportDirectory == nil ? nil : site.publishedPath(for: asset)
    }

    private static func joinedPath(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: "/")
    }

    private func joinedPath(_ prefix: String, _ suffix: String) -> String {
        prefix.isEmpty ? suffix : prefix + "/" + suffix
    }

    private func render(page: Page, language: String, theme: Theme, stylesheetPaths: [String], scripts: [FoundryWebScript], assetPrefix: String, packageAssetPrefix: String, assets: ProjectAssetContents, site: Site, webIconPlan: WebIconExportPlan) -> String {
        let outputHooks = PublishedPartHooks(page: page, site: site)
        let body = page.parts.map { render($0, page: page, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site, outputHooks: outputHooks) }.joined(separator: "\n")
        let pageTitle = page.metadata.browserTitle.isEmpty ? page.title : page.metadata.browserTitle
        let browserTitle = pageTitle + site.titleSuffix
        let metadata = metadataHTML(for: page, browserTitle: browserTitle, assetPrefix: assetPrefix, assets: assets, site: site, webIconPlan: webIconPlan)
        let headStart = placedHTML(for: page, placement: .headStart, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, site: site)
        let headEnd = placedHTML(for: page, placement: .headEnd, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, site: site)
        let bodyStart = placedHTML(for: page, placement: .bodyStart, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, site: site)
        let bodyEnd = placedHTML(for: page, placement: .bodyEnd, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, site: site)
        let scriptTags = scripts.map(\.htmlTag).joined(separator: "\n")
        let php = packagePHP(for: page, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site)
        let customHeadCode = site.customCodeEnabled ? site.headCode : ""
        let customBodyStartCode = site.customCodeEnabled ? site.bodyStartCode : ""
        let customBodyEndCode = site.customCodeEnabled ? site.bodyEndCode : ""
        let rootPrefix = String(assetPrefix.dropLast("assets".count))
        let customStyle = site.customCodeEnabled && !site.cssCode.isEmpty
            ? "<link rel=\"stylesheet\" href=\"\(rootPrefix)files/custom-site.css\">" : ""
        let customScript = site.customCodeEnabled && !site.javaScriptCode.isEmpty
            ? FoundryWebScript(path: rootPrefix + "files/custom-site.js", isModule: true).htmlTag : ""
        let documentLanguage = (page.language ?? language).trimmingCharacters(in: .whitespacesAndNewlines)
        // Conditional pieces that render nothing must not leave blank lines
        // in the document, so assemble from non-empty lines instead of
        // interpolating everything.
        let headLines = [
            headStart,
            customHeadCode,
            "  <meta charset=\"utf-8\">",
            "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "  <meta name=\"color-scheme\" content=\"\(site.appearanceMode.cssColorScheme)\">",
            "  <title>\(escape(browserTitle))</title>",
            metadata,
            site.appearanceMode.bootstrap(siteID: site.id, defaultMode: page.parts.flatMap(\.flattened)
                .first(where: { $0.type == .appearanceSwitcher })?.property(.init(rawValue: "defaultAppearance")) ?? "system"),
            stylesheetPaths.map { "  <link rel=\"stylesheet\" href=\"\($0)\">" }.joined(separator: "\n"),
            headEnd,
            customStyle
        ]
        let bodyLines = [customBodyStartCode, bodyStart, body, bodyEnd, scriptTags, customBodyEndCode, customScript]
        func joined(_ lines: [String]) -> String {
            lines
                .map { $0.trimmingCharacters(in: .newlines) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        }
        let document = """
        <!doctype html>
        <html lang="\(escapeAttribute(documentLanguage.isEmpty ? "en" : documentLanguage))">
        <head>
        \(joined(headLines))
        </head>
        <body\(page.backgroundOverride == nil ? "" : " style=\"background-color: " + escapeAttribute(site.appearanceMode.colour(light: page.backgroundColour(theme: theme, appearance: .light), dark: page.backgroundColour(theme: theme, appearance: .dark))) + "\"")>
        \(joined(bodyLines))
        </body>
        </html>
        """
        return php.isEmpty ? document : php + "\n" + document
    }

    private func packagePHP(for page: Page, theme: Theme, assetPrefix: String, packageAssetPrefix: String, assets: ProjectAssetContents, site: Site) -> String {
        let nodes = page.parts.flatMap(\.flattened)
        let instancePHP = nodes.compactMap { node -> String? in
            guard !Task.isCancelled else { return nil }
            guard let package = node.definition.package else { return nil }
            let source = package.instancePHP
            guard !source.isEmpty else { return nil }
            return PartTemplateRenderer.render(
                source,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site),
                    templateValues: navigationValues(for: page, in: site),
                    slots: [:],
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment,
                    loopMaximums: package.loopMaximums
                )
            )
        }
        var seenPackages: Set<String> = []
        let sharedPHP = nodes.compactMap { node -> String? in
            guard let package = node.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = package.pagePHP
            guard !source.isEmpty else { return nil }
            return PartTemplateRenderer.render(
                source,
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    templateValues: navigationValues(for: page, in: site),
                    slots: [:],
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment,
                    loopMaximums: package.loopMaximums
                )
            )
        }
        return (instancePHP + sharedPHP).joined(separator: "\n")
    }

    private func pageScripts(for page: Page, theme: Theme, assetPrefix: String, packageAssetPrefix: String, assets: ProjectAssetContents, site: Site) -> String {
        let nodes = page.parts.flatMap(\.flattened)
        let instanceScripts = nodes.compactMap { node -> String? in
            guard !Task.isCancelled else { return nil }
            guard let package = node.definition.package else { return nil }
            let source = [
                package.instanceJavaScript,
                PartArtifactPlan.htmlArtifact(for: node, suffix: "JavaScript"),
                package.renderDefinition.controlGroupJavaScript
            ]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            guard !source.isEmpty else { return nil }
            return PartTemplateRenderer.render(
                source,
                context: .init(instanceID: node.id, packageIdentifier: package.manifest.identifier, properties: packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site), templateValues: navigationValues(for: page, in: site), slots: [:], assetBasePath: packageAssetPrefix, assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix), siteBaseURL: siteBaseURL(for: site), pageURL: pageURL(for: page, in: site), siteRootPath: siteRootPath(for: assetPrefix), siteAssetsPath: assetPrefix, environment: environment, loopMaximums: package.loopMaximums)
            )
        }
        var seenPackages: Set<String> = []
        let sharedScripts = nodes.compactMap { node -> String? in
            guard let package = node.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = package.pageJavaScript
            guard !source.isEmpty else { return nil }
            return PartTemplateRenderer.render(source, context: .init(instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), packageIdentifier: package.manifest.identifier, properties: [:], templateValues: navigationValues(for: page, in: site), slots: [:], assetBasePath: packageAssetPrefix, assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix), siteBaseURL: siteBaseURL(for: site), pageURL: pageURL(for: page, in: site), siteRootPath: siteRootPath(for: assetPrefix), siteAssetsPath: assetPrefix, environment: environment, loopMaximums: package.loopMaximums))
        }
        let source = (instanceScripts + sharedScripts).joined(separator: "\n")
        return source
    }

    private func placedHTML(for page: Page, placement: PartPackageTemplateFile.Placement, assetPrefix: String, packageAssetPrefix: String, site: Site) -> String {
        var seenPackages: Set<String> = []
        return page.parts.flatMap(\.flattened).compactMap { node -> String? in
            guard let package = node.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let templates = package.placedHTML.filter { $0.placement == placement }
            guard !templates.isEmpty else { return nil }
            let context = PartTemplateContext(
                instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                packageIdentifier: package.manifest.identifier,
                properties: [:],
                templateValues: navigationValues(for: page, in: site),
                slots: [:],
                assetBasePath: packageAssetPrefix,
                assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                siteBaseURL: siteBaseURL(for: site),
                pageURL: pageURL(for: page, in: site),
                siteRootPath: siteRootPath(for: assetPrefix),
                siteAssetsPath: assetPrefix,
                environment: environment,
                loopMaximums: package.loopMaximums
            )
            return templates.map { PartTemplateRenderer.render($0.contents, context: context) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func metadataHTML(
        for page: Page,
        browserTitle: String,
        assetPrefix: String,
        assets: ProjectAssetContents,
        site: Site,
        webIconPlan: WebIconExportPlan
    ) -> String {
        var tags: [String] = []
        let description = page.metadata.description.isEmpty ? site.defaultDescription : page.metadata.description
        if !description.isEmpty {
            tags.append("<meta name=\"description\" content=\"\(escapeAttribute(description))\">")
        }

        let socialTitle = page.metadata.socialTitle.isEmpty ? browserTitle : page.metadata.socialTitle
        tags.append("<meta property=\"og:title\" content=\"\(escapeAttribute(socialTitle))\">")
        if !site.name.isEmpty {
            tags.append("<meta property=\"og:site_name\" content=\"\(escapeAttribute(site.name))\">")
        }
        tags.append("<meta property=\"og:type\" content=\"website\">")
        let languageTag = (page.language ?? site.language).trimmingCharacters(in: .whitespacesAndNewlines)
        if !languageTag.isEmpty {
            let locale = languageTag.replacingOccurrences(of: "-", with: "_")
            tags.append("<meta property=\"og:locale\" content=\"\(escapeAttribute(locale))\">")
        }

        tags.append("<meta name=\"generator\" content=\"Foundry\">")
        if !site.allowsSearchIndexing {
            tags.append("<meta name=\"robots\" content=\"noindex, nofollow\">")
        } else if !page.includeInSearch {
            tags.append("<meta name=\"robots\" content=\"noindex\">")
        }

        if site.generatesCanonicalURLs,
           let baseURL = validPublicURL(site.publicURL) {
            let canonicalURL = absoluteURL(for: page, in: site, baseURL: baseURL)
            tags.append("<link rel=\"canonical\" href=\"\(escapeAttribute(canonicalURL))\">")
            tags.append("<meta property=\"og:url\" content=\"\(escapeAttribute(canonicalURL))\">")
        }

        let socialDescription = page.metadata.socialDescription.isEmpty
            ? description
            : page.metadata.socialDescription
        if !socialDescription.isEmpty {
            tags.append("<meta property=\"og:description\" content=\"\(escapeAttribute(socialDescription))\">")
        }
        let socialImage = page.metadata.socialImage.isEmpty ? site.defaultSocialImage : page.metadata.socialImage
        var sharesImage = false
        if !socialImage.isEmpty {
            let source = exportSource(socialImage, assetPrefix: assetPrefix, assets: assets, site: site)
            if !source.isEmpty {
                tags.append("<meta property=\"og:image\" content=\"\(escapeAttribute(source))\">")
                sharesImage = true
                // The site-wide alt describes the site-wide image only.
                if page.metadata.socialImage.isEmpty, !site.socialImageAlt.isEmpty {
                    tags.append("<meta property=\"og:image:alt\" content=\"\(escapeAttribute(site.socialImageAlt))\">")
                }
            }
        }
        tags.append("<meta name=\"twitter:card\" content=\"\(sharesImage ? "summary_large_image" : "summary")\">")
        if !site.socialAccount.isEmpty {
            tags.append("<meta name=\"twitter:site\" content=\"\(escapeAttribute(site.socialAccount))\">")
        }
        tags.append(contentsOf: webIconPlan.markup(
            rootPrefix: siteRootPrefix(from: assetPrefix)
        ))
        if site.favicon.foundryAssetID == nil, !site.favicon.isEmpty {
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
        baseURL + Self.urlPath(for: page, pages: site.pages, folders: site.pageFolders)
    }

    private func sitemap(for site: Site, baseURL: String) -> String {
        // Noindexed pages stay out of the sitemap: inviting crawlers to a
        // page that refuses indexing draws search-console warnings.
        let entries = site.pages.filter { $0.includeInSitemap && $0.includeInSearch }.map { page in
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

    private func render(_ node: PartNode, page: Page, theme: Theme, assetPrefix: String, packageAssetPrefix: String, assets: ProjectAssetContents, site: Site, outputHooks: PublishedPartHooks) -> String {
        guard !Task.isCancelled else { return "" }
        switch node.definition.renderKind {
        case .package:
            guard let package = node.definition.package else {
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
            let slots = Dictionary(uniqueKeysWithValues: package.renderDefinition.slots.map { slot in
                let children = node.children.filter {
                    ($0.slotID ?? (package.hasDropZone ? nil : package.renderDefinition.slots.first?.id)) == slot.id
                }
                return (slot.id, children.map { render($0, page: page, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site, outputHooks: outputHooks) }.joined())
            })
            let dropZones = Dictionary(uniqueKeysWithValues: package.dropZoneNames.enumerated().map { index, name in
                let slotID = package.dropZoneSlotID(for: name)
                let children = node.children.filter { $0.slotID == slotID || (index == 0 && $0.slotID == nil) }
                return (name, children.map {
                    render($0, page: page, theme: theme, assetPrefix: assetPrefix, packageAssetPrefix: packageAssetPrefix, assets: assets, site: site, outputHooks: outputHooks)
                }.joined())
            })
            let anchor = PartAnchorValidator.validated(node.anchor)
            let anchorAttribute = anchor.map { " id=\"\(escapeAttribute($0))\"" } ?? ""
            let customAttributes = PartRootAttributeValidator.validAttributes(node.rootAttributes ?? []).map {
                " \($0.name)=\"\(escapeAttribute($0.value))\""
            }.joined()
            let requiresIdentity = outputHooks.requiresIdentity(for: node, package: package)
            let identityAttributes = requiresIdentity
                ? "data-foundry-id=\"\(node.id.uuidString)\" data-foundry-part data-foundry-package=\"\(escapeAttribute(package.manifest.identifier))\""
                : ""
            let outputClass = requiresIdentity
                ? partClass(node) + " " + PartTemplateRenderer.packageClass(for: package.manifest.identifier)
                : PartRootAttributeValidator.normalizedClasses(node.customClasses)
            let properties = packageProperties(node, theme: theme, assetPrefix: assetPrefix, assets: assets, site: site)
            let templateContext = PartTemplateContext(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: properties,
                    templateValues: navigationValues(for: page, in: site),
                    slots: slots,
                    dropZones: dropZones,
                    partClass: outputClass,
                    partAttributes: "\(identityAttributes)\(anchorAttribute)\(customAttributes)",
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
                    ),
                    richTextColourContext: .init(
                        palettes: theme.colourPalettes,
                        mode: site.appearanceMode
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
            return "<div \(identityAttributes)\(anchorAttribute)\(customAttributes) class=\"\(outputClass)\">\(decorated)</div>"
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
        assets: ProjectAssetContents,
        site: Site
    ) -> String {
        guard let id = source.foundryAssetID else { return source }
        guard let asset = assets.asset(id) else { return "" }
        return siteRootPrefix(from: assetPrefix) + site.publishedPath(for: asset)
    }

    private func siteRootPrefix(from assetPrefix: String) -> String {
        let managedAssetsPath = "assets"
        guard assetPrefix.hasSuffix(managedAssetsPath) else { return "" }
        return String(assetPrefix.dropLast(managedAssetsPath.count))
    }

    private func stylesheet(for site: Site, assets: ProjectAssetContents) -> String {
        let theme = site.theme
        let sitePackages = PartArtifactPlan.sitePackages(in: site)
        return """
        \(theme.fontSourceCSS(
            assets: assets,
            destination: .export,
            exportedSource: { "../" + site.publishedPath(for: $0) }
        ))
        \(FoundryWebLibraryRegistry.exportCSS(for: sitePackages))
        \(BootstrapThemeCSS.render(theme: theme))
        \(BootstrapColorCSS.export(theme: theme, mode: site.appearanceMode))
        \(sitePackageStyles(for: site))
        """
    }

    private func partAssetFiles(
        for packages: [LoadedPartPackage],
        scope: PartPackageAsset.Scope,
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
        _ declaration: PartPackageAsset,
        from resourceRootURL: URL,
        destinationDirectory: String
    ) -> [SiteExportFile] {
        guard isSafeRelativePath(declaration.path) else { return [] }
        let sourceURL = resourceRootURL.appending(path: declaration.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else { return [] }

        if !isDirectory.boolValue {
            guard let data = try? Data(contentsOf: sourceURL, options: .mappedIfSafe) else { return [] }
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
                  let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
            let sourceParts = sourceURL.standardizedFileURL.pathComponents
            let fileParts = fileURL.standardizedFileURL.pathComponents
            guard fileParts.starts(with: sourceParts) else { return nil }
            let relativePath = fileParts.dropFirst(sourceParts.count).joined(separator: "/")
            let outputPath = Self.joinedPath(destinationDirectory, declaration.path, relativePath)
            return .init(path: outputPath, data: data)
        }
    }

    private func templateAssetPaths(
        for package: LoadedPartPackage,
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
        assets: ProjectAssetContents
    ) -> String {
        let nodes = page.parts.flatMap(\.flattened)
        return ResponsiveBreakpoint.allCases.dropFirst().compactMap { breakpoint in
            guard let minimumWidth = breakpoint.minimumWidth(in: site.theme.screens) else { return nil }
            let rules = nodes.compactMap { node -> String? in
                guard !Task.isCancelled else { return nil }
                let hasPartOverride = node.responsiveOverrides?.contains(where: { $0.breakpoint == breakpoint }) == true
                let hasCollectionOverride = node.definition.properties.contains { definition in
                    guard definition.control.isCollection else { return false }
                    let value = node.storedPropertyValue(definition.key) ?? definition.defaultValue
                    return PartCollectionValue.hasOverride(in: value, at: breakpoint)
                }
                guard hasPartOverride || hasCollectionOverride else { return nil }
                let resolved = node.resolved(at: breakpoint, screens: site.theme.screens)
                if let package = resolved.definition.package {
                    let css = PartTemplateRenderer.render(
                        [package.css, package.renderDefinition.controlGroupCSS]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n"),
                        context: .init(
                            instanceID: resolved.id,
                            packageIdentifier: package.manifest.identifier,
                            properties: packageProperties(
                                resolved,
                                theme: site.theme,
                                assetPrefix: assetPrefix,
                                assets: assets,
                                site: site,
                                breakpoint: breakpoint
                            ),
                            templateValues: navigationValues(for: page, in: site),
                            slots: [:],
                            partClass: partClass(resolved),
                            assetBasePath: packageAssetPrefix,
                            assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                            siteBaseURL: siteBaseURL(for: site),
                            pageURL: pageURL(for: page, in: site),
                            siteRootPath: siteRootPath(for: assetPrefix),
                            siteAssetsPath: assetPrefix,
                            environment: environment,
                            loopMaximums: package.loopMaximums
                        )
                    )
                    let scopedCSS = PartTemplateRenderer.scopedCSS(
                        css,
                        packageIdentifier: package.manifest.identifier,
                        instanceID: resolved.id
                    )
                    let background = PartPackageBackgroundResolver.stylesheet(packageProperties(resolved, theme: site.theme, assetPrefix: assetPrefix, assets: assets, site: site, breakpoint: breakpoint))
                    return scopedCSS + background
                }
                return nil
            }.joined()
            return rules.isEmpty ? nil : "@media(min-width:\(minimumWidth)px){\(rules)}"
        }.joined(separator: "\n")
    }

    private func partClass(_ node: PartNode) -> String {
        ["c-" + node.id.uuidString.lowercased(), PartRootAttributeValidator.normalizedClasses(node.customClasses)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func pageStyles(
        for page: Page,
        site: Site,
        assetPrefix: String,
        packageAssetPrefix: String,
        assets: ProjectAssetContents
    ) -> String {
        let nodes = PartArtifactPlan(page: page).nodes
        let instanceStyles = nodes.compactMap { node in
            guard !Task.isCancelled else { return nil as String? }
            guard let package = node.definition.package else { return nil }
            let properties = packageProperties(node, theme: site.theme, assetPrefix: assetPrefix, assets: assets, site: site)
            let cssTemplate = [package.css, PartArtifactPlan.htmlArtifact(for: node, suffix: "CSS"), package.renderDefinition.controlGroupCSS]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            // Empty templates need no navigation/asset context. Background
            // styles still use the same resolved values below.
            let css = cssTemplate.isEmpty ? "" : PartTemplateRenderer.render(
                cssTemplate,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: properties,
                    templateValues: navigationValues(for: page, in: site),
                    slots: [:],
                    partClass: partClass(node),
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment,
                    loopMaximums: package.loopMaximums
                )
            )
            let scoped = PartTemplateRenderer.scopedCSS(
                css,
                packageIdentifier: package.manifest.identifier,
                instanceID: node.id
            )
            let custom = PartTemplateRenderer.scopedCustomCSS(node.customCSS, instanceID: node.id)
            let background = PartPackageBackgroundResolver.stylesheet(properties)
            return [scoped, custom, background].filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n")
        let pagePackageStyles = PartArtifactPlan(page: page).packages.compactMap { package -> String? in
            guard !package.pageCSS.isEmpty else { return nil }
            return PartTemplateRenderer.render(
                package.pageCSS,
                context: .init(
                    instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
                    packageIdentifier: package.manifest.identifier,
                    properties: [:],
                    templateValues: navigationValues(for: page, in: site),
                    slots: [:],
                    assetBasePath: packageAssetPrefix,
                    assetPaths: templateAssetPaths(for: package, pageAssetPrefix: packageAssetPrefix, siteAssetPrefix: assetPrefix),
                    siteBaseURL: siteBaseURL(for: site),
                    pageURL: pageURL(for: page, in: site),
                    siteRootPath: siteRootPath(for: assetPrefix),
                    siteAssetsPath: assetPrefix,
                    environment: environment,
                    loopMaximums: package.loopMaximums
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
        // Derive and deduplicate only the current page's local themes. No registry
        // survives a render, so deleting the last user removes the rule.
        let paletteStyles = Set(nodes.map { BootstrapPartUtilityCSS.render(node: $0, theme: site.theme) }).sorted().joined(separator: "\n")
        return CSSTidy.tidy(
            [instanceStyles, paletteStyles, pagePackageStyles, responsiveStyles]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )
    }

    private func sitePackageStyles(for site: Site) -> String {
        PartArtifactPlan.sitePackages(in: site).compactMap { package -> String? in
            guard !package.siteCSS.isEmpty else { return nil }
            return PartTemplateRenderer.render(
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
                    environment: environment,
                    loopMaximums: package.loopMaximums
                )
            )
        }.joined(separator: "\n")
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
        case .packageFontSize(let value): .string(value.source)
        case .packageShadow(let value): .string(value.source)
        case .packageStackingOrder(let value): .string(value.source)
        case .themeSpacing, .themePadding, .themeMargin, .themeBorderWidth, .themeRadius: .string("")
        }
    }

    private func packageProperties(
        _ node: PartNode,
        theme: Theme,
        assetPrefix: String,
        assets: ProjectAssetContents,
        site: Site,
        breakpoint: ResponsiveBreakpoint = .mobile
    ) -> [String: PartPackageValue] {
        // One definition fetch, one stored-value index and one manifest
        // property expansion for the whole pass; repeating any of them per
        // key dominates page-render profiles.
        let partDefinition = node.definition
        let definitions = partDefinition.properties
        let manifestProperties = partDefinition.package?.renderDefinition.properties ?? []
        var values: [String: PartPackageValue] = Dictionary(uniqueKeysWithValues: definitions.map { definition in
            let value = node.storedPropertyValue(definition.key) ?? definition.defaultValue
            if let classes = BootstrapControlGroupClasses.resolve(node: node, key: definition.key, theme: theme) {
                return (definition.key.rawValue, .string(classes))
            }
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
                return (definition.key.rawValue, PartPackageSingleSpacingControl.resolved(
                    spacing,
                    theme: theme,
                    noneValue: manifestProperties.first { $0.id == definition.key.rawValue }?.noneValue
                ))
            }
            if case .themePadding(let padding) = value {
                return (definition.key.rawValue, PartPackageThemePaddingControl.resolved(padding, theme: theme))
            }
            if case .themeFont = definition.control {
                return (definition.key.rawValue, PartPackageFontControl.resolved(definition.key.rawValue, node: node, theme: theme))
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
                            theme: theme,
                            source: { source, _ in
                                exportSource(source, assetPrefix: assetPrefix, assets: assets, site: site)
                            },
                            link: { destination, absoluteURL in
                                PartLinkResolver.resolve(
                                    destination,
                                    pages: site.pages,
                                    folders: site.pageFolders,
                                    assets: site.assets,
                                    assetLibrary: site.assetLibrary,
                                    publicURL: site.publicURL,
                                    absoluteURL: absoluteURL
                                )
                            }
                        )
                    })
                )
            }
            if definition.control.isMedia {
                return (
                    definition.key.rawValue,
                    resolvedImageValue(value, assetPrefix: assetPrefix, assets: assets, site: site)
                )
            }
            if case .color = definition.control {
                return (definition.key.rawValue, .string(node.colorProperty(definition.key, theme: theme)))
            }
            if case .themeColors = definition.control {
                return (definition.key.rawValue, .string(BootstrapPaletteTheme.resolve(node.property(definition.key), theme: theme)))
            }
            if node.type == .container && definition.key.rawValue == "width" {
                return (definition.key.rawValue, .string(BootstrapLayout.containerClass(node.property(definition.key), screens: theme.screens)))
            }
            if case .themeFontSize = definition.control {

                return (definition.key.rawValue, .string(theme.fontSizeCSSVariable(for: node.property(definition.key))))
            }
            if case .themeStackingOrder = definition.control {
                if case .packageStackingOrder(let selected) = value, selected.isCustom {
                    return (definition.key.rawValue, .string(String(Int(selected.customValue))))
                }
                return (definition.key.rawValue, .string(theme.zIndexCSSVariable(for: node.property(definition.key))))
            }
            if case .packageShadow = definition.control,
               case .packageShadow(let shadowValue) = value {
                if manifestProperties.first(where: { $0.id == definition.key.rawValue })?.controlGroupSource?.type == .filters {
                    return (definition.key.rawValue, .string(PartPackageShadowResolver.filter(shadowValue, theme: theme)))
                }
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
        for definition in definitions {
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
            if case .themeFontSize = definition.control {
                // The size's paired leading travels with it in the theme.
                values[definition.key.rawValue + ".lineHeight"] = .string(
                    theme.lineHeightCSSVariable(for: node.property(definition.key))
                )
            }
        }
        if let package = partDefinition.package {
            PartSVGRenderer.insert(node: node, package: package, assets: assets, canvas: false, into: &values)
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
                    let href: String
                    // Only point at a rendition file that export will make;
                    // SVG, animated GIF and small images serve the original.
                    if let assetID = source.foundryAssetID, let asset = assets.asset(assetID),
                       canMakeRendition(of: asset, maximumDimension: rendition.effectiveMaximumDimension, assets: assets) {
                        href = siteRootPrefix(from: assetPrefix) + imageRenditionPath(
                            assetID: assetID,
                            maximumDimension: rendition.effectiveMaximumDimension,
                            fileExtension: PartImageProcessor.renditionFileExtension(
                                mimeType: asset.mediaType,
                                fallback: asset.imageMetadata.fileExtension
                            )
                        )
                    } else {
                        href = values[property.id]?.stringValue ?? ""
                    }
                    PartImageTemplateValues.insertRendition(
                        propertyID: property.id,
                        renditionID: rendition.id,
                        href: href,
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
                let poster: String
                if property.usesAutomaticVideoPoster {
                    poster = asset.flatMap(PartVideoTemplateValues.generatedPosterPath)
                        .map { siteRootPrefix(from: assetPrefix) + $0 } ?? ""
                } else {
                    poster = customPoster.isEmpty ? ""
                        : exportSource(customPoster, assetPrefix: assetPrefix, assets: assets, site: site)
                }
                PartVideoTemplateValues.insert(
                    propertyID: property.id,
                    href: values[property.id]?.stringValue ?? "",
                    poster: poster,
                    asset: asset,
                    playback: PartVideoTemplateValues.playbackOptions(propertyID: property.id, node: node),
                    into: &values
                )
            }
        }
        for definition in definitions {
            guard case .link(let absoluteURL) = definition.control,
                  case .link(let link) = node.propertyValue(definition.key) else { continue }
            let resolved = PartLinkResolver.resolve(
                link, pages: site.pages, folders: site.pageFolders, assets: site.assets,
                assetLibrary: site.assetLibrary,
                publicURL: site.publicURL, absoluteURL: absoluteURL
            )
            values[definition.key.rawValue] = .string(resolved.href)
            values[definition.key.rawValue + ".target"] = .string(resolved.target)
            values[definition.key.rawValue + ".attributes"] = .string(resolved.attributes)
        }
        PartPackageBackgroundResolver.resolve(
            &values,
            properties: manifestProperties,
            enablesEditorMarkup: false,
            instanceID: node.id
        )
        PartPackageControlGroupCSSResolver.resolve(&values, properties: manifestProperties)
        PartColourPurpose.insert(node: node, theme: theme, into: &values)
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
            screens: theme.screens
        )
    }

    private func resolvedImageValue(
        _ value: PartProperty.Value,
        assetPrefix: String,
        assets: ProjectAssetContents,
        site: Site
    ) -> PartPackageValue {
        switch value {
        case .url(let source):
            .string(exportSource(source, assetPrefix: assetPrefix, assets: assets, site: site))
        case .array(let values):
            .array(values.map {
                resolvedImageValue($0, assetPrefix: assetPrefix, assets: assets, site: site)
            })
        case .object(let values):
            .object(values.mapValues {
                resolvedImageValue($0, assetPrefix: assetPrefix, assets: assets, site: site)
            })
        default:
            packageValue(value)
        }
    }

    private func backgroundVideoPosterFiles(
        site: Site,
        assets: ProjectAssetContents,
        emit: (SiteExportFile) throws -> Void
    ) throws {
        var emitted = Set<UUID>()
        for page in site.pages {
            for node in page.parts.flatMap(\.flattened) {
                guard let package = node.definition.package else { continue }
                for property in package.renderDefinition.properties where property.usesAutomaticVideoPoster {
                    guard let id = node.property(.init(rawValue: property.id)).foundryAssetID,
                          emitted.insert(id).inserted,
                          let asset = assets.asset(id),
                          let path = PartVideoTemplateValues.generatedPosterPath(for: asset),
                          let data = asset.videoMetadata?.posterJPEG else { continue }
                    try Task.checkCancellation()
                    try emit(.init(path: path, data: data))
                }
            }
        }
    }

    private func imageRenditionFiles(
        site: Site,
        assets: ProjectAssetContents,
        emit: (SiteExportFile) throws -> Void
    ) throws {
        var requests = Set<ImageRenditionRequest>()
        for page in site.pages {
            for node in page.parts.flatMap(\.flattened) {
                guard let package = node.definition.package else { continue }
                for property in package.renderDefinition.properties where property.control.type == .image {
                    guard case .url(let source) = node.propertyValue(.init(rawValue: property.id)),
                          let assetID = source.foundryAssetID else { continue }
                    for rendition in property.renditions {
                        requests.insert(.init(assetID: assetID, maximumDimension: rendition.effectiveMaximumDimension))
                    }
                }
            }
        }
        for request in requests {
            try Task.checkCancellation()
            guard let asset = assets.asset(request.assetID),
                  canMakeRendition(of: asset, maximumDimension: request.maximumDimension, assets: assets),
                  let digest = assets.digest(request.assetID) else { continue }
            let path = imageRenditionPath(
                assetID: request.assetID,
                maximumDimension: request.maximumDimension,
                fileExtension: PartImageProcessor.renditionFileExtension(
                    mimeType: asset.mediaType,
                    fallback: asset.imageMetadata.fileExtension
                )
            )
            try emit(SiteExportFile(
                path: path,
                fingerprint: "\(digest)-\(request.maximumDimension)",
                resolve: {
                    guard let content = assets[request.assetID],
                          let output = PartImageProcessor.rendition(
                              data: content.data,
                              filename: content.asset.filename,
                              mimeType: content.asset.mediaType,
                              maximumDimension: request.maximumDimension,
                              digest: content.digest
                          ) else { return nil }
                    return output.data
                }
            ))
        }
    }

    /// The one decision both the template and the file list rely on, so a
    /// rendition path is never written for a file that will not exist.
    private func canMakeRendition(of asset: ProjectAsset, maximumDimension: Int, assets: ProjectAssetContents) -> Bool {
        PartImageProcessor.canMakeRendition(
            mediaType: asset.mediaType,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            maximumDimension: maximumDimension,
            data: { assets[asset.id]?.data }
        )
    }

    private func imageRenditionPath(assetID: UUID, maximumDimension: Int, fileExtension: String) -> String {
        "assets/renditions/\(assetID.uuidString.lowercased())-\(maximumDimension).\(fileExtension)"
    }

    private struct ImageRenditionRequest: Hashable {
        let assetID: UUID
        let maximumDimension: Int
    }

    private func safeCSSValue(_ value: PartProperty.Value) -> String {
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
        case .object:
            raw = ""
        case .link:
            raw = ""
        case .packageFontSize(let value):
            raw = value.source
        case .packageShadow(let value):
            raw = value.source
        case .packageStackingOrder(let value):
            raw = value.isCustom ? String(Int(value.customValue)) : value.source
        case .themeSpacing, .themePadding, .themeMargin, .themeBorderWidth, .themeRadius:
            raw = ""
        }
        return raw.filter { !";{}<>".contains($0) }
    }

    private func missingPackageHTML(
        _ node: PartNode,
        page: Page,
        theme: Theme,
        assetPrefix: String,
        packageAssetPrefix: String,
        assets: ProjectAssetContents,
        site: Site
    ) -> String {
        let outputHooks = PublishedPartHooks(page: page, site: site)
        return node.children.map {
            render(
                $0,
                page: page,
                theme: theme,
                assetPrefix: assetPrefix,
                packageAssetPrefix: packageAssetPrefix,
                assets: assets,
                site: site,
                outputHooks: outputHooks
            )
        }.joined()
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty
            && !path.hasPrefix("/")
            && !parts.contains("")
            && !parts.contains(".")
            && !parts.contains("..")
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

nonisolated extension PartNode {
    var flattened: [PartNode] {
        [self] + children.flatMap(\.flattened)
    }
}
