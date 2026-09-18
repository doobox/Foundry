import SwiftUI

struct ThemeTypeScaleSettings: View {
    let theme: Theme
    let editor: ProjectEditor
    @State private var selectedID = "base"
    @State private var pendingDeletion: ThemeFontSize?

    var body: some View {
        ThemeEditorColumns {
            VStack(spacing: 20) {
                ThemeEditorCard(title: "Type scale", subtitle: "Choose a size to preview it. Edit its size and line height in place.") {
                    HStack {
                        Text("STYLE").frame(maxWidth: .infinity, alignment: .leading)
                        Text("SIZE").frame(width: 112, alignment: .leading)
                        Text("LINE HEIGHT").frame(width: 112, alignment: .leading)
                    }
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(theme.typography.predefinedFontSizes) { token in
                            typeRow(token)
                            if token.id != theme.typography.predefinedFontSizes.last?.id { Divider() }
                        }
                    }
                }
                ThemeEditorCard(title: "Custom sizes") {
                    ForEach(theme.typography.customFontSizes) { token in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Size name", text: Binding(
                                    get: { token.title },
                                    set: { editor.setThemeFontSizeTitle(id: token.id, value: $0) }
                                ))
                                Button("Delete Size", systemImage: "trash", role: .destructive) { pendingDeletion = token }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Delete custom size")
                            }
                            typeRow(token)
                        }
                        Divider()
                    }
                    HStack {
                        if theme.typography.customFontSizes.isEmpty {
                            Text("Add a size for a specific purpose.").foregroundStyle(.secondary).font(.callout)
                        }
                        Spacer(minLength: 8)
                        Button("Add Size", systemImage: "plus") { selectedID = editor.addThemeFontSize() }
                    }
                }
            }
        } preview: {
            if let selected {
                ThemeEditorCard(title: "Preview", subtitle: displayTitle(selected)) {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(["The art of", "a good first", "impression."], id: \.self) { line in
                                Text(line)
                                    .font(.system(size: selected.size * 16))
                                    .fixedSize()
                                    .frame(height: selected.size * 16 * selected.lineHeight)
                            }
                        }
                            .fixedSize()
                            .padding(16)
                    }
                    .frame(height: 210)
                    .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Size", value: "\((selected.size * 16).formatted()) px · \(selected.size.formatted()) rem")
                        Slider(value: sliderBinding(pixels(selected.id), range: 8...160), in: 8...160, step: 1)
                            .accessibilityLabel("Preview font size")
                        LabeledContent("Line height", value: "\((selected.size * 16 * selected.lineHeight).formatted(.number.precision(.fractionLength(0...1)))) px")
                        Slider(value: sliderBinding(lineHeight(selected.id), range: 0.8...2.5), in: 0.8...2.5, step: 0.01)
                            .accessibilityLabel("Preview line height")
                    }
                    .font(.callout)
                    Text("1 rem = 16 px. Line height is a multiple of the font size.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: theme.typography.fontSizes.map(\.id)) { _, ids in
            if !ids.contains(selectedID) { selectedID = ids.contains("base") ? "base" : ids.first ?? "" }
        }
        .confirmationDialog("Replace \(pendingDeletion?.title ?? "Custom Size")", isPresented: deletionPresented, titleVisibility: .visible) {
            ForEach(theme.typography.fontSizes.filter { $0.id != pendingDeletion?.id }) { replacement in
                Button("Replace with \(displayTitle(replacement))") {
                    guard let pendingDeletion else { return }
                    editor.removeThemeFontSize(id: pendingDeletion.id, replacingWith: replacement.id)
                    self.pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Choose the size that parts should use before deleting this custom size.")
        }
    }

    private func typeRow(_ token: ThemeFontSize) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedID = token.id
            } label: {
                HStack(spacing: 8) {
                    Text(displayTitle(token)).fontWeight(selectedID == token.id ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "eye").font(.caption).opacity(selectedID == token.id ? 1 : 0)
                }
                .foregroundStyle(selectedID == token.id ? Color.accentColor : .primary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain).help("Preview \(displayTitle(token))")
            .frame(maxWidth: .infinity, alignment: .leading)
            ThemeNumberField(title: "\(displayTitle(token)) size", value: pixels(token.id), precision: 1)
            ThemeNumberField(title: "\(displayTitle(token)) line height", value: lineHeight(token.id), unit: "×", step: 0.05, precision: 3)
        }
        .frame(minHeight: 43)
        .accessibilityElement(children: .contain)
    }

    private var selected: ThemeFontSize? { theme.typography.fontSizes.first { $0.id == selectedID } ?? theme.typography.fontSizes.first }
    private func displayTitle(_ token: ThemeFontSize) -> String {
        theme.typography.predefinedFontSizes.contains(where: { $0.id == token.id })
            ? themeScaleTitle(id: token.id, fallback: token.title) : token.title
    }
    private func pixels(_ id: String) -> Binding<Double> {
        Binding(get: { (theme.typography.fontSizes.first { $0.id == id }?.size ?? 1) * 16 },
                set: { editor.setThemeFontSize(id: id, value: $0 / 16) })
    }
    private func lineHeight(_ id: String) -> Binding<Double> {
        Binding(get: { theme.typography.fontSizes.first { $0.id == id }?.lineHeight ?? 1.5 },
                set: { editor.setThemeFontSizeLineHeight(id: id, value: $0) })
    }
    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}

