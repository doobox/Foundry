import SwiftUI
import AppKit

struct ThemeShadowSettings: View {
    let shadows: ShadowTokens
    let editor: ProjectEditor

    @State private var selectedShadowID: String?
    @State private var selectedLayerID: UUID?
    @State private var shadowPendingDeletion: ThemeShadow?

    var body: some View {
        ThemeEditorColumns {
            VStack(alignment: .leading, spacing: 20) {
                styleCard
                if let shadow = selectedShadow {
                    layerCard(shadow)
                }
            }
        } preview: {
            if let shadow = selectedShadow {
                ThemeEditorCard(
                    title: "Preview",
                    subtitle: "All layers are shown together. Drag the point to position the selected layer."
                ) {
                    ThemeShadowPreview(
                        layers: shadow.layers,
                        selectedLayer: selectedLayerBinding
                    )
                }
            }
        }
        .controlSize(.regular)
        .onAppear(perform: reconcileSelection)
        .onChange(of: shadows.shadows.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: selectedShadowID) { _, _ in reconcileLayerSelection() }
        .onChange(of: selectedShadow?.layers.map(\.id)) { _, _ in reconcileLayerSelection() }
        .confirmationDialog(
            "Choose a replacement for \(shadowPendingDeletion?.title ?? "this custom shadow")",
            isPresented: Binding(
                get: { shadowPendingDeletion != nil },
                set: { if !$0 { shadowPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(shadows.shadows.filter { $0.id != shadowPendingDeletion?.id }) { replacement in
                Button("Replace with \(replacement.title)") {
                    guard let pending = shadowPendingDeletion else { return }
                    editor.removeThemeShadow(id: pending.id, replacingWith: replacement.id)
                    selectedShadowID = replacement.id
                    shadowPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { shadowPendingDeletion = nil }
        } message: {
            Text("Every block using this shadow will use the replacement before the custom shadow is deleted.")
        }
    }

    private var styleCard: some View {
        ThemeEditorCard(title: "Shadow style", subtitle: "Choose a scale value or create a custom style.") {
            VStack(alignment: .leading, spacing: 16) {
                ThemeEditorPropertyRow(title: "Style") {
                    Picker("Shadow style", selection: shadowSelection) {
                        Section("Theme Scale") {
                            ForEach(shadows.predefined) { shadow in
                                Text(themeScaleTitle(id: shadow.id, fallback: shadow.title)).tag(shadow.id)
                            }
                        }
                        if !shadows.custom.isEmpty {
                            Section("Custom Styles") {
                                ForEach(shadows.custom) { shadow in
                                    Text(shadow.title).tag(shadow.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                }

                if let shadow = selectedShadow, isCustom(shadow) {
                    ThemeEditorPropertyRow(title: "Name") {
                        TextField("Shadow name", text: Binding(
                            get: { shadow.title },
                            set: { editor.setThemeShadowTitle(id: shadow.id, value: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel("Custom shadow name")
                    }
                }

                HStack {
                    Button("Add Style", systemImage: "plus") {
                        selectedShadowID = editor.addThemeShadow()
                    }
                    Spacer()
                    if let shadow = selectedShadow, isCustom(shadow) {
                        Button("Delete Style…", systemImage: "trash", role: .destructive) {
                            shadowPendingDeletion = shadow
                        }
                    }
                }
            }
        }
    }

    private func layerCard(_ shadow: ThemeShadow) -> some View {
        ThemeEditorCard(title: "Layers", subtitle: "Combine up to three layers to create depth.") {
            VStack(alignment: .leading, spacing: 16) {
                if !shadow.layers.isEmpty {
                    Picker("Selected layer", selection: layerSelection) {
                        ForEach(Array(shadow.layers.enumerated()), id: \.element.id) { index, layer in
                            Text("Layer \(index + 1)").tag(Optional(layer.id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if let layer = selectedLayerBinding {
                    layerFields(layer)
                } else {
                    Text("This style has no shadow. Add a layer to give it depth.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                }

                Divider()
                HStack {
                    Button("Add Layer", systemImage: "plus") {
                        guard shadow.layers.count < 3 else { return }
                        selectedLayerID = editor.addThemeShadowLayer(shadowID: shadow.id)
                    }
                    .disabled(shadow.layers.count >= 3)

                    Spacer()

                    Button("Remove Layer", systemImage: "minus") {
                        guard let layer = selectedLayer else { return }
                        editor.removeThemeShadowLayer(shadowID: shadow.id, layerID: layer.id)
                    }
                    .disabled(shadow.layers.isEmpty)
                }
            }
        }
    }

    private func layerFields(_ layer: Binding<ThemeShadowLayer>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ThemeEditorPropertyRow(title: "Colour") {
                ColorPicker("Shadow colour", selection: colourBinding(layer), supportsOpacity: true)
                    .labelsHidden()
            }

            ThemeShadowNumberRow(
                title: "Opacity", value: opacityBinding(layer), range: 0...100, unit: "%"
            )

            Divider()

            ThemeShadowNumberRow(title: "Horizontal", value: layer.x, range: -50...50, unit: "px")
            ThemeShadowNumberRow(title: "Vertical", value: layer.y, range: -50...50, unit: "px")
            ThemeShadowNumberRow(title: "Blur", value: layer.blur, range: 0...100, unit: "px")
            ThemeShadowNumberRow(title: "Spread", value: layer.spread, range: -50...50, unit: "px")

            Divider()

            Toggle("Inset shadow", isOn: layer.isInset)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedShadow: ThemeShadow? {
        shadows.shadows.first { $0.id == selectedShadowID }
            ?? shadows.predefined.first { $0.id == "sm" }
            ?? shadows.shadows.first
    }

    private var selectedLayer: ThemeShadowLayer? {
        selectedShadow?.layers.first { $0.id == selectedLayerID }
            ?? selectedShadow?.layers.first
    }

    private var selectedLayerBinding: Binding<ThemeShadowLayer>? {
        guard let shadow = selectedShadow, let layer = selectedLayer else { return nil }
        return Binding(
            get: {
                editor.document.site.theme.shadows.shadows
                    .first { $0.id == shadow.id }?.layers.first { $0.id == layer.id } ?? layer
            },
            set: { editor.setThemeShadowLayer(shadowID: shadow.id, layer: $0) }
        )
    }

    private var shadowSelection: Binding<String> {
        Binding(
            get: { selectedShadow?.id ?? "" },
            set: { selectedShadowID = $0 }
        )
    }

    private var layerSelection: Binding<UUID?> {
        Binding(
            get: { selectedLayer?.id },
            set: { selectedLayerID = $0 }
        )
    }

    private func isCustom(_ shadow: ThemeShadow) -> Bool {
        shadows.custom.contains { $0.id == shadow.id }
    }

    private func reconcileSelection() {
        if !shadows.shadows.contains(where: { $0.id == selectedShadowID }) {
            selectedShadowID = shadows.predefined.first { $0.id == "sm" }?.id
                ?? shadows.shadows.first?.id
        }
        reconcileLayerSelection()
    }

    private func reconcileLayerSelection() {
        if selectedShadow?.layers.contains(where: { $0.id == selectedLayerID }) != true {
            selectedLayerID = selectedShadow?.layers.first?.id
        }
    }

    private func opacityBinding(_ layer: Binding<ThemeShadowLayer>) -> Binding<Double> {
        Binding(
            get: { layer.wrappedValue.opacity * 100 },
            set: { layer.wrappedValue.opacity = min(100, max(0, $0)) / 100 }
        )
    }

    private func colourBinding(_ layer: Binding<ThemeShadowLayer>) -> Binding<Color> {
        Binding(
            get: { (Color(hex: layer.wrappedValue.color) ?? .black).opacity(layer.wrappedValue.opacity) },
            set: { newColour in
                guard let colour = NSColor(newColour).usingColorSpace(.sRGB) else { return }
                let values = [colour.redComponent, colour.greenComponent, colour.blueComponent, colour.alphaComponent]
                guard values.allSatisfy(\.isFinite) else { return }
                func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
                var updated = layer.wrappedValue
                updated.color = String(
                    format: "#%02X%02X%02X",
                    byte(colour.redComponent), byte(colour.greenComponent), byte(colour.blueComponent)
                )
                updated.opacity = Double(min(1, max(0, colour.alphaComponent)))
                layer.wrappedValue = updated
            }
        )
    }
}

private struct ThemeShadowNumberRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 76, alignment: .leading)
            Slider(value: boundedValue, in: range, step: 1)
                .labelsHidden()
                .accessibilityLabel(title)
            ThemeNumberField(title: title, value: boundedValue, unit: unit, precision: 0)
        }
    }

    private var boundedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { value = min(range.upperBound, max(range.lowerBound, $0.rounded())) }
        )
    }
}

private struct ThemeShadowPreview: View {
    let layers: [ThemeShadowLayer]
    let selectedLayer: Binding<ThemeShadowLayer>?

    @State private var appearance = ColorScheme.light

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Preview appearance", selection: $appearance) {
                Label("Light", systemImage: "sun.max").tag(ColorScheme.light)
                Label("Dark", systemImage: "moon").tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            GeometryReader { geometry in
                let side = min(120.0, geometry.size.width * 0.36)
                let rect = CGRect(
                    x: (geometry.size.width - side) / 2,
                    y: (geometry.size.height - side) / 2,
                    width: side,
                    height: side
                )

                ZStack {
                    ThemeShadowPreviewCanvas(layers: layers, rect: rect, appearance: appearance)

                    if let selectedLayer {
                        Path { path in
                            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                        }
                        .stroke(appearance == .light ? Color.black.opacity(0.15) : Color.white.opacity(0.2),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                        Circle()
                            .fill(Color.accentColor)
                            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                            .frame(width: 15, height: 15)
                            .position(
                                x: rect.midX + min(50, max(-50, selectedLayer.wrappedValue.x)) / 100 * rect.width,
                                y: rect.midY + min(50, max(-50, selectedLayer.wrappedValue.y)) / 100 * rect.height
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

                        Rectangle()
                            .fill(.clear)
                            .frame(width: rect.width, height: rect.height)
                            .contentShape(.rect)
                            .position(x: rect.midX, y: rect.midY)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("themeShadowPreview"))
                                .onChanged { value in
                                    var layer = selectedLayer.wrappedValue
                                    layer.x = min(50, max(-50, (value.location.x - rect.midX) / rect.width * 100)).rounded()
                                    layer.y = min(50, max(-50, (value.location.y - rect.midY) / rect.height * 100)).rounded()
                                    selectedLayer.wrappedValue = layer
                                }
                            )
                            .help("Drag to set the selected layer’s horizontal and vertical offset.")
                    }
                }
                .coordinateSpace(name: "themeShadowPreview")
            }
            .frame(height: 280)
            .background(appearance == .light ? Color(white: 0.96) : Color(white: 0.10))
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Combined shadow preview")
            .accessibilityValue(layers.isEmpty ? "No shadow" : "\(layers.count) shadow layers")

            Text("Preview appearance changes this sample only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ThemeShadowPreviewCanvas: View {
    let layers: [ThemeShadowLayer]
    let rect: CGRect
    let appearance: ColorScheme

    private let cornerRadius = 18.0

    var body: some View {
        Canvas { context, _ in
            let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

            for layer in layers where !layer.isInset {
                let shadowRect = rect.insetBy(dx: -layer.spread, dy: -layer.spread)
                guard shadowRect.width > 0, shadowRect.height > 0 else { continue }
                let shadowPath = Path(
                    roundedRect: shadowRect,
                    cornerRadius: max(0, cornerRadius + layer.spread)
                )
                var shadowContext = context
                shadowContext.addFilter(.shadow(
                    color: shadowColour(layer), radius: max(0, layer.blur) / 2,
                    x: layer.x, y: layer.y, options: [.shadowOnly]
                ))
                shadowContext.fill(shadowPath, with: .color(.white))
            }

            context.fill(path, with: .color(appearance == .light ? .white : Color(white: 0.22)))

            for layer in layers where layer.isInset {
                let sourceRect = rect.insetBy(dx: layer.spread, dy: layer.spread)
                guard sourceRect.width > 0, sourceRect.height > 0 else {
                    context.fill(path, with: .color(shadowColour(layer)))
                    continue
                }
                let sourcePath = Path(
                    roundedRect: sourceRect,
                    cornerRadius: max(0, cornerRadius - layer.spread)
                )
                var insetContext = context
                insetContext.clip(to: path)
                insetContext.addFilter(.shadow(
                    color: shadowColour(layer), radius: max(0, layer.blur) / 2,
                    x: layer.x, y: layer.y, options: [.invertsAlpha, .shadowOnly]
                ))
                insetContext.fill(sourcePath, with: .color(.white))
            }
        }
    }

    private func shadowColour(_ layer: ThemeShadowLayer) -> Color {
        (Color(hex: layer.color) ?? .black).opacity(layer.opacity)
    }
}
