import SwiftUI
import AppKit

enum ShadowControlPresentation {
    case compact
    case expanded
}

struct InspectorShadowControl: View {
    @Binding var layers: [FrameworkShadowLayer]

    @State private var selectedLayerID: UUID?

    var body: some View {
        InspectorRow(title: "Layers") {
            LayerPicker(
                layers: layers,
                selection: $selectedLayerID,
                colorForLayer: { layer in
                    ShadowColorCodec.decode(hex: layer.color, opacity: layer.opacity) ?? .magenta
                },
                onColorChange: updateLayerColor,
                onAdd: addLayer,
                onRemove: removeSelectedLayer
            )
            .controlSize(.small)
            .fixedSize()
            .onAppear(perform: selectLayerIfNeeded)
            .onChange(of: layers.map(\.id)) { _, _ in
                selectLayerIfNeeded()
            }
        }

        if let layerBinding {
            InspectorRow(title: "Offset") {
                HStack(spacing: 6) {
                    Text("X")
                    numberEditor(value: valueBinding(layerBinding, keyPath: \.x), range: -50...50, label: "X offset")
                    Divider().frame(height: 20)
                    Text("Y")
                    numberEditor(value: valueBinding(layerBinding, keyPath: \.y), range: -50...50, label: "Y offset")
                }
            }

            InspectorRow(title: "Shape") {
                HStack(spacing: 6) {
                    Text("B")
                    numberEditor(value: valueBinding(layerBinding, keyPath: \.blur), range: 0...100, label: "Blur")
                    Divider().frame(height: 20)
                    Text("S")
                    numberEditor(value: valueBinding(layerBinding, keyPath: \.spread), range: -50...50, label: "Spread")
                }
            }

            InspectorRow(title: "Inset") {
                Toggle("Inset", isOn: valueBinding(layerBinding, keyPath: \.isInset))
                    .labelsHidden()
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
        }
    }

    private var layerBinding: Binding<FrameworkShadowLayer>? {
        guard let id = selectedLayerID ?? layers.first?.id,
              let index = layers.firstIndex(where: { $0.id == id }) else { return nil }
        return $layers[index]
    }

    private func valueBinding<Value>(
        _ layer: Binding<FrameworkShadowLayer>,
        keyPath: WritableKeyPath<FrameworkShadowLayer, Value>
    ) -> Binding<Value> {
        Binding(
            get: { layer.wrappedValue[keyPath: keyPath] },
            set: { value in
                var updatedLayer = layer.wrappedValue
                updatedLayer[keyPath: keyPath] = value
                layer.wrappedValue = updatedLayer
            }
        )
    }

    private func numberEditor(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        label: String
    ) -> some View {
        let roundedValue = Binding(
            get: { value.wrappedValue.rounded() },
            set: { value.wrappedValue = min(max($0.rounded(), range.lowerBound), range.upperBound) }
        )
        return HStack(spacing: 2) {
            TextField(label, value: roundedValue, format: .number.precision(.fractionLength(0)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 38)
                .accessibilityLabel(label)
            Stepper(label, value: roundedValue, in: range, step: 1)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func addLayer() {
        guard layers.count < 3 else { return }
        let layer = FrameworkShadowLayer(x: 0, y: 4, blur: 8, opacity: 0.15)
        layers.append(layer)
        selectedLayerID = layer.id
    }

    private func removeSelectedLayer() {
        guard let id = selectedLayerID ?? layers.first?.id else { return }
        layers.removeAll { $0.id == id }
        selectedLayerID = layers.first?.id
    }

    private func updateLayerColor(layerID: UUID, color selectedColor: NSColor) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }),
              let stored = ShadowColorCodec.encode(selectedColor) else { return }
        var updatedLayers = layers
        updatedLayers[index].color = stored.hex
        updatedLayers[index].opacity = stored.opacity
        layers = updatedLayers
    }

    private func selectLayerIfNeeded() {
        guard layers.contains(where: { $0.id == selectedLayerID }) == false else { return }
        selectedLayerID = layers.first?.id
    }
}

struct ShadowControl: View {
    @Binding var layers: [FrameworkShadowLayer]
    let presentation: ShadowControlPresentation

