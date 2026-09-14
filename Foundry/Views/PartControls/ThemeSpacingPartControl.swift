import SwiftUI

typealias ThemeBorderWidthPartControl = ThemeSpacingPartControl<BorderWidthPolicy>
typealias ThemeRadiusPartControl = ThemeSpacingPartControl<RadiusPolicy>
typealias ThemePaddingPartControl = ThemeSpacingPartControl<PaddingPolicy>
typealias ThemeMarginPartControl = ThemeSpacingPartControl<MarginPolicy>

struct ThemeSpacingPartControl<Policy: ThemeSpacingPolicy>: View {
    var label: String? = nil
    let theme: Theme
    var indicator: InspectorRowIndicator? = nil
    @Binding var value: ThemeSpacingValue<Policy>
    @State private var hoveredLink: String?
    private typealias Edge = ThemeSpacingValue<Policy>.Edge

    private var options: [ThemeEdgeChoice] { Policy.choices(in: theme) }

    var body: some View {
        InspectorGrid(contentInsets: EdgeInsets()) {
            InspectorRow(title: resolvedLabel, indicator: indicator) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        if value.linked { value.unlinkAll() }
                        else { value.linkAll() }
                    } label: { linkIcon(linked: value.linked, preview: previewValue.linked) }
                    .modifier(PaddingLinkButtonStyle(linked: value.linked))
                    .anchorPreference(key: PaddingLinkAnchors.self, value: .bounds) { ["all": $0] }
                    .onHover { setHover("all", hovering: $0) }
                    .help(value.linked ? "Unlink edges, keeping their values" : "Link all using \(Edge.top.title)")
                    .accessibilityLabel(value.linked ? "Unlink \(Policy.label.lowercased()) edges" : "Link \(Policy.label.lowercased()) edges")
                }
            }
            ForEach(Edge.allCases) { edge in edgeRow(edge, title: edge.title) }
        }
        .overlayPreferenceValue(PaddingLinkAnchors.self) { anchors in
            GeometryReader { geometry in
                let nodes = ["all", "Top", "Bottom", "Left", "Right"]
                ForEach(0..<4) { index in
                    let active = hasConnection(index, in: value)
                    if active || hasConnection(index, in: previewValue) {
                        linkLine(from: nodes[index], to: nodes[index + 1], anchors: anchors,
                                 geometry: geometry, color: .primary)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlayPreferenceValue(PaddingLinkAnchors.self) { anchors in
            GeometryReader { geometry in
                pairHoverGap(from: .top, to: .bottom, anchors: anchors, geometry: geometry)
                pairHoverGap(from: .left, to: .right, anchors: anchors, geometry: geometry)
            }
            .accessibilityHidden(true)
        }
        .onDisappear { hoveredLink = nil }
    }

    @ViewBuilder
    private func linkIcon(linked: Bool, preview: Bool) -> some View {
        if linked {
            Image(systemName: "link")
        } else {
            Image(systemName: "link")
                .foregroundStyle(preview ? Color.primary : Color.secondary)
        }
    }

    @ViewBuilder
    private func pairHoverGap(from: Edge, to: Edge, anchors: [String: Anchor<CGRect>],
                              geometry: GeometryProxy) -> some View {
        if let start = anchors[from.rawValue], let end = anchors[to.rawValue] {
            let first = geometry[start]
            let second = geometry[end]
            let left = min(first.minX, second.minX)
            let right = max(first.maxX, second.maxX)
            let height = max(0, second.minY - first.maxY)
            Color.clear
                .frame(width: right - left, height: height)
                .contentShape(Rectangle())
                .onHover { setHover("gap:\(from.rawValue)", hovering: $0) }
                .position(x: (left + right) / 2, y: first.maxY + height / 2)
        }
    }

    private func setHover(_ target: String, hovering: Bool) {
        if hovering { hoveredLink = target }
        else if hoveredLink == target { hoveredLink = nil }
    }

    /// Simulate the actual click on a copy, including promotion of two pairs to all.
    private var previewValue: ThemeSpacingValue<Policy> {
        var preview = value
        if hoveredLink == "all", !value.linked {
            preview.linkAll()
        } else if let hoveredLink,
                  let edge = Edge(rawValue: hoveredLink.replacingOccurrences(of: "gap:", with: "")),
                  !value.isPairLinked(edge) {
            preview.togglePair(using: edge)
        }
        return preview
    }

    private func hasConnection(_ index: Int, in state: ThemeSpacingValue<Policy>) -> Bool {
        state.linked || (index == 1 && state.verticalLinked) || (index == 3 && state.horizontalLinked)
    }

    @ViewBuilder
    private func linkLine(from: String, to: String, anchors: [String: Anchor<CGRect>],
                          geometry: GeometryProxy, color: Color) -> some View {
        if let start = anchors[from], let end = anchors[to] {
            let first = geometry[start]
            let second = geometry[end]
            let connection = Path { path in
                path.move(to: CGPoint(x: first.midX, y: first.maxY + 1))
                path.addLine(to: CGPoint(x: second.midX, y: second.minY - 1))
            }
            connection.stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .square))
        }
    }

    private func edgeRow(_ edge: Edge, title: String) -> some View {
        let binding = Binding(get: { value.value(for: edge) }, set: { value.set($0, for: edge) })
        return InspectorRow(title: title) {
            HStack(spacing: 10) {
                ThemeSpacingInput<Policy>(binding: binding, title: title, theme: theme)
                Button { value.togglePair(using: edge) } label: {
                    linkIcon(linked: value.isPairLinked(edge), preview: previewValue.isPairLinked(edge))
                }
                .modifier(PaddingLinkButtonStyle(linked: value.isPairLinked(edge)))
                .anchorPreference(key: PaddingLinkAnchors.self, value: .bounds) { [edge.rawValue: $0] }
                .onHover { setHover(edge.rawValue, hovering: $0) }
                .help(value.isPairLinked(edge)
                    ? "Unlink \(edge.title) and \(edge.partner.title)"
                    : ((value.verticalLinked || value.horizontalLinked)
                       ? "Link all using \(Edge.top.title)"
                       : "Link \(edge.title) and \(edge.partner.title), using \(edge.isVertical ? Edge.top.title : Edge.left.title)"))
                .accessibilityLabel("\(edge.title)–\(edge.partner.title) link")
                .accessibilityValue(value.isPairLinked(edge) ? "Linked" : "Unlinked")
            }
        }
    }

    var resolvedLabel: String {
        guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Policy.label }
        return label
    }


}

