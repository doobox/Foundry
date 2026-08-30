import AppKit
import SwiftUI

enum InspectorMetrics {
    static let labelWidth: CGFloat = 90
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static let horizontalSectionPadding: CGFloat = 16
    static let verticalSectionPadding: CGFloat = 12
}

struct InspectorGrid<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
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
        .padding(.horizontal, InspectorMetrics.horizontalSectionPadding)
        .padding(.vertical, InspectorMetrics.verticalSectionPadding)
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
            ZStack(alignment: .leading) {
                if let indicator {
                    InspectorResponsiveIndicator(
                        isVisible: indicator.isVisible,
                        isOverridden: indicator.isOverridden,
                        breakpointName: indicator.breakpointName,
                        toggle: indicator.toggle
                    )
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

    var id: Value { value }
}

struct InspectorPopup<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [InspectorPopupOption<Value>]
    let accessibilityLabel: String
    let help: String?
    @Environment(\.isEnabled) private var isEnabled

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
        popup.controlSize = .small
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        rebuildMenu(of: popup)
        updateSelection(of: popup)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
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
        popup.addItems(withTitles: options.map(\.title))
    }

    private func updateSelection(of popup: NSPopUpButton) {
        if let selectedIndex = options.firstIndex(where: { $0.value == selection }) {
            popup.selectItem(at: selectedIndex)
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
            guard !isUpdating, options.indices.contains(sender.indexOfSelectedItem) else { return }
            selection.wrappedValue = options[sender.indexOfSelectedItem].value
        }
    }
}

struct InspectorTextField: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let help: String?
    @Environment(\.isEnabled) private var isEnabled

    init(text: Binding<String>, accessibilityLabel: String, help: String? = nil) {
        _text = text
        self.accessibilityLabel = accessibilityLabel
        self.help = help
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.controlSize = .small
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
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

struct InspectorStepper: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let increment: Double
    let accessibilityLabel: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSStepper {
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.valueChanged(_:))
        return stepper
    }

    func updateNSView(_ stepper: NSStepper, context: Context) {
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
    let restrictsToTickMarks: Bool
    let isContinuous: Bool
    let accessibilityLabel: String
    let help: String?
    @Environment(\.isEnabled) private var isEnabled

    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        tickMarkCount: Int = 0,
        restrictsToTickMarks: Bool = false,
        isContinuous: Bool = true,
        accessibilityLabel: String,
        help: String? = nil
    ) {
        _value = value
        self.range = range
        self.step = step
        self.tickMarkCount = tickMarkCount
        self.restrictsToTickMarks = restrictsToTickMarks
        self.isContinuous = isContinuous
        self.accessibilityLabel = accessibilityLabel
        self.help = help
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.controlSize = .small
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.isUpdating = true
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.altIncrementValue = step
        slider.numberOfTickMarks = tickMarkCount
        slider.allowsTickMarkValuesOnly = restrictsToTickMarks
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
        var isUpdating = false

        init(value: Binding<Double>) { self.value = value }

        @objc func valueChanged(_ sender: NSSlider) {
            guard !isUpdating else { return }
            value.wrappedValue = sender.doubleValue
        }
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

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, segments: segments) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.controlSize = .small
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

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell()
        colorWell.controlSize = .small
        colorWell.supportsAlpha = supportsAlpha
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        return colorWell
    }

    func updateNSView(_ colorWell: NSColorWell, context: Context) {
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
