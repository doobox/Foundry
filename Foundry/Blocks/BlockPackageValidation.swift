import Foundation

nonisolated struct BlockPackageDiagnostic: Equatable, Sendable {
    enum Severity: String, Sendable {
        case error
        case warning
    }

    let severity: Severity
    let location: String
    let message: String
}

nonisolated enum BlockPackageValidator {
    static let maximumIconByteCount = 64 * 1024
    private static let maximumTagCount = 5
    private static let identifierExpression = try! NSRegularExpression(
        pattern: #"^[a-z](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?){2,}$"#
    )
    private static let propertyExpression = try! NSRegularExpression(
        pattern: #"^[A-Za-z][A-Za-z0-9_-]*$"#
    )
    static func validate(_ manifest: BlockPackageManifest, rootURL: URL) -> [BlockPackageDiagnostic] {
        var diagnostics: [BlockPackageDiagnostic] = []

        if manifest.minimumAPIVersion > FoundryBlockAPI.supportedVersions.upperBound {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:minimumAPIVersion",
                message: "This block requires Foundry block API \(manifest.minimumAPIVersion), but this version of Foundry supports through API \(FoundryBlockAPI.supportedVersions.upperBound). Update Foundry to use this block."
            ))
        } else if manifest.minimumAPIVersion < FoundryBlockAPI.supportedVersions.lowerBound {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:minimumAPIVersion",
                message: "This block requires an unsupported Foundry block API."
            ))
        }
        validate(manifest.identifier, expression: identifierExpression, location: "Info.plist:id", message: "Use a lowercase reverse-DNS identifier, for example com.example.focal-point-hero.", into: &diagnostics)
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(.init(severity: .error, location: "Info.plist:title", message: "A block title is required."))
        }
        if SemanticVersion(manifest.version) == nil {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:version",
                message: "Use a semantic version in MAJOR.MINOR.PATCH form, for example 1.0.0."
            ))
        }
        if manifest.tags.count > maximumTagCount {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:tags",
                message: "A block can declare at most \(maximumTagCount) tags."
            ))
        }

        var seenLibraries = Set<BlockPackageLibraryRequirement>()
        for library in manifest.libraries {
            let location = "Info.plist:libraries.\(library.identifier)"
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

        validateUnique(manifest.properties.map(\.id), kind: "property", into: &diagnostics)
        validateUnique(manifest.slots.map(\.id), kind: "slot", into: &diagnostics)
        for property in manifest.properties {
            validate(property.id, expression: propertyExpression, location: "Info.plist:controls.\(property.id)", message: "Property IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.", into: &diagnostics)
            validate(property, into: &diagnostics)
            validateVisibility(property, properties: manifest.properties, into: &diagnostics)
            if let font = property.control.font,
               !manifest.properties.contains(where: { $0.id == font && $0.control.type == .themeFont }) {
                diagnostics.append(.init(severity: .error, location: "Info.plist:controls.\(property.id).font", message: "font must reference a themeFont control in this block."))
            }
        }
        validateVisibilityCycles(manifest.properties, into: &diagnostics)
        for slot in manifest.slots {
            validate(slot.id, expression: propertyExpression, location: "Info.plist:slots.\(slot.id)", message: "Slot IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.", into: &diagnostics)
            if slot.minimum < 0 || (slot.maximum.map { $0 < slot.minimum } == true) {
                diagnostics.append(.init(severity: .error, location: "Info.plist:slots.\(slot.id)", message: "Slot minimum and maximum values are inconsistent."))
            }
            if slot.accepts.isEmpty {
                diagnostics.append(.init(severity: .error, location: "Info.plist:controls.\(slot.id)", message: "A childPicker must accept at least one block identifier, category, or '*'."))
            }
        }

        let declaredFiles = ["icon.svg", manifest.render.html, manifest.render.editorCSS]
            .compactMap { $0 }
            .filter { !$0.isEmpty } + manifest.assets.map(\.path) + manifest.render.files.map(\.path)
        for path in declaredFiles {
            if !isSafeRelativePath(path) {
                diagnostics.append(.init(severity: .error, location: path, message: "Package paths must be relative and cannot contain '..'."))
            } else if !FileManager.default.fileExists(atPath: rootURL.appending(path: path).path) {
                diagnostics.append(.init(severity: .error, location: path, message: "The declared package file does not exist."))
            }
        }
        let iconURL = rootURL.appending(path: "icon.svg")
        if let byteCount = try? iconURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           byteCount > maximumIconByteCount {
            diagnostics.append(.init(
                severity: .error,
                location: "icon.svg",
                message: "Block icons cannot exceed 64 KiB."
            ))
        }
        for file in manifest.render.files {
            let fileExtension = URL(fileURLWithPath: file.path).pathExtension.lowercased()
            if file.scope == .site, fileExtension != "css" {
                diagnostics.append(.init(
                    severity: .error,
                    location: "Info.plist:templates.files.\(file.path)",
                    message: "Site scope is available only to CSS templates."
                ))
            }
            if fileExtension == "css", file.placement != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "Info.plist:templates.files.\(file.path)",
                    message: "CSS templates do not use HTML placement."
                ))
            }
            if fileExtension == "js", file.placement != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "Info.plist:templates.files.\(file.path)",
                    message: "JavaScript templates are emitted at the end of the body and do not use placement."
                ))
            }
            if fileExtension == "php", file.placement != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "Info.plist:templates.files.\(file.path)",
                    message: "PHP templates run before page markup and do not use HTML placement."
                ))
            }
            if fileExtension == "html", file.placement == nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "Info.plist:templates.files.\(file.path)",
                    message: "Additional HTML templates require placement."
                ))
            }
            if fileExtension == "html", file.scope == .instance {
                diagnostics.append(.init(
                    severity: .error,
                    location: "Info.plist:templates.files.\(file.path)",
                    message: "Placed HTML templates currently require page scope."
                ))
            }
            if fileExtension != "css" && fileExtension != "html" && fileExtension != "js" && fileExtension != "php" {
                diagnostics.append(.init(
                    severity: .error,
                    location: "Info.plist:templates.files.\(file.path)",
                    message: "Template files currently support CSS, JavaScript, PHP and placed HTML."
                ))
            }
        }
        let declaresPHP = manifest.render.files.contains { $0.path.lowercased().hasSuffix(".php") }
            || manifest.assets.contains { $0.path.lowercased().hasSuffix(".php") }
        if !manifest.requiresPHP, declaresPHP {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:requiresPHP",
                message: "Blocks with PHP templates or assets must set requiresPHP to true."
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
        for file in manifest.render.files where file.scope != .instance {
            guard let template = templateContents[file.path] else {
                continue
            }
            if template.matches(#"\{\{\s*(?:id|instance\.|block\.|control\.|slot\.)"#) ||
                template.matches(#"\{\{\s*(?:text|html|image|dropZone|childArea)\s*\("#) ||
                template.matches(#"\{\{\s*(?:slot\s+id|text(?:\s*=|\s*\}\})|html(?:\s*=|\s*\}\})|image(?:\s+[^}]+)?\s*\}\})"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: file.path,
                    message: "Page- and site-scoped templates cannot use instance, block, control, slot, or editable-content macros."
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
        manifest: BlockPackageManifest,
        into diagnostics: inout [BlockPackageDiagnostic]
    ) {
        let propertyIDs = Set(manifest.properties.filter { $0.control.type != .divider }.map(\.id))
        let childPickerIDs = Set(manifest.slots.map(\.id))

        if requiresEditorAttributes {
            let rootTag = template.firstRootOpeningTag ?? ""
            if !rootTag.matches(#"\{\{\s*block\.attributes\s*\}\}"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "The root element must include {{ block.attributes }}."
                ))
            }
            if !rootTag.matches(#"(?i)\bclass\s*=\s*([\"'])[^\"']*\{\{\s*block\.class\s*\}\}[^\"']*\1"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "The root class must include {{ block.class }}."
                ))
            } else if rootTag.matches(#"[^\s\"']\{\{\s*block\.class\s*\}\}"#) ||
                        rootTag.matches(#"\{\{\s*block\.class\s*\}\}[^\s\"']"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Separate {{ block.class }} from adjacent class names with literal whitespace."
                ))
            }
            if rootTag.matches(#"(?i)\sid\s*="#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "The block root cannot declare an id."
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
        for property in manifest.properties
            where property.control.type != .color && property.control.type != .themeColor {
            let escapedID = NSRegularExpression.escapedPattern(for: property.id)
            if template.matches(#"\{\{\s*control\."# + escapedID + #"\s*\|\s*(?:lighten|darken|withAlpha|mix)\s*\("#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Colour filters are not available for '\(property.id)'."
                ))
            }
        }
        for property in manifest.properties where property.control.type != .date {
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
        let primitiveDeclarations = (try? BlockTemplateLoop.declarations(in: template)) ?? []
        let primitiveNames = primitiveDeclarations.map(\.key)
        let primitiveCandidateCount = template.matchCount(#"\{\{\s*(?:text|html|image)\b[^}]*\}\}"#)
        if primitiveCandidateCount != primitiveNames.count {
            diagnostics.append(.init(
                severity: .error,
                location: templateLocation,
                message: "Every editable macro must have a permanent quoted name, for example {{ text(\"heading\", default: \"Heading\") }} or {{ image(\"hero\") }}."
            ))
        }
        if requiresEditorAttributes {
            let dropZoneNames = BlockTemplateRenderer.dropZoneNames(in: template)
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
            let childReferences = Set(template.references(
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
                    message: "Asset '\(reference.value)' must be declared in Info.plist."
                ))
            }
        }

        for (index, property) in manifest.properties.enumerated() where property.control.type == .image {
            let defaultPath = property.defaultValue.stringValue
            if !defaultPath.isEmpty && manifest.assetDeclaration(containing: defaultPath) == nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "Info.plist:controls[\(index)].default",
                    message: "The default image '\(defaultPath)' must reference a declared package asset."
                ))
            }
        }

        for reference in template.references(
            matching: #"<img\b[^>]*\bsrc\s*=\s*[\"']\{\{\s*control\.([A-Za-z][A-Za-z0-9_-]*)(?:\.href|\.rendition\.[A-Za-z][A-Za-z0-9_-]*(?:\.href)?)?\s*\}\}[\"']"#
        ) {
            let propertyID = replacingLoopMetadata(in: reference.value)
            guard let property = manifest.properties.first(where: { $0.id == propertyID }),
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
                  let property = manifest.properties.first(where: { $0.id == parts[0] }),
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
            let maximums = Dictionary(uniqueKeysWithValues: manifest.properties.compactMap { property -> (String, Int)? in
                guard property.control.type == .number || property.control.type == .slider,
                      let maximum = property.control.maximum,
                      maximum.isFinite,
                      maximum >= 0,
                      maximum <= Double(BlockTemplateLoop.maximumIterationCount) else { return nil }
                return (property.id, Int(maximum.rounded(.down)))
            })
            do {
                _ = try BlockTemplateLoop.expand(
                    template,
                    properties: Dictionary(uniqueKeysWithValues: manifest.properties.map { ($0.id, $0.defaultValue) }),
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
                    let expression = try BlockTemplateExpression.parse(predicate)
                    try BlockTemplateExpression.validate(expression)
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
                if !(0...BlockTemplateLoop.maximumIterationCount).contains(literal) {
                    diagnostics.append(templateDiagnostic(
                        templateLocation,
                        template: template,
                        offset: reference.offset,
                        message: "A literal loop count must be between 0 and \(BlockTemplateLoop.maximumIterationCount)."
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
            guard let property = manifest.properties.first(where: { $0.id == propertyID }) else {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "Unknown property '\(propertyID)'. Declare it in Info.plist controls."
                ))
                continue
            }
            if case .array = property.defaultValue { continue }
            guard property.control.type == .number || property.control.type == .slider,
                  let maximum = property.control.maximum,
                  maximum.isFinite,
                  maximum >= 0,
                  maximum <= Double(BlockTemplateLoop.maximumIterationCount) else {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "A loop control must be numeric and declare a maximum from 0 through \(BlockTemplateLoop.maximumIterationCount)."
                ))
                continue
            }
        }

        for reference in template.references(matching: #"\{\{\s*(?:if|elseif)\s+([^{}]+?)\s*\}\}"#) {
            let condition = replacingLoopMetadata(in: reference.value.trimmingCharacters(in: .whitespacesAndNewlines))
            do {
                let expression = try BlockTemplateExpression.parse(condition)
                try BlockTemplateExpression.validate(expression)
                for propertyID in Set(BlockTemplateExpression.references(in: expression)) where !propertyIDs.contains(propertyID) {
                    diagnostics.append(templateDiagnostic(
                        templateLocation,
                        template: template,
                        offset: reference.offset,
                        message: "Unknown property '\(propertyID)'. Declare it in Info.plist controls."
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
                source.hasPrefix("image(") || source.hasPrefix("dropZone(") || source.hasPrefix("childArea(") || source.hasPrefix("asset(") ||
                ["text", "html", "image", "instance.id", "package.id", "site.baseURL", "page.url", "path.siteRoot", "path.siteAssets", "block.class", "block.attributes", "dropZone", "childArea", "asset"].contains(source) {
                continue
            }
            if loopAliases.contains(where: { source == $0 || source.hasPrefix($0 + ".") }) { continue }
            let normalizedSource = replacingLoopMetadata(in: source)
            let expressionSource = BlockTemplateExpression.templateParts(normalizedSource).first ?? normalizedSource
            do {
                let expression = try BlockTemplateExpression.parse(expressionSource)
                try BlockTemplateExpression.validate(expression)
                for propertyID in Set(BlockTemplateExpression.references(in: expression)) where !propertyIDs.contains(propertyID) {
                    diagnostics.append(templateDiagnostic(
                        templateLocation,
                        template: template,
                        offset: match.range.location,
                        message: "Unknown property '\(propertyID)'. Declare it in Info.plist controls."
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
            "id", "instance", "package", "site", "page", "path", "block", "control", "asset", "slot", "dropZone", "childArea",
            "if", "elseif", "else", "endif", "loop", "endloop", "text", "html", "image", "canvas", "preview", "published", "navigation", "pages", "assets"
        ]
        for reference in template.references(matching: #"\{\{\s*([A-Za-z]+)(?:\.|\s|\}\})"#)
            where !supportedMacroNames.contains(reference.value) && !loopAliases.contains(reference.value) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Unknown template macro '\(reference.value)'."
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
        severity: BlockPackageDiagnostic.Severity = .error,
        message: String
    ) -> BlockPackageDiagnostic {
        let line = template.prefix(offset).reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
        return .init(severity: severity, location: "\(location):\(line)", message: message)
    }

    private static func validate(_ property: BlockPackageProperty, into diagnostics: inout [BlockPackageDiagnostic]) {
        let location = "Info.plist:controls.\(property.id)"
        validateThemeValues(property, location: location, into: &diagnostics)
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

    private static func validateThemeValues(
        _ property: BlockPackageProperty,
        location: String,
        into diagnostics: inout [BlockPackageDiagnostic]
    ) {
        if property.control.type == .select, property.control.themeValues != nil {
            diagnostics.append(.init(severity: .error, location: "\(location).themeValues",
                message: "Select supports only declared options; remove themeValues."))
        }
        let supportsCustomThemeValue = property.control.type == .shadow
            || property.control.type == .themeColor
        if property.control.allowsCustom != nil, !supportsCustomThemeValue {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).allowsCustom",
                message: "allowsCustom requires a theme-aware control."
            ))
        }

        if property.control.outputFormat != nil, property.control.type != .color {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).outputFormat",
                message: "outputFormat is supported only by color controls."
            ))
        }
        if property.control.type == .color {
            if property.control.themeValues != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).themeValues",
                    message: "A color control does not use themeValues; use type themeColor."
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
        } else if property.control.type == .themeColor {
            if property.control.themeValues != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).themeValues", message: "A themeColor control uses theme colours automatically; remove themeValues."))
            }
            if property.control.count != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).count", message: "A themeColor control cannot be a multi control; remove count."))
            }
            if property.control.customColor != nil, property.control.allowsCustom != true {
                diagnostics.append(.init(severity: .error, location: "\(location).customColor", message: "customColor requires allowsCustom to be true."))
            }
            return
        } else if property.control.themeValueDefault != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).themeValues",
                message: "The \(property.control.type.rawValue) control does not accept a theme role as themeValues."
            ))
        }
        if property.control.type == .shadow, property.control.themeValues != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).themeValues",
                message: "A shadow control automatically uses theme shadows; remove themeValues."
            ))
            return
        }

        guard let source = property.control.themeValueSource else { return }
        let supported: Bool
        switch (property.control.type, source) {
        case (.shadow, .shadows):
            supported = true
        default:
            supported = false
        }
        if !supported {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).themeValues",
                message: "The \(property.control.type.rawValue) control cannot request \(source.rawValue) theme values."
            ))
        }
    }

    private static func validate(
        _ defaultValue: BlockPackageValue,
        for property: BlockPackageProperty,
        location: String,
        allowsLiteralColor: Bool,
        into diagnostics: inout [BlockPackageDiagnostic]
    ) {
        switch property.control.type {
        case .divider, .note:
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
        case .themeFont:
            let fields = BlockPackageFontControl.defaults(defaultValue)
            guard case .string(let family) = fields["family"], ThemeFontRole(rawValue: family) != nil else {
                diagnostics.append(.init(severity: .error, location: location, message: "A themeFont default family must be body, heading, or monospaced."))
                return
            }
            if property.control.showsFamily == false && property.control.showsWeight != true && property.control.showsStyle != true {
                diagnostics.append(.init(severity: .error, location: location, message: "A themeFont must expose at least one field."))
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
                  let date = BlockDateValue(value) else {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A date control requires a real calendar date using YYYY-MM-DD."
                ))
                return
            }
            if let minimum = property.control.minimumDate.flatMap(BlockDateValue.init), date.date < minimum.date {
                diagnostics.append(.init(severity: .error, location: location, message: "The default date is before minimum."))
            }
            if let maximum = property.control.maximumDate.flatMap(BlockDateValue.init), date.date > maximum.date {
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
        case .themeColor:
            guard case .object(let initial) = defaultValue,
                  case .string(let value)? = initial["palette"] else {
                diagnostics.append(.init(severity: .error, location: location, message: "A themeColor default requires a dictionary with a string palette."))
                return
            }
            for key in initial.keys where !["palette", "lightShade", "darkShade"].contains(key) {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "Unknown themeColor default key '\(key)'."))
            }
            for key in ["lightShade", "darkShade"] {
                guard let supplied = initial[key] else { continue }
                if case .number(let number) = supplied, let shade = Int(exactly: number), (1...11).contains(shade) {
                    if value == BlockThemeValueSelection.manifestCustom {
                        diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "\(key) requires a theme-role palette, not custom."))
                    }
                } else {
                    diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "\(key) must be an integer from 1 to 11."))
                }
            }
            let isThemeRole = ThemeColorRole(rawValue: value) != nil
            let isCustom = value == BlockThemeValueSelection.manifestCustom && property.control.allowsCustom.orFalse
            if !isThemeRole && !isCustom {
                diagnostics.append(.init(severity: .error, location: location, message: "A themeColor default must be page, background, surface, text, muted-text, accent, links, or custom when allowsCustom is true."))
            }
            if value == BlockThemeValueSelection.manifestCustom && property.control.customColor == nil {
                diagnostics.append(.init(severity: .error, location: location, message: "customColor is required when a themeColor default is custom."))
            }
            if let customColor = property.control.customColor,
               !customColor.matches(#"^#[0-9A-Fa-f]{6}$"#) {
                diagnostics.append(.init(severity: .error, location: location, message: "customColor must be a six-digit hexadecimal colour."))
            }
        case .shadow:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A shadow control requires a string default value."))
                return
            }
            let isThemeShadow = Theme.standard.shadowChoices.contains { $0.value == value }
            let isAllowedCustom = value == BlockThemeValueSelection.manifestCustom
                && property.control.allowsCustom.orFalse
            if !isThemeShadow && !isAllowedCustom {
                diagnostics.append(.init(
                    severity: .error,
                    location: location,
                    message: "A shadow default must be a standard theme shadow ID, or custom when allowsCustom is enabled."
                ))
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
        _ property: BlockPackageProperty,
        location: String,
        into diagnostics: inout [BlockPackageDiagnostic]
    ) {
        guard property.control.type == .date else { return }
        let minimum = property.control.minimumDate.flatMap(BlockDateValue.init)
        let maximum = property.control.maximumDate.flatMap(BlockDateValue.init)
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
        _ value: BlockPackageValue?,
        key: String,
        count: Int,
        location: String,
        into diagnostics: inout [BlockPackageDiagnostic]
    ) {
        guard case .array(let values) = value, values.count != count else { return }
        diagnostics.append(.init(
            severity: .error,
            location: "\(location).\(key)",
            message: "A button control array requires exactly \(count) \(key) values."
        ))
    }

    private static func validateUnique(_ values: [String], kind: String, into diagnostics: inout [BlockPackageDiagnostic]) {
        var seen: Set<String> = []
        for value in values where !seen.insert(value).inserted {
            diagnostics.append(.init(severity: .error, location: "Info.plist", message: "Duplicate \(kind) identifier '\(value)'."))
        }
    }

    private static func validateVisibility(
        _ property: BlockPackageProperty,
        properties: [BlockPackageProperty],
        into diagnostics: inout [BlockPackageDiagnostic]
    ) {
        guard let visibleWhen = property.visibleWhen else { return }
        let location = "Info.plist:controls.\(property.id).visibleWhen"
        let expression = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9_-]*)(?:\[([0-9]+)\])?$"#)
        guard let match = expression.firstMatch(in: visibleWhen.id, range: NSRange(visibleWhen.id.startIndex..., in: visibleWhen.id)),
              let keyRange = Range(match.range(at: 1), in: visibleWhen.id) else {
            diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen id must reference a control, optionally followed by a zero-based array index."))
            return
        }
        let key = String(visibleWhen.id[keyRange])
        guard key != property.id else {
            diagnostics.append(.init(severity: .error, location: location, message: "A control's visibleWhen condition cannot reference itself."))
            return
        }
        guard let source = properties.first(where: { $0.id == key }) else {
            diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen references unknown control '\(key)'."))
            return
        }
        if let indexRange = Range(match.range(at: 2), in: visibleWhen.id), let index = Int(visibleWhen.id[indexRange]) {
            guard let count = source.control.count else {
                diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen index requires '\(key)' to be a multi-control."))
                return
            }
            if index >= count {
                diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen index \(index) is outside '\(key)' count \(count)."))
            }
        }

        let operation = BlockPackageVisibilityEvaluator.canonicalOperation(visibleWhen.operation)
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
        _ properties: [BlockPackageProperty],
        into diagnostics: inout [BlockPackageDiagnostic]
    ) {
        let dependencies = Dictionary(uniqueKeysWithValues: properties.compactMap { property -> (String, String)? in
            guard let id = property.visibleWhen?.id else { return nil }
            return (property.id, String(id.prefix { $0 != "[" }))
        })
        for property in properties {
            var visited = Set<String>()
            var current: String? = property.id
            while let value = current, let next = dependencies[value] {
                guard visited.insert(value).inserted else {
                    diagnostics.append(.init(severity: .error, location: "Info.plist:controls.\(property.id).visibleWhen", message: "visibleWhen conditions contain a dependency cycle."))
                    break
                }
                current = next
            }
        }
    }

    private static func validate(
        _ value: String,
        expression: NSRegularExpression,
        location: String,
        message: String,
        into diagnostics: inout [BlockPackageDiagnostic]
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

private nonisolated struct BlockTemplateReference {
    let value: String
    let offset: Int
}

private nonisolated extension String {
    var firstRootOpeningTag: String? {
        let pattern = #"(?is)\A\s*(?:(?:<!--.*?-->)|(?:<!DOCTYPE.*?>)|(?:<\?.*?\?>))*\s*(<(?!!|/)[^>]+>)"#
        let expression = try! NSRegularExpression(pattern: pattern)
        guard let match = expression.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }

    func matches(_ pattern: String) -> Bool {
        matchCount(pattern) > 0
    }

    func matchCount(_ pattern: String) -> Int {
        let expression = try! NSRegularExpression(pattern: pattern)
        return expression.numberOfMatches(in: self, range: NSRange(startIndex..., in: self))
    }

    func references(matching pattern: String) -> [BlockTemplateReference] {
        let expression = try! NSRegularExpression(pattern: pattern)
        return expression.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: self) else { return nil }
            return BlockTemplateReference(value: String(self[valueRange]), offset: match.range.location)
        }
    }
}
