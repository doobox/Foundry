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
    private static let maximumTagCount = 5
    private static let identifierExpression = try! NSRegularExpression(
        pattern: #"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$"#
    )
    private static let propertyExpression = try! NSRegularExpression(
        pattern: #"^[A-Za-z][A-Za-z0-9_-]*$"#
    )
    static func validate(_ manifest: ComponentPackageManifest, rootURL: URL) -> [ComponentPackageDiagnostic] {
        var diagnostics: [ComponentPackageDiagnostic] = []

        if manifest.minimumAPIVersion > FoundryComponentAPI.supportedVersions.upperBound {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:minimumAPIVersion",
                message: "This component requires Foundry component API \(manifest.minimumAPIVersion), but this version of Foundry supports through API \(FoundryComponentAPI.supportedVersions.upperBound). Update Foundry to use this component."
            ))
        } else if manifest.minimumAPIVersion < FoundryComponentAPI.supportedVersions.lowerBound {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:minimumAPIVersion",
                message: "This component requires an unsupported Foundry component API."
            ))
        }
        validate(manifest.identifier, expression: identifierExpression, location: "Info.plist:id", message: "Use a lowercase reverse-DNS identifier, for example com.example.hero.", into: &diagnostics)
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(.init(severity: .error, location: "Info.plist:title", message: "A component title is required."))
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
                message: "A component can declare at most \(maximumTagCount) tags."
            ))
        }

        var seenLibraries = Set<ComponentPackageLibraryRequirement>()
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

        if manifest.properties.contains(where: { $0.control.type == .icon }),
           !manifest.libraries.contains(FoundryWebLibraryRegistry.iconRequirement) {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:libraries",
                message: "An icon control requires com.foundry.icons major version 1 in libraries."
            ))
        }

        validateUnique(manifest.properties.map(\.id), kind: "property", into: &diagnostics)
        validateUnique(manifest.slots.map(\.id), kind: "slot", into: &diagnostics)
        for property in manifest.properties {
            validate(property.id, expression: propertyExpression, location: "Info.plist:customItems.\(property.id)", message: "Property IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.", into: &diagnostics)
            validate(property, into: &diagnostics)
            validateEnable(property, properties: manifest.properties, into: &diagnostics)
        }
        validateEnableCycles(manifest.properties, into: &diagnostics)
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
            || manifest.assets.contains { $0.lowercased().hasSuffix(".php") }
        if !manifest.requiresPhp, declaresPHP {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:requiresPhp",
                message: "Components with PHP templates or assets must set requiresPhp to true."
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
                template.matches(#"\{\{\s*(?:slot\s+id|if\s+property|text(?:\s*=|\s*\}\})|html(?:\s*=|\s*\}\})|image\s*\}\})"#) {
                diagnostics.append(.init(
                    severity: .error,
                    location: file.path,
                    message: "Page- and site-scoped templates cannot use instance, component, control, property, slot, condition, or editable-content macros."
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
            template.references(matching: #"\{\{\s*if\s+property\.([A-Za-z][A-Za-z0-9_-]*)"#) {
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
            matching: #"\{\{\s*slot\s+id\s*=\s*[\"']([A-Za-z][A-Za-z0-9_.-]*)[\"']"#
        )
        let invalidSlotReferences = template.references(
            matching: #"\{\{\s*slot\.([A-Za-z][A-Za-z0-9_.-]*)\s*\}\}"#
        )
        for reference in slotReferences where !slotIDs.contains(reference.value) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Unknown slot '\(reference.value)'. Declare it in Info.plist."
            ))
        }
        for reference in invalidSlotReferences {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Slot macros must use {{ slot id=\"…\" }}."
            ))
        }
        if requiresEditorAttributes {
            let referencedSlotIDs = Set(slotReferences.map(\.value))
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

        let ifCount = template.matchCount(#"\{\{\s*if\b"#)
        let endIfCount = template.matchCount(#"\{\{\s*endif\s*\}\}"#)
        let elseCount = template.matchCount(#"\{\{\s*else\s*\}\}"#)
        if ifCount != endIfCount || elseCount > ifCount {
            diagnostics.append(.init(
                severity: .error,
                location: templateLocation,
                message: "Conditional directives are unbalanced; every if requires one endif and at most one else."
            ))
        }

        let supportedMacroNames: Set<String> = [
            "id", "instance", "package", "component", "control", "property", "asset", "slot",
            "if", "else", "endif", "text", "html", "image"
        ]
        for reference in template.references(matching: #"\{\{\s*([A-Za-z]+)(?:\.|\s|\}\})"#)
            where !supportedMacroNames.contains(reference.value) {
            diagnostics.append(templateDiagnostic(
                templateLocation,
                template: template,
                offset: reference.offset,
                message: "Unknown template macro '\(reference.value)'."
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
        validateThemeValues(property, location: location, into: &diagnostics)
        if property.control.type == .padding || property.control.type == .margin {
            validateSpacing(property, location: location, into: &diagnostics)
            return
        }
        if let count = property.control.count {
            guard (2...4).contains(count) else {
                diagnostics.append(.init(severity: .error, location: location, message: "Control arrays must contain between two and four controls."))
                return
            }
            guard case .array(let values) = property.defaultValue, values.count == count else {
                diagnostics.append(.init(severity: .error, location: location, message: "A control array requires exactly \(count) default values."))
                return
            }
            if property.labels.count != count || property.labels.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                diagnostics.append(.init(severity: .error, location: location, message: "A control array requires a non-empty label for every control."))
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

    private static func validateThemeValues(
        _ property: ComponentPackageProperty,
        location: String,
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        if property.control.allowsCustom.orFalse,
           property.control.type != .select || property.control.themeValueSource == nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).allowsCustom",
                message: "allowsCustom requires a select control with a named themeValues source."
            ))
        }
        if property.control.type == .color {
            if let themeDefault = property.control.themeValueDefault,
               ThemeColorRole(rawValue: themeDefault) == nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).themeValues",
                    message: "A color themeValues string must be background, surface, text, accent, or links."
                ))
            }
            if property.control.themeValues != nil, property.control.themeValueDefault == nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).themeValues",
                    message: "A color themeValues string must be background, surface, text, accent, or links."
                ))
            }
            return
        } else if property.control.themeValueDefault != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).themeValues",
                message: "The \(property.control.type.rawValue) control does not accept a theme role as themeValues."
            ))
        }
        guard let source = property.control.themeValueSource else { return }
        let supported: Bool
        switch (property.control.type, source) {
        case (.select, .fontFamilies), (.select, .fontSizes), (.select, .lineHeights), (.select, .spacing),
             (.fontFamily, .fontFamilies),
             (.fontSize, .fontSizes), (.margin, .spacing), (.padding, .spacing):
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

    private static func validateSpacing(
        _ property: ComponentPackageProperty,
        location: String,
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        let isMargin = property.control.type == .margin
        if property.control.count != nil {
            diagnostics.append(.init(
                severity: .error,
                location: location,
                message: "\(isMargin ? "Margin" : "Padding") always contains top, right, bottom and left values; remove count."
            ))
        }
        guard case .array(let defaults) = property.defaultValue, defaults.count == 4 else {
            diagnostics.append(.init(
                severity: .error,
                location: location,
                message: "A \(isMargin ? "margin" : "padding") control requires exactly four string defaults in top, right, bottom, left order."
            ))
            return
        }
        let permitted = Set(["none", "custom", "3xs", "2xs", "xs", "sm", "md", "lg", "xl", "2xl", "3xl"] + (isMargin ? ["auto"] : []))
        for (index, value) in defaults.enumerated() {
            guard case .string(let source) = value, permitted.contains(source) else {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).default[\(index)]",
                    message: "Use none, custom, a standard theme spacing ID\(isMargin ? ", or auto" : "")."
                ))
                continue
            }
        }

        if let declaredCustomValue = property.control.customValue {
            guard case .array(let rawCustomValues) = declaredCustomValue else {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).customValue",
                    message: "customValue must contain exactly four numbers in top, right, bottom, left order."
                ))
                return
            }
            let customValues = rawCustomValues.compactMap(\.numberValue)
            if customValues.count != 4 {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).customValue",
                    message: "customValue must contain exactly four numbers in top, right, bottom, left order."
                ))
            }
            if !isMargin, customValues.contains(where: { $0 < 0 }) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).customValue",
                    message: "Padding custom values cannot be negative."
                ))
            }
            let minimum = property.control.minimum ?? (isMargin ? -640 : 0)
            let maximum = property.control.maximum ?? 640
            if customValues.contains(where: { $0 < minimum || $0 > maximum }) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).customValue",
                    message: "Every customValue must be within the control's \(minimum)…\(maximum) range."
                ))
            }
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
        if !isMargin, let minimum = property.control.minimum, minimum < 0 {
            diagnostics.append(.init(
                severity: .error,
                location: location,
                message: "Padding minimum cannot be negative."
            ))
        }
        if let step = property.control.step, step <= 0 {
            diagnostics.append(.init(
                severity: .error,
                location: location,
                message: "The control step must be greater than zero."
            ))
        }
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
        case .toggle, .details, .button:
            if case .boolean = defaultValue {} else {
                diagnostics.append(.init(severity: .error, location: location, message: "A toggle control requires a Boolean default value."))
            }
        case .select:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A select default must match one of its options."))
                return
            }
            let declaredMatch = property.control.options?.contains(where: { $0.value == value }) == true
            let themeMatch = property.control.themeValueSource.map {
                ComponentPackageThemeValueResolver.choices(for: $0, theme: .standard).contains(where: { $0.value == value })
            } ?? false
            let customMatch = value == "custom" && (
                property.control.allowsCustom.orFalse || property.control.themeValueSource == .lineHeights
            )
            if !declaredMatch && !themeMatch && !customMatch {
                diagnostics.append(.init(severity: .error, location: location, message: "A select default must match one of its declared or requested theme values."))
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
        case .color:
            guard case .string(let value) = defaultValue else {
                diagnostics.append(.init(severity: .error, location: location, message: "A color control requires a string default value."))
                return
            }
            let isLiteralColor = allowsLiteralColor && value.matches(#"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#)
            if !isLiteralColor && value != "custom" {
                diagnostics.append(.init(severity: .error, location: location, message: "A color default must be custom."))
            }
            if let customColor = property.control.customColor,
               !customColor.matches(#"^#[0-9A-Fa-f]{6}$"#) {
                diagnostics.append(.init(severity: .error, location: location, message: "customColor must be a six-digit hexadecimal colour."))
            }
        case .fontFamily:
            if case .string(let value) = defaultValue {
                let roles = Set(ThemeFontRole.allCases.map(\.rawValue))
                if !roles.contains(value) {
                    diagnostics.append(.init(severity: .error, location: location, message: "A fontFamily default must be a known theme font role."))
                }
            } else {
                diagnostics.append(.init(severity: .error, location: location, message: "A fontFamily control requires a string default value."))
            }
        case .fontSize:
            if case .string(let value) = defaultValue {
                let sizes = Set(Theme.standard.typography.fontSizes.map(\.id))
                if value != "custom" && (property.control.themeValueSource != .fontSizes || !sizes.contains(value)) {
                    diagnostics.append(.init(severity: .error, location: location, message: "A fontSize default must be custom, or a known theme size when themeValues is enabled."))
                }
            } else {
                diagnostics.append(.init(severity: .error, location: location, message: "A fontSize control requires a string default value."))
            }
            if let customValue = property.control.customValue {
                guard case .string(let value) = customValue,
                      value.matches(#"^(?:\d+(?:\.\d+)?|\.\d+)(?:px|rem|em|%|vw|vh|vmin|vmax|ch|ex)$"#) else {
                    diagnostics.append(.init(
                        severity: .error,
                        location: "\(location).customValue",
                        message: "A fontSize customValue must be a CSS length such as 1rem or 18px."
                    ))
                    return
                }
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

    private static func validateEnable(
        _ property: ComponentPackageProperty,
        properties: [ComponentPackageProperty],
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        guard let enable = property.enable else { return }
        let location = "Info.plist:customItems.\(property.id).enable"
        let expression = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9_-]*)(?:\[([0-9]+)\])?$"#)
        guard let match = expression.firstMatch(in: enable.id, range: NSRange(enable.id.startIndex..., in: enable.id)),
              let keyRange = Range(match.range(at: 1), in: enable.id) else {
            diagnostics.append(.init(severity: .error, location: location, message: "Enable id must reference a control, optionally followed by a zero-based array index."))
            return
        }
        let key = String(enable.id[keyRange])
        guard key != property.id else {
            diagnostics.append(.init(severity: .error, location: location, message: "A control cannot enable itself."))
            return
        }
        guard let source = properties.first(where: { $0.id == key }) else {
            diagnostics.append(.init(severity: .error, location: location, message: "Enable references unknown control '\(key)'."))
            return
        }
        if let indexRange = Range(match.range(at: 2), in: enable.id), let index = Int(enable.id[indexRange]) {
            guard let count = source.control.count else {
                diagnostics.append(.init(severity: .error, location: location, message: "Enable index requires '\(key)' to be a multi-control."))
                return
            }
            if index >= count {
                diagnostics.append(.init(severity: .error, location: location, message: "Enable index \(index) is outside '\(key)' count \(count)."))
            }
        }

        let operation = ComponentPackageEnableEvaluator.canonicalOperation(enable.operation)
        let supported = Set(["==", "!=", "<", "<=", ">", ">=", "contains", "notContains",
                             "containsInsensitive", "notContainsInsensitive", "matches", "notMatches",
                             "matchesInsensitive", "notMatchesInsensitive", "containsValue", "notContainsValue",
                             "isEmpty", "isNotEmpty"])
        guard supported.contains(operation) else {
            diagnostics.append(.init(severity: .error, location: location, message: "Unknown enable operation '\(enable.operation)'."))
            return
        }
        let needsValue = operation != "isEmpty" && operation != "isNotEmpty"
        if needsValue && enable.value == nil {
            diagnostics.append(.init(severity: .error, location: location, message: "Enable operation '\(operation)' requires a value."))
        } else if !needsValue && enable.value != nil {
            diagnostics.append(.init(severity: .error, location: location, message: "Enable operation '\(operation)' does not accept a value."))
        }
    }

    private static func validateEnableCycles(
        _ properties: [ComponentPackageProperty],
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        let dependencies = Dictionary(uniqueKeysWithValues: properties.compactMap { property -> (String, String)? in
            guard let id = property.enable?.id else { return nil }
            return (property.id, String(id.prefix { $0 != "[" }))
        })
        for property in properties {
            var visited = Set<String>()
            var current: String? = property.id
            while let value = current, let next = dependencies[value] {
                guard visited.insert(value).inserted else {
                    diagnostics.append(.init(severity: .error, location: "Info.plist:customItems.\(property.id).enable", message: "Enable conditions contain a dependency cycle."))
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
