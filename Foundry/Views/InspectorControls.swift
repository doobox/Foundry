import AppKit
import SwiftUI

enum InspectorMetrics {
    static let labelWidth: CGFloat = 90
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static let controlSpacing: CGFloat = 20
    static let horizontalSectionPadding: CGFloat = 16
    static let verticalSectionPadding: CGFloat = 12
}

private extension ControlSize {
    var appKitControlSize: NSControl.ControlSize {
        switch self {
        case .mini: .mini
        case .small: .small
        case .regular: .regular
        case .large, .extraLarge: .large
        @unknown default: .small
        }
    }
}

struct InspectorGrid<Content: View>: View {
    private let content: Content
    private let contentInsets: EdgeInsets

    init(
        contentInsets: EdgeInsets = EdgeInsets(
            top: InspectorMetrics.verticalSectionPadding,
            leading: InspectorMetrics.horizontalSectionPadding,
            bottom: InspectorMetrics.verticalSectionPadding,
            trailing: InspectorMetrics.horizontalSectionPadding
        ),
        @ViewBuilder content: () -> Content
    ) {
        self.contentInsets = contentInsets
        self.content = content()
    }

    var body: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: InspectorMetrics.columnSpacing,
            verticalSpacing: InspectorMetrics.rowSpacing
        ) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(contentInsets)
        .controlSize(.small)
        .font(.callout)
    }
}

struct InspectorRow<Control: View>: View {
    let title: String
    let alignment: VerticalAlignment
    let indicator: InspectorRowIndicator?
    private let control: Control

    init(
        title: String,
        alignment: VerticalAlignment = .firstTextBaseline,
        indicator: InspectorRowIndicator? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.alignment = alignment
        self.indicator = indicator
        self.control = control()
    }

    var body: some View {
        GridRow(alignment: alignment) {
            HStack(spacing: 3) {
                if let indicator {
                    InspectorResponsiveIndicator(
                        isVisible: indicator.isVisible,
                        isOverridden: indicator.isOverridden,
                        breakpointName: indicator.breakpointName,
                        toggle: indicator.toggle
                    )
                    .frame(width: 8)
                }

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .help(title)
            }
            .frame(width: InspectorMetrics.labelWidth)
            .gridColumnAlignment(.trailing)

            control
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridColumnAlignment(.leading)
        }
    }
}

struct InspectorRowIndicator {
    let isVisible: Bool
    let isOverridden: Bool
    let breakpointName: String
    let toggle: () -> Void
}

struct InspectorPopupOption<Value: Hashable>: Identifiable, Equatable {
    let title: String
    let value: Value
    var separatorBefore: Bool = false

    var id: Value { value }
}

struct InspectorPopup<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [InspectorPopupOption<Value>]
    let accessibilityLabel: String
    let help: String?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    init(
        selection: Binding<Value>,
        options: [InspectorPopupOption<Value>],
        accessibilityLabel: String,
        help: String? = nil
    ) {
        _selection = selection
        self.options = options
        self.accessibilityLabel = accessibilityLabel
        self.help = help
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, options: options)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = controlSize.appKitControlSize
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        rebuildMenu(of: popup)
        updateSelection(of: popup)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        popup.controlSize = controlSize.appKitControlSize
        context.coordinator.selection = $selection
        if context.coordinator.options != options {
            context.coordinator.options = options
            rebuildMenu(of: popup)
        }

        context.coordinator.isUpdating = true
        updateSelection(of: popup)
        popup.isEnabled = isEnabled
        popup.toolTip = help
        popup.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.isUpdating = false
    }

    static func dismantleNSView(_ popup: NSPopUpButton, coordinator: Coordinator) {
        popup.target = nil
        popup.action = nil
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSPopUpButton,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
            height: nsView.intrinsicContentSize.height
        )
    }

    private func rebuildMenu(of popup: NSPopUpButton) {
        popup.removeAllItems()
        for (index, option) in options.enumerated() {
            if option.separatorBefore, popup.numberOfItems > 0 {
                popup.menu?.addItem(.separator())
            }
            let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
            item.tag = index
            popup.menu?.addItem(item)
        }
    }

    private func updateSelection(of popup: NSPopUpButton) {
        if let selectedIndex = options.firstIndex(where: { $0.value == selection }) {
            popup.select(popup.itemArray.first(where: { !$0.isSeparatorItem && $0.tag == selectedIndex }))
        } else {
            popup.select(nil)
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var options: [InspectorPopupOption<Value>]
        var isUpdating = false

        init(selection: Binding<Value>, options: [InspectorPopupOption<Value>]) {
            self.selection = selection
            self.options = options
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let optionIndex = sender.selectedItem?.tag ?? -1
            guard !isUpdating, options.indices.contains(optionIndex) else { return }
            selection.wrappedValue = options[optionIndex].value
        }
    }
}

