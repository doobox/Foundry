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

/// Keeps editing controls and their preview side by side at every supported window size.
struct ThemeEditorColumns<Editor: View, Preview: View>: View {
    var equalColumns = false
    @ViewBuilder var editor: Editor
    @ViewBuilder var preview: Preview

    var body: some View {
        ThemeEditorColumnLayout(equalColumns: equalColumns) {
            editor
            preview
        }
    }
}

private struct ThemeEditorColumnLayout: Layout {
    var equalColumns: Bool
    private let gap: CGFloat = 16

    private func previewWidth(for width: CGFloat) -> CGFloat {
        let available = max(0, width - gap)
        return equalColumns ? available / 2 : min(300, available * 0.4)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? 1_040)
        let previewWidth = previewWidth(for: width)
        let editorWidth = max(0, width - previewWidth - gap)
        let sizes = subviews.enumerated().map { index, view in
            view.sizeThatFits(.init(width: index == 0 ? editorWidth : previewWidth, height: nil))
        }
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let previewWidth = previewWidth(for: bounds.width)
        let editorWidth = max(0, bounds.width - previewWidth - gap)
        for (index, view) in subviews.enumerated() {
            let width = index == 0 ? editorWidth : previewWidth
            let size = view.sizeThatFits(.init(width: width, height: nil))
            view.place(
                at: CGPoint(x: bounds.minX + (index > 0 ? editorWidth + gap : 0), y: bounds.minY),
                anchor: .topLeading,
                proposal: .init(width: width, height: equalColumns ? bounds.height : size.height)
            )
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