private struct PaddingLinkButtonStyle: ViewModifier {
    let linked: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if linked {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct PaddingLinkAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ThemeSpacingInput<Policy: ThemeSpacingPolicy>: View {
    let binding: Binding<ThemeSpacingValue<Policy>.EdgeValue>
    let title: String
    let theme: Theme
    private var options: [ThemeEdgeChoice] { Policy.choices(in: theme) }
    var body: some View { edgeInput(binding, title: title) }

    @ViewBuilder
    private func edgeInput(_ binding: Binding<ThemeSpacingValue<Policy>.EdgeValue>, title: String) -> some View {
            if binding.wrappedValue.isCustom {
                HStack(spacing: 6) {
                    TextField("Value", value: Binding(
                        get: { binding.wrappedValue.amount },
                        set: { binding.wrappedValue.amount = $0.isFinite ? (Policy.allowsAutoAndNegative ? $0 : max(0, $0)) : 0 }
                    ), format: .number.precision(.fractionLength(0...3)))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(title) custom \(Policy.label.lowercased())")
                    Picker("Unit", selection: binding.unit) {
                        ForEach(Policy.units, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 66)
                    .accessibilityLabel("\(title) \(Policy.label.lowercased()) unit")
                    Button { binding.wrappedValue.isCustom = false } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Return to the previous theme value")
                    .accessibilityLabel("Return \(title) to theme value")
                }
            } else {
                Picker(title, selection: Binding(
                    get: { binding.wrappedValue.token },
                    set: { selection in
                        if selection == "custom-input" {
                            binding.wrappedValue.amount = options.first { $0.id == binding.wrappedValue.token }?.amount ?? 0
                            binding.wrappedValue.unit = Policy.themeUnit
                            binding.wrappedValue.isCustom = true
                        } else { binding.wrappedValue.token = selection }
                    }
                )) {
                    Text("None · 0").tag("none")
                    if Policy.allowsAutoAndNegative { Text("Auto").tag("auto") }
                    if binding.wrappedValue.token != "none",
                       !(Policy.allowsAutoAndNegative && binding.wrappedValue.token == "auto"),
                       !options.contains(where: { $0.id == binding.wrappedValue.token }) {
                        Text("Missing value").tag(binding.wrappedValue.token)
                    }
                    Section("Theme values") {
                        ForEach(options, id: \.id) { option in
                            Text("\(option.label) · \(formatted(option.amount)) \(Policy.themeUnit)").tag(option.id)
                        }
                    }
                    Divider()
                    Text("Custom…").tag("custom-input")
                }
                .pickerStyle(.menu)
                .buttonSizing(.flexible)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(title) \(Policy.label.lowercased())")
            }
    }

    private func formatted(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...3)))
    }

}
