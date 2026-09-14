import Foundation

/// One public control, composed from the existing width editor and optional style picker.
nonisolated enum PartPackageThemeBorderControl {
    static let styles = ["solid", "dashed", "dotted", "double", "none", "hidden", "groove", "ridge", "inset", "outset"]

    static func fields(_ property: PartPackageProperty) -> [String: PartPackageValue] {
        if case .object(let fields) = property.defaultValue { return fields }
        return [:]
    }

    static func properties(_ property: PartPackageProperty) -> [PartPropertyDefinition] {
        let initial = fields(property)
        let section = PartPropertySection(rawValue: property.group)
        var result = [PartPropertyDefinition(
            key: .init(rawValue: property.id + ".width"),
            label: property.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Border" : property.label,
            subtitle: property.subtitles.first, section: section, control: .themeBorderWidth,
            defaultValue: .themeBorderWidth(PartPackageThemeBorderWidthControl.defaultValue(initial["width"] ?? .string("none")) ?? .init()),
            isResponsive: property.responsive, visibleWhen: property.visibleWhen
        )]
        result.append(PartPropertyDefinition(
            key: .init(rawValue: property.id + ".style"), label: "Style", section: section,
            control: .choice(styles.map { .init(value: $0, label: $0.capitalized) }),
            defaultValue: .choice(initial["style"]?.stringValue ?? "solid"),
            isResponsive: property.responsive,
            isInspectorVisible: property.control.showsStyle == true, visibleWhen: property.visibleWhen
        ))
        for index in result.indices { result[index].inspectorControlID = property.id }
        return result
    }
}
