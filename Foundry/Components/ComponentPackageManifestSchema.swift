import Foundation
import CoreFoundation

nonisolated enum FoundryComponentAPI {
    static let supportedVersions = 1...1
    static let currentVersion = supportedVersions.upperBound
}

nonisolated enum ComponentPackageManifestSchema {
    enum Kind: Sendable {
        case collection
        case component
    }

    struct Inspection: Sendable {
        let kind: Kind
        let identifier: String?
    }

    enum SchemaError: Error, LocalizedError {
        case rootIsNotDictionary
        case invalidCollectionFlag
        case invalidCollectionKeys([String])
        case missingComponentIdentifier

        var errorDescription: String? {
            switch self {
            case .rootIsNotDictionary:
                "Info.plist must contain a dictionary at its root."
            case .invalidCollectionFlag:
                "Info.plist:collection must be a Boolean."
            case .invalidCollectionKeys(let keys):
                "A collection Info.plist may contain only collection = true. Remove: \(keys.joined(separator: ", "))."
            case .missingComponentIdentifier:
                "A component Info.plist requires a non-empty id."
            }
        }
    }

    private static let componentKeys: Set<String> = [
        "minimumAPIVersion", "id", "title", "description", "author", "version", "group",
        "tags", "slots", "customItems", "templates", "assets", "helpURL", "missingComponent",
        "requiresPhp", "libraries", "collection", "updates"
    ]
    private static let collectionKeys: Set<String> = [
        "collection", "minimumAPIVersion", "id", "title", "author", "version", "updates"
    ]
    private static let updateKeys: Set<String> = ["appcastURL", "publicKey"]
    private static let slotKeys: Set<String> = ["id", "title", "accepts", "minimum", "maximum"]
    private static let propertyKeys: Set<String> = [
        "id", "label", "group", "default", "responsive", "subtitle", "buttonText", "units", "toolTip",
        "type", "minimum", "maximum", "step", "options", "themeValues", "allowsCustom", "colorMath", "opacity", "outputFormat",
        "customColor", "count", "ticks", "showsValueField", "trueValue", "falseValue",
        "buttonIcon", "activeButtonText", "activeButtonIcon", "selectionMode", "fontSize", "argument1", "argument2", "operation", "round", "absoluteURL", "enable", "alt", "focalPoint", "renditions"
    ]
    private static let enableKeys: Set<String> = ["id", "operation", "value"]
    private static let optionKeys: Set<String> = ["value", "title"]
    private static let templateKeys: Set<String> = ["html", "editorCSS", "files"]
    private static let templateFileKeys: Set<String> = ["path", "scope", "placement", "closure"]
    private static let missingComponentKeys: Set<String> = ["message", "preview"]
    private static let libraryKeys: Set<String> = ["id", "majorVersion"]
    private static let assetKeys: Set<String> = ["path", "scope"]
    private static let renditionKeys: Set<String> = ["id", "maximumDimension"]

    static func inspect(_ data: Data) throws -> Inspection {
        let dictionary = try rootDictionary(from: data)
        let collection: Bool
        if let rawCollection = dictionary["collection"] {
            guard isBoolean(rawCollection), let value = rawCollection as? Bool else {
                throw SchemaError.invalidCollectionFlag
            }
            collection = value
        } else {
            collection = false
        }

        if collection {
            let unknownKeys = dictionary.keys.filter { !collectionKeys.contains($0) }.sorted()
            guard unknownKeys.isEmpty else {
                throw SchemaError.invalidCollectionKeys(unknownKeys)
            }
            let identifier = dictionary["id"] as? String
            if dictionary["updates"] != nil,
               (identifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                || SemanticVersion(dictionary["version"] as? String ?? "") == nil) {
                throw SchemaError.invalidCollectionKeys(["An update-enabled collection requires id and semantic version"])
            }
            return Inspection(kind: .collection, identifier: identifier)
        }

        guard let identifier = dictionary["id"] as? String,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchemaError.missingComponentIdentifier
        }
        return Inspection(kind: .component, identifier: identifier)
    }

    static func diagnostics(for data: Data) throws -> [ComponentPackageDiagnostic] {
        let dictionary = try rootDictionary(from: data)
        var diagnostics: [ComponentPackageDiagnostic] = []
        unknownKeys(in: dictionary, allowed: componentKeys, location: "Info.plist", into: &diagnostics)
        validateComponentFields(in: dictionary, into: &diagnostics)

        if let collection = dictionary["collection"], !isBoolean(collection) {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:collection",
                message: "collection must be a Boolean."
            ))
        }
        validateAPIVersion(in: dictionary, into: &diagnostics)
        validateReleaseVersion(in: dictionary, into: &diagnostics)
        validateUpdates(in: dictionary, into: &diagnostics)

        validateDictionaryArray(dictionary["slots"], key: "slots", parent: "Info.plist", into: &diagnostics)
        dictionaries(in: dictionary["slots"]).enumerated().forEach { index, slot in
            let location = "Info.plist:slots[\(index)]"
            unknownKeys(
                in: slot,
                allowed: slotKeys,
                location: location,
                into: &diagnostics
            )
            validateSlot(slot, location: location, into: &diagnostics)
        }
        validateDictionaryArray(dictionary["customItems"], key: "customItems", parent: "Info.plist", into: &diagnostics)
        dictionaries(in: dictionary["customItems"]).enumerated().forEach { index, property in
            let location = "Info.plist:customItems[\(index)]"
            unknownKeys(in: property, allowed: propertyKeys, location: location, into: &diagnostics)
            validateProperty(property, location: location, into: &diagnostics)
            if let themeValues = property["themeValues"], !(themeValues is String) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).themeValues",
                    message: "themeValues must be a string."
                ))
            }
            if property["type"] as? String == ComponentPackageControl.Kind.select.rawValue,
               property["themeValues"] is String,
               property["count"] != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).count",
                    message: "A select control using themeValues cannot be a multi control; remove count."
                ))
            }
            if property["type"] as? String == ComponentPackageControl.Kind.themeColor.rawValue,
               property["count"] != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).count",
                    message: "A themeColor control cannot be a multi control; remove count."
                ))
            }
            if property["type"] as? String == ComponentPackageControl.Kind.shadow.rawValue,
               property["themeValues"] != nil {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).themeValues",
                    message: "A shadow control automatically uses theme shadows; remove themeValues."
                ))
            }
            if property["type"] as? String == ComponentPackageControl.Kind.select.rawValue,
               property["themeValues"] as? String == ComponentPackageThemeValueSource.shadows.rawValue {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location).type",
                    message: "Use type shadow instead of a select control requesting shadow theme values."
                ))
            }
            if let enable = property["enable"] as? [String: Any] {
                unknownKeys(in: enable, allowed: enableKeys, location: "\(location).enable", into: &diagnostics)
                validateEnable(enable, location: "\(location).enable", into: &diagnostics)
            }
            if let enable = property["enable"], !(enable is [String: Any]) {
                appendTypeError(key: "enable", expected: "a dictionary", location: location, into: &diagnostics)
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
            }
        }
        if let templates = dictionary["templates"], !(templates is [String: Any]) {
            appendTypeError(key: "templates", expected: "a dictionary", location: "Info.plist", into: &diagnostics)
        }
        if let templates = dictionary["templates"] as? [String: Any] {
            unknownKeys(
                in: templates,
                allowed: templateKeys,
                location: "Info.plist:templates",
                into: &diagnostics
            )
            requireString("html", in: templates, location: "Info.plist:templates", into: &diagnostics)
            optionalString("editorCSS", in: templates, location: "Info.plist:templates", into: &diagnostics)
            validateDictionaryArray(templates["files"], key: "files", parent: "Info.plist:templates", into: &diagnostics)
            dictionaries(in: templates["files"]).enumerated().forEach { index, file in
                let fileLocation = "Info.plist:templates.files[\(index)]"
                unknownKeys(
                    in: file,
                    allowed: templateFileKeys,
                    location: fileLocation,
                    into: &diagnostics
                )
                validateTemplateFile(file, location: fileLocation, into: &diagnostics)
            }
        }
        if let rawAssets = dictionary["assets"], !(rawAssets is [Any]) {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:assets",
                message: "assets must be an array of asset dictionaries."
            ))
        }
        if let assets = dictionary["assets"] as? [Any] {
            for (index, asset) in assets.enumerated() {
                let location = "Info.plist:assets[\(index)]"
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
        if let missingComponent = dictionary["missingComponent"] as? [String: Any] {
            unknownKeys(
                in: missingComponent,
                allowed: missingComponentKeys,
                location: "Info.plist:missingComponent",
                into: &diagnostics
            )
            optionalString("message", in: missingComponent, location: "Info.plist:missingComponent", into: &diagnostics)
            optionalString("preview", in: missingComponent, location: "Info.plist:missingComponent", into: &diagnostics)
        } else if dictionary["missingComponent"] != nil {
            appendTypeError(key: "missingComponent", expected: "a dictionary", location: "Info.plist", into: &diagnostics)
        }
        validateDictionaryArray(dictionary["libraries"], key: "libraries", parent: "Info.plist", into: &diagnostics)
        dictionaries(in: dictionary["libraries"]).enumerated().forEach { index, library in
            let location = "Info.plist:libraries[\(index)]"
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

    private static func validateComponentFields(in dictionary: [String: Any], into diagnostics: inout [ComponentPackageDiagnostic]) {
        requireString("id", in: dictionary, location: "Info.plist", into: &diagnostics)
        requireString("title", in: dictionary, location: "Info.plist", into: &diagnostics)
        optionalString("description", in: dictionary, location: "Info.plist", into: &diagnostics)
        optionalString("author", in: dictionary, location: "Info.plist", into: &diagnostics)
        optionalString("group", in: dictionary, location: "Info.plist", into: &diagnostics)
        optionalString("helpURL", in: dictionary, location: "Info.plist", into: &diagnostics)
        optionalBoolean("requiresPhp", in: dictionary, location: "Info.plist", into: &diagnostics)
        optionalStringArray("tags", in: dictionary, location: "Info.plist", into: &diagnostics)
        if dictionary["templates"] == nil {
            appendMissing("templates", expected: "dictionary", location: "Info.plist", into: &diagnostics)
        }
    }

    private static func validateSlot(_ slot: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        requireString("id", in: slot, location: location, into: &diagnostics)
        requireString("title", in: slot, location: location, into: &diagnostics)
        requireStringArray("accepts", in: slot, location: location, into: &diagnostics)
        requireInteger("minimum", in: slot, location: location, into: &diagnostics)
        optionalInteger("maximum", in: slot, location: location, into: &diagnostics)
    }

    private static func validateProperty(_ property: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        requireString("id", in: property, location: location, into: &diagnostics)
        optionalString("group", in: property, location: location, into: &diagnostics)
        optionalString("toolTip", in: property, location: location, into: &diagnostics)
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
        guard let type = ComponentPackageControl.Kind(rawValue: typeName) else {
            diagnostics.append(.init(severity: .error, location: "\(location):type", message: "Unknown control type '\(typeName)'."))
            return
        }
        if type == .divider {
            let supportedKeys: Set<String> = ["type", "id", "group", "enable"]
            for key in property.keys where !supportedKeys.contains(key) {
                diagnostics.append(.init(
                    severity: .error,
                    location: "\(location):\(key)",
                    message: "A divider control does not support \(key)."
                ))
            }
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
        if type == .shadow, property["count"] != nil {
            diagnostics.append(.init(
                severity: .error,
                location: "\(location).count",
                message: "A shadow control cannot be a multi control; use its visual layer editor instead."
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
            optionalString("units", in: property, location: location, into: &diagnostics)
        }
        optionalString("label", in: property, location: location, into: &diagnostics)

        if type == .date {
            optionalString("minimum", in: property, location: location, into: &diagnostics)
            optionalString("maximum", in: property, location: location, into: &diagnostics)
        } else {
            for key in ["minimum", "maximum"] { optionalNumber(key, in: property, location: location, into: &diagnostics) }
        }
        optionalNumber("step", in: property, location: location, into: &diagnostics)
        for key in ["allowsCustom", "colorMath", "opacity", "showsValueField", "round", "absoluteURL"] {
            optionalBoolean(key, in: property, location: location, into: &diagnostics)
        }
        for key in ["ticks"] { optionalInteger(key, in: property, location: location, into: &diagnostics) }
        for key in ["customColor", "operation"] { optionalString(key, in: property, location: location, into: &diagnostics) }
        optionalEnumString("selectionMode", values: ["multiple", "single"], in: property, location: location, into: &diagnostics)
        optionalEnumString(
            "outputFormat",
            values: Set(ComponentPackageControl.ColorOutputFormat.allCases.map(\.rawValue)),
            in: property,
            location: location,
            into: &diagnostics
        )
        for key in ["default", "trueValue", "falseValue", "argument1", "argument2"] {
            optionalComponentValue(key, in: property, location: location, into: &diagnostics)
        }

        let permitsMissingDefault = type == .divider || type == .image || type == .info || type == .math || type == .slider
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

    private static func validateEnable(_ enable: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        requireString("id", in: enable, location: location, into: &diagnostics)
        optionalString("operation", in: enable, location: location, into: &diagnostics)
        optionalComponentValue("value", in: enable, location: location, into: &diagnostics)
    }

    private static func validateTemplateFile(_ file: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        requireString("path", in: file, location: location, into: &diagnostics)
        optionalEnumString("scope", values: ["instance", "page", "site"], in: file, location: location, into: &diagnostics)
        optionalEnumString("placement", values: ["headStart", "headEnd", "bodyStart", "bodyEnd"], in: file, location: location, into: &diagnostics)
        optionalBoolean("closure", in: file, location: location, into: &diagnostics)
    }

    private static func validateAPIVersion(
        in dictionary: [String: Any],
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        guard let rawVersion = dictionary["minimumAPIVersion"] else {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:minimumAPIVersion",
                message: "A minimumAPIVersion integer is required."
            ))
            return
        }
        guard let version = integer(rawVersion) else {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:minimumAPIVersion",
                message: "minimumAPIVersion must be an integer."
            ))
            return
        }
        if version > FoundryComponentAPI.supportedVersions.upperBound {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:minimumAPIVersion",
                message: "This component requires Foundry component API \(version), but this version of Foundry supports through API \(FoundryComponentAPI.supportedVersions.upperBound). Update Foundry to use this component."
            ))
        } else if version < FoundryComponentAPI.supportedVersions.lowerBound {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:minimumAPIVersion",
                message: "This component requires Foundry component API \(version), which is no longer supported. The oldest supported API is \(FoundryComponentAPI.supportedVersions.lowerBound)."
            ))
        }
    }

    private static func validateReleaseVersion(
        in dictionary: [String: Any],
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        guard let version = dictionary["version"] as? String else {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:version",
                message: "A semantic component version such as 1.0.0 is required."
            ))
            return
        }
        guard SemanticVersion(version) != nil else {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:version",
                message: "Use a semantic version in MAJOR.MINOR.PATCH form, for example 1.0.0."
            ))
            return
        }
    }

    private static func validateUpdates(
        in dictionary: [String: Any],
        into diagnostics: inout [ComponentPackageDiagnostic]
    ) {
        guard let value = dictionary["updates"] else { return }
        guard let updates = value as? [String: Any] else {
            appendTypeError(key: "updates", expected: "a dictionary", location: "Info.plist", into: &diagnostics)
            return
        }
        unknownKeys(in: updates, allowed: updateKeys, location: "Info.plist:updates", into: &diagnostics)
        requireString("appcastURL", in: updates, location: "Info.plist:updates", into: &diagnostics)
        requireString("publicKey", in: updates, location: "Info.plist:updates", into: &diagnostics)
        if let value = updates["appcastURL"] as? String,
           URL(string: value)?.scheme?.lowercased() != "https" {
            diagnostics.append(.init(severity: .error, location: "Info.plist:updates:appcastURL", message: "appcastURL must use HTTPS."))
        }
        if let value = updates["publicKey"] as? String,
           Data(base64Encoded: value)?.count != 32 {
            diagnostics.append(.init(severity: .error, location: "Info.plist:updates:publicKey", message: "publicKey must be a Base64-encoded Ed25519 public key."))
        }
    }

    private static func rootDictionary(from data: Data) throws -> [String: Any] {
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = value as? [String: Any] else {
            throw SchemaError.rootIsNotDictionary
        }
        return dictionary
    }

    private static func validateDictionaryArray(
        _ value: Any?, key: String, parent: String,
        into diagnostics: inout [ComponentPackageDiagnostic]
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

    private static func requireString(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        guard let value = dictionary[key] else {
            appendMissing(key, expected: "string", location: location, into: &diagnostics)
            return
        }
        guard value is String else { appendTypeError(key: key, expected: "a string", location: location, into: &diagnostics); return }
    }

    private static func optionalString(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        if let value = dictionary[key], !(value is String) {
            appendTypeError(key: key, expected: "a string", location: location, into: &diagnostics)
        }
    }

    private static func requireInteger(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        guard let value = dictionary[key] else {
            appendMissing(key, expected: "integer", location: location, into: &diagnostics)
            return
        }
        if integer(value) == nil { appendTypeError(key: key, expected: "an integer", location: location, into: &diagnostics) }
    }

    private static func optionalInteger(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        if let value = dictionary[key], integer(value) == nil {
            appendTypeError(key: key, expected: "an integer", location: location, into: &diagnostics)
        }
    }

    private static func optionalNumber(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        if let value = dictionary[key], !isNumber(value) {
            appendTypeError(key: key, expected: "a number", location: location, into: &diagnostics)
        }
    }

    private static func optionalBoolean(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        if let value = dictionary[key], !isBoolean(value) {
            appendTypeError(key: key, expected: "a Boolean", location: location, into: &diagnostics)
        }
    }

    private static func requireStringArray(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        guard dictionary[key] != nil else {
            appendMissing(key, expected: "array of strings", location: location, into: &diagnostics)
            return
        }
        optionalStringArray(key, in: dictionary, location: location, into: &diagnostics)
    }

    private static func optionalStringArray(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        guard let value = dictionary[key] else { return }
        guard let array = value as? [Any], array.allSatisfy({ $0 is String }) else {
            appendTypeError(key: key, expected: "an array of strings", location: location, into: &diagnostics)
            return
        }
    }

    private static func optionalEnumString(
        _ key: String, values: Set<String>, in dictionary: [String: Any], location: String,
        into diagnostics: inout [ComponentPackageDiagnostic]
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

    private static func optionalComponentValue(_ key: String, in dictionary: [String: Any], location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        guard let value = dictionary[key], !isComponentValue(value) else { return }
        appendTypeError(key: key, expected: "a string, number, Boolean, or array of those values", location: location, into: &diagnostics)
    }

    private static func appendMissing(_ key: String, expected: String, location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        diagnostics.append(.init(severity: .error, location: "\(location):\(key)", message: "A \(key) \(expected) is required."))
    }

    private static func appendTypeError(key: String, expected: String, location: String, into diagnostics: inout [ComponentPackageDiagnostic]) {
        diagnostics.append(.init(severity: .error, location: "\(location):\(key)", message: "\(key) must be \(expected)."))
    }

    private static func dictionaries(in value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func unknownKeys(
        in dictionary: [String: Any],
        allowed: Set<String>,
        location: String,
        into diagnostics: inout [ComponentPackageDiagnostic]
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

    private static func isComponentValue(_ value: Any) -> Bool {
        if value is String || isBoolean(value) || isNumber(value) { return true }
        guard let array = value as? [Any] else { return false }
        return array.allSatisfy(isComponentValue)
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
