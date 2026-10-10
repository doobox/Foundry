import Foundation

nonisolated enum PartCollectionValue {
    static let identityKey = "_id"
    static let responsiveValuesKey = "_responsive"

    static func record(
        fields: [PartPropertyDefinition],
        overriding overrides: [String: PartProperty.Value] = [:],
        id: UUID = UUID()
    ) -> PartProperty.Value {
        var values = Dictionary(uniqueKeysWithValues: fields.map { ($0.key.rawValue, $0.defaultValue) })
        values.merge(overrides) { _, replacement in replacement }
        values[identityKey] = .string(id.uuidString)
        let responsive = fields.reduce(into: [String: PartProperty.Value]()) { result, field in
            guard !field.breakpointDefaults.isEmpty else { return }
            result[field.key.rawValue] = .object(Dictionary(uniqueKeysWithValues:
                field.breakpointDefaults.map { ($0.key.rawValue, $0.value) }
            ))
        }
        if !responsive.isEmpty { values[responsiveValuesKey] = .object(responsive) }
        return .object(values)
    }

    static func id(of record: PartProperty.Value) -> String? {
        record.objectValue?[identityKey]?.stringValue.nilIfEmpty
    }

    static func title(
        itemLabel: String,
        position: Int
    ) -> String {
        return "\(itemLabel) \(position + 1)"
    }

    static func value(
        fieldID: String,
        in record: PartProperty.Value,
        at breakpoint: ResponsiveBreakpoint,
        screens: ScreenTokens
    ) -> PartProperty.Value {
        let values = record.objectValue ?? [:]
        let responsive = values[responsiveValuesKey]?.objectValue?[fieldID]?.objectValue ?? [:]
        for candidate in breakpoint.inheritedBreakpoints where candidate.minimumWidth(in: screens) != nil {
            if let value = responsive[candidate.rawValue] { return value }
        }
        return values[fieldID] ?? .string("")
    }

    static func hasOverride(
        fieldID: String,
        in record: PartProperty.Value,
        at breakpoint: ResponsiveBreakpoint
    ) -> Bool {
        record.objectValue?[responsiveValuesKey]?
            .objectValue?[fieldID]?
            .objectValue?[breakpoint.rawValue] != nil
    }

    static func hasOverride(
        in collection: PartProperty.Value,
        at breakpoint: ResponsiveBreakpoint
    ) -> Bool {
        collection.arrayValue?.contains { record in
            record.objectValue?[responsiveValuesKey]?.objectValue?.values.contains { field in
                field.objectValue?[breakpoint.rawValue] != nil
            } == true
        } == true
    }

    static func governingBreakpoint(
        fieldID: String,
        in record: PartProperty.Value,
        at breakpoint: ResponsiveBreakpoint,
        screens: ScreenTokens
    ) -> ResponsiveBreakpoint {
        for candidate in breakpoint.inheritedBreakpoints where candidate.minimumWidth(in: screens) != nil {
            if hasOverride(fieldID: fieldID, in: record, at: candidate) { return candidate }
        }
        return .mobile
    }

    static func setting(
        _ value: PartProperty.Value,
        fieldID: String,
        in record: PartProperty.Value,
        at breakpoint: ResponsiveBreakpoint = .mobile
    ) -> PartProperty.Value {
        var values = record.objectValue ?? [:]
        if breakpoint == .mobile {
            values[fieldID] = value
        } else {
            var responsive = values[responsiveValuesKey]?.objectValue ?? [:]
            var fieldValues = responsive[fieldID]?.objectValue ?? [:]
            fieldValues[breakpoint.rawValue] = value
            responsive[fieldID] = .object(fieldValues)
            values[responsiveValuesKey] = .object(responsive)
        }
        if values[identityKey]?.stringValue.isEmpty != false {
            values[identityKey] = .string(UUID().uuidString)
        }
        return .object(values)
    }

    static func removingOverride(
        fieldID: String,
        from record: PartProperty.Value,
        at breakpoint: ResponsiveBreakpoint
    ) -> PartProperty.Value {
        guard breakpoint != .mobile else { return record }
        var values = record.objectValue ?? [:]
        var responsive = values[responsiveValuesKey]?.objectValue ?? [:]
        var fieldValues = responsive[fieldID]?.objectValue ?? [:]
        fieldValues.removeValue(forKey: breakpoint.rawValue)
        if fieldValues.isEmpty {
            responsive.removeValue(forKey: fieldID)
        } else {
            responsive[fieldID] = .object(fieldValues)
        }
        if responsive.isEmpty {
            values.removeValue(forKey: responsiveValuesKey)
        } else {
            values[responsiveValuesKey] = .object(responsive)
        }
        return .object(values)
    }

    static func resolved(
        _ record: PartProperty.Value,
        fields: [PartPropertyDefinition],
        at breakpoint: ResponsiveBreakpoint,
        screens: ScreenTokens
    ) -> PartProperty.Value {
        var values = record.objectValue ?? [:]
        values.removeValue(forKey: identityKey)
        values.removeValue(forKey: responsiveValuesKey)
        for field in fields {
            values[field.key.rawValue] = value(
                fieldID: field.key.rawValue,
                in: record,
                at: field.isResponsive ? breakpoint : .mobile,
                screens: screens
            )
        }
        for field in fields where field.valueAvailability == .whenVisible {
            if !PartPackageVisibilityEvaluator.isVisible(field.visibleWhen, values: values) {
                values.removeValue(forKey: field.key.rawValue)
            }
        }
        for field in fields {
            switch field.control {
            case .image, .svg:
                let id = field.key.rawValue
                guard values[id] != nil else { continue }
                let altKey = PartPackageAdapter.imageAltKey(for: id).rawValue
                values[id + ".alt"] = values.removeValue(forKey: altKey) ?? .string("")
                let focalKey = PartPackageAdapter.imageFocalPointKey(for: id).rawValue
                if let focal = values.removeValue(forKey: focalKey)?.arrayValue, focal.count == 2 {
                    values[id + ".focalPointX"] = focal[0]
                    values[id + ".focalPointY"] = focal[1]
                }
            default:
                continue
            }
        }
        return .object(values)
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
