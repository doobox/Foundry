import SwiftUI

/// Project-named additions to Bootstrap's fixed scales, gathered on one page.
///
/// Bootstrap's spacing steps, text sizes, border widths, radii, shadows and z-index
/// values ship fixed. Additions do not change them; each becomes an extra utility
/// class such as `p-hero`, `text-hero` or `rounded-soft` that part controls can offer.
struct ThemeExtensionsSettings: View {
    let theme: Theme
    let session: ThemeEditorSession

    private static let sections: [BootstrapEditorSection] = [.fontSize, .borderWidth, .borderRadius, .shadows, .zIndex]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bootstrap's scales stay as shipped. Add named values here to extend them; each one becomes a Bootstrap-style utility class, such as p-hero or text-hero, that part controls can use.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ThemeCustomSpacingCard(theme: theme, session: session)
                ForEach(Self.sections, id: \.self) { section in
                    BootstrapCustomTokenCard(section: section, theme: theme, editor: session.editor)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("theme-section-Extensions")
    }
}
