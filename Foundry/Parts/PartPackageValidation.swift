import Foundation

nonisolated struct PartPackageDiagnostic: Equatable, Sendable {
    enum Severity: String, Sendable {
        case error
        case warning
    }

    let severity: Severity
    let location: String
    let message: String
}

nonisolated enum PartPackageValidator {
    static let maximumIconByteCount = 64 * 1024

    /// Icons draw as template images, so only their alpha survives and the
    /// file's own colours are discarded. A solid fill in any colour is fine;
    /// what matters is anything that makes the alpha partial or derived from
    /// artwork rather than geometry.
    static func iconArtworkAltersShape(_ source: String) -> Bool {
        let patterns = [
            #"(?i)Gradient"#,                             // linear/radial gradients
            #"(?i)<(image|pattern|filter)\b"#,           // raster, tiled or filtered artwork
            #"(?i)opacity\s*[=:]"#,                       // opacity, fill-opacity, stroke-opacity
            #"(?i)(rgba|hsla)\s*\("#,                     // colours with an alpha channel
            #"#(?:[0-9A-Fa-f]{4}|[0-9A-Fa-f]{8})\b"#     // #RGBA and #RRGGBBAA
        ]
        return patterns.contains { source.matches($0) }
    }
    private static let maximumTagCount = 5
    private static let identifierExpression = try! NSRegularExpression(
        pattern: #"^[a-z](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?){2,}$"#
    )
    private static let propertyExpression = try! NSRegularExpression(
        pattern: #"^[A-Za-z][A-Za-z0-9_-]*$"#
    )
    static func validate(_ manifest: PartPackageManifest, rootURL: URL) -> [PartPackageDiagnostic] {
        var diagnostics: [PartPackageDiagnostic] = []

        if manifest.minimumAPIVersion > FoundryPartAPI.supportedVersions.upperBound {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:minimumAPIVersion",
                message: "This part requires Foundry part API \(manifest.minimumAPIVersion), but this version of Foundry supports through API \(FoundryPartAPI.supportedVersions.upperBound). Update Foundry to use this part."
            ))
        } else if manifest.minimumAPIVersion < FoundryPartAPI.supportedVersions.lowerBound {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:minimumAPIVersion",
                message: "This part requires an unsupported Foundry part API."
            ))
        }
        validate(manifest.identifier, expression: identifierExpression, location: "manifest.json:id", message: "Use a lowercase reverse-DNS identifier, for example com.example.focal-point-hero.", into: &diagnostics)
        if LoadedPartPackage.usesReservedIdentifier(manifest.identifier, at: rootURL) {
            diagnostics.append(.init(severity: .error, location: "manifest.json:id", message: LoadedPartPackage.reservedIdentifierMessage))
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(.init(severity: .error, location: "manifest.json:title", message: "A part title is required."))
        }
        if SemanticVersion(manifest.version) == nil {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:version",
                message: "Use a semantic version in MAJOR.MINOR.PATCH form, for example 1.0.0."
            ))
        }
        if manifest.tags.count > maximumTagCount {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:tags",
                message: "A part can declare at most \(maximumTagCount) tags."
            ))
        }

        var seenLibraries = Set<PartPackageLibraryRequirement>()
        for library in manifest.libraries {
            let location = "manifest.json:libraries.\(library.identifier)"
            if library.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A library id is required."
                ))
            } else if library.majorVersion < 1 {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A library majorVersion must be greater than zero."
                ))
            } else if !FoundryWebLibraryRegistry.supports(library) {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "Foundry does not provide \(library.identifier) major version \(library.majorVersion)."
                ))
            }
            if !seenLibraries.insert(library).inserted {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "This library requirement is declared more than once."
                ))
            }
        }

        validateUnique(manifest.resolvedProperties.map(\.id), kind: "property", into: &diagnostics)
        let namespaces = Set(manifest.controlGroups.compactMap(\.id))
        for property in manifest.resolvedProperties where namespaces.contains(property.id) {
            diagnostics.append(.init(severity: .error, location: "manifest.json:inspector.\(property.id)", message: "Control ID '\(property.id)' conflicts with a control group namespace."))
        }
        validateUnique(manifest.slots.map(\.id), kind: "slot", into: &diagnostics)
        validateUnique(manifest.resolvedProperties.map(\.id), kind: "control", into: &diagnostics)
        for property in manifest.resolvedProperties {
            if !property.hasSynthesizedID {
                validate(property.controlGroupSource?.localID ?? property.id, expression: propertyExpression, location: "manifest.json:inspector.\(property.id)", message: "Property IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.", into: &diagnostics)
            }
            validate(property, into: &diagnostics)
            validateVisibility(property, properties: manifest.resolvedProperties, into: &diagnostics)
            if let font = property.control.font,
               !manifest.resolvedProperties.contains(where: { $0.id == font && $0.control.type == .frameworkFont }) {
                diagnostics.append(.init(severity: .error, location: "manifest.json:inspector.\(property.id).font", message: "font must reference a frameworkFont control in this part."))
            }
        }
        validateVisibilityCycles(manifest.resolvedProperties, into: &diagnostics)
        for slot in manifest.slots {
            validate(slot.id, expression: propertyExpression, location: "manifest.json:slots.\(slot.id)", message: "Slot IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.", into: &diagnostics)
            if slot.minimum < 0 || (slot.maximum.map { $0 < slot.minimum } == true) {
                diagnostics.append(.init(severity: .error, location: "manifest.json:slots.\(slot.id)", message: "Slot minimum and maximum values are inconsistent."))
            }
            if slot.accepts.isEmpty {
                diagnostics.append(.init(severity: .error, location: "manifest.json:inspector.\(slot.id)", message: "A childPicker must accept at least one part identifier, category, or '*'."))
            }
        }

        let declaredFiles = [manifest.icon?.file, manifest.render.html, manifest.render.editorCSS]
            .compactMap { $0 }
            .filter { !$0.isEmpty } + manifest.assets.map(\.path) + manifest.render.files.map(\.path)
        for path in declaredFiles {
            if !isSafeRelativePath(path) {
                diagnostics.append(.init(severity: .error, location: path, message: "Package paths must be relative and cannot contain '..'."))
            } else if !FileManager.default.fileExists(atPath: rootURL.appending(path: path).path) {
                diagnostics.append(.init(severity: .error, location: path, message: "The declared package file does not exist."))
            }
        }
        if let iconFile = manifest.icon?.file, isSafeRelativePath(iconFile) {
            let iconURL = rootURL.appending(path: iconFile)
            if let byteCount = try? iconURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               byteCount > maximumIconByteCount {
                diagnostics.append(.init(
                    severity: .error,
                    location: iconFile,
                    message: "Part icons cannot exceed 64 KiB."
                ))
            }
            if !iconFile.lowercased().hasSuffix(".svg") {
                diagnostics.append(.init(
                    severity: .error,
                    location: iconFile,
                    message: "Icon glyphs must be SVG files."
                ))
            } else if manifest.icon?.resolvedRendering != .original,
                      let source = try? String(contentsOf: iconURL, encoding: .utf8),
                      Self.iconArtworkAltersShape(source) {
                // Original artwork draws as-is, so its colours and shading are intended.
                diagnostics.append(.init(
                    severity: .warning,
                    location: iconFile,
                    message: "Icon glyphs are used only as a shape, so any solid colour works. Transparency, gradients, images, patterns and filters change that shape: partly transparent areas turn faint and shaded artwork turns into a flat silhouette."
                ))
            }
        }
        for file in manifest.render.files {
            let fileExtension = URL(fileURLWithPath: file.path).pathExtension.lowercased()
            if file.scope == .site, fileExtension != "css" {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:templates.files.\(file.path)",
                    message: "Site scope is available only to CSS templates."
                ))
            }
            if fileExtension == "css", file.placement != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:templates.files.\(file.path)",
                    message: "CSS templates do not use HTML placement."
                ))
            }
            if fileExtension == "js", file.placement != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:templates.files.\(file.path)",
                    message: "JavaScript templates are emitted at the end of the body and do not use placement."
                ))
            }
            if fileExtension == "php", file.placement != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:templates.files.\(file.path)",
                    message: "PHP templates run before page markup and do not use HTML placement."
                ))
            }
            if fileExtension == "html", file.placement == nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:templates.files.\(file.path)",
                    message: "Additional HTML templates require placement."
                ))
            }
            if fileExtension == "html", file.scope == .instance {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:templates.files.\(file.path)",
                    message: "Placed HTML templates currently require page scope."
                ))
            }
            if fileExtension != "css" && fileExtension != "html" && fileExtension != "js" && fileExtension != "php" {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:templates.files.\(file.path)",
                    message: "Template files currently support CSS, JavaScript, PHP and placed HTML."
                ))
            }
        }
        let declaresPHP = manifest.render.files.contains { $0.path.lowercased().hasSuffix(".php") }
            || manifest.assets.contains { $0.path.lowercased().hasSuffix(".php") }
        if !manifest.requiresPHP, declaresPHP {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:requiresPHP",
                message: "Parts with PHP templates or assets must set requiresPHP to true."
            ))
        }
        let templates: [(path: String?, requiresEditorAttributes: Bool)] = [
            (manifest.render.html, true),
            (manifest.render.editorCSS, false)
        ] + manifest.render.files
            .filter { $0.path.lowercased().hasSuffix(".css") || $0.path.lowercased().hasSuffix(".html") || $0.path.lowercased().hasSuffix(".js") || $0.path.lowercased().hasSuffix(".php") }
            .map { ($0.path as String?, false) }
        let templateContents: [String: String] = Dictionary(
            uniqueKeysWithValues: Set(templates.compactMap(\.path)).compactMap { path -> (String, String)? in
            guard isSafeRelativePath(path),
                  let contents = try? String(contentsOf: rootURL.appending(path: path), encoding: .utf8) else {
                return nil
            }
            return (path, contents)
            }
        )
        for declaredTemplate in templates {
            guard let path = declaredTemplate.path,
                  let template = templateContents[path] else {
                continue
            }
            validateTemplate(
                template,
                location: path,
                requiresEditorAttributes: declaredTemplate.requiresEditorAttributes,
                manifest: manifest,
                into: &diagnostics
            )
        }
        let linkGroups = manifest.controlGroups.filter { $0.type == .linkOverlay }
        let lightboxGroups = manifest.controlGroups.filter { $0.type == .lightbox }
        if !lightboxGroups.isEmpty, let template = templateContents[manifest.render.html] {
            if lightboxGroups.count > 1 {
                diagnostics.append(.init(severity: .error, location: "manifest.json:inspector", message: "Declare only one Lightbox group per part."))
            }
            if let root = PartRootLinkRenderer.root(in: template),
               !["div", "section", "article", "figure", "main", "aside", "header", "footer", "nav"].contains(root.name) {
                diagnostics.append(.init(severity: .error, location: manifest.render.html, message: "The Lightbox group requires a flow-content container root, such as div, section or figure."))
            }
        }
        if !linkGroups.isEmpty, let template = templateContents[manifest.render.html] {
            if linkGroups.count > 1 {
                diagnostics.append(.init(severity: .error, location: "manifest.json:inspector", message: "Declare only one Link group per part root."))
            }
            if let root = PartRootLinkRenderer.root(in: template), !PartRootLinkRenderer.allowedTags.contains(root.name) {
                diagnostics.append(.init(severity: .error, location: manifest.render.html, message: "The Link group cannot convert a <\(root.name)> root into an anchor. Use an ordinary content container or the primitive link control."))
            }
            if PartRootLinkRenderer.hasInteractiveChildren(template) {
                diagnostics.append(.init(severity: .warning, location: manifest.render.html, message: "The Link group cannot activate while the rendered root contains links, controls or focusable descendants."))
            }
        }
        for (index, contribution) in manifest.htmlContributions.enumerated() {
            validateTemplate(
                contribution.template,
                location: "manifest.json:templates.htmlContributions[\(index)].template",
                requiresEditorAttributes: false,
                manifest: manifest,
                into: &diagnostics
            )
        }
        for file in manifest.render.files where file.scope != .instance {
            guard let template = templateContents[file.path] else {
                continue
            }
            if template.matches(#"\{\{\s*(?:id|instance\.|part\.|control\.|slot\.)"#) ||
                template.matches(#"\{\{\s*(?:text|html|image|svg|video|dropZone|childArea)\s*\("#) ||
                template.matches(#"\{\{\s*(?:slot\s+id|text(?:\s*=|\s*\}\})|html(?:\s*=|\s*\}\})|image(?:\s+[^}]+)?\s*\}\})"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: file.path,
                    message: "Page- and site-scoped templates cannot use instance, part, control, slot, or editable-content macros."
                ))
            }
            if template.matches(#":(?:host|instance)\b"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: file.path,
                    message: ":host and :instance are available only in instance CSS and editor CSS."
                ))
            }
            if file.scope == .site, template.matches(#"\{\{\s*page\."#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: file.path,
                    message: "Site-scoped templates cannot use page macros."
                ))
            }
            if file.scope == .site {
                for reference in template.references(matching: #"\{\{\s*asset\(\s*\"([^\"]+)\"\s*\)\s*\}\}"#) {
                    if let asset = manifest.assetDeclaration(containing: reference.value), asset.scope != .site {
                        diagnostics.append(templateDiagnostic(
                            file.path,
                            template: template,
                            offset: reference.offset,
                            message: "Site-scoped templates can reference only site-scoped assets."
                        ))
                    }
                }
            }
        }
        return diagnostics
    }

    private static func validateTemplate(
        _ template: String,
        location templateLocation: String,
        requiresEditorAttributes: Bool,
        manifest: PartPackageManifest,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        // Dividers and notes carry no value, so a template has nothing to read.
        var propertyIDs = Set(manifest.resolvedProperties.filter { !$0.control.type.permitsOmittedID }.map(\.id))
        let namedGroupNamespaces = Set(manifest.controlGroups.compactMap(\.id))
        for namespace in PartPackageControlGroupCSSResolver.composedNamespaces(for: manifest.resolvedProperties) {
            propertyIDs.insert(namespace + ".css")
        }
        for group in manifest.controlGroups where group.type == .background {
            for field in ["css", "color", "image", "position", "size", "repeat", "video", "hover", "hover.selector"] {
                propertyIDs.insert(group.namespace + "." + field)
            }
        }
        for group in manifest.controlGroups where group.type == .flexbox {
            propertyIDs.insert(group.namespace + ".childCSS")
        }
        for group in manifest.controlGroups where group.type == .filters || group.type == .transforms {
            propertyIDs.insert(group.namespace + ".hover")
            propertyIDs.insert(group.namespace + ".hover.css")
            propertyIDs.insert(group.namespace + ".hover.selector")
        }
        let childPickerIDs = Set(manifest.slots.map(\.id))

        if requiresEditorAttributes {
            if let issue = template.partRootStructureIssue {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: issue.offset,
                    message: issue.message
                ))
            }
            let rootTag = template.firstRootOpeningTag ?? ""
            if !rootTag.matches(#"\{\{\s*part\.attributes\s*\}\}"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "The root element must include {{ part.attributes }}."
                ))
            }
            let rootClassContainsHook =
                rootTag.matches(#"(?i)\bclass\s*=\s*\"[^\"]*\{\{\s*part\.class\s*\}\}[^\"]*\""#) ||
                rootTag.matches(#"(?i)\bclass\s*=\s*'[^']*\{\{\s*part\.class\s*\}\}[^']*'"#)
            if rootClassContainsHook == false {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "The root class must include {{ part.class }}."
                ))
            } else if rootTag.matches(#"[^\s\"']\{\{\s*part\.class\s*\}\}"#) ||
                        rootTag.matches(#"\{\{\s*part\.class\s*\}\}[^\s\"']"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Separate {{ part.class }} from adjacent class names with literal whitespace."
                ))
            }
            if rootTag.matches(#"(?i)\sid\s*="#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "The part root cannot declare an id."
                ))
            }
        }

        let supportedFilters: Set<String> = [
            "lighten", "darken", "withAlpha", "mix", "formatDate", "addDays", "addMonths",
            "escapeHTML", "escapeHTMLAttribute", "encodeURL", "encodeURIComponent", "encodeJSON"
        ]
        for reference in template.references(matching: #"(?<!\|)\|(?!\|)\s*([A-Za-z][A-Za-z0-9_-]*)\b"#)
            where !supportedFilters.contains(reference.value) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Unknown template filter '\(reference.value)'."
            ))
        }
        for property in manifest.resolvedProperties
            where property.control.type != .color && property.control.type != .frameworkColor {
            let escapedID = NSRegularExpression.escapedPattern(for: property.id)
            if template.matches(#"\{\{\s*control\."# + escapedID + #"\s*\|\s*(?:lighten|darken|withAlpha|mix)\s*\("#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Colour filters are not available for '\(property.id)'."
                ))
            }
        }
        for property in manifest.resolvedProperties where property.control.type != .date {
            let escapedID = NSRegularExpression.escapedPattern(for: property.id)
            if template.matches(#"\{\{\s*control\."# + escapedID + #"(?:\[[0-9]+\])?\s*\|\s*(?:formatDate|addDays|addMonths)\s*\("#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Date filters are available only for date controls; '\(property.id)' is \(property.control.type.rawValue)."
                ))
            }
        }

        for reference in template.references(matching: #"\{\{\s*(slot)(?:\s|\.)"#) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Slot macros are not supported. Declare a childPicker and render it with {{ childArea(\"id\") }}."
            ))
        }
        let primitiveDeclarations = (try? PartTemplateLoop.declarations(in: template)) ?? []
        let primitiveNames = primitiveDeclarations.map(\.key)
        let primitiveCandidateCount = template.matchCount(#"\{\{\s*(?:text|html|image|svg|video)\b[^}]*\}\}"#)
        if primitiveCandidateCount != primitiveNames.count {
            diagnostics.append(.init(
                severity: .error,
                location: templateLocation,
                message: "Every editable macro must have a permanent quoted name, for example {{ text(\"heading\", default: \"Heading\") }} or {{ image(\"hero\") }}."
            ))
        }
        if requiresEditorAttributes {
            let dropZoneNames = PartTemplateRenderer.dropZoneNames(in: template)
            let dropZoneCandidateCount = template.matchCount(#"\{\{\s*dropZone\b[^}]*\}\}"#)
            if dropZoneCandidateCount != dropZoneNames.count {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Every drop zone must have a permanent quoted name, for example {{ dropZone(\"content\") }}."
                ))
            }
            let persistentNames = primitiveNames + dropZoneNames
            let duplicatePersistentNames = Dictionary(grouping: persistentNames, by: { $0 })
                .filter { $0.value.count > 1 }.keys.sorted()
            for name in duplicatePersistentNames {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Editable macro and drop-zone names must be unique; '\(name)' is used more than once."
                ))
            }
            for name in Set(persistentNames).intersection(propertyIDs).sorted() {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Persistent template name '\(name)' conflicts with a custom control id."
                ))
            }
            let childTemplates = ([template] + manifest.htmlContributions.map(\.template)).joined(separator: "\n")
            let childReferences = Set(childTemplates.references(
                matching: #"\{\{\s*childArea\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*\)\s*\}\}"#
            ).map(\.value))
            for childPickerID in childPickerIDs.subtracting(childReferences).sorted() {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "childPicker '\(childPickerID)' is not rendered with {{ childArea(\"\(childPickerID)\") }}."
                ))
            }
        }

        for reference in template.references(matching: #"\{\{\s*asset\(\s*\"([^\"]+)\"\s*\)\s*\}\}"#) {
            if !isSafeRelativePath(reference.value) {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "Asset paths must be relative and cannot contain '..'."
                ))
            } else if manifest.assetDeclaration(containing: reference.value) == nil {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "Asset '\(reference.value)' must be declared in manifest.json."
                ))
            }
        }

        for (index, property) in manifest.resolvedProperties.enumerated() where property.control.type == .image || property.control.type == .svg {
            let defaultPath = property.defaultValue.stringValue
            if !defaultPath.isEmpty && manifest.assetDeclaration(containing: defaultPath) == nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:inspector[\(index)].default",
                    message: "The default image '\(defaultPath)' must reference a declared package asset."
                ))
            }
        }

        for reference in template.references(
            matching: #"<img\b[^>]*\bsrc\s*=\s*[\"']\{\{\s*control\.([A-Za-z][A-Za-z0-9_-]*)(?:\.href|\.rendition\.[A-Za-z][A-Za-z0-9_-]*(?:\.href)?)?\s*\}\}[\"']"#
        ) {
            let propertyID = replacingLoopMetadata(in: reference.value)
            guard let property = manifest.resolvedProperties.first(where: { $0.id == propertyID }),
                  property.control.type == .image else {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "An img src control binding must reference an image control."
                ))
                continue
            }
        }
        for reference in template.references(
            matching: #"control\.([A-Za-z][A-Za-z0-9_-]*\.rendition\.[A-Za-z][A-Za-z0-9_-]*)"#
        ) {
            let parts = reference.value.split(separator: ".").map(String.init)
            guard parts.count == 3,
                  let property = manifest.resolvedProperties.first(where: { $0.id == parts[0] }),
                  property.control.type == .image,
                  property.renditions.contains(where: { $0.id == parts[2] }) else {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "An image rendition binding must reference a rendition declared by that image control."
                ))
                continue
            }
        }

        let ifCount = template.matchCount(#"\{\{\s*if\b"#)
        let elseIfCount = template.matchCount(#"\{\{\s*elseif\b"#)
        let endIfCount = template.matchCount(#"\{\{\s*endif\s*\}\}"#)
        let elseCount = template.matchCount(#"\{\{\s*else\s*\}\}"#)
        if ifCount != endIfCount || elseCount > ifCount || (elseIfCount > 0 && ifCount == 0) {
            diagnostics.append(.init(
                severity: .error,
                location: templateLocation,
                message: "Conditional directives are unbalanced; every if requires one endif and at most one else."
            ))
        }

        let loopCount = template.matchCount(#"\{\{\s*loop\s+"#)
        let endLoopCount = template.matchCount(#"\{\{\s*endloop\s*\}\}"#)
        if loopCount != endLoopCount {
            diagnostics.append(.init(
                severity: .error,
                location: templateLocation,
                message: "Loop directives are unbalanced; every loop requires one endloop."
            ))
        } else if loopCount > 0 {
            let maximums = Dictionary(manifest.resolvedProperties.compactMap { property -> (String, Int)? in
                guard property.control.type == .number || property.control.type == .slider,
                      let maximum = property.control.maximum,
                      maximum.isFinite,
                      maximum >= 0,
                      maximum <= Double(PartTemplateLoop.maximumIterationCount) else { return nil }
                return (property.id, Int(maximum.rounded(.down)))
            }, uniquingKeysWith: { first, _ in first })
            do {
                _ = try PartTemplateLoop.expand(
                    template,
                    properties: Dictionary(manifest.resolvedProperties.map { ($0.id, $0.defaultValue) }, uniquingKeysWith: { first, _ in first }),
                    maximums: maximums,
                    usingMaximumCounts: true
                )
            } catch {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Invalid loop structure: \(error)"
                ))
            }
        }
        let loopReferences = template.references(matching: #"\{\{\s*loop\s+([^{}]+?)\s*\}\}"#)
        let loopAliases = Set(loopReferences.compactMap { reference -> String? in
            let value = reference.value.hasSuffix(" reversed")
                ? String(reference.value.dropLast(" reversed".count))
                : reference.value
            let head = value.components(separatedBy: " where ")[0]
            let parts = head.components(separatedBy: " as ")
            return parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        })
        for reference in loopReferences {
            let value = reference.value.hasSuffix(" reversed")
                ? String(reference.value.dropLast(" reversed".count))
                : reference.value
            let predicateParts = value.components(separatedBy: " where ")
            let head = predicateParts[0]
            if predicateParts.count > 1 {
                let predicate = predicateParts.dropFirst().joined(separator: " where ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    let expression = try PartTemplateExpression.parse(predicate)
                    try PartTemplateExpression.validate(expression)
                } catch {
                    diagnostics.append(templateDiagnostic(
                        templateLocation,
                        template: template,
                        offset: reference.offset,
                        message: "Invalid loop filter: \(error)"
                    ))
                }
            }
            let count = head.components(separatedBy: " as ")[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if let literal = Int(count) {
                if !(0...PartTemplateLoop.maximumIterationCount).contains(literal) {
                    diagnostics.append(templateDiagnostic(
                        templateLocation,
                        template: template,
                        offset: reference.offset,
                        message: "A literal loop count must be between 0 and \(PartTemplateLoop.maximumIterationCount)."
                    ))
                }
                continue
            }
            if count.hasPrefix("navigation.") || count.hasPrefix("pages.") || count.hasPrefix("assets.") { continue }
            if loopAliases.contains(where: { count == $0 || count.hasPrefix($0 + ".") }) { continue }
            guard count.hasPrefix("control.") else {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "A loop count must be an integer or a control reference."
                ))
                continue
            }
            let propertyID = String(count.dropFirst("control.".count))
            guard let property = manifest.resolvedProperties.first(where: { $0.id == propertyID }) else {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "Unknown property '\(propertyID)'. Declare it in manifest.json controls."
                ))
                continue
            }
            if case .array = property.defaultValue { continue }
            guard property.control.type == .number || property.control.type == .slider,
                  let maximum = property.control.maximum,
                  maximum.isFinite,
                  maximum >= 0,
                  maximum <= Double(PartTemplateLoop.maximumIterationCount) else {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "A loop control must be numeric and declare a maximum from 0 through \(PartTemplateLoop.maximumIterationCount)."
                ))
                continue
            }
        }

        for reference in template.references(matching: #"\{\{\s*(?:if|elseif)\s+([^{}]+?)\s*\}\}"#) {
            let condition = replacingLoopMetadata(in: reference.value.trimmingCharacters(in: .whitespacesAndNewlines))
            do {
                let expression = try PartTemplateExpression.parse(condition)
                try PartTemplateExpression.validate(expression)
                for propertyID in Set(PartTemplateExpression.references(in: expression, groupNamespaces: namedGroupNamespaces)) where !propertyIDs.contains(propertyID) {
                    diagnostics.append(templateDiagnostic(
                        templateLocation,
                        template: template,
                        offset: reference.offset,
                        message: "Unknown property '\(propertyID)'. Declare it in manifest.json controls."
                    ))
                }
            } catch {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "Invalid condition: \(error)"
                ))
            }
        }

        let interpolationExpression = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
        for match in interpolationExpression.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            guard let sourceRange = Range(match.range(at: 1), in: template) else { continue }
            let source = String(template[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if source.hasPrefix("if ") || source.hasPrefix("elseif ") || source == "else" || source == "endif" ||
                source.hasPrefix("loop ") || source == "endloop" || source.hasPrefix("loop.") ||
                source.hasPrefix("slot ") || source.hasPrefix("text(") || source.hasPrefix("html(") ||
                source.hasPrefix("image(") || source.hasPrefix("svg(") || source.hasPrefix("video(") || source.hasPrefix("dropZone(") || source.hasPrefix("childArea(") || source.hasPrefix("asset(") ||
                ["text", "html", "image", "svg", "video", "instance.id", "package.id", "site.baseURL", "page.url", "path.siteRoot", "path.siteAssets", "part.class", "part.attributes", "dropZone", "childArea", "asset"].contains(source) {
                continue
            }
            if loopAliases.contains(where: { source == $0 || source.hasPrefix($0 + ".") }) { continue }
            let normalizedSource = replacingLoopMetadata(in: source)
            let expressionSource = PartTemplateExpression.templateParts(normalizedSource).first ?? normalizedSource
            do {
                let expression = try PartTemplateExpression.parse(expressionSource)
                try PartTemplateExpression.validate(expression)
                for propertyID in Set(PartTemplateExpression.references(in: expression, groupNamespaces: namedGroupNamespaces)) where !propertyIDs.contains(propertyID) {
                    diagnostics.append(templateDiagnostic(
                        templateLocation,
                        template: template,
                        offset: match.range.location,
                        message: "Unknown property '\(propertyID)'. Declare it in manifest.json controls."
                    ))
                }
            } catch {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: match.range.location,
                    message: "Invalid template expression: \(error)"
                ))
            }
        }

        let supportedMacroNames: Set<String> = [
            "id", "instance", "package", "site", "page", "path", "part", "control", "asset", "slot", "dropZone", "childArea",
            "if", "elseif", "else", "endif", "loop", "endloop", "text", "html", "image", "svg", "video", "canvas", "preview", "published", "navigation", "pages", "assets"
        ]
        for reference in template.references(matching: #"\{\{\s*([A-Za-z]+)(?:\.|\s|\}\})"#)
            where !supportedMacroNames.contains(reference.value) && !loopAliases.contains(reference.value) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: reference.value == "block"
                    ? "The block template namespace has been removed. Use part.class and part.attributes."
                    : "Unknown template macro '\(reference.value)'."
            ))
        }
    }

    private static func replacingLoopMetadata(in source: String) -> String {
        var result = source
        for key in ["loop.parent.first", "loop.parent.last", "loop.first", "loop.last"] {
            result = result.replacingOccurrences(of: key, with: "true")
        }
        for key in ["loop.parent.position", "loop.parent.index", "loop.parent.count", "loop.position", "loop.index", "loop.count"] {
            result = result.replacingOccurrences(of: key, with: "1")
        }
        return result
    }

    private static func templateDiagnostic(
        _ location: String,
        template: String,
        offset: Int,
        severity: PartPackageDiagnostic.Severity = .error,
        message: String
    ) -> PartPackageDiagnostic {
        let line = template.prefix(offset).reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
        return .init(severity: severity, location: "\(location):\(line)", message: message)
    }

    private static func validate(_ property: PartPackageProperty, into diagnostics: inout [PartPackageDiagnostic]) {
        validateBase(property, into: &diagnostics)
        for (name, value) in property.breakpointDefaults {
            var variant = property
            variant.defaultValue = value
            variant.breakpointDefaults = [:]
            var errors: [PartPackageDiagnostic] = []
            validateBase(variant, into: &errors)
            diagnostics += errors.map { .init(severity: $0.severity, location: $0.location + ".defaults." + name, message: $0.message) }
        }
    }

    private static func validateBase(_ property: PartPackageProperty, into diagnostics: inout [PartPackageDiagnostic]) {
        let location = "manifest.json:inspector.\(property.id)"
        validateFrameworkValues(property, location: location, into: &diagnostics)
        validateDateBounds(property, location: location, into: &diagnostics)
        if let count = property.control.count {
            guard (2...4).contains(count) else {
                diagnostics.append(.init(severity: .error, location: "\(location).count", message: "count must be between 2 and 4."))
                return
            }
            guard case .array(let values) = property.defaultValue, values.count == count else {
                diagnostics.append(.init(severity: .error, location: "\(location).default", message: "default must contain exactly \(count) values."))
                return
            }
            if property.subtitles.count > count {
                diagnostics.append(.init(severity: .error, location: "\(location).subtitle", message: "subtitle cannot contain more than \(count) values."))
            }
            if property.control.type == .button {
                if property.buttonTexts.count > count {
                    diagnostics.append(.init(severity: .error, location: "\(location).buttonText", message: "A button control array cannot have more buttonText values than controls."))
                }
                for (key, values) in [
                    ("buttonIcon", property.buttonIcons),
                    ("activeButtonText", property.activeButtonTexts),
                    ("activeButtonIcon", property.activeButtonIcons)
                ] where values.count > count {
                    diagnostics.append(.init(
                        severity: .error,
                        location: "\(location).\(key)",
                        message: "A button control array cannot have more \(key) values than controls."
                    ))
                }
                validateButtonMapping(property.control.trueValue, key: "trueValue", count: count, location: location, into: &diagnostics)
                validateButtonMapping(property.control.falseValue, key: "falseValue", count: count, location: location, into: &diagnostics)
                let selectedCount = values.filter { if case .boolean(true) = $0 { true } else { false } }.count
                if property.control.selectionMode == .single, selectedCount != 1 {
                    diagnostics.append(.init(
                        severity: .error,
                        location: "\(location).default",
                        message: "A button control using single selectionMode requires exactly one true default value."
                    ))
                }
                if property.control.selectionMode == .single, property.control.falseValue != nil {
                    diagnostics.append(.init(
                        severity: .error,
                        location: "\(location).falseValue",
                        message: "A button control using single selectionMode does not use falseValue."
                    ))
                }
            }
            for (index, value) in values.enumerated() {
                validate(value, for: property, location: "\(location).default[\(index)]", allowsLiteralColor: true, into: &diagnostics)
            }
            return
        }
        validate(property.defaultValue, for: property, location: "\(location).default", allowsLiteralColor: false, into: &diagnostics)
    }

    /// The unit list the generic edges/corners controls actually offer: the declared
    /// manifest units filtered to the supported set, or the full set when omitted.
    private static func boxUnits(for property: PartPackageProperty, fallback: [String]) -> [String] {
        let filtered = property.units.filter(fallback.contains)
        return filtered.isEmpty ? fallback : filtered
    }

    private static func validateFrameworkValues(
        _ property: PartPackageProperty,
        location: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        if property.control.type == .select, property.control.frameworkValues != nil {
            diagnostics.append(.init(severity: .error, location: "\(location).frameworkValues",
                message: "Select supports only declared options; remove frameworkValues."))
        }
        let supportsCustomFrameworkValue = property.control.type == .frameworkShadow
            || property.control.type == .frameworkColor
        if property.control.allowsCustom != nil, !supportsCustomFrameworkValue {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).allowsCustom",
                message: "allowsCustom requires a framework-aware control."
            ))
        }

        if property.control.type == .edges || property.control.type == .corners,
           property.control.count != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).count",
                message: "An \(property.control.type.rawValue) control cannot be a multi control; remove count."
            ))
        }
        if let outputFormat = property.control.outputFormat {
            let fragmentFormats: Set<PartPackageControl.ColorOutputFormat> = [
                .hexValue, .rgbValues, .rgbaValues, .hslValues, .hslaValues
            ]
            if property.control.type == .frameworkColor, fragmentFormats.contains(outputFormat) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).outputFormat",
                    message: "A frameworkColor outputs a complete CSS colour so it can adapt between light and dark; use the light/dark qualified fields for \(outputFormat.rawValue)."
                ))
            } else if property.control.type != .color, property.control.type != .frameworkColor {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).outputFormat",
                    message: "outputFormat is supported only by color and frameworkColor controls."
                ))
            }
        }
        if property.control.type == .color {
            if property.control.frameworkValues != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).frameworkValues",
                    message: "A color control does not use frameworkValues; use type frameworkColor."
                ))
            }
            if property.control.customColor != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).customColor",
                    message: "A color control declares its initial colour in default; remove customColor."
                ))
            }
            return
        } else if property.control.type == .frameworkColor {
            if property.control.frameworkValues != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).frameworkValues", message: "A frameworkColor control uses framework colours automatically; remove frameworkValues."))
            }
            if property.control.count != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).count", message: "A frameworkColor control cannot be a multi control; remove count."))
            }
            if property.control.customColor != nil, property.control.allowsCustom != true {
                diagnostics.append(.init(severity: .error, location: "\(location).customColor", message: "customColor requires allowsCustom to be true."))
            }
            return
        } else if property.control.frameworkValueDefault != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).frameworkValues",
                message: "The \(property.control.type.rawValue) control does not accept a framework role as frameworkValues."
            ))
        }
        if property.control.type == .frameworkShadow, property.control.frameworkValues != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).frameworkValues",
                message: "A frameworkShadow control automatically uses framework shadows; remove frameworkValues."
            ))
            return
        }

        guard let source = property.control.frameworkValueSource else { return }
        let supported: Bool
        switch (property.control.type, source) {
        case (.frameworkShadow, .shadows):
            supported = true
        default:
            supported = false
        }
        if !supported {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).frameworkValues",
                message: "The \(property.control.type.rawValue) control cannot request \(source.rawValue) framework values."
            ))
        }
    }

    private static func validate(
        _ defaultValue: PartPackageValue,
        for property: PartPackageProperty,
        location: String,
        allowsLiteralColor: Bool,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        switch property.control.type {
        case .divider, .spacer, .note:
            break
        case .math:
            let operations = Set(["+", "-", "*", "/", "%", "min", "max"])
            if property.control.argument1 == nil || property.control.argument2 == nil {
                diagnostics.append(.init(severity: .error, location: location, message: "A math control requires argument1 and argument2."))
            }
            if !operations.contains(property.control.operation ?? "") {
                diagnostics.append(.init(severity: .error, location: location, message: "A math operation must be +, -, *, /, %, min, or max."))
            }
        case .number, .slider:
            if property.units.contains(where: { $0.count > 3 }) {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A control unit can contain at most three characters."
                ))
            }
            if let count = property.control.count,
               !property.units.isEmpty,
               property.units.count != count {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A multi control must provide one unit for each value."
                ))
            }
            if let minimum = property.control.minimum,
               let maximum = property.control.maximum,
               maximum <= minimum {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "The control maximum must be greater than its minimum."
                ))
            }
            if let step = property.control.step, step < 0 {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "The control step cannot be negative."
                ))
            }
            if property.control.type == .slider,
               let ticks = property.control.ticks,
               ticks == 1 || ticks < 0 {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "Slider ticks must be zero or at least two."
                ))
            }
            if property.control.type == .slider {
                let range = (property.control.minimum ?? 0)...(property.control.maximum ?? 100)
                let labelledValues = [("tickLabels", property.control.tickLabels), ("valueLabels", property.control.valueLabels)]
                for (key, labels) in labelledValues {
                    for valueKey in (labels ?? [:]).keys.sorted() {
                        if let labelled = Double(valueKey), !range.contains(labelled) {
                            diagnostics.append(.init(severity: .error, location: location, message: "\(key) value \(valueKey) is outside the slider's range."))
                        }
                    }
                }
                if let neutralValue = property.control.neutralValue, !range.contains(neutralValue) {
                    diagnostics.append(.init(severity: .error, location: location, message: "The slider's neutralValue is outside its range."))
                }
            }
            guard case .number(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A number control requires a numeric default value."))
                return
            }
            if let minimum = property.control.minimum, value < minimum {
                diagnostics.append(.init(severity: .error, location: location, message: "The default value is below the control minimum."))
            }
            if let maximum = property.control.maximum, value > maximum {
                diagnostics.append(.init(severity: .error, location: location, message: "The default value is above the control maximum."))
            }
        case .toggle, .button:
            if case .boolean = defaultValue {} else {
                diagnostics.append(.init(severity: .error, location: location, message: "A \(property.control.type.rawValue) control requires a Boolean default value."))
            }
        case .frameworkBorder:
            guard case .object(let fields) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkBorder default requires a dictionary with width and optional style."))
                return
            }
            for key in fields.keys where !["width", "style"].contains(key) {
                diagnostics.append(.init(severity: .error, location: location, message: "Unknown border default key '\(key)'."))
            }
            if PartPackageFrameworkBorderWidthControl.defaultValue(fields["width"] ?? .string("")) == nil {
                diagnostics.append(.init(severity: .error, location: location,
                    message: "default.width requires a border width token, none, a nonnegative custom length (px/rem/em), or four edge defaults."))
            }
            if let style = fields["style"] {
                if case .string(let name) = style, PartPackageFrameworkBorderControl.styles.contains(name) {} else {
                    diagnostics.append(.init(severity: .error, location: location, message: "Invalid border style."))
                }
            }
        case .frameworkSpacing:
            if PartPackageSingleSpacingControl.defaultValue(defaultValue) == nil {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkSpacing default requires a spacing token, none, or a nonnegative {value, unit} length (px/rem/em/%)."))
            }
        case .frameworkRadius:
            if PartPackageFrameworkRadiusControl.defaultValue(defaultValue) == nil {
                diagnostics.append(.init(severity: .error, location: location,
                    message: "A frameworkRadius default must be a radius token, none, a nonnegative {value, unit} length (px/rem/em/%), or a dictionary with topLeft/topRight/bottomLeft/bottomRight defaults."))
            }
        case .frameworkMargin:
            if PartPackageFrameworkMarginControl.defaultValue(defaultValue) == nil {
                diagnostics.append(.init(severity: .error, location: location,
                    message: "A frameworkMargin default must be a spacing token, none, auto, a finite {value, unit} length (px/rem/em/%), or a dictionary with top/right/bottom/left defaults."))
            }
        case .frameworkPadding:
            if PartPackageFrameworkPaddingControl.defaultValue(defaultValue) == nil {
                diagnostics.append(.init(severity: .error, location: location,
                    message: "A frameworkPadding default must be a spacing token, a nonnegative {value, unit} length (px/rem/em/%), or a dictionary with top/right/bottom/left defaults."))
            }
        case .edges:
            if let converted = PartPackageFrameworkMarginControl.customDefaultValue(defaultValue, units: boxUnits(for: property, fallback: MarginPolicy.units)) {
                if property.control.linked == true, !converted.allEqual {
                    diagnostics.append(.init(severity: .error, location: location,
                        message: "linked: true requires all four edge defaults to be equal."))
                }
            } else {
                diagnostics.append(.init(severity: .error, location: location,
                    message: "An edges default must be a {value, unit} length in a declared unit, or a dictionary with top/right/bottom/left lengths. Framework tokens are not accepted."))
            }
        case .corners:
            if let converted = PartPackageFrameworkRadiusControl.customDefaultValue(defaultValue, units: boxUnits(for: property, fallback: RadiusPolicy.units)) {
                if property.control.linked == true, !converted.allEqual {
                    diagnostics.append(.init(severity: .error, location: location,
                        message: "linked: true requires all four corner defaults to be equal."))
                }
            } else {
                diagnostics.append(.init(severity: .error, location: location,
                    message: "A corners default must be a nonnegative {value, unit} length in a declared unit, or a dictionary with topLeft/topRight/bottomLeft/bottomRight lengths. Framework tokens are not accepted."))
            }
        case .frameworkFont:
            let fields = PartPackageFontControl.defaults(defaultValue)
            guard case .string(let family) = fields["family"], FrameworkFontRole(rawValue: family) != nil else {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkFont default family must be body, heading, or monospaced."))
                return
            }
            if property.control.showsFamily == false, property.control.showsWeight != true,
               property.control.showsStyle != true, property.control.showsSize != true {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkFont must expose at least one field."))
            }
            if let weight = fields["weight"] {
                if property.control.showsWeight != true {
                    diagnostics.append(.init(severity: .error, location: location, message: "default.weight requires showsWeight."))
                }
                if case .number(let value) = weight, value >= 1, value <= 1000, value.rounded() == value {} else {
                    diagnostics.append(.init(severity: .error, location: location, message: "default.weight must be an integer from 1 to 1000."))
                }
            }
            if let style = fields["style"] {
                if property.control.showsStyle != true {
                    diagnostics.append(.init(severity: .error, location: location, message: "default.style requires showsStyle."))
                }
                if case .string(let value) = style, ["normal", "italic"].contains(value) {} else {
                    diagnostics.append(.init(severity: .error, location: location, message: "default.style must be normal or italic."))
                }
            }
            if let size = fields["size"] {
                if property.control.showsSize != true {
                    diagnostics.append(.init(severity: .error, location: location, message: "default.size requires showsSize."))
                }
                // Only the predefined scale is portable; project custom sizes are not.
                if case .string(let value) = size, TypographyTokens.standardFontSizes.contains(where: { $0.id == value }) {} else {
                    diagnostics.append(.init(severity: .error, location: location, message: "default.size must be a predefined size ID: xs, sm, base, lg, xl, or 2xl through 9xl."))
                }
            }
        case .fontWeight:
            guard case .number(let value) = defaultValue, value >= 1, value <= 1000, value.rounded() == value else {
                diagnostics.append(.init(severity: .error, location: location, message: "A fontWeight default must be an integer from 1 to 1000."))
                return
            }
        case .fontStyle:
            guard case .string(let value) = defaultValue, ["normal", "italic"].contains(value) else {
                diagnostics.append(.init(severity: .error, location: location, message: "A fontStyle default must be normal or italic."))
                return
            }
        case .select:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A select default must match one of its options."))
                return
            }
            let declaredMatch = property.control.options?.contains(where: { $0.value == value }) == true
            if !declaredMatch {
                diagnostics.append(.init(severity: .error, location: location, message: "A select default must match one of its options."))
            }
        case .icon:
            guard case .string(let value) = defaultValue,
                  FoundryWebLibraryRegistry.icon(named: value) != nil else {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "An icon default must be a valid Foundry icon name, for example stars."
                ))
                return
            }
        case .date:
            guard case .string(let value) = defaultValue,
                  let date = PartDateValue(value) else {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A date control requires a real calendar date using YYYY-MM-DD."
                ))
                return
            }
            if let minimum = property.control.minimumDate.flatMap(PartDateValue.init), date.date < minimum.date {
                diagnostics.append(.init(severity: .error, location: location, message: "The default date is before minimum."))
            }
            if let maximum = property.control.maximumDate.flatMap(PartDateValue.init), date.date > maximum.date {
                diagnostics.append(.init(severity: .error, location: location, message: "The default date is after maximum."))
            }
        case .color:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A color control requires a string default value."))
                return
            }
            let pattern = property.control.opacity == true
                ? #"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#
                : #"^#[0-9A-Fa-f]{6}$"#
            if !value.matches(pattern) {
                diagnostics.append(.init(severity: .error, location: location, message: property.control.opacity == true
                    ? "A color default must be a six- or eight-digit hexadecimal colour."
                    : "A color default must be a six-digit hexadecimal colour; visibleWhen opacity to use alpha."))
            }
        case .frameworkColor:
            guard case .object(let initial) = defaultValue,
                  case .string(let value)? = initial["palette"] else {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkColor default requires a dictionary with a string palette."))
                return
            }
            for key in initial.keys where !["palette", "lightShade", "darkShade", "opacity"].contains(key) {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "Unknown frameworkColor default key '\(key)'."))
            }
            if let supplied = initial["opacity"] {
                if case .number(let alpha) = supplied, alpha.isFinite, (0...1).contains(alpha) {
                    if property.control.opacity != true {
                        diagnostics.append(.init(severity: .error, location: "\(location).opacity", message: "An opacity default requires opacity: true on the frameworkColor control."))
                    }
                } else {
                    diagnostics.append(.init(severity: .error, location: "\(location).opacity", message: "An opacity default must be a number from 0 to 1."))
                }
            }
            for key in ["lightShade", "darkShade"] {
                guard let supplied = initial[key] else { continue }
                if case .number(let number) = supplied, let shade = Int(exactly: number), (1...11).contains(shade) {
                    if value == PartFrameworkValueSelection.manifestCustom {
                        diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "\(key) requires a framework or standard palette, not custom."))
                    }
                } else {
                    diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "\(key) must be an integer from 1 to 11."))
                }
            }
            let isFrameworkRole = FrameworkColorRole(rawValue: value) != nil
            let isStandard = ColourPaletteDefaults.standard.contains { $0.id == value }
            let isCustom = value == PartFrameworkValueSelection.manifestCustom && property.control.allowsCustom.orFalse
            if !isFrameworkRole && !isStandard && !isCustom {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkColor default must be a framework role, a supported standard palette ID such as standard.lime, or custom when allowsCustom is true."))
            }
            if value == PartFrameworkValueSelection.manifestCustom && property.control.customColor == nil {
                diagnostics.append(.init(severity: .error, location: location, message: "customColor is required when a frameworkColor default is custom."))
            }
            if let customColor = property.control.customColor,
               !customColor.matches(#"^#[0-9A-Fa-f]{6}$"#) {
                diagnostics.append(.init(severity: .error, location: location, message: "customColor must be a six-digit hexadecimal colour."))
            }
        case .frameworkShadow:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkShadow control requires a string default value."))
                return
            }
            let isFrameworkShadow = Framework.standard.shadowChoices.contains { $0.value == value }
            let isAllowedCustom = value == PartFrameworkValueSelection.manifestCustom
                && property.control.allowsCustom.orFalse
            if !isFrameworkShadow && !isAllowedCustom {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A frameworkShadow default must be a standard framework shadow ID, or custom when allowsCustom is enabled."
                ))
            }
        case .frameworkFontSize:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkFontSize control requires a string default value."))
                return
            }
            // Only the predefined scale is portable; project custom sizes are not.
            if !TypographyTokens.standardFontSizes.contains(where: { $0.id == value }) {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A frameworkFontSize default must be a predefined size ID: xs, sm, base, lg, xl, or 2xl through 9xl."
                ))
            }
        case .frameworkStackingOrder:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A frameworkStackingOrder control requires a string default value."))
                return
            }
            // Only the predefined scale is portable; project custom values are not.
            if !FrameworkDimensionTokens.standardZIndexes.predefined.contains(where: { $0.id == value }) {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A frameworkStackingOrder default must be a predefined stacking ID: base, dropdown, sticky, overlay, modal, tooltip, or toast."
                ))
            }
        case .pageFolder:
            // Folders belong to individual projects, so no selection is portable.
            guard case .string(let value) = defaultValue, value.isEmpty else {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A pageFolder default must be an empty string; users choose a project folder in the Inspector."
                ))
                return
            }
        case .textAlignment:
            if case .string(let value) = defaultValue,
               ["start", "center", "end", "justify"].contains(value) {
                break
            }
            diagnostics.append(.init(
                severity: .error,
                location: location,
                message: "A textAlignment default must be start, center, end, or justify."
            ))
        default:
            if case .string = defaultValue {} else {
                diagnostics.append(.init(severity: .error, location: location, message: "This control requires a string default value."))
            }
        }
    }

    private static func validateDateBounds(
        _ property: PartPackageProperty,
        location: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard property.control.type == .date else { return }
        let minimum = property.control.minimumDate.flatMap(PartDateValue.init)
        let maximum = property.control.maximumDate.flatMap(PartDateValue.init)
        if property.control.minimumDate != nil, minimum == nil {
            diagnostics.append(.init(severity: .error, location: "\(location).minimum", message: "minimum must be a real calendar date using YYYY-MM-DD."))
        }
        if property.control.maximumDate != nil, maximum == nil {
            diagnostics.append(.init(severity: .error, location: "\(location).maximum", message: "maximum must be a real calendar date using YYYY-MM-DD."))
        }
        if let minimum, let maximum, minimum.date > maximum.date {
            diagnostics.append(.init(severity: .error, location: "\(location).maximum", message: "maximum must be the same as or later than minimum."))
        }
    }

    private static func validateButtonMapping(
        _ value: PartPackageValue?,
        key: String,
        count: Int,
        location: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard case .array(let values) = value, values.count != count else { return }
        diagnostics.append(.init(
            severity: .error,
            location: "\(location).\(key)",
            message: "A button control array requires exactly \(count) \(key) values."
        ))
    }

    private static func validateUnique(_ values: [String], kind: String, into diagnostics: inout [PartPackageDiagnostic]) {
        var seen: Set<String> = []
        for value in values where !seen.insert(value).inserted {
            diagnostics.append(.init(severity: .error, location: "manifest.json", message: "Duplicate \(kind) identifier '\(value)'."))
        }
    }

    private static func validateVisibility(
        _ property: PartPackageProperty,
        properties: [PartPackageProperty],
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard let visibleWhen = property.visibleWhen else { return }
        let location = "manifest.json:inspector.\(property.id).visibleWhen"
        validateVisibilityCondition(visibleWhen, property: property, properties: properties, location: location, into: &diagnostics)
    }

    private static func validateVisibilityCondition(
        _ visibleWhen: PartPackageVisibilityCondition,
        property: PartPackageProperty,
        properties: [PartPackageProperty],
        location: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        if let all = visibleWhen.all {
            for (index, condition) in all.enumerated() {
                validateVisibilityCondition(condition, property: property, properties: properties, location: "\(location).all[\(index)]", into: &diagnostics)
            }
            return
        }
        if let any = visibleWhen.any {
            for (index, condition) in any.enumerated() {
                validateVisibilityCondition(condition, property: property, properties: properties, location: "\(location).any[\(index)]", into: &diagnostics)
            }
            return
        }
        guard let id = visibleWhen.id else {
            diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen requires an id, all, or any expression."))
            return
        }
        let expression = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)?)(?:\[([0-9]+)\])?$"#)
        guard let match = expression.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
              let keyRange = Range(match.range(at: 1), in: id) else {
            diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen id must reference a control, optionally followed by a zero-based array index."))
            return
        }
        let key = String(id[keyRange])
        guard key != property.id else {
            diagnostics.append(.init(severity: .error, location: location, message: "A control's visibleWhen condition cannot reference itself."))
            return
        }
        guard let source = properties.first(where: { $0.id == key }) else {
            diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen references unknown control '\(key)'."))
            return
        }
        if let indexRange = Range(match.range(at: 2), in: id), let index = Int(id[indexRange]) {
            guard let count = source.control.count else {
                diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen index requires '\(key)' to be a multi-control."))
                return
            }
            if index >= count {
                diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen index \(index) is outside '\(key)' count \(count)."))
            }
        }

        let operation = PartPackageVisibilityEvaluator.canonicalOperation(visibleWhen.operation)
        let supported = Set(["==", "!=", "<", "<=", ">", ">=", "contains", "notContains",
                             "containsInsensitive", "notContainsInsensitive", "matches", "notMatches",
                             "matchesInsensitive", "notMatchesInsensitive", "containsValue", "notContainsValue",
                             "isEmpty", "isNotEmpty"])
        guard supported.contains(operation) else {
            diagnostics.append(.init(severity: .error, location: location, message: "Unknown visibleWhen operation '\(visibleWhen.operation)'."))
            return
        }
        let needsValue = operation != "isEmpty" && operation != "isNotEmpty"
        if needsValue && visibleWhen.value == nil {
            diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen operation '\(operation)' requires a value."))
        } else if !needsValue && visibleWhen.value != nil {
            diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen operation '\(operation)' does not accept a value."))
        }
    }

    private static func validateVisibilityCycles(
        _ properties: [PartPackageProperty],
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        // Duplicate IDs are reported separately; they must not stop validation here.
        let dependencies = Dictionary(properties.map { property in
            (property.id, visibilityReferences(property.visibleWhen))
        }, uniquingKeysWith: { first, _ in first })
        for property in properties {
            var visited = Set<String>()
            func visit(_ value: String) {
                guard visited.insert(value).inserted else {
                    diagnostics.append(.init(severity: .error, location: "manifest.json:inspector.\(property.id).visibleWhen", message: "visibleWhen conditions contain a dependency cycle."))
                    return
                }
                for next in dependencies[value] ?? [] { visit(next) }
                visited.remove(value)
            }
            visit(property.id)
        }
    }

    private static func visibilityReferences(_ condition: PartPackageVisibilityCondition?) -> Set<String> {
        guard let condition else { return [] }
        if let id = condition.id { return [String(id.prefix { $0 != "[" })] }
        return Set((condition.all ?? condition.any ?? []).flatMap { visibilityReferences($0) })
    }

    private static func validate(
        _ value: String,
        expression: NSRegularExpression,
        location: String,
        message: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        if expression.firstMatch(in: value, range: range) == nil {
            diagnostics.append(.init(severity: .error, location: location, message: message))
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}

private nonisolated extension Optional where Wrapped == Bool {
    var orFalse: Bool { self ?? false }
}

private nonisolated struct PartTemplateReference {
    let value: String
    let offset: Int
}

private nonisolated struct PartRootStructureIssue {
    let offset: Int
    let message: String
}

nonisolated struct PartHTMLTag {
    let range: Range<String.Index>
    let name: String
    let isClosing: Bool
    let isSelfClosing: Bool
}

nonisolated extension String {
    private static var partRootStructureMessage: String {
        "The primary HTML template must contain exactly one stable top-level root element. Put all rendered markup and template macros inside that root; only whitespace and HTML comments may appear outside it."
    }

    private static let htmlVoidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]

    fileprivate var partRootStructureIssue: PartRootStructureIssue? {
        guard let rootStart = indexAfterPartTemplateTrivia(from: startIndex),
              rootStart < endIndex,
              self[rootStart] == "<",
              let root = partHTMLTag(at: rootStart),
              !root.isClosing else {
            return .init(offset: 0, message: Self.partRootStructureMessage)
        }

        if root.isSelfClosing || Self.htmlVoidElements.contains(root.name) {
            return trailingPartRootIssue(after: root.range.upperBound)
        }

        var depth = 1
        var cursor = root.range.upperBound
        while cursor < endIndex,
              let tagStart = self[cursor...].firstIndex(of: "<") {
            if self[tagStart...].hasPrefix("<!--") {
                guard let commentEnd = range(of: "-->", range: tagStart..<endIndex)?.upperBound else {
                    return .init(offset: utf16Offset(of: tagStart), message: Self.partRootStructureMessage)
                }
                cursor = commentEnd
                continue
            }
            guard let tag = partHTMLTag(at: tagStart) else {
                cursor = index(after: tagStart)
                continue
            }
            cursor = tag.range.upperBound
            guard tag.name == root.name else { continue }
            if tag.isClosing {
                depth -= 1
                if depth == 0 {
                    return trailingPartRootIssue(after: tag.range.upperBound)
                }
            } else if !tag.isSelfClosing && !Self.htmlVoidElements.contains(tag.name) {
                depth += 1
            }
        }

        return .init(offset: utf16Offset(of: root.range.lowerBound), message: Self.partRootStructureMessage)
    }

    private func trailingPartRootIssue(after rootEnd: String.Index) -> PartRootStructureIssue? {
        guard let trailingStart = indexAfterPartTemplateTrivia(from: rootEnd) else {
            return .init(offset: utf16Offset(of: rootEnd), message: Self.partRootStructureMessage)
        }
        guard trailingStart == endIndex else {
            return .init(offset: utf16Offset(of: trailingStart), message: Self.partRootStructureMessage)
        }
        return nil
    }

    func indexAfterPartTemplateTrivia(from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < endIndex {
            if self[cursor].isWhitespace {
                cursor = index(after: cursor)
                continue
            }
            if self[cursor...].hasPrefix("<!--") {
                guard let commentEnd = range(of: "-->", range: cursor..<endIndex)?.upperBound else {
                    return nil
                }
                cursor = commentEnd
                continue
            }
            break
        }
        return cursor
    }

    func partHTMLTag(at start: String.Index) -> PartHTMLTag? {
        guard start < endIndex, self[start] == "<" else { return nil }
        var cursor = index(after: start)
        var isClosing = false
        if cursor < endIndex, self[cursor] == "/" {
            isClosing = true
            cursor = index(after: cursor)
        }
        guard cursor < endIndex,
              self[cursor] != "!",
              self[cursor] != "?" else { return nil }

        let nameStart = cursor
        var templateDepth = 0
        while cursor < endIndex {
            if self[cursor...].hasPrefix("{{") {
                templateDepth += 1
                cursor = index(cursor, offsetBy: 2)
                continue
            }
            if templateDepth > 0, self[cursor...].hasPrefix("}}") {
                templateDepth -= 1
                cursor = index(cursor, offsetBy: 2)
                continue
            }
            let character = self[cursor]
            if templateDepth == 0, character.isWhitespace || character == ">" || character == "/" {
                break
            }
            cursor = index(after: cursor)
        }
        guard cursor > nameStart else { return nil }
        let name = self[nameStart..<cursor]
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .lowercased()

        var tagCursor = cursor
        var quote: Character?
        var tagTemplateDepth = 0
        while tagCursor < endIndex {
            if quote == nil, self[tagCursor...].hasPrefix("{{") {
                tagTemplateDepth += 1
                tagCursor = index(tagCursor, offsetBy: 2)
                continue
            }
            if quote == nil, tagTemplateDepth > 0, self[tagCursor...].hasPrefix("}}") {
                tagTemplateDepth -= 1
                tagCursor = index(tagCursor, offsetBy: 2)
                continue
            }
            let character = self[tagCursor]
            if tagTemplateDepth == 0 {
                if let activeQuote = quote {
                    if character == activeQuote { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    let tagEnd = index(after: tagCursor)
                    let body = self[start..<tagCursor].trimmingCharacters(in: .whitespacesAndNewlines)
                    return .init(
                        range: start..<tagEnd,
                        name: name,
                        isClosing: isClosing,
                        isSelfClosing: !isClosing && body.hasSuffix("/")
                    )
                }
            }
            tagCursor = index(after: tagCursor)
        }
        return nil
    }

    private func utf16Offset(of index: String.Index) -> Int {
        utf16.distance(from: utf16.startIndex, to: index.samePosition(in: utf16) ?? utf16.endIndex)
    }

    var firstRootOpeningTag: String? {
        let pattern = #"(?is)\A\s*(?:(?:<!--.*?-->)|(?:<!DOCTYPE.*?>)|(?:<\?.*?\?>))*\s*(<(?!!|/)[^>]+>)"#
        let expression = try! NSRegularExpression(pattern: pattern)
        guard let match = expression.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }

    fileprivate func matches(_ pattern: String) -> Bool {
        matchCount(pattern) > 0
    }

    func matchCount(_ pattern: String) -> Int {
        let expression = try! NSRegularExpression(pattern: pattern)
        return expression.numberOfMatches(in: self, range: NSRange(startIndex..., in: self))
    }

    fileprivate func references(matching pattern: String) -> [PartTemplateReference] {
        let expression = try! NSRegularExpression(pattern: pattern)
        return expression.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: self) else { return nil }
            return PartTemplateReference(value: String(self[valueRange]), offset: match.range.location)
        }
    }
}