    @State private var selectedLayerID: UUID?

    private var isCompact: Bool { presentation == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 14) {
            if let layerBinding {
                ShadowPositionPad(
                    layers: layers,
                    layer: layerBinding,
                    isCompact: isCompact
                ) {
                    canvasLayerBar
                }
            } else {
                Button("Add Shadow Layer", systemImage: "plus") {
                    addLayer()
                }
                .frame(maxWidth: .infinity, minHeight: isCompact ? 80 : 150)
            }

        }
        .onAppear(perform: selectLayerIfNeeded)
        .onChange(of: layers.map(\.id)) { _, _ in
            selectLayerIfNeeded()
        }
    }

    private var cssEditor: some View {
        ScrollView(.horizontal) {
            Group {
                if let layerBinding {
                    cssLayerEditor(layerBinding)
                } else {
                    Text("box-shadow: none;")
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Shadow layer controls")
    }

    private func cssLayerEditor(_ layer: Binding<FrameworkShadowLayer>) -> some View {
        HStack(spacing: 8) {
            Text("X Axis")
            cssNumberField(value: cssValueBinding(layer.x, range: -50...50), label: "X offset")
            Text("px")
            Divider().frame(height: 20)
            Text("Y Axis")
            cssNumberField(value: cssValueBinding(layer.y, range: -50...50), label: "Y offset")
            Text("px")
            Divider().frame(height: 20)
            Text("Blur")
            cssNumberField(value: cssValueBinding(layer.blur, range: 0...100), label: "Blur")
            Text("px")
            Divider().frame(height: 20)
            Toggle("Inset", isOn: layer.isInset)
                .toggleStyle(.button)
                .controlSize(.small)
        }
        .fixedSize()
        .padding(10)
        .containerRelativeFrame(.horizontal, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }

    private func cssNumberField(
        value: Binding<Double>,
        label: String
    ) -> some View {
        HStack(spacing: 2) {
            TextField(label, value: value, format: .number.precision(.fractionLength(0)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 42)
                .controlSize(.small)
                .accessibilityLabel(label)
            Stepper(label, value: value, step: 1)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
        }
    }

    private var canvasLayerBar: some View {
        LayerPicker(
            layers: layers,
            selection: $selectedLayerID,
            colorForLayer: { layer in
                ShadowColorCodec.decode(hex: layer.color, opacity: layer.opacity) ?? .magenta
            },
            onColorChange: updateLayerColor,
            onAdd: addLayer,
            onRemove: removeSelectedLayer
        )
        .controlSize(.small)
        .fixedSize()
    }

    private func updateLayerColor(layerID: UUID, color selectedColor: NSColor) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }),
              let stored = ShadowColorCodec.encode(selectedColor) else { return }
        var updatedLayers = layers
        updatedLayers[index].color = stored.hex
        updatedLayers[index].opacity = stored.opacity
        layers = updatedLayers
    }

    private var layerBinding: Binding<FrameworkShadowLayer>? {
        guard let id = selectedLayerID ?? layers.first?.id,
              let index = layers.firstIndex(where: { $0.id == id }) else { return nil }
        return $layers[index]
    }

    private var producedCSS: String {
        let value = layers.isEmpty ? "none" : layers.map(\.cssValue).joined(separator: ", ")
        return "box-shadow: \(value);"
    }

    private func cssValueBinding(
        _ value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue.rounded() },
            set: { value.wrappedValue = min(max($0.rounded(), range.lowerBound), range.upperBound) }
        )
    }

    private func cssColorBinding(_ layer: Binding<FrameworkShadowLayer>) -> Binding<Color> {
        Binding(
            get: {
                (Color(hex: layer.wrappedValue.color) ?? .black)
                    .opacity(layer.wrappedValue.opacity)
            },
            set: { color in
                var updatedLayer = layer.wrappedValue
                updatedLayer.color = color.hexString ?? "#000000"
                updatedLayer.opacity = Double(
                    NSColor(color).usingColorSpace(.sRGB)?.alphaComponent ?? 1
                )
                layer.wrappedValue = updatedLayer
            }
        )
    }

