import SwiftUI

/// Shared presentation for every section of the project theme editor.
struct ThemeEditorPage<Actions: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.system(size: 24, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    actions
                        .controlSize(.regular)
                }
                content
            }
            .frame(maxWidth: 1_040, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .controlSize(.regular)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("theme-section-\(title)")
    }
}

struct ThemeEditorCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

/// Measures the same two subviews in either arrangement, preserving editor focus and draft state.
struct ThemeEditorColumns<Editor: View, Preview: View>: View {
    @ViewBuilder var editor: Editor
    @ViewBuilder var preview: Preview

    var body: some View {
        ThemeEditorColumnLayout {
            editor
            preview
        }
    }
}

private struct ThemeEditorColumnLayout: Layout {
    private let gap: CGFloat = 24
    private let previewWidth: CGFloat = 300

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? 1_040)
        let sideBySide = width >= 880
        let editorWidth = sideBySide ? width - previewWidth - gap : width
        let sizes = subviews.enumerated().map { index, view in
            view.sizeThatFits(.init(width: index == 0 ? editorWidth : (sideBySide ? previewWidth : width), height: nil))
        }
        return CGSize(width: width, height: sideBySide
            ? sizes.map(\.height).max() ?? 0
            : sizes.map(\.height).reduce(0, +) + gap * CGFloat(max(0, sizes.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sideBySide = bounds.width >= 880
        let editorWidth = sideBySide ? bounds.width - previewWidth - gap : bounds.width
        var y = bounds.minY
        for (index, view) in subviews.enumerated() {
            let width = index == 0 ? editorWidth : (sideBySide ? previewWidth : bounds.width)
            let size = view.sizeThatFits(.init(width: width, height: nil))
            view.place(
                at: CGPoint(x: bounds.minX + (sideBySide && index > 0 ? editorWidth + gap : 0), y: y),
                anchor: .topLeading,
                proposal: .init(width: width, height: size.height)
            )
            if !sideBySide { y += size.height + gap }
        }
    }
}

/// Aligned labels for short property forms, independent of the available window width.
struct ThemeEditorPropertyRow<Content: View>: View {
    let title: String
    var labelWidth: CGFloat = 76
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).frame(width: labelWidth, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ThemeNumberField: View {
    let title: String
    @Binding var value: Double
    var unit = "px"
    var step: Double = 1
    var precision = 2

    var body: some View {
        HStack(spacing: 5) {
            TextField(title, value: $value, format: .number.grouping(.never).precision(.fractionLength(0...precision)))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 66)
                .accessibilityLabel(title)
            Text(unit).foregroundStyle(.secondary).frame(minWidth: 14, alignment: .leading)
            Stepper(title, value: $value, step: step)
                .labelsHidden().fixedSize()
                .accessibilityLabel("Adjust \(title)")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A preset's identifier supplies its display label; custom names are left untouched.
func themeScaleTitle(id: String, fallback: String) -> String {
    switch id {
    case "base": "MD"
    case "none": "None"
    case "full": "Full"
    case "inner": "Inner"
    case "3xs", "2xs", "xs", "sm", "md", "lg", "xl", "2xl", "3xl", "4xl", "5xl", "6xl", "7xl", "8xl", "9xl": id.uppercased()
    default: fallback
    }
}