struct ThemeSpacingSettings: View {
    let theme: Theme
    let editor: ProjectEditor
    @State private var pendingDeletion: ThemeSpacing?
    private let ids = ["3xs", "2xs", "xs", "sm", "md", "lg", "xl", "2xl", "3xl"]

    var body: some View {
        ThemeEditorColumns {
            VStack(spacing: 20) {
                ThemeEditorCard(title: "Spacing scale", subtitle: "Each unit is 0.25 rem (4 px). Use the same scale for margins, padding and gaps.") {
                    VStack(spacing: 0) {
                        ForEach(DesignToken.spacingTokens) { token in
                            let value = theme.number(for: token) ?? 0
                            ThemeScaleValueRow(
                                title: token.displayName,
                                value: Binding(get: { value }, set: { editor.setThemeSpacing(token, value: $0) }),
                                range: 0...40, unit: "×", step: 0.5,
                                detail: "\((value * 0.25).formatted()) rem · \((value * 4).formatted()) px"
                            )
                            if token != DesignToken.spacingTokens.last { Divider() }
                        }
                    }
                }
                ThemeEditorCard(title: "Custom spacing") {
                    ForEach(theme.spacing.custom) { token in
                        VStack(spacing: 8) {
                            HStack {
                                TextField("Spacing name", text: Binding(get: { token.name }, set: { editor.setThemeSpacingName(id: token.id, value: $0) }))
                                Button("Delete Spacing", systemImage: "trash", role: .destructive) { pendingDeletion = token }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Delete custom spacing")
                            }
                            ThemeScaleValueRow(title: "Value", value: Binding(get: { token.value }, set: { editor.setThemeSpacingValue(id: token.id, value: $0) }), range: 0...40, unit: "×", step: 0.5, detail: "\((token.value * 0.25).formatted()) rem · \((token.value * 4).formatted()) px")
                        }
                        Divider()
                    }
                    HStack {
                        if theme.spacing.custom.isEmpty {
                            Text("Extend the scale for your project.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Add Spacing", systemImage: "plus") { editor.addThemeSpacing() }
                    }
                }
            }
        } preview: {
            ThemeEditorCard(title: "Preview", subtitle: "Relative sizes across the scale.") {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(DesignToken.spacingTokens) { token in
                        HStack(spacing: 12) {
                            Text(token.displayName).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: barWidth(token), height: 12)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Text("Bars share one scale, so their proportions reflect your values.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Replace \(pendingDeletion?.name ?? "Custom Spacing")", isPresented: deletionPresented, titleVisibility: .visible) {
            ForEach(replacements) { replacement in
                Button("Replace with \(replacement.label)") {
                    guard let pendingDeletion else { return }
                    editor.removeThemeSpacing(id: pendingDeletion.id, replacingWith: replacement.value)
                    self.pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { Text("Choose the spacing that parts should use before deleting this custom value.") }
    }

    private func barWidth(_ token: DesignToken) -> Double {
        let largest = max(1, DesignToken.spacingTokens.compactMap { theme.number(for: $0) }.max() ?? 1)
        return max(0, (theme.number(for: token) ?? 0) / largest * 180)
    }
    private var replacements: [PartPropertyChoice] {
        zip(ids, DesignToken.spacingTokens).map { PartPropertyChoice(value: $0.0, label: $0.1.displayName) }
        + theme.spacing.custom.filter { $0.id != pendingDeletion?.id }.map {
            PartPropertyChoice(value: "custom:\($0.id.uuidString.lowercased())", label: $0.name)
        }
    }
    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}

/// Which flavour of `ThemeDimensionTokens` scale is being edited. Each kind
/// describes its own title/unit/range and whether the shared shape preview
/// (which only makes visual sense for border width/radius) applies.
enum ThemeDimensionScaleKind {
    case borderWidth
    case borderRadius
    case zIndex

    var isRadius: Bool { self == .borderRadius }

    var title: String {
        switch self {
        case .borderWidth: "Border width scale"
        case .borderRadius: "Corner radius scale"
        case .zIndex: "Stacking order scale"
        }
    }

    var subtitle: String {
        switch self {
        case .borderWidth, .borderRadius: "Values are in pixels. Edit a field for precise control."
        case .zIndex: "Values set stacking order. Higher values sit in front."
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

    var showsShapePreview: Bool { self != .zIndex }
}

struct ThemeDimensionSettings: View {
    let tokens: ThemeDimensionTokens
    let kind: ThemeDimensionScaleKind
    let setValue: (String, Double) -> Void

    var body: some View {
        ThemeEditorColumns {
            ThemeEditorCard(title: kind.title, subtitle: kind.subtitle) {
                VStack(spacing: 0) {
                    ForEach(tokens.predefined) { token in
                        ThemeScaleValueRow(
                            title: themeScaleTitle(id: token.id, fallback: token.title),
                            value: Binding(get: { token.value }, set: { setValue(token.id, $0) }),
                            range: kind.range,
                            unit: kind.unit,
                            step: kind.step,
                            detail: kind.isRadius && token.id == "full" ? "Fully rounded at the usual element sizes." : nil,
                            showsSlider: !(kind.isRadius && token.id == "full")
                        )
                        if token.id != tokens.predefined.last?.id { Divider() }
                    }
                }
            }
        } preview: {
            if kind.showsShapePreview {
                ThemeEditorCard(title: "Preview", subtitle: kind.isRadius ? "The same shape, with each radius." : "The same shape, with each border width.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 16)], spacing: 20) {
                        ForEach(tokens.predefined) { token in
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: kind.isRadius ? min(28, token.value) : 8, style: .circular)
                                    .fill(Color.accentColor.opacity(0.09))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: kind.isRadius ? min(28, token.value) : 8, style: .circular)
                                            .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: kind.isRadius ? 1.5 : min(25, token.value))
                                    }
                                    .frame(width: 86, height: 56)
                                Text(themeScaleTitle(id: token.id, fallback: token.title)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                ThemeEditorCard(title: "Preview", subtitle: "Later tokens stack in front of earlier ones.") {
                    ZStack {
                        ForEach(Array(tokens.predefined.enumerated()), id: \.element.id) { index, token in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 8, style: .circular)
                                    .fill(Color.accentColor.opacity(0.15 + 0.6 * Double(index) / Double(max(1, tokens.predefined.count - 1))))
                                    .overlay {
                                        Text(themeScaleTitle(id: token.id, fallback: token.title))
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                    }
                                    .frame(width: 72, height: 44)
                            }
                            .zIndex(token.value)
                            .offset(x: CGFloat(index) * 14, y: CGFloat(index) * 8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                    .padding(.leading, 8)
                }
            }
        }
    }
}

private struct ThemeScaleValueRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = "px"
    var step: Double = 1
    var detail: String? = nil
    var showsSlider = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 14) {
                Text(title).fontWeight(.medium).frame(width: 44, alignment: .leading)
                if showsSlider {
                    Slider(value: sliderBinding($value, range: range), in: range, step: step)
                        .frame(minWidth: 60, maxWidth: .infinity)
                        .accessibilityLabel("\(title) \(unit == "×" ? "spacing" : "value")")
                } else {
                    Text("Capsule").font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                ThemeNumberField(title: "\(title) value", value: $value, unit: unit, step: step)
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).padding(.leading, 58)
            }
        }
        .padding(.vertical, detail == nil ? 10 : 9)
    }
}

/// Keep the visual thumb in range without rewriting valid values entered in the numeric field.
private func sliderBinding(_ value: Binding<Double>, range: ClosedRange<Double>) -> Binding<Double> {
    Binding(get: { min(max(value.wrappedValue, range.lowerBound), range.upperBound) }, set: { value.wrappedValue = $0 })
}
