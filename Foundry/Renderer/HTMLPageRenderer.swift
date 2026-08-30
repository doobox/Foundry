import Foundation

@MainActor
struct HTMLPageRenderer: PageRendering {
    let site: Site?

    init(site: Site? = nil) { self.site = site }
    func render(page: Page, theme: Theme) -> String {
        render(page: page, language: "en", theme: theme, assets: [:], breakpoint: .desktop)
    }

    func render(page: Page, language: String, theme: Theme, assets: [UUID: ProjectAssetContent], breakpoint: ResponsiveBreakpoint) -> String {
        let body = page.components.isEmpty
            ? rootDropZone
            : page.components.map { render($0, theme: theme, assets: assets, globalDefinitionID: $0.reusableDefinitionID, breakpoint: breakpoint) }.joined(separator: "\n")
        let browserTitle = page.metadata.browserTitle.isEmpty ? page.title : page.metadata.browserTitle
        let metadata = metadataHTML(for: page, browserTitle: browserTitle, assets: assets)
        let headStart = placedHTML(for: page, placement: .headStart)
        let headEnd = placedHTML(for: page, placement: .headEnd)
        let bodyStart = placedHTML(for: page, placement: .bodyStart)
        let bodyEnd = placedHTML(for: page, placement: .bodyEnd)
        let scripts = packageScripts(for: page, theme: theme, assets: assets, breakpoint: breakpoint)
        let documentLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        <!doctype html>
        <html lang="\(escapeAttribute(documentLanguage.isEmpty ? "en" : documentLanguage))">
        <head>
        \(headStart)
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(browserTitle))</title>
        \(metadata)
          <style>
            \(theme.fontSourceCSS(assets: assets, destination: .canvas))
            :root {
              font-size: \(theme.typography.baseSize)px;
              --background: \(theme.colors.background);
              --surface: \(theme.colors.surface);
              --text: \(theme.colors.text);
              --accent: \(theme.colors.accent);
              --font-body: \(theme.typography.bodyFont.cssFamily);
              --font-heading: \(theme.typography.headingFont.cssFamily);
              --font-monospace: \(theme.typography.monospacedFont.cssFamily);
              \(theme.customFontCSSVariables)
              \(theme.fontSizeCSSVariables)
              --editor-component: #0A84FF;
              --editor-global: #34C759;
              --space-s: \(theme.spacing.small)px;
              --space-m: \(theme.spacing.medium)px;
              --space-l: \(theme.spacing.large)px;
            }
            *, *::before, *::after { box-sizing: border-box; }
            [data-foundry-id] {
              --editor-chrome: var(--editor-component);
              position: relative; cursor: default;
            }
            [data-foundry-global] { --editor-chrome: var(--editor-global); }
            [data-foundry-global-override="true"],
            [data-foundry-global-override="true"] [data-foundry-global] {
              --editor-chrome: var(--editor-component);
            }
            [data-foundry-id]:hover:not(:has([data-foundry-id]:hover)) {
              outline: 3px solid color-mix(in srgb, var(--editor-chrome) 55%, transparent); outline-offset: -3px;
              border-radius: 2px !important;
            }
            [data-foundry-global]:hover:not(:has([data-foundry-id]:hover)) {
              outline-color: var(--editor-chrome);
            }
            [data-foundry-global-override="true"]:hover:not(:has([data-foundry-id]:hover)),
            [data-foundry-global-override="true"] [data-foundry-global]:hover:not(:has([data-foundry-id]:hover)) {
              outline-color: color-mix(in srgb, var(--editor-chrome) 55%, transparent);
            }
            html:not(.foundry-show-outlines) [data-foundry-id]:hover:not(:has([data-foundry-id]:hover)) {
              outline: none !important;
            }
            .foundry-multi-drag-image {
              position: fixed; left: -1000px; top: -1000px; z-index: 2000;
              min-width: 132px; padding: 9px 13px; border: 2px solid var(--drag-color);
              border-radius: 8px; background: rgba(255,255,255,.96); color: #171719;
              box-shadow: 4px 4px 0 color-mix(in srgb, var(--drag-color) 35%, white),
                          8px 8px 0 color-mix(in srgb, var(--drag-color) 18%, white),
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
            .foundry-selected {
              outline: 3px solid var(--editor-chrome) !important; outline-offset: -3px;
              border-radius: 2px !important;
            }
            [contenteditable="true"]:focus:not(.foundry-selected) {
              outline: none !important;
            }
            .foundry-drag-source { opacity: 0.4 !important; }
            [data-foundry-global].foundry-selected { outline-color: var(--editor-chrome) !important; }
            [data-foundry-global-override="true"].foundry-selected,
            [data-foundry-global-override="true"] [data-foundry-global].foundry-selected {
              outline-color: var(--editor-chrome) !important;
            }
            .foundry-drop-before { box-shadow: inset 0 4px 0 var(--editor-chrome) !important; }
            .foundry-drop-after { box-shadow: inset 0 -4px 0 var(--editor-chrome) !important; }
            .foundry-drop-inside { outline: 4px dashed var(--editor-chrome) !important; outline-offset: -8px; }
            .foundry-drop-end { border-color: var(--editor-chrome) !important; background: color-mix(in srgb, var(--editor-chrome) 12%, transparent) !important; }
            [data-foundry-global].foundry-drop-before { box-shadow: inset 0 4px 0 var(--editor-chrome) !important; }
            [data-foundry-global].foundry-drop-after { box-shadow: inset 0 -4px 0 var(--editor-chrome) !important; }
            [data-foundry-global].foundry-drop-inside { outline-color: var(--editor-chrome) !important; }
            [data-foundry-global].foundry-drop-end {
              border-color: var(--editor-chrome) !important;
              background: color-mix(in srgb, var(--editor-chrome) 12%, transparent) !important;
            }
            .foundry-empty-drop-zone {
              display: grid; place-items: center; min-height: 64px; padding: 16px;
              border: 2px dashed color-mix(in srgb, var(--editor-chrome) 42%, transparent);
              border-radius: 10px; color: color-mix(in srgb, var(--text) 58%, transparent);
              background: color-mix(in srgb, var(--surface) 72%, transparent);
              font: 600 13px system-ui; text-align: center;
            }
            .foundry-empty-page { min-height: 100vh; }
            .foundry-contentless-drop-zone { min-height: 32px; padding: 6px 12px; }
            .columns > .foundry-empty-drop-zone { grid-column: 1 / -1; }
            .foundry-editing {
              cursor: text !important; outline: 3px solid var(--editor-chrome) !important;
              outline-offset: 4px; user-select: text; -webkit-user-select: text;
            }
            [data-foundry-global].foundry-empty-drop-zone {
              border-color: color-mix(in srgb, var(--editor-chrome) 42%, transparent);
            }
            [data-foundry-global].foundry-editing { outline-color: var(--editor-chrome) !important; }
            html, body { min-height: 100%; }
            body {
              margin: 0; background: var(--background);
              color: var(--text); font-family: var(--font-body);
              font-size: var(--font-size-base); line-height: var(--font-size-base-line-height);
            }
            h1, h2, h3, h4, h5, h6, .heading { font-family: var(--font-heading); }
            code, pre, kbd, samp { font-family: var(--font-monospace); }
            .button {
              display: block; width: fit-content; text-decoration: none; font-weight: 600;
            }
            .columns { display: grid; }
            .image { display: block; width: 100%; height: auto; }
            .spacer { min-height: 8px; }
            .unavailable { padding: 16px; border: 2px dashed #C33; color: #922; background: #FFF5F5; }
            \(packageStyles(for: page, theme: theme, assets: assets, breakpoint: breakpoint))
            \(themeControlStyles(for: page, theme: theme, breakpoint: breakpoint))
          </style>
        \(headEnd)
        </head>
        <body>\(bodyStart)\(body)\(bodyEnd)\(scripts)</body>
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
                    slots: [:]
                )
            )
        }
        var seenPackages: Set<String> = []
        let sharedScripts = nodes.compactMap { node -> String? in
            guard let package = node.type.definition.package,
                  seenPackages.insert(package.manifest.identifier).inserted else { return nil }
            let source = [package.pageJavaScript, package.siteJavaScript].filter { !$0.isEmpty }.joined(separator: "\n")
            guard !source.isEmpty else { return nil }
            return ComponentTemplateRenderer.render(
                source,
                context: .init(instanceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), packageIdentifier: package.manifest.identifier, properties: [:], slots: [:])
            )
        }
        let source = (instanceScripts + sharedScripts).joined(separator: "\n")
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
                slots: [:]
            )
            return templates.map { ComponentTemplateRenderer.render($0.contents, context: context) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func metadataHTML(
        for page: Page,
        browserTitle: String,
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
            let source = canvasSource(page.metadata.socialImage, assets: assets)
            if !source.isEmpty {
                tags.append("<meta property=\"og:image\" content=\"\(escapeAttribute(source))\">")
            }
        }
        return tags.map { "  " + $0 }.joined(separator: "\n")
    }

    private func render(_ sourceNode: ComponentNode, theme: Theme, assets: [UUID: ProjectAssetContent], globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint) -> String {
        let node = sourceNode.resolved(at: breakpoint)
        let globalDefinitionID = node.reusableDefinitionID ?? globalDefinitionID
        switch node.type.definition.renderKind {
        case .section:
            let style = sharedStyles(for: node, theme: theme).joined(separator: "; ")
            let children = renderedChildren(of: node, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
            return "<section class=\"section\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"\(style)\">\(children)</section>"
        case .columns:
            let count = clamped(node.numberProperty(.columnCount), to: 1...6)
            let gap = clamped(node.numberProperty(.gap), to: 0...120)
            let style = (sharedStyles(for: node, theme: theme) + [
                "grid-template-columns: repeat(\(count), minmax(0, 1fr))",
                "gap: \(gap)px"
            ]).joined(separator: "; ")
            let children = renderedChildren(of: node, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
            return "<section class=\"columns\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"\(style)\">\(children)</section>"
        case .text:
            let color = safeHex(node.colorProperty(.textColor, theme: theme), fallback: "#171719")
            let size = clamped(node.numberProperty(.fontSize), to: 10...120)
            let alignment = cssAlignment(node.property(.alignment))
            let style = (sharedStyles(for: node, theme: theme) + [
                "color: \(color)",
                "font-size: \(size)px",
                "text-align: \(alignment)"
            ]).joined(separator: "; ")
            return "<div class=\"text\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"\(style)\">\(escape(node.property(.text)))</div>"
        case .heading:
            let color = safeHex(node.colorProperty(.textColor, theme: theme), fallback: "#171719")
            let size = clamped(node.numberProperty(.fontSize), to: 10...120)
            let level = Int(node.property(.headingLevel)) ?? 2
            let safeLevel = min(max(level, 1), 6)
            let style = (sharedStyles(for: node, theme: theme) + [
                "color: \(color)", "font-size: \(size)px", "text-align: \(cssAlignment(node.property(.alignment)))"
            ]).joined(separator: "; ")
            return "<h\(safeLevel) class=\"heading\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"\(style)\">\(escape(node.property(.text)))</h\(safeLevel)>"
        case .button:
            let title = escape(node.property(.text))
            let link = resolvedLink(for: node)
            let label = escapeAttribute(node.property(.accessibilityLabel))
            let ariaLabel = label.isEmpty ? "" : " aria-label=\"\(label)\""
            let target = link.target.isEmpty ? "" : " target=\"\(escapeAttribute(link.target))\""
            let customAttributes = link.attributes.isEmpty ? "" : " \(link.attributes)"
            let color = safeHex(node.colorProperty(.textColor, theme: theme), fallback: "#FFFFFF")
            let size = clamped(node.numberProperty(.fontSize), to: 10...72)
            let style = (sharedStyles(for: node, theme: theme) + [
                "color: \(color)",
                "font-size: \(size)px"
            ]).joined(separator: "; ")
            return "<a class=\"button\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"\(style)\" href=\"\(escapeAttribute(link.href))\"\(target)\(ariaLabel)\(customAttributes)>\(title)</a>"
        case .image:
            let source = escapeAttribute(canvasSource(node.property(.source), assets: assets))
            let altText = escapeAttribute(node.property(.altText))
            let style = sharedStyles(for: node, theme: theme).joined(separator: "; ")
            if source.isEmpty {
                return "<div class=\"image foundry-empty-drop-zone\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"\(style)\">Drop an image here</div>"
            }
            return "<img class=\"image\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"\(style)\" src=\"\(source)\" alt=\"\(altText)\">"
        case .divider:
            let color = safeHex(node.colorProperty(.borderColor, theme: theme), fallback: "#D9D9DE")
            let width = clamped(node.numberProperty(.borderWidth), to: 1...24)
            let style = (sharedStyles(for: node, theme: theme) + ["border: 0", "border-top: \(width)px solid \(color)"]).joined(separator: "; ")
            return "<hr class=\"divider\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"\(style)\">"
        case .spacer:
            let height = clamped(node.numberProperty(.height), to: 0...600)
            return "<div class=\"spacer\" \(attributes(for: node, globalDefinitionID: globalDefinitionID)) style=\"min-height: \(height)px\"><div class=\"foundry-empty-drop-zone foundry-contentless-drop-zone\" data-foundry-adjacent-target=\"\(node.id.uuidString)\">Spacer · \(height)px — drop before or after</div></div>"
        case .package:
            guard let package = node.type.definition.package else {
                return unavailableComponent(node, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
            }
            let slots = Dictionary(uniqueKeysWithValues: package.manifest.slots.map { slot in
                let children = node.children.filter { ($0.slotID ?? package.manifest.slots.first?.id) == slot.id }
                let html = children.map {
                    render($0, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
                }.joined()
                return (slot.id, html.isEmpty ? "<div class=\"foundry-empty-drop-zone\" data-foundry-empty-parent=\"\(node.id.uuidString)\" data-foundry-slot-id=\"\(escapeAttribute(slot.id))\">Drop a component into \(escape(slot.title))</div>" : html)
            })
            let rendered = ComponentTemplateRenderer.render(
                package.htmlTemplate,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assets: assets),
                    slots: slots,
                    componentAttributes: attributes(for: node, globalDefinitionID: globalDefinitionID) +
                        " data-foundry-package=\"\(escapeAttribute(package.manifest.identifier))\""
                )
            )
            if package.htmlTemplate.contains("{{ component.attributes }}") ||
                package.htmlTemplate.contains("{{component.attributes}}") {
                return rendered
            }
            return "<div \(attributes(for: node, globalDefinitionID: globalDefinitionID)) data-foundry-package=\"\(escapeAttribute(package.manifest.identifier))\">\(rendered)</div>"
        case .unavailable:
            return unavailableComponent(node, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint)
        }
    }

    private func resolvedLink(for node: ComponentNode) -> ComponentLinkResolver.Result {
        guard case .link(let link) = node.propertyValue(.destination) else {
            return .init(href: "", target: "", attributes: "")
        }
        return ComponentLinkResolver.resolve(
            link,
            pages: site?.pages ?? [],
            folders: site?.pageFolders ?? [],
            assets: site?.assets ?? [],
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
        let instanceStyles = page.components.flatMap(flattened).compactMap { sourceNode in
            let node = sourceNode.resolved(at: breakpoint)
            guard let package = node.type.definition.package else { return nil }
            let css = ComponentTemplateRenderer.render(
                package.css + "\n" + package.editorCSS,
                context: .init(
                    instanceID: node.id,
                    packageIdentifier: package.manifest.identifier,
                    properties: packageProperties(node, theme: theme, assets: assets),
                    slots: [:]
                )
            )
            return ComponentTemplateRenderer.scopedCSS(css, packageIdentifier: package.manifest.identifier)
        }.joined(separator: "\n")
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
                    slots: [:]
                )
            )
        }.joined(separator: "\n")
        return [instanceStyles, pageStyles].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func themeControlStyles(
        for page: Page,
        theme: Theme,
        breakpoint: ResponsiveBreakpoint
    ) -> String {
        page.components.flatMap(flattened).compactMap { sourceNode in
            let node = sourceNode.resolved(at: breakpoint)
            guard node.type.definition.package == nil else { return nil }
            var declarations: [String] = []
            if node.type.definition.properties.contains(where: { $0.control.isThemeFontFamily }) {
                declarations.append("font-family: \(theme.fontCSSVariable(for: node.property(.themeFontFamily)))")
            }
            if node.type.definition.properties.contains(where: { $0.control.isThemeFontSize }) {
                declarations.append(contentsOf: ThemeTypographyControlCSS.declarations(for: node, theme: theme))
            }
            guard !declarations.isEmpty else { return nil }
            return "[data-foundry-id=\"\(node.id.uuidString)\"] { \(declarations.joined(separator: "; ")); }"
        }.joined(separator: "\n")
    }

    private func packageProperties(_ node: ComponentNode, theme: Theme, assets: [UUID: ProjectAssetContent]) -> [String: ComponentPackageValue] {
        var values: [String: ComponentPackageValue] = Dictionary(uniqueKeysWithValues: node.type.definition.properties.map { definition in
            let value = node.propertyValue(definition.key)
            if case .asset = definition.control,
               case .url(let source) = value {
                return (definition.key.rawValue, .string(canvasSource(source, assets: assets)))
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
        }
    }

    private func unavailableComponent(_ node: ComponentNode, theme: Theme, assets: [UUID: ProjectAssetContent], globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint) -> String {
        let children = node.children.map { render($0, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint) }.joined()
        let name = node.missingPackageSnapshot?.name ?? node.type.rawValue
        return "<div class=\"unavailable\" \(attributes(for: node, globalDefinitionID: globalDefinitionID))>Missing component: \(escape(name))\(children)</div>"
    }

    private var rootDropZone: String {
        "<div class=\"foundry-empty-drop-zone foundry-empty-page\" data-foundry-root-drop-zone>Drop a component onto this page</div>"
    }

    private func renderedChildren(of node: ComponentNode, theme: Theme, assets: [UUID: ProjectAssetContent], globalDefinitionID: UUID?, breakpoint: ResponsiveBreakpoint) -> String {
        guard node.children.isEmpty else {
            return node.children.map { render($0, theme: theme, assets: assets, globalDefinitionID: globalDefinitionID, breakpoint: breakpoint) }.joined()
        }
        return "<div class=\"foundry-empty-drop-zone\" data-foundry-empty-parent=\"\(node.id.uuidString)\">Drop a component inside \(escape(node.type.displayName))</div>"
    }

    private func canvasSource(_ source: String, assets: [UUID: ProjectAssetContent]) -> String {
        guard let id = source.foundryAssetID else { return source }
        guard let content = assets[id] else { return "" }
        return "data:\(content.asset.mediaType);base64,\(content.data.base64EncodedString())"
    }

    private func sharedStyles(for node: ComponentNode, theme: Theme) -> [String] {
        var styles: [String] = []
        if node.type.definition.properties.contains(where: { $0.key == .backgroundColor }) {
            styles.append("background-color: \(safeHex(node.colorProperty(.backgroundColor, theme: theme), fallback: "#FFFFFF"))")
        }
        if node.type.definition.properties.contains(where: { $0.key == .borderColor }) {
            styles.append("border: \(clamped(node.numberProperty(.borderWidth, theme: theme), to: 0...24))px solid \(safeHex(node.colorProperty(.borderColor, theme: theme), fallback: "#D9D9DE"))")
            styles.append("border-radius: \(clamped(node.numberProperty(.cornerRadius), to: 0...160))px")
        }
        styles.append("padding: \(clamped(node.numberProperty(.padding, theme: theme), to: 0...160))px")
        styles.append("margin-top: \(clamped(node.numberProperty(.marginTop, theme: theme), to: 0...240))px")
        styles.append("margin-bottom: \(clamped(node.numberProperty(.marginBottom, theme: theme), to: 0...240))px")

        let maxWidth = min(max(node.numberProperty(.maxWidth), 0), 1600)
        if maxWidth > 0 {
            styles.append("max-width: \(clamped(maxWidth, to: 0...1600))px")
        }
        styles.append(contentsOf: horizontalPosition(node.property(.horizontalAlignment)))
        return styles
    }

    private func horizontalPosition(_ value: String) -> [String] {
        switch value {
        case "center": ["margin-left: auto", "margin-right: auto"]
        case "trailing": ["margin-left: auto", "margin-right: 0"]
        default: ["margin-left: 0", "margin-right: auto"]
        }
    }

    private func attributes(for node: ComponentNode, globalDefinitionID: UUID?) -> String {
        let acceptsChildren = node.type.definition.allowsChildren ? "true" : "false"
        let globalAttributes = globalDefinitionID.map {
            " data-foundry-global=\"\($0.uuidString)\" data-foundry-global-override=\"\(node.overridesGlobalDefinition == true)\""
        } ?? ""
        return "data-foundry-id=\"\(node.id.uuidString)\" data-foundry-type=\"\(escapeAttribute(node.type.displayName))\" data-foundry-name=\"\(escapeAttribute(node.name))\" data-foundry-accepts-children=\"\(acceptsChildren)\"\(globalAttributes)"
    }

    private func cssAlignment(_ value: String) -> String {
        switch value {
        case "center": "center"
        case "trailing": "right"
        default: "left"
        }
    }

    private func safeHex(_ value: String, fallback: String) -> String {
        let digits = value.hasPrefix("#") ? value.dropFirst() : Substring()
        guard digits.count == 6, digits.allSatisfy({ $0.isHexDigit }) else {
            return fallback
        }
        return "#\(digits)"
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>) -> String {
        min(max(value, range.lowerBound), range.upperBound).formatted(.number.precision(.fractionLength(0...2)))
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