struct InspectorTextField: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let help: String?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    init(text: Binding<String>, accessibilityLabel: String, help: String? = nil) {
        _text = text
        self.accessibilityLabel = accessibilityLabel
        self.help = help
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.controlSize = controlSize.appKitControlSize
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.controlSize = controlSize.appKitControlSize
        context.coordinator.text = $text
        context.coordinator.isUpdating = true
        if field.stringValue != text { field.stringValue = text }
        field.isEnabled = isEnabled
        field.toolTip = help
        field.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.isUpdating = false
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) { field.delegate = nil }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isUpdating = false
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdating, let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

struct InspectorNumberField: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityLabel: String
    let help: String?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 0,
        accessibilityLabel: String,
        help: String? = nil
    ) {
        _value = value
        self.range = range
        self.step = step
        self.accessibilityLabel = accessibilityLabel
        self.help = help
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, range: range, step: step)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.controlSize = controlSize.appKitControlSize
        field.alignment = .right
        field.delegate = context.coordinator
        field.formatter = context.coordinator.formatter
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.display(value, in: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.controlSize = controlSize.appKitControlSize
        context.coordinator.value = $value
        context.coordinator.update(range: range, step: step)
        if field.currentEditor() == nil, context.coordinator.displayedValue(in: field) != value {
            context.coordinator.display(value, in: field)
        }
        field.isEnabled = isEnabled
        field.toolTip = help
        field.setAccessibilityLabel(accessibilityLabel)
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        field.delegate = nil
        field.formatter = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<Double>
        let formatter: NumberFormatter
        private var range: ClosedRange<Double>
        private var step: Double

        init(value: Binding<Double>, range: ClosedRange<Double>, step: Double) {
            self.value = value
            self.range = range
            self.step = step
            formatter = NumberFormatter()
            super.init()
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.isLenient = false
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 12
            update(range: range, step: step)
        }

        func update(range: ClosedRange<Double>, step: Double) {
            self.range = range
            self.step = step
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let parsed = parsedValue(from: field),
                  parsed != value.wrappedValue else { return }
            value.wrappedValue = parsed
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            guard let parsed = numericValue(from: field) else {
                NSSound.beep()
                display(value.wrappedValue, in: field)
                return
            }
            let resolved = InspectorSliderValueResolver.resolve(parsed, range: range, step: step)
            value.wrappedValue = resolved
            display(resolved, in: field)
        }

        func displayedValue(in field: NSTextField) -> Double? {
            formatter.number(from: field.stringValue)?.doubleValue
        }

        func display(_ value: Double, in field: NSTextField) {
            field.stringValue = formatter.string(from: NSNumber(value: value)) ?? value.formatted()
        }

        private func parsedValue(from field: NSTextField) -> Double? {
            guard let parsed = numericValue(from: field), range.contains(parsed) else { return nil }
            return parsed
        }

        private func numericValue(from field: NSTextField) -> Double? {
            guard let parsed = formatter.number(from: field.stringValue)?.doubleValue,
                  parsed.isFinite else { return nil }
            return parsed
        }
    }
}

struct InspectorStepper: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let increment: Double
    let accessibilityLabel: String
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSStepper {
        let stepper = NSStepper()
        stepper.controlSize = controlSize.appKitControlSize
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.valueChanged(_:))
        return stepper
    }

    func updateNSView(_ stepper: NSStepper, context: Context) {
        stepper.controlSize = controlSize.appKitControlSize
        context.coordinator.value = $value
        context.coordinator.isUpdating = true
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = increment
        stepper.doubleValue = value
        stepper.isEnabled = isEnabled
        stepper.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.isUpdating = false
    }

    static func dismantleNSView(_ stepper: NSStepper, coordinator: Coordinator) {
        stepper.target = nil
        stepper.action = nil
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var isUpdating = false
        init(value: Binding<Double>) { self.value = value }
        @objc func valueChanged(_ sender: NSStepper) {
            guard !isUpdating else { return }
            value.wrappedValue = sender.doubleValue
        }
    }
}

struct InspectorSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tickMarkCount: Int
    let isContinuous: Bool
    let accessibilityLabel: String
    let help: String?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        tickMarkCount: Int = 0,
        isContinuous: Bool = true,
        accessibilityLabel: String,
        help: String? = nil
    ) {
        _value = value
        self.range = range
        self.step = step
        self.tickMarkCount = tickMarkCount
        self.isContinuous = isContinuous
        self.accessibilityLabel = accessibilityLabel
        self.help = help
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, range: range, step: step)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.controlSize = controlSize.appKitControlSize
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        slider.controlSize = controlSize.appKitControlSize
        context.coordinator.value = $value
        context.coordinator.range = range
        context.coordinator.step = step
        context.coordinator.isUpdating = true
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.altIncrementValue = step > 0 ? step : 0
        slider.numberOfTickMarks = tickMarkCount
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = isContinuous
        slider.doubleValue = value
        slider.isEnabled = isEnabled
        slider.toolTip = help
        slider.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.isUpdating = false
    }

    static func dismantleNSView(_ slider: NSSlider, coordinator: Coordinator) {
        slider.target = nil
        slider.action = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var range: ClosedRange<Double>
        var step: Double
        var isUpdating = false

        init(value: Binding<Double>, range: ClosedRange<Double>, step: Double) {
            self.value = value
            self.range = range
            self.step = step
        }

        @objc func valueChanged(_ sender: NSSlider) {
            guard !isUpdating else { return }
            let resolvedValue = InspectorSliderValueResolver.resolve(
                sender.doubleValue,
                range: range,
                step: step
            )
            sender.doubleValue = resolvedValue
            value.wrappedValue = resolvedValue
        }
    }
}

