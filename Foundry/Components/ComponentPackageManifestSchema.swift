import Foundation
import CoreFoundation

nonisolated enum FoundryComponentAPI {
    static let supportedVersions = 1...1
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
        "requiresPhp", "libraries", "collection"
    ]
    private static let slotKeys: Set<String> = ["id", "title", "accepts", "minimum", "maximum"]
    private static let propertyKeys: Set<String> = [
        "id", "labels", "group", "default", "responsive", "subtitles", "units", "toolTip",
        "type", "minimum", "maximum", "step", "options", "themeValues", "colorMath", "opacity",
        "customColor", "customValue", "count", "ticks", "showsValueField", "trueValue", "falseValue",
        "systemImage", "fontSize", "argument1", "argument2", "operation", "round", "absoluteURL"
    ]
    private static let optionKeys: Set<String> = ["value", "title"]
    private static let templateKeys: Set<String> = ["html", "editorCSS", "files"]
    private static let templateFileKeys: Set<String> = ["path", "scope", "placement", "closure"]
    private static let missingComponentKeys: Set<String> = ["message", "preview"]
    private static let libraryKeys: Set<String> = ["id", "majorVersion"]

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
            let unknownKeys = dictionary.keys.filter { $0 != "collection" }.sorted()
            guard unknownKeys.isEmpty else {
                throw SchemaError.invalidCollectionKeys(unknownKeys)
            }
            return Inspection(kind: .collection, identifier: nil)
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

        if let collection = dictionary["collection"], !isBoolean(collection) {
            diagnostics.append(.init(
                severity: .error,
                location: "Info.plist:collection",
                message: "collection must be a Boolean."
            ))
        }
        validateAPIVersion(in: dictionary, into: &diagnostics)
        validateReleaseVersion(in: dictionary, into: &diagnostics)

        dictionaries(in: dictionary["slots"]).enumerated().forEach { index, slot in
            unknownKeys(
                in: slot,
                allowed: slotKeys,
                location: "Info.plist:slots[\(index)]",
                into: &diagnostics
            )
        }
        dictionaries(in: dictionary["customItems"]).enumerated().forEach { index, property in
            let location = "Info.plist:customItems[\(index)]"
            unknownKeys(in: property, allowed: propertyKeys, location: location, into: &diagnostics)
            dictionaries(in: property["options"]).enumerated().forEach { optionIndex, option in
                unknownKeys(
                    in: option,
                    allowed: optionKeys,
                    location: "\(location):options[\(optionIndex)]",
                    into: &diagnostics
                )
            }
        }
        if let templates = dictionary["templates"] as? [String: Any] {
            unknownKeys(
                in: templates,
                allowed: templateKeys,
                location: "Info.plist:templates",
                into: &diagnostics
            )
            dictionaries(in: templates["files"]).enumerated().forEach { index, file in
                unknownKeys(
                    in: file,
                    allowed: templateFileKeys,
                    location: "Info.plist:templates.files[\(index)]",
                    into: &diagnostics
                )
            }
        }
        if let missingComponent = dictionary["missingComponent"] as? [String: Any] {
            unknownKeys(
                in: missingComponent,
                allowed: missingComponentKeys,
                location: "Info.plist:missingComponent",
                into: &diagnostics
            )
        }
        dictionaries(in: dictionary["libraries"]).enumerated().forEach { index, library in
            unknownKeys(
                in: library,
                allowed: libraryKeys,
                location: "Info.plist:libraries[\(index)]",
                into: &diagnostics
            )
        }
        return diagnostics
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

    private static func rootDictionary(from data: Data) throws -> [String: Any] {
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = value as? [String: Any] else {
            throw SchemaError.rootIsNotDictionary
        }
        return dictionary
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

    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let doubleValue = number.doubleValue
        guard doubleValue.rounded() == doubleValue else { return nil }
        return number.intValue
    }
}

nonisolated struct SemanticVersion: Equatable, Sendable {
    private static let expression = try! NSRegularExpression(
        pattern: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"#
    )

    let rawValue: String

    init?(_ rawValue: String) {
        let range = NSRange(rawValue.startIndex..., in: rawValue)
        guard Self.expression.firstMatch(in: rawValue, range: range)?.range == range else { return nil }
        self.rawValue = rawValue
    }
}
