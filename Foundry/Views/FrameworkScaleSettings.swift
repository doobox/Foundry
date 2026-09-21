import SwiftUI

/// List selection wants a type of its own: with plain `String` tags matching
/// the rows' ForEach identity, macOS list rows refuse to select — the Fonts
/// section works because its selection reference is a distinct type.
private enum FrameworkFontSizeSelection: Hashable {
    case size(String)
}

struct FrameworkFontSizeSettings: View {
    let framework: Framework
    let session: FrameworkEditorSession
    @State private var selectedID = "base"
    @State private var pendingDeletion: FrameworkFontSize?
    @State private var isConfirmingReset = false

    private var editor: ProjectEditor { session.editor }

    /// Custom sizes stay editable on built-in frameworks, mirroring custom
    /// fonts; only the predefined scale is locked.
    private var canEditSelection: Bool {
        isCustom(selectedID) || session.canEditFramework
    }

    private func isCustom(_ id: String) -> Bool {
        framework.typography.customFontSizes.contains { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                if let selected {
                    nameRow(selected)
                    // Stacked cards stay usable at the smallest window size;
                    // side-by-side columns would crush the sliders.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            sizeCard(selected)
                                .disabled(!canEditSelection)
                            previewCard(selected)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("framework-section-Font Size")
        .onChange(of: framework.typography.fontSizes.map(\.id)) { _, ids in
            if !ids.contains(selectedID) { selectedID = ids.contains("base") ? "base" : ids.first ?? "" }
        }
        .confirmationDialog("Replace \(pendingDeletion?.title ?? "Custom Size")", isPresented: deletionPresented, titleVisibility: .visible) {
            ForEach(framework.typography.fontSizes.filter { $0.id != pendingDeletion?.id }) { replacement in
                Button("Replace with \(displayTitle(replacement))") {
                    guard let pendingDeletion else { return }
                    editor.removeFrameworkFontSize(id: pendingDeletion.id, replacingWith: replacement.id)
                    self.pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Choose the size that parts should use before deleting this custom size.")
        }
        .confirmationDialog("Reset Font Size?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset Scale") { editor.resetFrameworkFontSizeScale() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore the preset values in this section. Custom sizes are kept. You can undo this change.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Sizes").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    selectedID = editor.addFrameworkFontSize()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add Custom Size")
                .accessibilityLabel("Add Custom Size")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            List(selection: sidebarSelectionBinding) {
                ForEach(framework.typography.customFontSizes) { token in
                    Text(token.title.isEmpty ? "Untitled Size" : token.title)
                        .tag(FrameworkFontSizeSelection.size(token.id))
                        .contextMenu {
                            Button("Delete Size…", systemImage: "trash", role: .destructive) {
                                pendingDeletion = token
                            }
                        }
                }
                Section("Framework Sizes") {
                    ForEach(framework.typography.predefinedFontSizes) { token in
                        Text(displayTitle(token)).tag(FrameworkFontSizeSelection.size(token.id))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            if let custom = framework.typography.customFontSizes.first(where: { $0.id == selectedID }) {
                HStack {
                    Button {
                        pendingDeletion = custom
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete Custom Size")
                    .accessibilityLabel("Delete Custom Size")
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private func nameRow(_ token: FrameworkFontSize) -> some View {
        HStack(spacing: 8) {
            Text("Name")
            if isCustom(token.id) {
                TextField("Custom size name", text: Binding(
                    get: { token.title },
                    set: { editor.setFrameworkFontSizeTitle(id: token.id, value: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            } else {
                Text(displayTitle(token))
                if !session.canEditFramework {
                    Image(systemName: "lock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Built-in framework")
                        .help("Create a new framework to edit its sizes.")
                }
            }
            Spacer()
            Button("Reset Scale…", systemImage: "arrow.counterclockwise") {
                isConfirmingReset = true
            }
            .help("Restore the preset values in this section")
            .disabled(!session.canEditFramework)
        }
        .frame(minHeight: 28)
    }

    private func sizeCard(_ token: FrameworkFontSize) -> some View {
        FrameworkEditorCard {
            HStack(spacing: 14) {
                Text("Size").fontWeight(.medium).frame(width: 76, alignment: .leading)
                Slider(value: sizeSliderBinding(token.id), in: 8...160)
                    .accessibilityLabel("Font size")
                FrameworkNumberField(title: "\(displayTitle(token)) size", value: pixels(token.id), precision: 1)
            }
            HStack(spacing: 14) {
                Text("Line height").fontWeight(.medium).frame(width: 76, alignment: .leading)
                Slider(value: rounded(sliderBinding(lineHeight(token.id), range: 0.8...2.5), decimals: 2), in: 0.8...2.5)
                    .accessibilityLabel("Line height")
                FrameworkNumberField(title: "\(displayTitle(token)) line height", value: lineHeight(token.id), unit: "×", step: 0.05, precision: 3)
            }
        }
    }

    /// The size slider carries the line height with it, computing the ideal
    /// leading for each size; the line height slider then overrides manually.
    private func sizeSliderBinding(_ id: String) -> Binding<Double> {
        Binding(
            get: { min(max((framework.typography.fontSizes.first { $0.id == id }?.size ?? 1) * 16, 8), 160) },
            set: { value in
                let px = value.rounded()
                editor.setFrameworkFontSize(id: id, value: px / 16)
                editor.setFrameworkFontSizeLineHeight(id: id, value: Self.idealLineHeight(forRem: px / 16))
            }
        )
    }

    /// Leading eases along a curve through 1.5 at 0.5 rem (8 px), 0.95 at
    /// 5 rem (80 px) and 0.9 at the top; past the curve's vertex it holds
    /// flat so the display range stays pinned at 0.9 rather than curling up.
    private static func idealLineHeight(forRem rem: Double) -> Double {
        let x = min(rem, 7.6)
        let curve = 1.5 * (x - 5.0) * (x - 9.375) / 39.9375
            - 0.95 * (x - 0.5) * (x - 9.375) / 19.6875
            + 0.9 * (x - 0.5) * (x - 5.0) / 38.828125
        return (min(max(curve, 0.9), 1.5) * 100).rounded() / 100
    }

    /// Continuous sliders show no tick marks; rounding in the binding keeps
    /// the stored values as clean as stepped ones.
    private func rounded(_ value: Binding<Double>, decimals: Int) -> Binding<Double> {
        let factor = pow(10, Double(decimals))
        return Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = ($0 * factor).rounded() / factor }
        )
    }

    private func previewCard(_ token: FrameworkFontSize) -> some View {
        FrameworkEditorCard(title: "Preview") {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(["The art of", "a good first", "impression."], id: \.self) { line in
                        Text(line)
                            .font(.system(size: token.size * 16))
                            .fixedSize()
                            .frame(height: token.size * 16 * token.lineHeight)
                    }
                }
                .fixedSize()
                .padding(16)
            }
            .frame(height: 210)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
        }
    }

    private var sidebarSelectionBinding: Binding<FrameworkFontSizeSelection?> {
        Binding(
            get: { .size(selectedID) },
            set: { if case .size(let id) = $0 { selectedID = id } }
        )
    }

    private var selected: FrameworkFontSize? { framework.typography.fontSizes.first { $0.id == selectedID } ?? framework.typography.fontSizes.first }
    private func displayTitle(_ token: FrameworkFontSize) -> String {
        framework.typography.predefinedFontSizes.contains(where: { $0.id == token.id })
            ? frameworkScaleTitle(id: token.id, fallback: token.title) : token.title
    }
    private func pixels(_ id: String) -> Binding<Double> {
        Binding(get: { (framework.typography.fontSizes.first { $0.id == id }?.size ?? 1) * 16 },
                set: { editor.setFrameworkFontSize(id: id, value: $0 / 16) })
    }
    private func lineHeight(_ id: String) -> Binding<Double> {
        Binding(get: { framework.typography.fontSizes.first { $0.id == id }?.lineHeight ?? 1.5 },
                set: { editor.setFrameworkFontSizeLineHeight(id: id, value: $0) })
    }
    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}

struct FrameworkSpacingSettings: View {
    let framework: Framework
    let session: FrameworkEditorSession
    @State private var isConfirmingReset = false

    private var editor: ProjectEditor { session.editor }

    /// Reset restores the source framework's saved scale, so it only makes
    /// sense while the current values differ from it.
    private var canResetScale: Bool {
        guard session.canEditFramework,
              let source = FrameworkLibrary.shared.frameworks
                .first(where: { $0.id == session.document.site.frameworkSourceID })
        else { return false }
        return !framework.spacing.matchesPredefinedScale(of: source.framework.spacing)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                customCard
                frameworkCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("framework-section-Spacing")
        .confirmationDialog("Reset Spacing?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset Scale") { editor.resetFrameworkSpacingScale() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore the preset values in this section. Custom spacing is kept. You can undo this change.")
        }
    }

    private var customCard: some View {
        FrameworkEditorCard {
            HStack(spacing: 8) {
                Text("Custom Spacing").font(.headline).accessibilityAddTraits(.isHeader)
                Button {
                    editor.addFrameworkSpacing()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add Custom Spacing")
                .accessibilityLabel("Add Custom Spacing")
            }
            if framework.spacing.custom.isEmpty {
                Text("Extend the scale for your project.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(framework.spacing.custom) { token in
                        spacingRow(
                            title: token.name.isEmpty ? "Untitled Spacing" : token.name,
                            value: customValue(token.id)
                        ) {
                            TextField("Spacing name", text: Binding(
                                get: { token.name },
                                set: { editor.setFrameworkSpacingName(id: token.id, value: $0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        } trailing: {
                            // No confirmation: parts keep the value's exact
                            // size as a custom length, and delete is undoable.
                            Button {
                                editor.removeFrameworkSpacing(id: token.id)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Delete Custom Spacing")
                            .accessibilityLabel("Delete \(token.name.isEmpty ? "Untitled Spacing" : token.name)")
                        }
                        if token.id != framework.spacing.custom.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var frameworkCard: some View {
        FrameworkEditorCard {
            HStack(spacing: 8) {
                Text("Framework Spacing").font(.headline).accessibilityAddTraits(.isHeader)
                if !session.canEditFramework {
                    Image(systemName: "lock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Built-in framework")
                        .help("Create a new framework to edit its spacing.")
                }
                Spacer()
                Button("Reset Scale…", systemImage: "arrow.counterclockwise") {
                    isConfirmingReset = true
                }
                .help("Restore the preset values in this scale")
                .disabled(!canResetScale)
            }
            VStack(spacing: 0) {
                ForEach(DesignToken.spacingTokens) { token in
                    spacingRow(title: token.displayName, value: tokenValue(token)) {
                        Text(token.displayName).fontWeight(.medium)
                            .frame(width: 120, alignment: .leading)
                    } trailing: { EmptyView() }
                    if token != DesignToken.spacingTokens.last { Divider() }
                }
            }
            .disabled(!session.canEditFramework)
        }
    }

    /// One row per spacing: name, slider, rem field and the px equivalent.
    private func spacingRow(
        title: String,
        value: Binding<Double>,
        @ViewBuilder label: () -> some View,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        let rem = remBinding(value)
        return HStack(spacing: 14) {
            label()
            Slider(value: rounded(sliderBinding(rem, range: 0...10), nearest: 0.125), in: 0...10)
                .accessibilityLabel("\(title) spacing")
            FrameworkNumberField(title: "\(title) value", value: rem, unit: "rem", step: 0.125, precision: 3)
            Text("\((value.wrappedValue * 4).formatted()) px")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            trailing()
        }
        .padding(.vertical, 8)
    }

    /// The scale stores quarter-rem multiples; the editor speaks rem, the
    /// unit the published CSS actually uses.
    private func remBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue * 0.25 },
            set: { value.wrappedValue = $0 * 4 }
        )
    }

    private func tokenValue(_ token: DesignToken) -> Binding<Double> {
        Binding(
            get: { framework.number(for: token) ?? 0 },
            set: { editor.setFrameworkSpacing(token, value: $0) }
        )
    }

    private func customValue(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { framework.spacing.custom.first { $0.id == id }?.value ?? 0 },
            set: { editor.setFrameworkSpacingValue(id: id, value: $0) }
        )
    }

}

/// Which flavour of `FrameworkDimensionTokens` scale is being edited. Each
/// kind describes its own titles, unit and slider range.
enum FrameworkDimensionScaleKind {
    case borderWidth
    case borderRadius
    case zIndex

    var isRadius: Bool { self == .borderRadius }

    var title: String {
        switch self {
        case .borderWidth: "Framework Border Widths"
        case .borderRadius: "Framework Corner Radii"
        case .zIndex: "Framework Stacking Order"
        }
    }

    var sectionTitle: String {
        switch self {
        case .borderWidth: "Border Width"
        case .borderRadius: "Border Radius"
        case .zIndex: "Stacking Order"
        }
    }

    var customTitle: String {
        switch self {
        case .borderWidth: "Custom Border Widths"
        case .borderRadius: "Custom Corner Radii"
        case .zIndex: "Custom Stacking Order"
        }
    }

    var unit: String {
        switch self {
        case .borderWidth, .borderRadius: "px"
        case .zIndex: ""
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .borderWidth: 0...20
        case .borderRadius: 0...100
        case .zIndex: 0...2_000
        }
    }

    var step: Double {
        switch self {
        case .borderWidth, .borderRadius: 0.5
        case .zIndex: 10
        }
    }

    func tokens(in framework: Framework) -> FrameworkDimensionTokens {
        switch self {
        case .borderWidth: framework.borderWidths
        case .borderRadius: framework.borderRadii
        case .zIndex: framework.zIndexes
        }
    }
}

struct FrameworkDimensionSettings: View {
    let framework: Framework
    let kind: FrameworkDimensionScaleKind
    let session: FrameworkEditorSession
    @State private var isConfirmingReset = false

    private var editor: ProjectEditor { session.editor }
    private var tokens: FrameworkDimensionTokens { kind.tokens(in: framework) }

    /// Reset restores the source framework's saved predefined scale, so it
    /// only makes sense while the current values differ from it. Custom
    /// values are the user's own and never reset.
    private var canResetScale: Bool {
        guard session.canEditFramework,
              let source = FrameworkLibrary.shared.frameworks
                .first(where: { $0.id == session.document.site.frameworkSourceID })
        else { return false }
        return tokens.predefined != kind.tokens(in: source.framework).predefined
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                customCard
                scaleCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("framework-section-\(kind.sectionTitle)")
        .confirmationDialog("Reset \(kind.sectionTitle)?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset Scale") { resetScale() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore the preset values in this section. Custom values are kept. You can undo this change.")
        }
    }

    private var customCard: some View {
        FrameworkEditorCard {
            HStack(spacing: 8) {
                Text(kind.customTitle).font(.headline).accessibilityAddTraits(.isHeader)
                Button {
                    addCustom()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add \(kind.customTitle)")
                .accessibilityLabel("Add \(kind.customTitle)")
            }
            if tokens.custom.isEmpty {
                Text("Extend the scale for your project.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(tokens.custom) { token in
                        customRow(token)
                        if token.id != tokens.custom.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func customRow(_ token: FrameworkCustomDimension) -> some View {
        HStack(spacing: 14) {
            TextField("Name", text: Binding(
                get: { token.name },
                set: { setCustomName(id: token.id, value: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
            Slider(value: rounded(sliderBinding(customValue(token.id), range: kind.range), nearest: kind.step), in: kind.range)
                .accessibilityLabel("\(token.name) value")
            FrameworkNumberField(title: "\(token.name) value", value: customValue(token.id), unit: kind.unit, step: kind.step)
            // No confirmation: parts keep the value's exact size as a custom
            // length, and delete is undoable.
            Button {
                removeCustom(id: token.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete Custom Value")
            .accessibilityLabel("Delete \(token.name)")
        }
        .padding(.vertical, 8)
    }

    private func customValue(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { tokens.custom.first { $0.id == id }?.value ?? 0 },
            set: { setCustomValue(id: id, value: $0) }
        )
    }

    private func addCustom() {
        switch kind {
        case .borderWidth: editor.addFrameworkBorderWidth()
        case .borderRadius: editor.addFrameworkBorderRadius()
        case .zIndex: editor.addFrameworkZIndexValue()
        }
    }

    private func setCustomName(id: UUID, value: String) {
        switch kind {
        case .borderWidth: editor.setFrameworkBorderWidthName(id: id, value: value)
        case .borderRadius: editor.setFrameworkBorderRadiusName(id: id, value: value)
        case .zIndex: editor.setFrameworkZIndexName(id: id, value: value)
        }
    }

    private func setCustomValue(id: UUID, value: Double) {
        switch kind {
        case .borderWidth: editor.setFrameworkBorderWidthValue(id: id, value: value)
        case .borderRadius: editor.setFrameworkBorderRadiusValue(id: id, value: value)
        case .zIndex: editor.setFrameworkZIndexValue(id: id, value: value)
        }
    }

    private func removeCustom(id: UUID) {
        switch kind {
        case .borderWidth: editor.removeFrameworkBorderWidth(id: id)
        case .borderRadius: editor.removeFrameworkBorderRadius(id: id)
        case .zIndex: editor.removeFrameworkZIndex(id: id)
        }
    }

    private var scaleCard: some View {
        FrameworkEditorCard {
            HStack(spacing: 8) {
                Text(kind.title).font(.headline).accessibilityAddTraits(.isHeader)
                if !session.canEditFramework {
                    Image(systemName: "lock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Built-in framework")
                        .help("Create a new framework to edit its values.")
                }
                Spacer()
                Button("Reset Scale…", systemImage: "arrow.counterclockwise") {
                    isConfirmingReset = true
                }
                .help("Restore the preset values in this scale")
                .disabled(!canResetScale)
            }
            VStack(spacing: 0) {
                ForEach(tokens.predefined) { token in
                    dimensionRow(token)
                    if token.id != tokens.predefined.last?.id { Divider() }
                }
            }
            .disabled(!session.canEditFramework)
        }
    }

    private func dimensionRow(_ token: FrameworkDimensionToken) -> some View {
        HStack(spacing: 14) {
            Text(frameworkScaleTitle(id: token.id, fallback: token.title))
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            if kind.isRadius && token.id == "full" {
                Text("Fully rounded at the usual element sizes.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Slider(value: rounded(sliderBinding(value(token.id), range: kind.range), nearest: kind.step), in: kind.range)
                    .accessibilityLabel("\(token.title) value")
                FrameworkNumberField(title: "\(token.title) value", value: value(token.id), unit: kind.unit, step: kind.step)
            }
        }
        .padding(.vertical, 8)
    }

    private func value(_ id: String) -> Binding<Double> {
        Binding(
            get: { tokens.predefined.first { $0.id == id }?.value ?? 0 },
            set: { setValue(id: id, value: $0) }
        )
    }

    private func setValue(id: String, value: Double) {
        switch kind {
        case .borderWidth: editor.setFrameworkBorderWidth(id: id, value: value)
        case .borderRadius: editor.setFrameworkBorderRadius(id: id, value: value)
        case .zIndex: editor.setFrameworkZIndex(id: id, value: value)
        }
    }

    private func resetScale() {
        switch kind {
        case .borderWidth: editor.resetFrameworkBorderWidths()
        case .borderRadius: editor.resetFrameworkBorderRadii()
        case .zIndex: editor.resetFrameworkZIndexes()
        }
    }
}

/// Keep the visual thumb in range without rewriting valid values entered in the numeric field.
private func sliderBinding(_ value: Binding<Double>, range: ClosedRange<Double>) -> Binding<Double> {
    Binding(get: { min(max(value.wrappedValue, range.lowerBound), range.upperBound) }, set: { value.wrappedValue = $0 })
}

/// Continuous sliders show no tick marks; rounding in the binding keeps
/// the stored values as clean as stepped ones.
private func rounded(_ value: Binding<Double>, nearest: Double) -> Binding<Double> {
    Binding(
        get: { value.wrappedValue },
        set: { value.wrappedValue = ($0 / nearest).rounded() * nearest }
    )
}
