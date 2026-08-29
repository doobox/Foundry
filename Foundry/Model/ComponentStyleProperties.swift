import Foundation

nonisolated enum ComponentStyleProperties {
    static func appearance(background: String, cornerRadius: Double) -> [ComponentPropertyDefinition] {
        [
            .init(key: .backgroundColor, label: "Background", section: .appearance, control: .color, defaultValue: .color(background))
        ] + border(cornerRadius: cornerRadius)
    }

    static func border(cornerRadius: Double) -> [ComponentPropertyDefinition] {
        [
            .init(key: .borderColor, label: "Border color", section: .appearance, control: .color, defaultValue: .color("#D9D9DE")),
            .init(key: .borderWidth, label: "Border width", section: .appearance, control: .number(range: 0...24, step: 1, unit: "px"), defaultValue: .number(0)),
            .init(key: .cornerRadius, label: "Corner radius", section: .appearance, control: .number(range: 0...160, step: 1, unit: "px"), defaultValue: .number(cornerRadius))
        ]
    }

    static func layout(
        padding: Double,
        maxWidth: Double,
        alignment: String,
        marginBottom: Double = 0
    ) -> [ComponentPropertyDefinition] {
        [
            .init(key: .padding, label: "Padding", section: .layout, control: .number(range: 0...160, step: 4, unit: "px"), defaultValue: .number(padding)),
            .init(key: .marginTop, label: "Margin top", section: .layout, control: .number(range: 0...240, step: 4, unit: "px"), defaultValue: .number(0)),
            .init(key: .marginBottom, label: "Margin bottom", section: .layout, control: .number(range: 0...240, step: 4, unit: "px"), defaultValue: .number(marginBottom)),
            .init(key: .maxWidth, label: "Maximum width", section: .layout, control: .number(range: 0...1600, step: 20, unit: "px"), defaultValue: .number(maxWidth)),
            .init(
                key: .horizontalAlignment,
                label: "Position",
                section: .layout,
                control: .choice([
                    .init(value: "leading", label: "Leading"),
                    .init(value: "center", label: "Center"),
                    .init(value: "trailing", label: "Trailing")
                ]),
                defaultValue: .choice(alignment)
            )
        ]
    }
}
