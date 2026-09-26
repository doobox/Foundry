import SwiftUI

/// A compact box-model widget: four edge fields with independently linkable vertical
/// and horizontal pairs, plus a single toggle that switches every edge between framework
/// tokens and raw custom values. Fields sit in plain VStack/HStack + Spacer layouts
/// rather than fixed offsets, so the horizontal pair naturally stretches to fill
/// whatever width is available. The connecting line for each axis is drawn in the
/// very same Spacer slot via a second, hidden copy of that axis's fields — reserving
/// identical geometry without being interactive — so the line always lines up with
/// the real gap, at any width.
struct EdgesControl<Top: View, Right: View, Bottom: View, Left: View>: View {
    let verticalLinked: Bool
    let horizontalLinked: Bool
    let usesFrameworkTokens: Bool
    let focusNamespace: Namespace.ID
    let toggleVerticalLink: () -> Void
    let toggleHorizontalLink: () -> Void
    /// Nil hides the framework/custom toggle entirely — the generic edges control has
    /// no framework mode to switch to.
    let toggleUsesFrameworkTokens: (() -> Void)?
    @ViewBuilder let top: () -> Top
    @ViewBuilder let right: () -> Right
    @ViewBuilder let bottom: () -> Bottom
    @ViewBuilder let left: () -> Left

    @State private var hoverTarget: EdgesLinkTarget?
    @Environment(\.resetFocus) private var resetFocus

    private let fieldWidth: CGFloat = 90
    private let verticalExtent: CGFloat = 110

    var body: some View {
        ZStack {
            // Click-away target. First child, so every real control above it
            // gets first refusal on the click.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { resetFocus(in: focusNamespace) }

            VStack(spacing: 0) {
                field { top() }
                Spacer(minLength: 0)
                field { bottom() }
            }
            .frame(height: verticalExtent)

            HStack(spacing: 0) {
                field { left() }
                Spacer(minLength: 0)
                field { right() }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                placeholder { top() }
                linkLine(.vertical)
                placeholder { bottom() }
            }
            .frame(height: verticalExtent)

            HStack(spacing: 0) {
                placeholder { left() }
                linkLine(.horizontal)
                placeholder { right() }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .overlay(alignment: .topTrailing) {
            if toggleUsesFrameworkTokens != nil { modeToggle.padding(.top, 5) }
        }
        .focusScope(focusNamespace)
        .onExitCommand { resetFocus(in: focusNamespace) }
        .onDisappear { hoverTarget = nil }
    }

    private var modeToggle: some View {
        FrameworkModeToggle(usesFrameworkTokens: usesFrameworkTokens) {
            resetFocus(in: focusNamespace)
            hoverTarget = nil
            toggleUsesFrameworkTokens?()
        }
    }

    // The wells are the bare controls — linked state is the link lines' job,
    // so the fields carry no chrome of their own.
    @ViewBuilder
    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(2)
            .frame(width: fieldWidth)
    }

    /// An invisible, non-interactive copy of a field that reserves the exact same
    /// geometry, so the link line drawn alongside it lines up with the real gap.
    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        field(content: content)
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func linkLine(_ axis: EdgesLinkAxis) -> some View {
        let target: EdgesLinkTarget = axis == .vertical ? .vertical : .horizontal
        let isLinked = axis == .vertical ? verticalLinked : horizontalLinked
        let action = axis == .vertical ? toggleVerticalLink : toggleHorizontalLink
        let isHovering = hoverTarget == target
        // Hover previews the state a click would produce: an active link dims
        // to the unlinked grey dash, an inactive one solidifies in accent.
        let previewsLinked = isHovering ? !isLinked : isLinked
        let color: Color = previewsLinked ? .accentColor : .secondary.opacity(0.5)
        let isDashed = !previewsLinked

        return Button {
            resetFocus(in: focusNamespace)
            hoverTarget = nil
            action()
        } label: {
            EdgesLinkShape(axis: axis)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .square, dash: isDashed ? [8, 5] : []))
                .frame(
                    maxWidth: axis == .horizontal ? .infinity : 12,
                    maxHeight: axis == .vertical ? .infinity : 12
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverTarget = $0 ? target : nil }
        .animation(.easeInOut(duration: 0.075), value: hoverTarget)
        .animation(.easeInOut(duration: 0.075), value: isLinked)
        .accessibilityLabel(axis == .vertical ? "Top–bottom link" : "Left–right link")
        .accessibilityValue(isLinked ? "Linked" : "Unlinked")
    }
}

private enum EdgesLinkAxis { case vertical, horizontal }
private enum EdgesLinkTarget: Equatable { case vertical, horizontal }

private struct EdgesLinkShape: Shape {
    let axis: EdgesLinkAxis

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch axis {
        case .horizontal:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        case .vertical:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return path
    }
}

#Preview {
    @Previewable @State var top = 0.0
    @Previewable @State var right = 0.0
    @Previewable @State var bottom = 0.0
    @Previewable @State var left = 0.0
    @Previewable @State var verticalLinked = true
    @Previewable @State var horizontalLinked = true
    @Previewable @State var usesFrameworkTokens = false
    @Previewable @Namespace var focusNamespace

    PartControlPreview {
        InspectorRow(title: "Margin") {
            EdgesControl(
                verticalLinked: verticalLinked,
                horizontalLinked: horizontalLinked,
                usesFrameworkTokens: usesFrameworkTokens,
                focusNamespace: focusNamespace,
                toggleVerticalLink: {
                    verticalLinked.toggle()
                    if verticalLinked { bottom = top }
                },
                toggleHorizontalLink: {
                    horizontalLinked.toggle()
                    if horizontalLinked { right = left }
                },
                toggleUsesFrameworkTokens: { usesFrameworkTokens.toggle() },
                top: {
                    EdgesControlPreviewField(value: Binding(
                        get: { top },
                        set: { newValue in
                            top = newValue
                            if verticalLinked { bottom = newValue }
                        }
                    ))
                },
                right: {
                    EdgesControlPreviewField(value: Binding(
                        get: { right },
                        set: { newValue in
                            right = newValue
                            if horizontalLinked { left = newValue }
                        }
                    ))
                },
                bottom: { EdgesControlPreviewField(value: $bottom) },
                left: { EdgesControlPreviewField(value: $left) }
            )
        }
    }
}

private struct EdgesControlPreviewField: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 4) {
            TextField("Value", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
            Text("px").font(.caption).foregroundStyle(.secondary)
        }
    }
}