nonisolated enum InspectorSliderValueResolver {
    static func resolve(
        _ rawValue: Double,
        range: ClosedRange<Double>,
        step: Double
    ) -> Double {
        guard step > 0 else {
            return min(max(rawValue, range.lowerBound), range.upperBound)
        }

        let offset = Decimal(rawValue - range.lowerBound)
        let increment = Decimal(step)
        var quotient = offset / increment
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .plain)
        let snapped = range.lowerBound + NSDecimalNumber(decimal: rounded * increment).doubleValue
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

struct InspectorSegment<Value: Hashable>: Equatable {
    let value: Value
    let title: String?
    let systemImage: String?
    let accessibilityLabel: String
    let help: String?

    init(
        value: Value,
        title: String? = nil,
        systemImage: String? = nil,
        accessibilityLabel: String,
        help: String? = nil
    ) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.help = help
    }
}

struct InspectorSegmentedControl<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let segments: [InspectorSegment<Value>]
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, segments: segments) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.controlSize = controlSize.appKitControlSize
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        control.controlSize = controlSize.appKitControlSize
        context.coordinator.selection = $selection
        context.coordinator.segments = segments
        context.coordinator.isUpdating = true
        if control.segmentCount != segments.count { control.segmentCount = segments.count }
        for (index, segment) in segments.enumerated() {
            control.setLabel(segment.title ?? "", forSegment: index)
            control.setImage(segment.systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: segment.accessibilityLabel) }, forSegment: index)
            control.setToolTip(segment.help ?? segment.accessibilityLabel, forSegment: index)
            control.setSelected(segment.value == selection, forSegment: index)
        }
        control.isEnabled = isEnabled
        context.coordinator.isUpdating = false
    }

    static func dismantleNSView(_ control: NSSegmentedControl, coordinator: Coordinator) {
        control.target = nil
        control.action = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var segments: [InspectorSegment<Value>]
        var isUpdating = false

        init(selection: Binding<Value>, segments: [InspectorSegment<Value>]) {
            self.selection = selection
            self.segments = segments
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            guard !isUpdating, segments.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = segments[sender.selectedSegment].value
        }
    }
}

struct InspectorResponsiveIndicator: View {
    let isVisible: Bool
    let isOverridden: Bool
    let breakpointName: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Circle()
                .fill(isOverridden ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .contentShape(Circle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
        .help(helpText)
        .accessibilityLabel("Responsive setting")
        .accessibilityValue(accessibilityValue)
    }

    private var helpText: String {
        isOverridden
            ? "Using a custom value at \(breakpointName). Click to inherit."
            : "Inherited at \(breakpointName). Click to create an override."
    }

    private var accessibilityValue: String {
        isOverridden ? "Overridden at \(breakpointName)" : "Inherited at \(breakpointName)"
    }
}

struct InspectorColorWell: View {
    @Binding var color: Color
    let supportsAlpha: Bool

    init(color: Binding<Color>, supportsAlpha: Bool = false) {
        _color = color
        self.supportsAlpha = supportsAlpha
    }

    var body: some View {
        AppKitColorWell(color: $color, supportsAlpha: supportsAlpha)
            .accessibilityLabel("Choose colour")
    }
}

private struct AppKitColorWell: NSViewRepresentable {
    @Binding var color: Color
    let supportsAlpha: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell()
        colorWell.controlSize = controlSize.appKitControlSize
        colorWell.supportsAlpha = supportsAlpha
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        return colorWell
    }

    func updateNSView(_ colorWell: NSColorWell, context: Context) {
        colorWell.controlSize = controlSize.appKitControlSize
        context.coordinator.color = $color
        context.coordinator.isUpdating = true
        colorWell.color = NSColor(color)
        colorWell.supportsAlpha = supportsAlpha
        colorWell.isEnabled = isEnabled
        colorWell.setAccessibilityLabel("Choose colour")
        context.coordinator.isUpdating = false
    }

    static func dismantleNSView(_ colorWell: NSColorWell, coordinator: Coordinator) {
        colorWell.target = nil
        colorWell.action = nil
    }

    final class Coordinator: NSObject {
        var color: Binding<Color>
        var isUpdating = false

        init(color: Binding<Color>) {
            self.color = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            guard !isUpdating else { return }
            color.wrappedValue = Color(nsColor: sender.color)
        }
    }
}
