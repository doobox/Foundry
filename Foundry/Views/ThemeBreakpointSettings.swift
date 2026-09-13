import SwiftUI

struct ThemeBreakpointSettings: View {
    let screens: ScreenTokens
    let editor: ProjectEditor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Responsive Breakpoints")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                breakpointList
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("theme-section-Breakpoints")
    }

    private var breakpointList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Breakpoint")
                    .frame(width: ThemeBreakpointColumns.identity, alignment: .leading)
                Text("Starts at")
                    .frame(width: ThemeBreakpointColumns.minimumWidth, alignment: .leading)
                    .help("The minimum viewport width where a breakpoint’s settings begin to apply.")
                Text("Container max width")
                    .frame(width: ThemeBreakpointColumns.container, alignment: .leading)
                    .help("Limits the width of blocks that use Foundry’s theme container sizing. It does not limit the whole page.")
                Spacer(minLength: 12)
                Text("Enabled")
                    .frame(width: ThemeBreakpointColumns.toggle)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(height: 24)
            .accessibilityAddTraits(.isHeader)

            Divider()
            ForEach(ThemeScreenID.allCases) { id in
                ThemeBreakpointRow(
                    screen: screens.screen(id),
                    mobileRange: mobileRange,
                    editor: editor
                )
                Divider()
            }
        }
    }

    private var mobileRange: String {
        guard let next = screens.enabledScreens.first(where: { $0.id != .mobile }) else {
            return "All widths"
        }
        return "Below \(next.id.shortTitle)"
    }
}

private enum ThemeBreakpointColumns {
    static let identity: CGFloat = 86
    static let minimumWidth: CGFloat = 124
    static let container: CGFloat = 196
    static let toggle: CGFloat = 54
}

private struct ThemeBreakpointRow: View {
    let screen: ThemeScreen
    let mobileRange: String
    let editor: ProjectEditor

    var body: some View {
        HStack(spacing: 12) {
            identity
            minimumWidth.frame(width: ThemeBreakpointColumns.minimumWidth, alignment: .leading)
            containerControls
            Spacer(minLength: 12)
            enabled
        }
        .frame(minHeight: 62)
        .accessibilityElement(children: .contain)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            Text(screen.id == .mobile ? "Mobile" : screen.id.shortTitle)
                .fontWeight(.medium)
                .frame(width: 54, alignment: .trailing)
            Image(systemName: screen.id.systemImage)
                .foregroundStyle(.secondary)
                .font(.callout)
                .accessibilityHidden(true)
        }
        .frame(width: ThemeBreakpointColumns.identity, alignment: .leading)
        .help(screen.id == .mobile ? "Mobile (XS) is the base size and is always enabled." : "\(screen.id.shortTitle) breakpoint")
    }

    @ViewBuilder private var enabled: some View {
        if screen.id == .mobile {
            Color.clear.frame(width: ThemeBreakpointColumns.toggle, height: 22).accessibilityHidden(true)
        } else {
            Toggle("Enable \(screen.id.shortTitle)", isOn: Binding(
                get: { screen.isEnabled },
                set: { editor.setThemeScreenEnabled(screen.id, value: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(width: ThemeBreakpointColumns.toggle)
            .help("Enable this breakpoint. Turning it off keeps its values for later.")
        }
    }

    @ViewBuilder private var minimumWidth: some View {
        if screen.id == .mobile {
            Text(mobileRange)
                .foregroundStyle(.secondary)
                .help("Applies below the first enabled breakpoint, or at every width if all other breakpoints are off.")
        } else {
            ThemeBreakpointNumberField(
                title: "\(screen.id.shortTitle) minimum width",
                value: Binding(get: { screen.minimumWidth }, set: { editor.setThemeScreenMinimumWidth(screen.id, value: $0) }),
                unit: "px"
            )
            .disabled(!screen.isEnabled)
            .help("The minimum viewport width for this breakpoint, in pixels.")
        }
    }

    private var containerControls: some View {
        HStack(spacing: 10) {
            if screen.container.unit != .auto {
                ThemeBreakpointNumberField(
                    title: "\(screen.id.shortTitle) maximum container width",
                    value: Binding(
                        get: { screen.container.value },
                        set: { editor.setThemeScreenContainerWidth(screen.id, value: $0) }
                    )
                )
                .frame(width: 96, alignment: .leading)
                .disabled(!screen.isEnabled)
                .help("The maximum container width, using the selected unit.")
            }

            Picker("\(screen.id.shortTitle) container unit", selection: Binding(
                get: { screen.container.unit },
                set: { editor.setThemeScreenContainerUnit(screen.id, value: $0) }
            )) {
                Text("Auto").tag(ThemeContainerUnit.auto)
                Text("px").tag(ThemeContainerUnit.pixels)
                Text("vw").tag(ThemeContainerUnit.viewportWidth)
                Text("%").tag(ThemeContainerUnit.percent)
            }
            .labelsHidden()
            .frame(width: 90, alignment: .leading)
            .disabled(!screen.isEnabled)
            .accessibilityValue(screen.container.unit.title)
            .help(screen.id == .mobile
                  ? "Auto sets no maximum container width for Mobile. px is pixels, vw is a percentage of the viewport, and % is a percentage of the parent container."
                  : "Auto follows this breakpoint’s starting width; it does not mean unlimited. px is pixels, vw is a percentage of the viewport, and % is a percentage of the parent container.")
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: ThemeBreakpointColumns.container, alignment: .leading)
    }
}

private struct ThemeBreakpointNumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, value: $value, format: .number.grouping(.never).precision(.fractionLength(0...2)))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .accessibilityLabel(title)
            Stepper(title, value: $value, step: 1)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Adjust \(title)")
            if let unit {
                Text(unit).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