    private func addLayer() {
        guard layers.count < 3 else { return }
        let layer = FrameworkShadowLayer(x: 0, y: 4, blur: 8, opacity: 0.15)
        layers.append(layer)
        selectedLayerID = layer.id
    }

    private func removeSelectedLayer() {
        guard let id = selectedLayerID ?? layers.first?.id else { return }
        layers.removeAll { $0.id == id }
        selectedLayerID = layers.first?.id
    }

    private func selectLayerIfNeeded() {
        guard layers.contains(where: { $0.id == selectedLayerID }) == false else { return }
        selectedLayerID = layers.first?.id
    }
}

private struct LayerPicker<Layer: Identifiable>: NSViewRepresentable where Layer.ID == UUID {
    let layers: [Layer]
    @Binding var selection: UUID?
    let colorForLayer: (Layer) -> NSColor
    let onColorChange: (UUID, NSColor) -> Void
    var maximumLayers = 3
    let onAdd: () -> Void
    let onRemove: () -> Void

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> LayerPickerCoordinator {
        LayerPickerCoordinator()
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(frame: .zero)
        control.segmentStyle = .rounded
        control.trackingMode = .selectOne
        control.target = context.coordinator
        control.action = #selector(LayerPickerCoordinator.segmentClicked(_:))
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .vertical)
        control.setAccessibilityLabel("Shadow layers")
        context.coordinator.control = control
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        let coordinator = context.coordinator
        control.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        switch controlSize {
        case .mini: control.controlSize = .mini
        case .small: control.controlSize = .small
        case .regular: control.controlSize = .regular
        case .large: control.controlSize = .large
        default: control.controlSize = .large
        }
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: control.controlSize))
        control.isEnabled = isEnabled
        control.segmentCount = layers.count * 2 + 2

        let swatchSize: CGFloat = controlSize == .mini ? 10 : 12
        let cell = control.cell as? NSSegmentedCell
        for (index, layer) in layers.enumerated() {
            let numberSegment = index * 2
            let colorSegment = numberSegment + 1
            control.setImage(nil, forSegment: numberSegment)
            control.setLabel("\(index + 1)", forSegment: numberSegment)
            control.setLabel("", forSegment: colorSegment)
            control.setImage(
                LayerPickerCoordinator.swatch(
                    colorForLayer(layer),
                    size: swatchSize,
                    label: "Layer \(index + 1) color"
                ),
                forSegment: colorSegment
            )
            control.setImageScaling(.scaleNone, forSegment: colorSegment)
            control.setWidth(0, forSegment: numberSegment)
            control.setWidth(0, forSegment: colorSegment)
            control.setEnabled(isEnabled, forSegment: numberSegment)
            control.setEnabled(isEnabled, forSegment: colorSegment)
            cell?.setToolTip("Select layer \(index + 1)", forSegment: numberSegment)
            cell?.setToolTip("Select layer \(index + 1) and edit its color", forSegment: colorSegment)
        }

        let addSegment = layers.count * 2
        let removeSegment = addSegment + 1
        for (segment, symbol, title) in [
            (addSegment, "plus", "Add layer"),
            (removeSegment, "minus", "Remove selected layer")
        ] {
            control.setLabel("", forSegment: segment)
            control.setImage(
                NSImage(systemSymbolName: symbol, accessibilityDescription: title),
                forSegment: segment
            )
            control.setImageScaling(.scaleProportionallyDown, forSegment: segment)
            control.setWidth(0, forSegment: segment)
            cell?.setToolTip(title, forSegment: segment)
        }
        control.setEnabled(isEnabled && layers.count < maximumLayers, forSegment: addSegment)
        control.setEnabled(
            isEnabled && layers.contains { $0.id == selection },
            forSegment: removeSegment
        )

        coordinator.restoreSelection = { [weak control] in
            control?.selectedSegment = layers.firstIndex { $0.id == selection }.map { $0 * 2 } ?? -1
        }
        coordinator.restoreSelection()

        coordinator.onSegment = { [weak coordinator] segment in
            guard isEnabled, let coordinator else { return }
            let layerSegmentCount = layers.count * 2
            if segment < layerSegmentCount {
                let index = segment / 2
                guard layers.indices.contains(index) else { return }
                let layer = layers[index]
                selection = layer.id
                coordinator.restoreSelection()
                if segment.isMultiple(of: 2) {
                    if coordinator.activeID != layer.id {
                        coordinator.stopEditing()
                    }
                } else {
                    coordinator.openColorPanel(for: layer.id, color: colorForLayer(layer))
                }
            } else if segment == layerSegmentCount {
                guard layers.count < maximumLayers else { return }
                coordinator.stopEditing()
                onAdd()
            } else if segment == layerSegmentCount + 1 {
                guard layers.contains(where: { $0.id == selection }) else { return }
                coordinator.stopEditing()
                onRemove()
            }
            coordinator.restoreSelection()
        }

        coordinator.onColor = { id, newColor in
            guard isEnabled else { return }
            onColorChange(id, newColor)
        }

        if let id = coordinator.activeID {
            if isEnabled,
               let layer = layers.first(where: { $0.id == id }),
               selection == layer.id {
                // Keep the panel's full-precision color while the user edits.
                // Feeding the stored 8-bit hex back here can disturb a drag.
            } else {
                coordinator.stopEditing()
            }
        }
        control.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSSegmentedControl,
        context: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }

    static func dismantleNSView(
        _ control: NSSegmentedControl,
        coordinator: LayerPickerCoordinator
    ) {
        coordinator.stopEditing()
        control.target = nil
        coordinator.onSegment = { _ in }
        coordinator.onColor = { _, _ in }
        coordinator.restoreSelection = {}
    }
}

