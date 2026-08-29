import Foundation
import Synchronization

nonisolated enum ComponentRegistry {
    static let builtInTypes: [ComponentType] = [
        .text
    ]

    static func definition(for type: ComponentType) -> ComponentDefinition {
        packageDefinitions.withLock { $0[type] } ?? builtInDefinitions[type] ?? unavailableDefinition(for: type)
    }

    static var availableTypes: [ComponentType] {
        builtInTypes + packageDefinitions.withLock { definitions in
            definitions.keys.filter { !builtInTypes.contains($0) }.sorted { $0.rawValue < $1.rawValue }
        }
    }

    static func register(_ package: LoadedComponentPackage) {
        let definition = ComponentPackageAdapter.definition(from: package)
        packageDefinitions.withLock { $0[definition.type] = definition }
    }

    static func unregisterPackage(identifier: String) {
        _ = packageDefinitions.withLock { $0.removeValue(forKey: ComponentType(rawValue: identifier)) }
    }

    private static let packageDefinitions = Mutex<[ComponentType: ComponentDefinition]>([:])

    private static let builtInDefinitions: [ComponentType: ComponentDefinition] = [
        .container: definition(
            .container, "Container", "rectangle.3.group", .layout, children: true, render: .container,
            properties: ComponentStyleProperties.appearance(background: "#FFFFFF", cornerRadius: 18) +
                ComponentStyleProperties.layout(padding: 32, maxWidth: 760, alignment: "center")
        ),
        .section: definition(
            .section, "Section", "rectangle.inset.filled", .layout, children: true, render: .section,
            properties: ComponentStyleProperties.appearance(background: "#FFFFFF", cornerRadius: 0) +
                ComponentStyleProperties.layout(padding: 48, maxWidth: 1200, alignment: "center")
        ),
        .columns: definition(
            .columns, "Columns", "rectangle.split.3x1", .layout, children: true, render: .columns,
            properties: [
                .init(key: .columnCount, label: "Columns", section: .layout, control: .number(range: 1...6, step: 1, unit: ""), defaultValue: .number(2)),
                .init(key: .gap, label: "Gap", section: .layout, control: .number(range: 0...120, step: 4, unit: "px"), defaultValue: .number(24))
            ] + ComponentStyleProperties.layout(padding: 0, maxWidth: 1200, alignment: "center")
        ),
        .text: definition(
            .text, "Text", "textformat", .content, inline: .text, render: .text,
            properties: textProperties(label: "Text", defaultText: "New text", size: 38) +
                ComponentStyleProperties.border(cornerRadius: 0) +
                ComponentStyleProperties.layout(padding: 0, maxWidth: 0, alignment: "leading", marginBottom: 32)
        ),
        .heading: definition(
            .heading, "Heading", "textformat.size.larger", .content, inline: .text, render: .heading,
            properties: [
                .init(key: .text, label: "Heading", section: .content, control: .singleLineText, defaultValue: .string("New heading")),
                .init(key: .headingLevel, label: "Level", section: .content, control: .choice((1...6).map { .init(value: "\($0)", label: "Heading \($0)") }), defaultValue: .choice("2"))
            ] + typographyProperties(size: 48) +
                ComponentStyleProperties.layout(padding: 0, maxWidth: 0, alignment: "leading", marginBottom: 24)
        ),
        .button: definition(
            .button, "Button", "capsule", .content, inline: .text, render: .button,
            properties: [
                .init(key: .text, label: "Title", section: .content, control: .singleLineText, defaultValue: .string("Button")),
                .init(key: .destination, label: "Destination", section: .link, control: .url, defaultValue: .url("#")),
                .init(key: .textColor, label: "Text color", section: .typography, control: .color, defaultValue: .color("#FFFFFF")),
                .init(key: .fontSize, label: "Font size", section: .typography, control: .number(range: 10...72, step: 1, unit: "px"), defaultValue: .number(17)),
                .init(key: .accessibilityLabel, label: "Accessibility label", section: .accessibility, control: .singleLineText, defaultValue: .string(""))
            ] + ComponentStyleProperties.appearance(background: "#5B5BD6", cornerRadius: 10) +
                ComponentStyleProperties.layout(padding: 12, maxWidth: 0, alignment: "leading")
        ),
        .image: definition(
            .image, "Image", "photo", .media, render: .image,
            properties: [
                .init(key: .source, label: "Source", section: .content, control: .asset, defaultValue: .url("https://picsum.photos/1200/700")),
                .init(key: .altText, label: "Alternative text", section: .accessibility, control: .singleLineText, defaultValue: .string(""))
            ] + ComponentStyleProperties.border(cornerRadius: 12) +
                ComponentStyleProperties.layout(padding: 0, maxWidth: 1200, alignment: "center", marginBottom: 24)
        ),
        .divider: definition(
            .divider, "Divider", "minus", .content, render: .divider,
            properties: [
                .init(key: .borderColor, label: "Color", section: .appearance, control: .color, defaultValue: .color("#D9D9DE")),
                .init(key: .borderWidth, label: "Thickness", section: .appearance, control: .number(range: 1...24, step: 1, unit: "px"), defaultValue: .number(1))
            ] + ComponentStyleProperties.layout(padding: 0, maxWidth: 1200, alignment: "center", marginBottom: 24)
        ),
        .spacer: definition(
            .spacer, "Spacer", "arrow.up.and.down", .layout, render: .spacer,
            properties: [
                .init(key: .height, label: "Height", section: .layout, control: .number(range: 0...600, step: 4, unit: "px"), defaultValue: .number(48))
            ]
        )
    ]

    private static func definition(
        _ type: ComponentType,
        _ name: String,
        _ icon: String,
        _ category: ComponentCategory,
        children: Bool = false,
        inline: ComponentProperty.Key? = nil,
        render: ComponentRenderKind,
        properties: [ComponentPropertyDefinition]
    ) -> ComponentDefinition {
        ComponentDefinition(
            type: type,
            displayName: name,
            systemImage: icon,
            category: category,
            allowsChildren: children,
            inlineEditableProperty: inline,
            renderKind: render,
            properties: properties
        )
    }

    private static func textProperties(label: String, defaultText: String, size: Double) -> [ComponentPropertyDefinition] {
        [.init(key: .text, label: label, section: .content, control: .multilineText, defaultValue: .string(defaultText))] +
            typographyProperties(size: size)
    }

    private static func typographyProperties(size: Double) -> [ComponentPropertyDefinition] {
        [
            .init(key: .alignment, label: "Alignment", section: .typography, control: .choice([
                .init(value: "leading", label: "Leading"),
                .init(value: "center", label: "Center"),
                .init(value: "trailing", label: "Trailing")
            ]), defaultValue: .choice("leading")),
            .init(key: .textColor, label: "Text color", section: .typography, control: .color, defaultValue: .color("#171719")),
            .init(key: .fontSize, label: "Font size", section: .typography, control: .number(range: 10...120, step: 1, unit: "px"), defaultValue: .number(size))
        ]
    }

    private static func unavailableDefinition(for type: ComponentType) -> ComponentDefinition {
        definition(
            type,
            type.rawValue.split(separator: ".").last.map(String.init) ?? "Unavailable",
            "questionmark.square.dashed",
            .unavailable,
            render: .unavailable,
            properties: []
        )
    }
}
