import Foundation
import CoreFoundation

nonisolated enum FoundryPartAPI {
    static let supportedVersions = 1...1
    static let currentVersion = supportedVersions.upperBound
}

nonisolated enum PartPackageManifestSchema {
    private static let partIdentifierExpression = try! NSRegularExpression(
        pattern: #"^[a-z](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$"#
    )

    enum SchemaError: Error, LocalizedError {
        case rootIsNotDictionary
        case missingPartIdentifier

        var errorDescription: String? {
            switch self {
            case .rootIsNotDictionary:
                "manifest.json must contain a dictionary at its root."
            case .missingPartIdentifier:
                "A part manifest.json requires a non-empty id."
            }
        }
    }

    private static let partKeys: Set<String> = [
        "minimumAPIVersion", "id", "title", "description", "author", "version", "group",
        "tags", "showsInPartLibrary", "allowedParents", "controls", "groups", "templates", "assets", "helpURL", "missingPart",
        "requiresPHP", "libraries"
    ]
    private static let propertyKeys: Set<String> = [
        "id", "label", "title", "body", "systemImage", "group", "defaults", "responsive", "subtitle", "buttonText", "units", "tooltip", "linked",
        "type", "font", "showsFamily", "showsWeight", "showsStyle", "minimum", "maximum", "step", "options", "frameworkValues", "allowsCustom", "opacity", "outputFormat",
        "customColor", "count", "ticks", "showsValueField", "trueValue", "falseValue",
        "buttonIcon", "activeButtonText", "activeButtonIcon", "selectionMode", "fontSize", "argument1", "argument2", "operation", "round", "absoluteURL", "presentation", "visibleWhen", "valueAvailability", "alt", "focalPoint", "renditions", "accepts", "pickerItems", "initial", "containment"
    ]
    private static let visibleWhenKeys: Set<String> = ["id", "operation", "value", "all", "any"]
    private static let optionKeys: Set<String> = ["value", "title", "systemImage"]
    private static let templateKeys: Set<String> = ["html", "editorCSS", "files", "htmlContributions"]
    private static let templateFileKeys: Set<String> = ["path", "scope", "placement", "closure"]
    private static let htmlContributionKeys: Set<String> = ["placement", "template"]
    private static let missingPartKeys: Set<String> = ["message", "preview"]
    private static let libraryKeys: Set<String> = ["id", "majorVersion"]
    private static let assetKeys: Set<String> = ["path", "scope"]
    private static let renditionKeys: Set<String> = ["id", "maximumDimension"]
    private static let controlGroupKeys: Set<String> = ["type", "styles", "states", "defaultOverrides"]
    private static let groupKeys: Set<String> = ["name", "systemImage"]

    static func inspect(_ data: Data) throws -> String {
        let dictionary = try rootDictionary(from: data)
        guard let identifier = dictionary["id"] as? String,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchemaError.missingPartIdentifier
        }
        return identifier
    }

    static func diagnostics(for data: Data) throws -> [PartPackageDiagnostic] {
        let dictionary = try rootDictionary(from: data)
        var diagnostics: [PartPackageDiagnostic] = []
        unknownKeys(in: dictionary, allowed: partKeys, location: "manifest.json", into: &diagnostics)
        validatePartFields(in: dictionary, into: &diagnostics)

        validateAPIVersion(in: dictionary, into: &diagnostics)
        validateReleaseVersion(in: dictionary, into: &diagnostics)

        validateDictionaryArray(dictionary["controls"], key: "controls", parent: "manifest.json", into: &diagnostics)
        let knownControlGroupKinds = Set(PartPackageControlGroup.Kind.allCases.map(\.rawValue))
        var seenControlGroupKinds: Set<String> = []
        dictionaries(in: dictionary["controls"]).enumerated().forEach { index, entry in
            let location = "manifest.json:controls[\(index)]"
            guard let type = entry["type"] as? String, knownControlGroupKinds.contains(type) else {
                validateStandardOrFrameworkControl(entry, location: location, into: &diagnostics)
                return
            }
            validateGroupedControlReference(
                entry,
                type: type,
                location: location,
                seenKinds: &seenControlGroupKinds,
                into: &diagnostics
            )
        }
        validateGroups(in: dictionary, into: &diagnostics)
        if let templates = dictionary["templates"], !(templates is [String: Any]) {
            appendTypeError(key: "templates", expected: "a dictionary", location: "manifest.json", into: &diagnostics)
        }
        if let templates = dictionary["templates"] as? [String: Any] {
            unknownKeys(
                in: templates,
                allowed: templateKeys,
                location: "manifest.json:templates",
                into: &diagnostics
            )
            requireString("html", in: templates, location: "manifest.json:templates", into: &diagnostics)
            optionalString("editorCSS", in: templates, location: "manifest.json:templates", into: &diagnostics)
            validateDictionaryArray(templates["files"], key: "files", parent: "manifest.json:templates", into: &diagnostics)
            dictionaries(in: templates["files"]).enumerated().forEach { index, file in
                let fileLocation = "manifest.json:templates.files[\(index)]"
                unknownKeys(
                    in: file,
                    allowed: templateFileKeys,
                    location: fileLocation,
                    into: &diagnostics
                )
                validateTemplateFile(file, location: fileLocation, into: &diagnostics)
            }
            validateDictionaryArray(templates["htmlContributions"], key: "htmlContributions", parent: "manifest.json:templates", into: &diagnostics)
            dictionaries(in: templates["htmlContributions"]).enumerated().forEach { index, contribution in
                let location = "manifest.json:templates.htmlContributions[\(index)]"
                unknownKeys(in: contribution, allowed: htmlContributionKeys, location: location, into: &diagnostics)
                requireString("placement", in: contribution, location: location, into: &diagnostics)
                requireString("template", in: contribution, location: location, into: &diagnostics)
                if let placement = contribution["placement"] as? String,
                   PartPackageHTMLContribution.Placement(rawValue: placement) == nil {
                    diagnostics.append(.init(severity: .error, location: "\(location).placement", message: "Unknown HTML contribution placement '\(placement)'."))
                }
            }
        }
        if let rawAssets = dictionary["assets"], !(rawAssets is [Any]) {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:assets",
                message: "assets must be an array of asset dictionaries."
            ))
        }
        if let assets = dictionary["assets"] as? [Any] {
            for (index, asset) in assets.enumerated() {
                let location = "manifest.json:assets[\(index)]"
                guard let dictionary = asset as? [String: Any] else {
                    diagnostics.append(.init(
                        severity: .error,
                        location: location,
                        message: "Each asset must be a dictionary containing path and an optional scope."
                    ))
                    continue
                }
                unknownKeys(
                    in: dictionary,
                    allowed: assetKeys,
                    location: location,
                    into: &diagnostics
                )
                guard let path = dictionary["path"] as? String,
                      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    diagnostics.append(.init(severity: .error, location: "\(location):path", message: "A non-empty path string is required."))
                    continue
                }
                if let scope = dictionary["scope"] {
                    guard let value = scope as? String, value == "page" || value == "site" else {
                        diagnostics.append(.init(severity: .error, location: "\(location):scope", message: "scope must be 'page' or 'site'."))
                        continue
                    }
                }
            }
        }
        if let missingPart = dictionary["missingPart"] as? [String: Any] {
            unknownKeys(
                in: missingPart,
                allowed: missingPartKeys,
                location: "manifest.json:missingPart",
                into: &diagnostics
            )
            optionalString("message", in: missingPart, location: "manifest.json:missingPart", into: &diagnostics)
            optionalString("preview", in: missingPart, location: "manifest.json:missingPart", into: &diagnostics)
        } else if dictionary["missingPart"] != nil {
            appendTypeError(key: "missingPart", expected: "a dictionary", location: "manifest.json", into: &diagnostics)
        }
        validateDictionaryArray(dictionary["libraries"], key: "libraries", parent: "manifest.json", into: &diagnostics)
        dictionaries(in: dictionary["libraries"]).enumerated().forEach { index, library in
            let location = "manifest.json:libraries[\(index)]"
            unknownKeys(
                in: library,
                allowed: libraryKeys,
                location: location,
                into: &diagnostics
            )
            requireString("id", in: library, location: location, into: &diagnostics)
            requireInteger("majorVersion", in: library, location: location, into: &diagnostics)
        }
        return diagnostics
    }

    private static func validatePartFields(in dictionary: [String: Any], into diagnostics: inout [PartPackageDiagnostic]) {
        requireString("id", in: dictionary, location: "manifest.json", into: &diagnostics)
        requireString("title", in: dictionary, location: "manifest.json", into: &diagnostics)
        optionalString("description", in: dictionary, location: "manifest.json", into: &diagnostics)
        optionalString("author", in: dictionary, location: "manifest.json", into: &diagnostics)
        optionalString("group", in: dictionary, location: "manifest.json", into: &diagnostics)
        optionalString("helpURL", in: dictionary, location: "manifest.json", into: &diagnostics)
        optionalBoolean("requiresPHP", in: dictionary, location: "manifest.json", into: &diagnostics)
        optionalBoolean("showsInPartLibrary", in: dictionary, location: "manifest.json", into: &diagnostics)
        optionalStringArray("tags", in: dictionary, location: "manifest.json", into: &diagnostics)
        optionalStringArray("allowedParents", in: dictionary, location: "manifest.json", into: &diagnostics)
        if let identifiers = dictionary["allowedParents"] as? [String] {
            for (index, identifier) in identifiers.enumerated() where partIdentifierExpression.firstMatch(
                in: identifier,
                range: NSRange(identifier.startIndex..., in: identifier)
            ) == nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "manifest.json:allowedParents[\(index)]",
                    message: "Use a lowercase reverse-DNS part identifier."
                ))
            }
        }
        if dictionary["templates"] == nil {
            appendMissing("templates", expected: "dictionary", location: "manifest.json", into: &diagnostics)
        }
    }

    /// Validates one `controls` entry that is a plain Standard/Framework
    /// property (i.e. its `type` didn't match a Grouped-control kind).
    private static func validateStandardOrFrameworkControl(
        _ property: [String: Any],
        location: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        unknownKeys(in: property, allowed: propertyKeys, location: location, into: &diagnostics)
        validateProperty(property, location: location, into: &diagnostics)
        if let frameworkValues = property["frameworkValues"], !(frameworkValues is String) {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).frameworkValues",
                message: "frameworkValues must be a string."
            ))
        }
        if property["type"] as? String == PartPackageControl.Kind.select.rawValue {
            for key in ["frameworkValues", "allowsCustom"] where property[key] != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)",
                    message: "Select supports only declared options; remove \(key)."))
            }
            if let presentation = property["presentation"] as? String,
               PartPackageControl.SelectPresentation(rawValue: presentation) == nil {
                diagnostics.append(.init(severity: .error, location: "\(location).presentation", message: "Unknown select presentation '\(presentation)'."))
            }
        } else if property["presentation"] != nil {
            diagnostics.append(.init(severity: .error, location: "\(location).presentation", message: "presentation is available only for select controls."))
        }
        if property["type"] as? String == PartPackageControl.Kind.frameworkColor.rawValue,
           property["count"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).count",
                message: "A frameworkColor control cannot be a multi control; remove count."
            ))
        }
        if property["type"] as? String == PartPackageControl.Kind.frameworkShadow.rawValue,
           property["frameworkValues"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).frameworkValues",
                message: "A frameworkShadow control automatically uses framework shadows; remove frameworkValues."
            ))
        }

        if let visibleWhen = property["visibleWhen"] as? [String: Any] {
            unknownKeys(in: visibleWhen, allowed: visibleWhenKeys, location: "\(location).visibleWhen", into: &diagnostics)
            validateVisibility(visibleWhen, location: "\(location).visibleWhen", into: &diagnostics)
        }
        if let visibleWhen = property["visibleWhen"], !(visibleWhen is [String: Any]) {
            appendTypeError(key: "visibleWhen", expected: "a dictionary", location: location, into: &diagnostics)
        }
        optionalEnumString(
            "valueAvailability",
            values: Set(PartPackageProperty.ValueAvailability.allCases.map(\.rawValue)),
            in: property,
            location: location,
            into: &diagnostics
        )
        if property["valueAvailability"] as? String == PartPackageProperty.ValueAvailability.whenVisible.rawValue,
           property["visibleWhen"] == nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).valueAvailability",
                message: "valueAvailability 'whenVisible' requires visibleWhen."
            ))
        }
        validateDictionaryArray(property["options"], key: "options", parent: location, into: &diagnostics)
        dictionaries(in: property["options"]).enumerated().forEach { optionIndex, option in
            let optionLocation = "\(location):options[\(optionIndex)]"
            unknownKeys(
                in: option,
                allowed: optionKeys,
                location: optionLocation,
                into: &diagnostics
            )
            requireString("value", in: option, location: optionLocation, into: &diagnostics)
            requireString("title", in: option, location: optionLocation, into: &diagnostics)
            optionalString("systemImage", in: option, location: optionLocation, into: &diagnostics)
        }
    }

    /// Validates one `controls` entry that references a prebuilt Grouped
    /// control (`background`, `spacing`, `sizing`, `borders`, `effects`,
    /// `layoutItem`) — a `type` plus, for `background` only, `styles`/
    /// `states`, plus the generic `defaultOverrides`.
    private static func validateGroupedControlReference(
        _ controlGroup: [String: Any],
        type: String,
        location: String,
        seenKinds: inout Set<String>,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        unknownKeys(in: controlGroup, allowed: controlGroupKeys, location: location, into: &diagnostics)
        if !seenKinds.insert(type).inserted {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).type",
                message: "Control group '\(type)' is declared more than once."
            ))
        }
        optionalStringArray("styles", in: controlGroup, location: location, into: &diagnostics)
        optionalStringArray("states", in: controlGroup, location: location, into: &diagnostics)
        if type == PartPackageControlGroup.Kind.background.rawValue {
            validateControlGroupValues(
                controlGroup["styles"],
                key: "styles",
                permitted: Set(PartPackageControlGroup.BackgroundStyle.allCases.map(\.rawValue)),
                location: location,
                into: &diagnostics
            )
            validateControlGroupValues(
                controlGroup["states"],
                key: "states",
                permitted: Set(PartPackageControlGroup.BackgroundState.allCases.map(\.rawValue)),
                location: location,
                into: &diagnostics
            )
            if let states = controlGroup["states"] as? [String],
               !states.contains(PartPackageControlGroup.BackgroundState.staticState.rawValue) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).states",
                    message: "states must include 'static'; hover augments the static background."
                ))
            }
        }
    }

    private static func validateProperty(_ property: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        if property["default"] != nil {
            diagnostics.append(.init(severity: .error, location: location, message: "default is no longer supported; use defaults with a base entry."))
            return
        }
        var normalized = property
        normalized.removeValue(forKey: "defaults")
        guard let raw = property["defaults"] else {
            var result: [PartPackageDiagnostic] = []
            validateResolvedProperty(normalized, location: location, into: &result)
            diagnostics += result.map { .init(severity: $0.severity, location: $0.location.replacingOccurrences(of: ":default", with: ":defaults"), message: $0.message.replacingOccurrences(of: "A default value", with: "A defaults dictionary with base")) }
            return
        }
        if ["divider", "note", "math", "childPicker"].contains(property["type"] as? String ?? "") {
            diagnostics.append(.init(severity: .error, location: location + ":defaults", message: "This control does not support defaults."))
            return
        }
        guard let defaults = raw as? [String: Any], defaults["base"] != nil else {
            diagnostics.append(.init(severity: .error, location: location + ".defaults", message: "defaults requires a dictionary containing base."))
            return
        }
        let names = Set(ResponsiveBreakpoint.allCases.filter { $0 != .mobile }.map(\.rawValue))
        for (name, value) in defaults {
            guard name == "base" || names.contains(name) else {
                diagnostics.append(.init(severity: .error, location: location + ".defaults." + name, message: "Unknown breakpoint name."))
                continue
            }
            if name != "base" && property["responsive"] as? Bool != true {
                diagnostics.append(.init(severity: .error, location: location + ".defaults." + name, message: "Breakpoint defaults require responsive: true."))
            }
            if name != "base" && property["type"] as? String == "image" {
                diagnostics.append(.init(severity: .error, location: location + ".defaults." + name, message: "Image asset defaults support base only; responsive applies to focal points."))
            }
            if name != "base", property["type"] as? String == "frameworkFont", property["showsFamily"] as? Bool == false {
                let baseFamily = (defaults["base"] as? [String: Any])?["family"] as? String ?? defaults["base"] as? String
                let family = (value as? [String: Any])?["family"] as? String ?? value as? String
                if family != baseFamily {
                    diagnostics.append(.init(severity: .error, location: location + ".defaults." + name, message: "A hidden font family is fixed; use the same family as base."))
                }
            }
            normalized["default"] = value
            var result: [PartPackageDiagnostic] = []
            validateResolvedProperty(normalized, location: location, into: &result)
            diagnostics += result.map { .init(severity: $0.severity,
                location: $0.location.replacingOccurrences(of: ":default", with: ":defaults." + name).replacingOccurrences(of: ".default", with: ".defaults." + name),
                message: $0.message.replacingOccurrences(of: "default must", with: "defaults." + name + " must")) }
        }
    }

    private static func validateResolvedProperty(_ property: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        requireString("id", in: property, location: location, into: &diagnostics)
        optionalString("group", in: property, location: location, into: &diagnostics)
        optionalString("tooltip", in: property, location: location, into: &diagnostics)
        optionalString("alt", in: property, location: location, into: &diagnostics)
        optionalBoolean("focalPoint", in: property, location: location, into: &diagnostics)
        if let rawRenditions = property["renditions"] {
            guard let renditions = rawRenditions as? [[String: Any]] else {
                appendTypeError(key: "renditions", expected: "an array of dictionaries", location: location, into: &diagnostics)
                return
            }
            var identifiers = Set<String>()
            for (index, rendition) in renditions.enumerated() {
                let renditionLocation = "\(location):renditions[\(index)]"
                unknownKeys(in: rendition, allowed: renditionKeys, location: renditionLocation, into: &diagnostics)
                requireString("id", in: rendition, location: renditionLocation, into: &diagnostics)
                requireInteger("maximumDimension", in: rendition, location: renditionLocation, into: &diagnostics)
                if let id = rendition["id"] as? String {
                    if id.range(of: #"^[A-Za-z][A-Za-z0-9_-]*$"#, options: .regularExpression) == nil {
                        diagnostics.append(.init(
                            severity: .error,
                            location: "\(renditionLocation):id",
                            message: "A rendition id must start with a letter and contain only letters, numbers, underscores, or hyphens."
                        ))
                    }
                    if !identifiers.insert(id).inserted {
                        diagnostics.append(.init(severity: .error, location: "\(renditionLocation):id", message: "Rendition ids must be unique within an image control."))
                    }
                }
                if let maximumDimension = rendition["maximumDimension"].flatMap(integer), maximumDimension < 1 {
                    diagnostics.append(.init(severity: .error, location: "\(renditionLocation):maximumDimension", message: "maximumDimension must be greater than zero."))
                }
            }
        }

        guard let rawType = property["type"] else {
            appendMissing("type", expected: "control type string", location: location, into: &diagnostics)
            return
        }
        guard let typeName = rawType as? String else {
            appendTypeError(key: "type", expected: "a string", location: location, into: &diagnostics)
            return
        }
        guard let type = PartPackageControl.Kind(rawValue: typeName) else {
            diagnostics.append(.init(severity: .error, location: "\(location):type", message: "Unknown control type '\(typeName)'."))
            return
        }
        if (type == .frameworkSpacing || type == .frameworkPadding || type == .frameworkMargin || type == .frameworkRadius) {
            let allowed: Set<String> = ["type", "id", "label", "subtitle", "group", "default", "responsive", "tooltip", "visibleWhen", "valueAvailability"]
            unknownKeys(in: property, allowed: allowed, location: location, into: &diagnostics)
        }
        if type == .edges || type == .corners {
            let allowed: Set<String> = ["type", "id", "label", "subtitle", "group", "default", "responsive", "tooltip", "visibleWhen", "valueAvailability", "units", "linked"]
            unknownKeys(in: property, allowed: allowed, location: location, into: &diagnostics)
            optionalBoolean("linked", in: property, location: location, into: &diagnostics)
            if let units = property["units"] {
                let names = (units as? [Any])?.compactMap { $0 as? String }
                let permitted: Set<String> = ["px", "rem", "em", "%"]
                let isValid = names.map { !$0.isEmpty && $0.allSatisfy(permitted.contains) && Set($0).count == $0.count } ?? false
                if !isValid || (units as? [Any])?.count != names?.count {
                    diagnostics.append(.init(
                        severity: .error,
                        location: "\(location).units",
                        message: "units must be a non-empty array of distinct values from px, rem, em, and %."
                    ))
                }
            }
        }
        if type == .frameworkFont {
            for key in ["showsFamily", "showsWeight", "showsStyle"] {
                optionalBoolean(key, in: property, location: location, into: &diagnostics)
            }
            if let fields = property["default"] as? [String: Any] {
                unknownKeys(in: fields, allowed: ["family", "weight", "style"], location: "\(location).default", into: &diagnostics)
                requireString("family", in: fields, location: "\(location).default", into: &diagnostics)
                optionalInteger("weight", in: fields, location: "\(location).default", into: &diagnostics)
                if fields["style"] != nil { requireString("style", in: fields, location: "\(location).default", into: &diagnostics) }
            }
            for key in ["count", "frameworkValues", "options", "allowsCustom"] where property[key] != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "A frameworkFont control does not accept \(key)."))
            }
        }
        if type == .frameworkFontSize {
            for key in ["count", "frameworkValues", "options", "allowsCustom"] where property[key] != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "A frameworkFontSize control does not accept \(key)."))
            }
        }
        if type == .frameworkStackingOrder {
            for key in ["count", "frameworkValues", "options", "allowsCustom"] where property[key] != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "A frameworkStackingOrder control does not accept \(key)."))
            }
        }
        if type == .pageFolder {
            for key in ["count", "frameworkValues", "options", "allowsCustom"] where property[key] != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "A pageFolder control does not accept \(key)."))
            }
        }
        if type == .frameworkBorder {
            unknownKeys(in: property, allowed: ["type", "id", "label", "subtitle", "group", "default", "responsive", "tooltip", "visibleWhen", "valueAvailability", "showsStyle"], location: location, into: &diagnostics)
            for key in ["showsStyle"] {
                optionalBoolean(key, in: property, location: location, into: &diagnostics)
            }
        }
        if type == .fontWeight || type == .fontStyle {
            diagnostics.append(.init(severity: .error, location: "\(location).type", message: "Use one frameworkFont control with showsWeight/showsStyle instead of separate font controls."))
            for key in ["count", "options", "frameworkValues", "allowsCustom"] where property[key] != nil {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "A \(type.rawValue) control does not accept \(key)."))
            }
            if property["font"] != nil {
                requireString("font", in: property, location: location, into: &diagnostics)
            }
        } else if property["font"] != nil {
            diagnostics.append(.init(severity: .error, location: "\(location).font", message: "font is only supported by fontWeight and fontStyle controls."))
        }
        if type != .frameworkFont {
            for key in ["showsFamily", "showsWeight", "showsStyle"] where property[key] != nil {
                if type == .frameworkBorder && key == "showsStyle" { continue }
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "\(key) requires a frameworkFont control."))
            }
        }
        if type != .edges, type != .corners, property["linked"] != nil {
            diagnostics.append(.init(severity: .error, location: "\(location).linked", message: "linked requires an edges or corners control."))
        }
        if type == .childPicker {
            let supportedKeys: Set<String> = [
                "type", "id", "label", "group", "tooltip", "visibleWhen",
                "accepts", "pickerItems", "initial", "minimum", "maximum", "containment"
            ]
            for key in property.keys where !supportedKeys.contains(key) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):\(key)",
                    message: "A childPicker control does not support \(key)."
                ))
            }
            if property["pickerItems"] == nil {
                appendMissing("pickerItems", expected: "array of part identifiers", location: location, into: &diagnostics)
            }
            optionalStringArray("accepts", in: property, location: location, into: &diagnostics)
            optionalStringArray("pickerItems", in: property, location: location, into: &diagnostics)
            optionalStringArray("initial", in: property, location: location, into: &diagnostics)
            if let pickerItems = property["pickerItems"] as? [String], pickerItems.isEmpty {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):pickerItems",
                    message: "pickerItems must contain at least one part identifier."
                ))
            }
            optionalInteger("minimum", in: property, location: location, into: &diagnostics)
            optionalInteger("maximum", in: property, location: location, into: &diagnostics)
            optionalEnumString(
                "containment",
                values: ["open", "locked"],
                in: property,
                location: location,
                into: &diagnostics
            )
            if let minimum = property["minimum"].flatMap(integer), minimum < 0 {
                diagnostics.append(.init(severity: .error, location: "\(location):minimum", message: "minimum cannot be negative."))
            }
            if let maximum = property["maximum"].flatMap(integer), maximum < 1 {
                diagnostics.append(.init(severity: .error, location: "\(location):maximum", message: "maximum must be greater than zero."))
            }
            if let minimum = property["minimum"].flatMap(integer),
               let maximum = property["maximum"].flatMap(integer), minimum > maximum {
                diagnostics.append(.init(severity: .error, location: "\(location):minimum", message: "minimum cannot exceed maximum."))
            }
            let initial = property["initial"] as? [String] ?? []
            if let maximum = property["maximum"].flatMap(integer), initial.count > maximum {
                diagnostics.append(.init(severity: .error, location: "\(location):initial", message: "initial cannot exceed maximum."))
            }
            if let minimum = property["minimum"].flatMap(integer), initial.count < minimum {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):initial",
                    message: "initial must contain at least minimum children."
                ))
            }
            for key in ["pickerItems", "initial"] {
                guard let identifiers = property[key] as? [String] else { continue }
                for (index, identifier) in identifiers.enumerated() where partIdentifierExpression.firstMatch(
                    in: identifier,
                    range: NSRange(identifier.startIndex..., in: identifier)
                ) == nil {
                    diagnostics.append(.init(
                        severity: .error,
                        location: "\(location):\(key)[\(index)]",
                        message: "Use a lowercase reverse-DNS part identifier."
                    ))
                }
            }
            let accepts = property["accepts"] as? [String] ?? (property["pickerItems"] as? [String] ?? [])
            for (index, value) in accepts.enumerated() where value != "*" && partIdentifierExpression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ) == nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):accepts[\(index)]",
                    message: "Use '*' or a lowercase reverse-DNS part identifier."
                ))
            }
            for (index, identifier) in initial.enumerated() where !accepts.contains("*") && !accepts.contains(identifier) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):initial[\(index)]",
                    message: "Every initial part must be permitted by accepts."
                ))
            }
            return
        }
        if type == .divider {
            let supportedKeys: Set<String> = ["type", "id", "group", "visibleWhen"]
            for key in property.keys where !supportedKeys.contains(key) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):\(key)",
                    message: "A divider control does not support \(key)."
                ))
            }
        }
        if type == .note {
            let supportedKeys: Set<String> = ["type", "id", "title", "body", "systemImage", "group", "visibleWhen"]
            for key in property.keys where !supportedKeys.contains(key) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):\(key)",
                    message: "A note control does not support \(key)."
                ))
            }
            optionalString("title", in: property, location: location, into: &diagnostics)
            requireString("body", in: property, location: location, into: &diagnostics)
            optionalString("systemImage", in: property, location: location, into: &diagnostics)
        } else {
            for key in ["title", "body", "systemImage"] where property[key] != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):\(key)",
                    message: "\(key) is supported only by note controls."
                ))
            }
        }
        if type == .link {
            for key in ["count", "responsive"] where property[key] != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):\(key)",
                    message: "A link control does not support \(key)."
                ))
            }
        }
        if type == .video, property["responsive"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):responsive",
                message: "A video control does not support responsive."
            ))
        }
        if type != .image, property["alt"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):alt",
                message: "alt is supported only by image controls."
            ))
        }
        if type != .image, property["focalPoint"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):focalPoint",
                message: "focalPoint is supported only by image controls."
            ))
        }
        if type != .image, property["renditions"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):renditions",
                message: "renditions are supported only by image controls."
            ))
        }

        let count = property["count"].flatMap(integer)
        if property["count"] != nil && count == nil {
            appendTypeError(key: "count", expected: "an integer", location: location, into: &diagnostics)
        }
        if type == .image, property["count"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).count",
                message: "An image control represents one named image; remove count and declare each image property explicitly."
            ))
        }
        if type == .frameworkShadow, property["count"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).count",
                message: "A frameworkShadow control cannot be a multi control; use its visual layer editor instead."
            ))
        }
        if type == .video, property["count"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).count",
                message: "A video control represents one named video; remove count and declare each video property explicitly."
            ))
        }
        if property["count"] != nil {
            optionalStringArray("subtitle", in: property, location: location, into: &diagnostics)
            optionalStringArray("buttonText", in: property, location: location, into: &diagnostics)
            optionalStringArray("buttonIcon", in: property, location: location, into: &diagnostics)
            optionalStringArray("activeButtonText", in: property, location: location, into: &diagnostics)
            optionalStringArray("activeButtonIcon", in: property, location: location, into: &diagnostics)
            optionalStringArray("units", in: property, location: location, into: &diagnostics)
        } else {
            optionalString("subtitle", in: property, location: location, into: &diagnostics)
            optionalString("buttonText", in: property, location: location, into: &diagnostics)
            optionalString("buttonIcon", in: property, location: location, into: &diagnostics)
            optionalString("activeButtonText", in: property, location: location, into: &diagnostics)
            optionalString("activeButtonIcon", in: property, location: location, into: &diagnostics)
            if type == .edges || type == .corners {
                // The unit menu is a list even without count; membership is
                // validated with the control's own rules above.
                optionalStringArray("units", in: property, location: location, into: &diagnostics)
            } else {
                optionalString("units", in: property, location: location, into: &diagnostics)
            }
        }
        optionalString("label", in: property, location: location, into: &diagnostics)

        if type == .date {
            optionalString("minimum", in: property, location: location, into: &diagnostics)
            optionalString("maximum", in: property, location: location, into: &diagnostics)
        } else {
            for key in ["minimum", "maximum"] { optionalNumber(key, in: property, location: location, into: &diagnostics) }
        }
        optionalNumber("step", in: property, location: location, into: &diagnostics)
        for key in ["allowsCustom", "opacity", "showsValueField", "round", "absoluteURL"] {
            optionalBoolean(key, in: property, location: location, into: &diagnostics)
        }
        optionalInteger("ticks", in: property, location: location, into: &diagnostics)
        if type == .frameworkColor {
            if let initial = property["default"] as? [String: Any] {
                unknownKeys(in: initial, allowed: ["palette", "lightShade", "darkShade"], location: "\(location).default", into: &diagnostics)
                optionalString("palette", in: initial, location: "\(location).default", into: &diagnostics)
                if initial["palette"] == nil {
                    appendMissing("palette", expected: "string", location: "\(location).default", into: &diagnostics)
                }
                for key in ["lightShade", "darkShade"] {
                    optionalInteger(key, in: initial, location: "\(location).default", into: &diagnostics)
                }
            } else {
                diagnostics.append(.init(severity: .error, location: "\(location).default", message: "A frameworkColor default must be a dictionary containing palette and optional lightShade/darkShade."))
            }
        }
        for key in ["customColor", "operation"] { optionalString(key, in: property, location: location, into: &diagnostics) }
        optionalEnumString("selectionMode", values: ["multiple", "single"], in: property, location: location, into: &diagnostics)
        optionalEnumString(
            "outputFormat",
            values: Set(PartPackageControl.ColorOutputFormat.allCases.map(\.rawValue)),
            in: property,
            location: location,
            into: &diagnostics
        )
        for key in ["default", "trueValue", "falseValue", "argument1", "argument2"] {
            if key == "default" && type == .frameworkColor { continue }
            if key == "default" && (type == .frameworkSpacing || type == .frameworkPadding || type == .frameworkMargin || type == .frameworkBorder || type == .frameworkRadius || type == .edges || type == .corners) { continue }
            if key == "default" && type == .frameworkFont && property[key] is [String: Any] { continue }
            optionalPartValue(key, in: property, location: location, into: &diagnostics)
        }

        let permitsMissingDefault = type == .divider || type == .image || type == .video || type == .note || type == .math
        if !permitsMissingDefault && property["default"] == nil {
            appendMissing("default", expected: "value", location: location, into: &diagnostics)
        }
        optionalBoolean("responsive", in: property, location: location, into: &diagnostics)
        if type != .button, property["buttonText"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):buttonText",
                message: "buttonText is supported only by button controls."
            ))
        }
        if type != .button, property["buttonIcon"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):buttonIcon",
                message: "buttonIcon is supported only by button controls."
            ))
        }
        for key in ["activeButtonText", "activeButtonIcon"] where type != .button && property[key] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):\(key)",
                message: "\(key) is supported only by button controls."
            ))
        }
        if type != .button, property["selectionMode"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):selectionMode",
                message: "selectionMode is supported only by button controls."
            ))
        } else if type == .button, property["selectionMode"] != nil, count == nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):selectionMode",
                message: "selectionMode requires count."
            ))
        }
        if type == .image, let value = property["default"], !(value is String) {
            appendTypeError(key: "default", expected: "an asset path string", location: location, into: &diagnostics)
        }
    }

    private static func validateVisibility(_ visibleWhen: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        let expressionKeys = ["id", "all", "any"].filter { visibleWhen[$0] != nil }
        if expressionKeys.count != 1 {
            diagnostics.append(.init(severity: .error, location: location, message: "visibleWhen requires exactly one of id, all, or any."))
            return
        }
        if visibleWhen["id"] != nil {
            requireString("id", in: visibleWhen, location: location, into: &diagnostics)
        }
        optionalString("operation", in: visibleWhen, location: location, into: &diagnostics)
        optionalPartValue("value", in: visibleWhen, location: location, into: &diagnostics)
        for key in ["all", "any"] where visibleWhen[key] != nil {
            validateDictionaryArray(visibleWhen[key], key: key, parent: location, into: &diagnostics)
            if let conditions = visibleWhen[key] as? [Any], conditions.isEmpty {
                diagnostics.append(.init(severity: .error, location: "\(location).\(key)", message: "\(key) requires at least one condition."))
            }
            dictionaries(in: visibleWhen[key]).enumerated().forEach { index, condition in
                let childLocation = "\(location).\(key)[\(index)]"
                unknownKeys(in: condition, allowed: visibleWhenKeys, location: childLocation, into: &diagnostics)
                validateVisibility(condition, location: childLocation, into: &diagnostics)
            }
        }
    }

    private static func validateTemplateFile(_ file: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        requireString("path", in: file, location: location, into: &diagnostics)
        optionalEnumString("scope", values: ["instance", "page", "site"], in: file, location: location, into: &diagnostics)
        optionalEnumString("placement", values: ["headStart", "headEnd", "bodyStart", "bodyEnd"], in: file, location: location, into: &diagnostics)
        optionalBoolean("closure", in: file, location: location, into: &diagnostics)
    }

    private static func validateAPIVersion(
        in dictionary: [String: Any],
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard let rawVersion = dictionary["minimumAPIVersion"] else {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:minimumAPIVersion",
                message: "A minimumAPIVersion integer is required."
            ))
            return
        }
        guard let version = integer(rawVersion) else {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:minimumAPIVersion",
                message: "minimumAPIVersion must be an integer."
            ))
            return
        }
        if version > FoundryPartAPI.supportedVersions.upperBound {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:minimumAPIVersion",
                message: "This part requires Foundry part API \(version), but this version of Foundry supports through API \(FoundryPartAPI.supportedVersions.upperBound). Update Foundry to use this part."
            ))
        } else if version < FoundryPartAPI.supportedVersions.lowerBound {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:minimumAPIVersion",
                message: "This part requires Foundry part API \(version), which is no longer supported. The oldest supported API is \(FoundryPartAPI.supportedVersions.lowerBound)."
            ))
        }
    }

    private static func validateReleaseVersion(
        in dictionary: [String: Any],
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard let version = dictionary["version"] as? String else {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:version",
                message: "A semantic part version such as 1.0.0 is required."
            ))
            return
        }
        guard SemanticVersion(version) != nil else {
            diagnostics.append(.init(
                severity: .error,
                location: "manifest.json:version",
                message: "Use a semantic version in MAJOR.MINOR.PATCH form, for example 1.0.0."
            ))
            return
        }
    }

    private static func rootDictionary(from data: Data) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = value as? [String: Any] else {
            throw SchemaError.rootIsNotDictionary
        }
        return dictionary
    }

    private static func validateGroups(
        in dictionary: [String: Any],
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard dictionary["groups"] != nil else { return }
        validateDictionaryArray(dictionary["groups"], key: "groups", parent: "manifest.json", into: &diagnostics)

        // Editable template primitives inject their properties into Content,
        // so that group can carry an icon even with no declared control in it.
        var usedGroups: Set<String> = ["Content"]
        for entry in dictionaries(in: dictionary["controls"]) {
            if let type = entry["type"] as? String,
               let kind = PartPackageControlGroup.Kind(rawValue: type) {
                usedGroups.insert(kind.groupName)
            } else {
                usedGroups.insert(entry["group"] as? String ?? "Settings")
            }
        }

        var seenNames: Set<String> = []
        dictionaries(in: dictionary["groups"]).enumerated().forEach { index, entry in
            let location = "manifest.json:groups[\(index)]"
            unknownKeys(in: entry, allowed: groupKeys, location: location, into: &diagnostics)
            requireString("name", in: entry, location: location, into: &diagnostics)
            optionalString("systemImage", in: entry, location: location, into: &diagnostics)
            guard let name = entry["name"] as? String else { return }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(.init(severity: .error, location: "\(location).name", message: "A group entry requires a non-empty name."))
                return
            }
            if !seenNames.insert(name).inserted {
                diagnostics.append(.init(severity: .error, location: "\(location).name", message: "Duplicate group entry '\(name)'."))
            }
            if !usedGroups.contains(name) {
                diagnostics.append(.init(severity: .error, location: "\(location).name", message: "groups declares '\(name)' but no control uses that group."))
            }
        }
    }

    private static func validateDictionaryArray(
        _ value: Any?, key: String, parent: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard let value else { return }
        guard let array = value as? [Any] else {
            appendTypeError(key: key, expected: "an array of dictionaries", location: parent, into: &diagnostics)
            return
        }
        for (index, entry) in array.enumerated() where !(entry is [String: Any]) {
            diagnostics.append(.init(
                severity: .error,
                location: "\(parent):\(key)[\(index)]",
                message: "Each \(key) entry must be a dictionary."
            ))
        }
    }

    private static func requireString(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        guard let value = dictionary[key] else {
            appendMissing(key, expected: "string", location: location, into: &diagnostics)
            return
        }
        guard value is String else { appendTypeError(key: key, expected: "a string", location: location, into: &diagnostics); return }
    }

    private static func optionalString(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        if let value = dictionary[key], !(value is String) {
            appendTypeError(key: key, expected: "a string", location: location, into: &diagnostics)
        }
    }

    private static func requireInteger(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        guard let value = dictionary[key] else {
            appendMissing(key, expected: "integer", location: location, into: &diagnostics)
            return
        }
        if integer(value) == nil { appendTypeError(key: key, expected: "an integer", location: location, into: &diagnostics) }
    }

    private static func optionalInteger(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        if let value = dictionary[key], integer(value) == nil {
            appendTypeError(key: key, expected: "an integer", location: location, into: &diagnostics)
        }
    }

    private static func optionalNumber(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        if let value = dictionary[key], !isNumber(value) {
            appendTypeError(key: key, expected: "a number", location: location, into: &diagnostics)
        }
    }

    private static func optionalBoolean(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        if let value = dictionary[key], !isBoolean(value) {
            appendTypeError(key: key, expected: "a Boolean", location: location, into: &diagnostics)
        }
    }

    private static func requireStringArray(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        guard dictionary[key] != nil else {
            appendMissing(key, expected: "array of strings", location: location, into: &diagnostics)
            return
        }
        optionalStringArray(key, in: dictionary, location: location, into: &diagnostics)
    }

    private static func optionalStringArray(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        guard let value = dictionary[key] else { return }
        guard let array = value as? [Any], array.allSatisfy({ $0 is String }) else {
            appendTypeError(key: key, expected: "an array of strings", location: location, into: &diagnostics)
            return
        }
    }

    private static func validateControlGroupValues(
        _ value: Any?,
        key: String,
        permitted: Set<String>,
        location: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard let value else { return }
        guard let values = value as? [String] else { return }
        if values.isEmpty {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).\(key)",
                message: "\(key) must contain at least one value."
            ))
            return
        }
        for (index, value) in values.enumerated() where !permitted.contains(value) {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).\(key)[\(index)]",
                message: "Unknown \(key) value '\(value)'."
            ))
        }
        var seen: Set<String> = []
        for (index, value) in values.enumerated() where !seen.insert(value).inserted {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).\(key)[\(index)]",
                message: "Duplicate \(key) value '\(value)'."
            ))
        }
    }

    private static func optionalEnumString(
        _ key: String, values: Set<String>, in dictionary: [String: Any], location: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        guard let value = dictionary[key] else { return }
        guard let string = value as? String else {
            appendTypeError(key: key, expected: "a string", location: location, into: &diagnostics)
            return
        }
        if !values.contains(string) {
            diagnostics.append(.init(severity: .error, location: "\(location):\(key)", message: "\(key) must be one of: \(values.sorted().joined(separator: ", "))."))
        }
    }

    private static func optionalPartValue(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        guard let value = dictionary[key], !isPartValue(value) else { return }
        appendTypeError(key: key, expected: "a string, number, Boolean, or array of those values", location: location, into: &diagnostics)
    }

    private static func appendMissing(_ key: String, expected: String, location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        diagnostics.append(.init(severity: .error, location: "\(location):\(key)", message: "A \(key) \(expected) is required."))
    }

    private static func appendTypeError(key: String, expected: String, location: String, into diagnostics: inout [PartPackageDiagnostic]) {
        diagnostics.append(.init(severity: .error, location: "\(location):\(key)", message: "\(key) must be \(expected)."))
    }

    private static func dictionaries(in value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func unknownKeys(
        in dictionary: [String: Any],
        allowed: Set<String>,
        location: String,
        into diagnostics: inout [PartPackageDiagnostic]
    ) {
        for key in dictionary.keys where !allowed.contains(key) {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location):\(key)",
                message: "Unknown key '\(key)'. Check the spelling or remove it."
            ))
        }
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func isNumber(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }

    private static func isPartValue(_ value: Any) -> Bool {
        if value is String || isBoolean(value) || isNumber(value) { return true }
        guard let array = value as? [Any] else { return false }
        return array.allSatisfy(isPartValue)
    }

    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let doubleValue = number.doubleValue
        guard doubleValue.rounded() == doubleValue else { return nil }
        return number.intValue
    }
}

nonisolated struct SemanticVersion: Comparable, Sendable {
    private static let expression = try! NSRegularExpression(
        pattern: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"#
    )

    let rawValue: String
    private let core: [Int]
    private let prerelease: [String]

    init?(_ rawValue: String) {
        let range = NSRange(rawValue.startIndex..., in: rawValue)
        guard Self.expression.firstMatch(in: rawValue, range: range)?.range == range else { return nil }
        self.rawValue = rawValue
        let versionAndBuild = rawValue.split(separator: "+", maxSplits: 1)[0]
        let parts = versionAndBuild.split(separator: "-", maxSplits: 1)
        core = parts[0].split(separator: ".").compactMap { Int($0) }
        prerelease = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.core != rhs.core { return lhs.core.lexicographicallyPrecedes(rhs.core) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            if let leftNumber = Int(left), let rightNumber = Int(right) { return leftNumber < rightNumber }
            if Int(left) != nil { return true }
            if Int(right) != nil { return false }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