private final class LayerPickerCoordinator: NSObject {
    weak var control: NSSegmentedControl?
    private static weak var panelOwner: LayerPickerCoordinator?
    private(set) var activeID: UUID?
    private var isSettingInitialColor = false
    var onSegment: (Int) -> Void = { _ in }
    var onColor: (UUID, NSColor) -> Void = { _, _ in }
    var restoreSelection: () -> Void = {}

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: NSColorPanel.shared
        )
    }

    @objc func segmentClicked(_ sender: NSSegmentedControl) {
        let segment = sender.selectedSegment
        guard segment >= 0, sender.isEnabled(forSegment: segment) else { return }
        onSegment(segment)
    }

    func openColorPanel(for layerID: UUID, color: NSColor) {
        if Self.panelOwner !== self {
            Self.panelOwner?.stopEditing(closePanel: false)
        }
        let panel = NSColorPanel.shared
        Self.panelOwner = self
        activeID = layerID
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.isContinuous = true
        panel.showsAlpha = true

        isSettingInitialColor = true
        panel.color = color
        isSettingInitialColor = false
        panel.orderFront(nil)
    }

    @objc func colorChanged(_ sender: Any?) {
        guard Self.panelOwner === self,
              !isSettingInitialColor,
              let activeID else { return }
        onColor(activeID, NSColorPanel.shared.color)
    }

    func stopEditing(closePanel: Bool = true) {
        activeID = nil
        guard Self.panelOwner === self else { return }
        Self.panelOwner = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        if closePanel { panel.orderOut(nil) }
    }

    @objc private func panelWillClose(_ notification: Notification) {
        stopEditing(closePanel: false)
    }

    static func swatch(_ color: NSColor, size: CGFloat, label: String) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            NSColor.white.setFill()
            bounds.fill()
            NSColor(white: 0.78, alpha: 1).setFill()
            let tile: CGFloat = 3
            let count = Int(ceil(size / tile))
            for row in 0..<count {
                for column in 0..<count where (row + column).isMultiple(of: 2) {
                    NSRect(
                        x: CGFloat(column) * tile,
                        y: CGFloat(row) * tile,
                        width: tile,
                        height: tile
                    ).fill()
                }
            }
            color.setFill()
            bounds.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.separatorColor.setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = label
        return image
    }
}

