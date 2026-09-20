import SwiftUI

/// A compact four-corner widget for radius editing: fields sit in a 2×2 grid at the
/// position of the corner they edit, joined by a single all-or-none link drawn as a
/// ring of four segments spanning the gaps between adjacent fields. Linked, every
/// corner shares one value; unlinked, all four are independent — corners have no
/// meaningful pair state the way edges do. The same shippingbox toggle switches the
/// whole control between framework tokens and custom values. Segment geometry reuses the
/// hidden-placeholder technique from EdgesControl, so the ring always lines up with
/// the real gaps at any width.
struct CornersControl<TopLeft: View, TopRight: View, BottomLeft: View, BottomRight: View>: View {
    let linked: Bool
    let usesFrameworkTokens: Bool
    let focusNamespace: Namespace.ID
    let toggleLinked: () -> Void
    /// Nil hides the framework/custom toggle entirely — the generic corners control has
    /// no framework mode to switch to.
    let toggleUsesFrameworkTokens: (() -> Void)?
    @ViewBuilder let topLeft: () -> TopLeft
    @ViewBuilder let topRight: () -> TopRight
    @ViewBuilder let bottomLeft: () -> BottomLeft
    @ViewBuilder let bottomRight: () -> BottomRight

    @State private var isHoveringLink = false
    @Environment(\.resetFocus) private var resetFocus

    private let fieldWidth: CGFloat = 90
    private let rowGap: CGFloat = 28

    var body: some View {
        ZStack {
            // Click-away target. First child, so every real control above it
            // gets first refusal on the click.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { resetFocus(in: focusNamespace) }

            HStack(alignment: .top, spacing: 8) {
                // The ring's placeholders must share the grid's exact bounds, so
                // the link overlays the grid inside the same HStack cell — the
                // toggle column narrows both together.
                ZStack {
                    VStack(spacing: rowGap) {
                        HStack(spacing: 0) {
                            field { topLeft() }
                            Spacer(minLength: 0)
                            field { topRight() }
                        }
                        HStack(spacing: 0) {
                            field { bottomLeft() }
                            Spacer(minLength: 0)
                            field { bottomRight() }
                        }
                    }

                    linkButton
                }

                if toggleUsesFrameworkTokens != nil { modeToggle }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .focusScope(focusNamespace)
        .onExitCommand { resetFocus(in: focusNamespace) }
        .onDisappear { isHoveringLink = false }
    }

    /// One button whose label is the whole ring: four segments, each spanning the
    /// gap between two adjacent fields. Hidden placeholders reserve the fields'
    /// exact geometry so every segment lands in the real gap.
    private var linkButton: some View {
        Button {
            resetFocus(in: focusNamespace)
            isHoveringLink = false
            toggleLinked()
        } label: {
            ZStack {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        placeholder { topLeft() }
                        segment(.horizontal)
                        placeholder { topRight() }
                    }
                    Color.clear.frame(height: rowGap)
                    HStack(spacing: 0) {
                        placeholder { bottomLeft() }
                        segment(.horizontal)
                        placeholder { bottomRight() }
                    }
                }

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        placeholder { topLeft() }
                        segment(.vertical)
                        placeholder { bottomLeft() }
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        placeholder { topRight() }
                        segment(.vertical)
                        placeholder { bottomRight() }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHoveringLink)
        .animation(.easeInOut(duration: 0.15), value: linked)
        .accessibilityLabel("Corner link")
        .accessibilityValue(linked ? "Linked" : "Unlinked")
    }

    private func segment(_ axis: CornersLinkAxis) -> some View {
        let color: Color = (linked || isHoveringLink) ? .accentColor : .secondary.opacity(0.5)
        let isDashed = !linked || isHoveringLink

        return CornersLinkShape(axis: axis)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .square, dash: isDashed ? [8, 5] : []))
            .frame(
                maxWidth: axis == .horizontal ? .infinity : fieldWidth,
                maxHeight: axis == .vertical ? rowGap : nil
            )
            .contentShape(Rectangle())
            .onHover { isHoveringLink = $0 }
    }

    private var modeToggle: some View {
        FrameworkModeToggle(usesFrameworkTokens: usesFrameworkTokens) {
            resetFocus(in: focusNamespace)
            isHoveringLink = false
            toggleUsesFrameworkTokens?()
        }
    }

    @ViewBuilder
    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(2)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(linked ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 2)
            }
            .animation(.easeInOut(duration: 0.15), value: linked)
            .frame(width: fieldWidth)
    }

    /// An invisible, non-interactive copy of a field that reserves the exact same
    /// geometry, so ring segments drawn alongside it line up with the real gaps.
    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        field(content: content)
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum CornersLinkAxis { case vertical, horizontal }

private struct CornersLinkShape: Shape {
    let axis: CornersLinkAxis

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
    @Previewable @State var topLeft = 0.0
    @Previewable @State var topRight = 0.0
    @Previewable @State var bottomLeft = 0.0
    @Previewable @State var bottomRight = 0.0
    @Previewable @State var linked = true
    @Previewable @State var usesFrameworkTokens = false
    @Previewable @Namespace var focusNamespace

    PartControlPreview {
        InspectorRow(title: "Radius") {
            CornersControl(
                linked: linked,
                usesFrameworkTokens: usesFrameworkTokens,
                focusNamespace: focusNamespace,
                toggleLinked: {
                    linked.toggle()
                    if linked {
                        topRight = topLeft
                        bottomLeft = topLeft
                        bottomRight = topLeft
                    }
                },
                toggleUsesFrameworkTokens: { usesFrameworkTokens.toggle() },
                topLeft: {
                    CornersControlPreviewField(value: Binding(
                        get: { topLeft },
                        set: { newValue in
                            topLeft = newValue
                            if linked {
                                topRight = newValue
                                bottomLeft = newValue
                                bottomRight = newValue
                            }
                        }
                    ))
                },
                topRight: { CornersControlPreviewField(value: $topRight) },
                bottomLeft: { CornersControlPreviewField(value: $bottomLeft) },
                bottomRight: { CornersControlPreviewField(value: $bottomRight) }
            )
        }
    }
}

private struct CornersControlPreviewField: View {
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
