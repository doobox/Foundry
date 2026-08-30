import Foundation

nonisolated struct ComponentPackageDiagnostic: Equatable, Sendable {
    enum Severity: String, Sendable {
        case error
        case warning
    }

    let severity: Severity
    let location: String
    let message: String
}

nonisolated enum ComponentPackageValidator {
    private static let identifierExpression = try! NSRegularExpression(
        pattern: #"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$"#
    )
    private static let propertyExpression = try! NSRegularExpression(
        pattern: #"^[A-Za-z][A-Za-z0-9_-]*$"#
    )
    static func validate(_ manifest: ComponentPackageManifest, rootURL: URL) -> [ComponentPackageDiagnostic] {
        var diagnostics: [ComponentPackageDiagnostic] = []

        validate(manifest.identifier, expression: identifierExpression, location: "Info.plist:CFBundleIdentifier", message: "Use a lowercase reverse-DNS identifier, for example com.example.hero.", into: &diagnostics)
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(.init(severity: .error, location: "Info.plist:title", message: "A component title is required."))
        }

        validateUnique(manifest.properties.map(\.id), kind: "property", into: &diagnostics)
        validateUnique(manifest.slots.map(\.id), kind: "slot", into: &diagnostics)
        if manifest.properties.filter(\.inlineEditable).count > 1 {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:customItems",
                message: "Only one property can be inline editable."
            ))
        }
        for property in manifest.properties {
            validate(property.id, expression: propertyExpression, location: "Info.plist:customItems.\(property.id)", message: "Property IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.", into: &diagnostics)
            validate(property, into: &diagnostics)
        }
        for slot in manifest.slots {
            validate(slot.id, expression: propertyExpression, location: "Info.plist:slots.\(slot.id)", message: "Slot IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.", into: &diagnostics)
            if slot.minimum < 0 || (slot.maximum.map { $0 < slot.minimum } == true) {
                diagnostics.append(.init(severity: .error, location: "Info.plist:slots.\(slot.id)", message: "Slot minimum and maximum values are inconsistent."))
            }
        }

        let declaredFiles = ["icon.svg", manifest.render.html, manifest.render.editorCSS]
            .compactMap { $0 }
            .filter { !$0.isEmpty } + manifest.assets + manifest.render.files.map(\.path)
        for path in declaredFiles {
            if !isSafeRelativePath(path) {
                diagnostics.append(.init(severity: .error, location: path, message: "Package paths must be relative and cannot contain '..'."))
            } else if !FileManager.default.fileExists(atPath: rootURL.appending(path: path).path) {
                diagnostics.append(.init(severity: .error, location: path, message: "The declared package file does not exist."))
            }
        }
        for file in manifest.render.files {
            let fileExtension = URL(fileURLWithPath: file.path).pathExtension.lowercased()
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
            if fileExtension == "html", file.scope != .page {
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
        if !manifest.requiresPhp,
           manifest.render.files.contains(where: { $0.path.lowercased().hasSuffix(".php") }) {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:requiresPhp",
                message: "Components with PHP templates must set requiresPhp to true."
            ))
        }
        let templates: [(path: String?, requiresEditorAttributes: Bool)] = [
            (manifest.render.html, true),
            (manifest.render.editorCSS, false)
        ] + manifest.render.files
            .filter { $0.path.lowercased().hasSuffix(".css") || $0.path.lowercased().hasSuffix(".html") || $0.path.lowercased().hasSuffix(".js") || $0.path.lowercased().hasSuffix(".php") }
            .map { ($0.path as String?, false) }
        for declaredTemplate in templates {
            guard let path = declaredTemplate.path,
                  isSafeRelativePath(path),
                  let template = try? String(contentsOf: rootURL.appending(path: path), encoding: .utf8) else {
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
            guard isSafeRelativePath(file.path),
                  let template = try? String(contentsOf: rootURL.appending(path: file.path), encoding: .utf8) else {
                continue
            }
            if template.matches(#"\{\{\s*(?:id|instance\.id|component\.|control\.|property\.|slot\.)"#) ||
                template.matches(#"\{%\s*(?:slot|if)\b"#) || template.matches(#"%(?:text(?:=|%)|image%)"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: file.path,
                    message: "Page- and site-scoped templates cannot use instance, component, control, property, slot, condition, or editable-text macros."
                ))
            }
        }
        return diagnostics
    }

    private static func validateTemplate(
        _ template: String,
        location templateLocation: String,
        requiresEditorAttributes: Bool,
        manifest: ComponentPackageManifest,
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        let propertyIDs = Set(manifest.properties.filter { $0.control.type != .divider }.map(\.id))
        let slotIDs = Set(manifest.slots.map(\.id))
        let declaredAssets = Set(manifest.assets)

        if requiresEditorAttributes && !template.matches(#"\{\{\s*component\.attributes\s*\}\}"#) {
            diagnostics.append(.init(
                severity: .error,
                location: templateLocation,
                message: "The root element must include {{ component.attributes }} so Foundry can select and edit the component."
            ))
        }

        for reference in template.references(matching: #"\{\{\s*(?:control|property)\.([A-Za-z][A-Za-z0-9_-]*)"#) +
            template.references(matching: #"\{%\s*if\s+property\.([A-Za-z][A-Za-z0-9_-]*)"#) {
            if !propertyIDs.contains(reference.value) {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "Unknown property '\(reference.value)'. Declare it in Info.plist customItems."
                ))
            }
        }

        let supportedFilters: Set<String> = ["lighten", "darken"]
        for reference in template.references(matching: #"\|\s*([A-Za-z][A-Za-z0-9_-]*)\s*\("#)
            where !supportedFilters.contains(reference.value) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Unknown template filter '\(reference.value)'."
            ))
        }
        for property in manifest.properties where property.control.colorMath != true {
            let escapedID = NSRegularExpression.escapedPattern(for: property.id)
            if template.matches(#"\{\{\s*control\."# + escapedID + #"\s*\|\s*(?:lighten|darken)\s*\("#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Enable colorMath on '\(property.id)' before using lighten or darken filters."
                ))
            }
        }

        let slotReferences = template.references(
            matching: #"\{%\s*slot\s+id\s*=\s*[\"']([A-Za-z][A-Za-z0-9_.-]*)[\"']"#
        )
        let legacySlotReferences = template.references(
            matching: #"\{\{\s*slot\.([A-Za-z][A-Za-z0-9_.-]*)\s*\}\}"#
        )
        for reference in slotReferences + legacySlotReferences where !slotIDs.contains(reference.value) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Unknown slot '\(reference.value)'. Declare it in Info.plist."
            ))
        }
        if let legacy = legacySlotReferences.first {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: legacy.offset,
                severity: .warning,
                message: "Use {% slot id=\"…\" %}; the {{ slot.… }} form cannot carry slot options."
            ))
        }
        if requiresEditorAttributes {
            let referencedSlotIDs = Set((slotReferences + legacySlotReferences).map(\.value))
            for slotID in slotIDs.subtracting(referencedSlotIDs).sorted() {
                diagnostics.append(.init(
                    severity: .error,
                    location: templateLocation,
                    message: "Declared slot '\(slotID)' is not placed in the template."
                ))
            }
        }

        for reference in template.references(matching: #"\{\{\s*asset\.([^\s}]+)\s*\}\}"#) {
            if !isSafeRelativePath(reference.value) {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "Asset paths must be relative and cannot contain '..'."
                ))
            } else if !declaredAssets.contains(reference.value) {
                diagnostics.append(templateDiagnostic(
                    templateLocation,
                    template: template,
                    offset: reference.offset,
                    message: "Asset '\(reference.value)' must be declared in Info.plist."
                ))
            }
        }

        let ifCount = template.matchCount(#"\{%\s*if\b"#)
        let endIfCount = template.matchCount(#"\{%\s*endif\s*%\}"#)
        let elseCount = template.matchCount(#"\{%\s*else\s*%\}"#)
        if ifCount != endIfCount || elseCount > ifCount {
            diagnostics.append(.init(
                severity: .error,
                location: templateLocation,
                message: "Conditional directives are unbalanced; every if requires one endif and at most one else."
            ))
        }

        let supportedDirectiveNames: Set<String> = ["if", "else", "endif", "slot"]
        for reference in template.references(matching: #"\{%\s*([A-Za-z]+)\b"#)
            where !supportedDirectiveNames.contains(reference.value) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Unknown template directive '\(reference.value)'."
            ))
        }
    }

    private static func templateDiagnostic(
        _ location: String,
        template: String,
        offset: Int,
        severity: ComponentPackageDiagnostic.Severity = .error,
        message: String
    ) -> ComponentPackageDiagnostic {
        let line = template.prefix(offset).reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
        return .init(severity: severity, location: "\(location):\(line)", message: message)
    }

    private static func validate(_ property: ComponentPackageProperty, into diagnostics: inout [ComponentPackageDiagnostic]) {
        let location = "Info.plist:customItems.\(property.id)"
        if let count = property.control.count {
            guard (2...4).contains(count) else {
                diagnostics.append(.init(severity: .error, location: location, message: "Control arrays must contain between two and four controls."))
                return
            }
            guard case .array(let values) = property.defaultValue, values.count == count else {
                diagnostics.append(.init(severity: .error, location: location, message: "A control array requires exactly \(count) default values."))
                return
            }
            if property.subtitles.count > count {
                diagnostics.append(.init(severity: .error, location: location, message: "A control array cannot have more subtitles than controls."))
            }
            for (index, value) in values.enumerated() {
                validate(value, for: property, location: "\(location).default[\(index)]", allowsLiteralColor: true, into: &diagnostics)
            }
            return
        }
        validate(property.defaultValue, for: property, location: location, allowsLiteralColor: false, into: &diagnostics)
    }

    private static func validate(
        _ defaultValue: ComponentPackageValue,
        for property: ComponentPackageProperty,
        location: String,
        allowsLiteralColor: Bool,
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        switch property.control.type {
        case .divider, .info:
            break
        case .math:
            let operations = Set(["+", "-", "*", "/", "%", "min", "max"])
            if property.control.argument1 == nil || property.control.argument2 == nil {
                diagnostics.append(.init(severity: .error, location: location, message: "A math control requires argument1 and argument2."))
            }
            if !operations.contains(property.control.operation ?? "") {
                diagnostics.append(.init(severity: .error, location: location, message: "A math operation must be +, -, *, /, %, min, or max."))
            }
        case .imageTransform:
            if property.control.input?.isEmpty != false {
                diagnostics.append(.init(severity: .error, location: location, message: "An imageTransform control requires the ID of an image control in input."))
            }
        case .number, .slider:
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
        case .toggle, .details, .button:
            if case .boolean = defaultValue {} else {
                diagnostics.append(.init(severity: .error, location: location, message: "A toggle control requires a Boolean default value."))
            }
        case .select:
            guard case .string(let value) = defaultValue,
                  property.control.options?.contains(where: { $0.value == value }) == true else {
                diagnostics.append(.init(severity: .error, location: location, message: "A select default must match one of its options."))
                return
            }
        case .color:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A color control requires a string default value."))
                return
            }
            let themeDefaults = Set(ThemeColorRole.allCases.map(\.rawValue))
            let isLiteralColor = allowsLiteralColor && value.matches(#"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#)
            if !isLiteralColor && value != "custom" && (!property.control.themeValues.orFalse || !themeDefaults.contains(value)) {
                diagnostics.append(.init(severity: .error, location: location, message: "A color default must be custom, or a known theme role when themeValues is enabled."))
            }
            if let customColor = property.control.customColor,
               !customColor.matches(#"^#[0-9A-Fa-f]{6}$"#) {
                diagnostics.append(.init(severity: .error, location: location, message: "customColor must be a six-digit hexadecimal colour."))
            }
        case .fontFamily:
            if case .string(let value) = defaultValue {
                let roles = Set(ThemeFontRole.allCases.map(\.rawValue))
                if value != "custom" && (!property.control.themeValues.orFalse || !roles.contains(value)) {
                    diagnostics.append(.init(severity: .error, location: location, message: "A fontFamily default must be custom, or a known theme role when themeValues is enabled."))
                }
            } else {
                diagnostics.append(.init(severity: .error, location: location, message: "A fontFamily control requires a string default value."))
            }
        case .fontSize:
            if case .string(let value) = defaultValue {
                let sizes = Set(Theme.standard.typography.fontSizes.map(\.id))
                if value != "custom" && (!property.control.themeValues.orFalse || !sizes.contains(value)) {
                    diagnostics.append(.init(severity: .error, location: location, message: "A fontSize default must be custom, or a known theme size when themeValues is enabled."))
                }
            } else {
                diagnostics.append(.init(severity: .error, location: location, message: "A fontSize control requires a string default value."))
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

    private static func validateUnique(_ values: [String], kind: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        var seen: Set<String> = []
        for value in values where !seen.insert(value).inserted {
            diagnostics.append(.init(severity: .error, location: "Info.plist", message: "Duplicate \(kind) identifier '\(value)'."))
        }
    }

    private static func validate(
        _ value: String,
        expression: NSRegularExpression,
        location: String,
        message: String,
        into diagnostics: inout [ComponentPackageDiagnostic]
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

private nonisolated struct ComponentTemplateReference {
    let value: String
    let offset: Int
}

private nonisolated extension String {
    func matches(_ pattern: String) -> Bool {
        matchCount(pattern) > 0
    }

    func matchCount(_ pattern: String) -> Int {
        let expression = try! NSRegularExpression(pattern: pattern)
        return expression.numberOfMatches(in: self, range: NSRange(startIndex..., in: self))
    }

    func references(matching pattern: String) -> [ComponentTemplateReference] {
        let expression = try! NSRegularExpression(pattern: pattern)
        return expression.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: self) else { return nil }
            return ComponentTemplateReference(value: String(self[valueRange]), offset: match.range.location)
        }
    }
}