private enum ShadowColorCodec {
    static func decode(hex: String, opacity: Double) -> NSColor? {
        guard hex.count == 7,
              hex.first == "#",
              hex.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let rgb = UInt32(hex.dropFirst(), radix: 16),
              opacity.isFinite else { return nil }

        return NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: CGFloat(min(1, max(0, opacity)))
        )
    }

    static func encode(_ selectedColor: NSColor) -> (hex: String, opacity: Double)? {
        guard let color = selectedColor.usingColorSpace(.sRGB) else { return nil }
        let parts = [
            color.redComponent,
            color.greenComponent,
            color.blueComponent,
            color.alphaComponent
        ]
        guard parts.allSatisfy(\.isFinite) else { return nil }

        func byte(_ part: CGFloat) -> Int {
            Int((min(1, max(0, part)) * 255).rounded())
        }

        return (
            String(
                format: "#%02X%02X%02X",
                byte(color.redComponent),
                byte(color.greenComponent),
                byte(color.blueComponent)
            ),
            Double(min(1, max(0, color.alphaComponent)))
        )
    }
}

private struct LayerColorControl: View {
    let number: Int
    let layerID: UUID

    @Binding var selectedLayerID: UUID?
    @Binding var color: Color

    @Environment(\.controlSize) private var controlSize

    private var isSelected: Bool {
        selectedLayerID == layerID
    }

    private var height: CGFloat {
        switch controlSize {
        case .mini: 20
        case .small: 24
        case .regular: 28
        case .large: 32
        default: 36
        }
    }

    private var segmentWidth: CGFloat {
        height + 4
    }

    private var fontSize: CGFloat {
        switch controlSize {
        case .mini: 10
        case .small: 11
        case .regular: 13
        case .large: 15
        default: 17
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                selectedLayerID = layerID
            } label: {
                Text(number.formatted())
                    .font(.system(size: fontSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: segmentWidth, height: height)
                    .background {
                        if isSelected {
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.7),
                                    Color.accentColor
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Layer \(number)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .help("Select layer \(number)")

            CircularColorWell(
                color: $color,
                label: "Layer \(number) color"
            )
            .frame(width: segmentWidth, height: height)
            .help("Change layer \(number) color")
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .fixedSize()
    }
}

private struct CircularColorWell: NSViewRepresentable {
    @Binding var color: Color
    let label: String

    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> SwatchWell {
        let well = SwatchWell(frame: .zero)
        well.supportsAlpha = true
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: SwatchWell, context: Context) {
        context.coordinator.color = $color

        let updatedColor = NSColor(color)
        if well.color != updatedColor {
            well.color = updatedColor
        }

        well.isEnabled = isEnabled
        well.setAccessibilityLabel(label)
        well.needsDisplay = true

        if !isEnabled {
            well.deactivate()
        }
    }

    static func dismantleNSView(_ well: SwatchWell, coordinator: Coordinator) {
        well.deactivate()
        well.target = nil
    }

    final class Coordinator: NSObject {
        var color: Binding<Color>

        init(color: Binding<Color>) {
            self.color = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            color.wrappedValue = Color(nsColor: sender.color)
            sender.needsDisplay = true
        }
    }

    final class SwatchWell: NSColorWell {
        override func draw(_ dirtyRect: NSRect) {
            let diameter = max(0, min(bounds.width, bounds.height) - 10)
            let rect = NSRect(
                x: bounds.midX - diameter / 2,
                y: bounds.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            let circle = NSBezierPath(ovalIn: rect)

            NSGraphicsContext.saveGraphicsState()
            circle.addClip()

            NSColor.white.setFill()
            rect.fill()
            NSColor.lightGray.setFill()

            let tile: CGFloat = 4
            let tileCount = Int(ceil(diameter / tile))
            for row in 0..<tileCount {
                for column in 0..<tileCount where (row + column).isMultiple(of: 2) {
                    NSRect(
                        x: rect.minX + CGFloat(column) * tile,
                        y: rect.minY + CGFloat(row) * tile,
                        width: tile,
                        height: tile
                    )
                    .fill()
                }
            }

            let displayedColor = isEnabled
                ? color
                : color.withAlphaComponent(color.alphaComponent * 0.4)
            displayedColor.setFill()
            circle.fill()

            NSGraphicsContext.restoreGraphicsState()

            NSColor.separatorColor.setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            activate(true)
        }

        override func accessibilityPerformPress() -> Bool {
            guard isEnabled else { return false }
            activate(true)
            return true
        }
    }
}

private struct ShadowPositionPad<LayerControls: View>: View {
    let layers: [FrameworkShadowLayer]
    @Binding var layer: FrameworkShadowLayer
    let isCompact: Bool
    let layerControls: LayerControls

    @State private var previewAppearance = ShadowPreviewAppearance.light

    private let range = -50.0...50.0
    private let logicalTileSide = 200.0
    private let logicalHorizontalMargin = 266.0
    private let logicalTopMargin = 89.0
    private let logicalBottomMargin = 180.0
    private var logicalCanvasWidth: Double { logicalTileSide + logicalHorizontalMargin * 2 }
    private var logicalCanvasHeight: Double { logicalTileSide + logicalTopMargin + logicalBottomMargin }

    init(
        layers: [FrameworkShadowLayer],
        layer: Binding<FrameworkShadowLayer>,
        isCompact: Bool,
        @ViewBuilder layerControls: () -> LayerControls
    ) {
        self.layers = layers
        _layer = layer
        self.isCompact = isCompact
        self.layerControls = layerControls()
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let layoutScale = min(
                size.width / logicalCanvasWidth,
                size.height / logicalCanvasHeight
            )
            let rect = previewRect(in: size, scale: layoutScale)
            let center = CGPoint(x: rect.midX, y: rect.midY)

            ZStack(alignment: .topLeading) {
                ShadowCanvas(
                    layers: layers,
                    rect: rect,
                    cornerRadius: (isCompact ? 12 : 18) * layoutScale,
                    previewScale: 2 * layoutScale,
                    tileBaseStyle: previewAppearance.tileBaseStyle,
                    tileOverlayStyle: previewAppearance.tileOverlayStyle
                )
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: rect.minY))
                    path.addLine(to: CGPoint(x: center.x, y: rect.maxY))
                    path.move(to: CGPoint(x: rect.minX, y: center.y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: center.y))
                }
                .stroke(previewAppearance.crosshairColor, style: .init(lineWidth: 1, dash: [5]))
                Circle()
                    .fill(Color.accentColor)
                    .overlay { Circle().stroke(previewAppearance.dotBorderColor, lineWidth: 2) }
                    .frame(width: isCompact ? 16 : 20, height: isCompact ? 16 : 20)
                    .position(position(in: rect))
                    .shadow(radius: 1)

                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .contentShape(Rectangle())
                    .gesture(positionGesture(in: rect))

                Picker("Preview appearance", selection: $previewAppearance) {
                    Label("Light", systemImage: "sun.max.fill")
                        .labelStyle(.iconOnly)
                        .tag(ShadowPreviewAppearance.light)
                    Label("Dark", systemImage: "moon.fill")
                        .labelStyle(.iconOnly)
                        .tag(ShadowPreviewAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .padding(10)

                layerControls
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                HStack(spacing: 24) {
                    Toggle("Inset", isOn: $layer.isInset)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .fixedSize()
                    shadowSlider(
                        "Blur",
                        value: $layer.blur,
                        range: 0...100
                    )
                    shadowSlider(
                        "Spread",
                        value: $layer.spread,
                        range: -50...50
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .aspectRatio(logicalCanvasWidth / logicalCanvasHeight, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(previewAppearance.canvasOverlayStyle, in: .rect(cornerRadius: isCompact ? 8 : 12))
        .background(previewAppearance.canvasBaseStyle, in: .rect(cornerRadius: isCompact ? 8 : 12))
        .environment(\.colorScheme, previewAppearance.colorScheme)
        .accessibilityElement()
        .accessibilityLabel("Shadow position")
        .accessibilityValue("X \(layer.x.formatted()), Y \(layer.y.formatted())")
    }

    private func previewRect(in size: CGSize, scale: Double) -> CGRect {
        let side = logicalTileSide * scale
        return CGRect(
            x: (size.width - side) / 2,
            y: (size.height - logicalCanvasHeight * scale) / 2 + logicalTopMargin * scale,
            width: side,
            height: side
        )
    }

    private func position(in rect: CGRect) -> CGPoint {
        return CGPoint(
            x: rect.minX + mapped(layer.x, length: rect.width, reversed: true),
            y: rect.minY + mapped(layer.y, length: rect.height, reversed: true)
        )
    }

    private func positionGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                var updatedLayer = layer
                updatedLayer.x = mapped(value.location.x - rect.minX, length: rect.width)
                updatedLayer.y = mapped(value.location.y - rect.minY, length: rect.height)
                layer = updatedLayer
            }
    }

    private func shadowSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        let wholePixelValue = Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = min(
                    max(newValue.rounded(), range.lowerBound),
                    range.upperBound
                )
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue.rounded().formatted()) px")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Slider(value: wholePixelValue, in: range)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }

    private func mapped(_ value: Double, length: Double, reversed: Bool = false) -> Double {
        if reversed {
            return ((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
                / (range.upperBound - range.lowerBound)) * length
        }
        return range.lowerBound + (min(max(value, 0), length) / max(length, 1))
            * (range.upperBound - range.lowerBound)
    }

}

private enum ShadowPreviewAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: Self { self }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    var canvasBaseStyle: AnyShapeStyle {
        switch self {
        case .light: AnyShapeStyle(Color.white)
        case .dark: AnyShapeStyle(Color.black)
        }
    }

    var canvasOverlayStyle: AnyShapeStyle {
        AnyShapeStyle(.quinary)
    }

    var tileBaseStyle: AnyShapeStyle {
        switch self {
        case .light: AnyShapeStyle(Color.white)
        case .dark: AnyShapeStyle(Color.black)
        }
    }

    var tileOverlayStyle: AnyShapeStyle {
        AnyShapeStyle(.quaternary)
    }

    var crosshairColor: AnyShapeStyle {
        AnyShapeStyle(.tertiary)
    }

    var dotBorderColor: AnyShapeStyle {
        switch self {
        case .light: AnyShapeStyle(.primary)
        case .dark: AnyShapeStyle(Color.white.opacity(0.9))
        }
    }
}

private struct ShadowCanvas: View {
    let layers: [FrameworkShadowLayer]
    let rect: CGRect
    let cornerRadius: Double
    let previewScale: Double
    let tileBaseStyle: AnyShapeStyle
    let tileOverlayStyle: AnyShapeStyle

    var body: some View {
        Canvas { context, _ in
            let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
            let scale = previewScale

            for layer in layers where !layer.isInset {
                let spread = layer.spread * scale
                let shadowRect = rect.insetBy(dx: -spread, dy: -spread)
                let shadowPath = Path(
                    roundedRect: shadowRect,
                    cornerRadius: max(0, cornerRadius + spread)
                )
                var shadowContext = context
                shadowContext.addFilter(.shadow(
                    color: shadowColor(for: layer),
                    radius: max(0, layer.blur) * scale / 2,
                    x: layer.x * scale,
                    y: layer.y * scale,
                    options: [.shadowOnly]
                ))
                shadowContext.fill(shadowPath, with: .color(.white))
            }

            context.fill(path, with: .style(tileBaseStyle))
            context.fill(path, with: .style(tileOverlayStyle))

            for layer in layers where layer.isInset {
                let spread = layer.spread * previewScale
                let sourceRect = rect.insetBy(dx: spread, dy: spread)
                let sourcePath = Path(
                    roundedRect: sourceRect,
                    cornerRadius: max(0, cornerRadius - spread)
                )
                var insetContext = context
                insetContext.clip(to: path)
                insetContext.addFilter(.shadow(
                    color: shadowColor(for: layer),
                    radius: max(0, layer.blur) * previewScale / 2,
                    x: layer.x * previewScale,
                    y: layer.y * previewScale,
                    options: [.invertsAlpha, .shadowOnly]
                ))
                insetContext.fill(sourcePath, with: .color(.white))
            }
        }
    }

    private func shadowColor(for layer: FrameworkShadowLayer) -> Color {
        (Color(hex: layer.color) ?? .black).opacity(layer.opacity)
    }

}
