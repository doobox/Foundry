import Foundation
import SwiftUI

extension AttributeScopes {
    /// SwiftUI's editing attributes plus Foundry's palette colour reference,
    /// so the editor preserves and reports the reference like any built-in
    /// attribute instead of stripping it as unknown.
    struct FoundryRichTextAttributes: AttributeScope {
        let colourReference: FoundryRichTextColourAttribute
        let swiftUI: SwiftUIAttributes
    }

    var foundryRichText: FoundryRichTextAttributes.Type { FoundryRichTextAttributes.self }
}

struct PageTextEditorView: View {
    private static let defaultFontSize = 16.0

    @Environment(\.self) private var environment
    @FocusState private var editorIsFocused: Bool
    @State private var text: AttributedString
    private let originalText: AttributedString
    @State private var closeRequested = false
    @State private var selection = AttributedTextSelection()
    @State private var rememberedSelection = AttributedTextSelection()
    @State private var linkDraft = PartLink()
    @State private var selectionHasLink = false
    @State private var showsLinkEditor = false
    @State private var showsColourPicker = false
    @State private var popoverReference: RichTextColourReference?
    @State private var foregroundPreviews: [String: String] = [:]
    @State private var popoverColor: Color?

    let theme: Theme
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let publicURL: String
    let cancel: () -> Void
    let save: (String) -> Void

    init(
        value: String,
        theme: Theme,
        pages: [Page],
        folders: [PageFolder],
        assets: [ProjectAsset],
        publicURL: String,
        cancel: @escaping () -> Void,
        save: @escaping (String) -> Void
    ) {
        let initialText = RichTextHTMLCodec.attributedString(from: value, palettes: theme.colourPalettes)
        originalText = initialText
        _text = State(initialValue: initialText)
        self.theme = theme
        self.pages = pages
        self.folders = folders
        self.assets = assets
        self.publicURL = publicURL
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            TextEditor(text: $text, selection: $selection)
                .attributedTextFormattingDefinition(\.foundryRichText)
                .font(.system(size: Self.defaultFontSize))
                .focused($editorIsFocused)
                .padding(14)
            Divider()
            HStack {
                Text(countSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { closeRequested = true }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(RichTextHTMLCodec.storageValue(from: text, environment: environment))
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .rememberedEditorSize("text", minimum: CGSize(width: 680, height: 440), defaultSize: CGSize(width: 820, height: 580))
        .editorCloseHandling(requested: $closeRequested, hasChanges: text != originalText, close: cancel)
        .onAppear { editorIsFocused = true }
        .task(id: foregroundPreviewCSS) { await resolveForegroundPreviews() }
    }

    // Sheets place `.toolbar` items in the bottom accessory bar on macOS, so
    // the top bar stays a custom row of native controls.
    private var toolbar: some View {
        HStack(spacing: 10) {
            ControlGroup {
                Button {
                    changeFontSize(by: -1)
                } label: {
                    Image(systemName: "minus")
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(fontSize <= 9)
                .help("Decrease text size (⌘−)")

                Button {
                    setFontSize(Self.defaultFontSize)
                } label: {
                    Text("\(Int(fontSize.rounded()))")
                        .monospacedDigit()
                        .frame(minWidth: 24)
                }
                .help("Reset text size to 16 pt")

                Button {
                    changeFontSize(by: 1)
                } label: {
                    Image(systemName: "plus")
                }
                // The +/= key without Shift produces "="; a hidden alias
                // catches an explicit ⇧⌘+ so both chords work.
                .keyboardShortcut("=", modifiers: .command)
                .background {
                    Button("") { changeFontSize(by: 1) }
                        .keyboardShortcut("+", modifiers: .command)
                        .hidden()
                }
                .disabled(fontSize >= 72)
                .help("Increase text size (⌘+)")
            }
            .controlGroupStyle(.navigation)
            .fixedSize()

            Divider().frame(height: 22)

            ControlGroup {
                formatButton("bold", help: "Bold (⌘B)", isActive: isBold) {
                    toggleFontTrait(\.isBold)
                }
                .keyboardShortcut("b", modifiers: .command)
                formatButton("italic", help: "Italic (⌘I)", isActive: isItalic) {
                    toggleFontTrait(\.isItalic)
                }
                .keyboardShortcut("i", modifiers: .command)
                formatButton("underline", help: "Underline (⌘U)", isActive: isUnderlined) {
                    transformSelection { attributes in
                        attributes.underlineStyle = attributes.underlineStyle == nil ? .single : nil
                    }
                }
                .keyboardShortcut("u", modifiers: .command)
                formatButton("strikethrough", help: "Strikethrough (⇧⌘X)", isActive: isStruckThrough) {
                    transformSelection { attributes in
                        attributes.strikethroughStyle = attributes.strikethroughStyle == nil ? .single : nil
                    }
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            }
            .controlGroupStyle(.navigation)
            .fixedSize()

            Button {
                rememberedSelection = selection
                let attributes = selection.typingAttributes(in: text)
                popoverReference = attributes[FoundryRichTextColourAttribute.self]
                popoverColor = attributes.foregroundColor
                showsColourPicker = true
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(swatchColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.secondary.opacity(0.4), lineWidth: 1)
                    }
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Text colour")
            .accessibilityLabel("Text colour")
            .popover(isPresented: $showsColourPicker, arrowEdge: .bottom) {
                RichTextColourPicker(
                    theme: theme,
                    reference: popoverReference,
                    previews: foregroundPreviews,
                    apply: applyColourReference
                )
            }

            Button {
                rememberedSelection = selection
                linkDraft = selectedLink
                selectionHasLink = currentAttributes.link != nil
                showsLinkEditor = true
            } label: {
                Image(systemName: "link")
                    .frame(width: 18, height: 18)
            }
            .keyboardShortcut("k", modifiers: .command)
            .help("Add or edit link (⌘K)")
            .popover(isPresented: $showsLinkEditor, arrowEdge: .bottom) {
                PartLinkEditor(
                    link: $linkDraft,
                    pages: pages,
                    folders: folders,
                    assets: assets,
                    assetLibrary: assets.map(ProjectAssetNode.asset),
                    anchorsForPage: { _ in [] },
                    publicURL: publicURL,
                    absoluteURL: false,
                    // Dismiss first and mutate a turn later: applying while the
                    // popover's dismissal commit is in flight opens a nested CA
                    // transaction (text relayout + focus restore mid-commit).
                    remove: selectionHasLink ? {
                        showsLinkEditor = false
                        Task { @MainActor in
                            applyLink(nil)
                        }
                    } : nil,
                    cancel: { showsLinkEditor = false },
                    apply: {
                        showsLinkEditor = false
                        Task { @MainActor in
                            applyLink(linkDraft)
                        }
                    }
                )
            }

            Spacer()

            Menu {
                Button("Clear All Formatting", action: clearAllFormatting)
                    .disabled(text.characters.isEmpty)
                Button("Clear Selected Formatting", action: clearSelectedFormatting)
                    .disabled(!hasSelectedText)
            } label: {
                Image(systemName: "eraser")
                    .frame(width: 18, height: 18)
            }
            .help("Clear formatting")
            .accessibilityLabel("Clear formatting")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func formatButton(
        _ systemImage: String,
        help: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .background(isActive ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .help(help)
    }

    private var currentAttributes: AttributeContainer {
        selection.typingAttributes(in: text)
    }

    private var resolvedFont: Font.Resolved? {
        currentAttributes.font?.resolve(in: environment.fontResolutionContext)
    }

    private var isBold: Bool { resolvedFont?.isBold ?? false }
    private var isItalic: Bool { resolvedFont?.isItalic ?? false }
    private var isUnderlined: Bool { currentAttributes.underlineStyle != nil }
    private var isStruckThrough: Bool { currentAttributes.strikethroughStyle != nil }
    private var fontSize: Double { Double(resolvedFont?.pointSize ?? CGFloat(Self.defaultFontSize)) }
    private var textColor: Color { currentAttributes.foregroundColor ?? .primary }

    /// While the popover is open the session state is authoritative: presenting
    /// it can collapse the live selection, and selection values don't reliably
    /// re-report attributes changed underneath them mid-session.
    private var swatchColor: Color {
        if showsColourPicker {
            return popoverColor ?? .primary
        }
        return currentAttributes.foregroundColor ?? .primary
    }
    private var selectedLink: PartLink {
        currentAttributes.link.map(FoundryRichTextCodec.partLink(from:)) ?? .init()
    }

    private var countSummary: String {
        let characters = text.characters.count
        let words = text.characters.split(whereSeparator: \Character.isWhitespace).count
        return "\(words) \(words == 1 ? "word" : "words")  ·  \(characters) \(characters == 1 ? "character" : "characters")"
    }

    private func changeFontSize(by amount: Double) {
        setFontSize(min(max(fontSize + amount, 9), 72))
    }

    private func setFontSize(_ size: Double) {
        transformSelection { attributes in
            let resolved = attributes.font?.resolve(in: environment.fontResolutionContext)
            attributes.font = Self.font(
                size: size,
                bold: resolved?.isBold ?? false,
                italic: resolved?.isItalic ?? false
            )
        }
    }

    private func toggleFontTrait(_ keyPath: KeyPath<Font.Resolved, Bool>) {
        let active = resolvedFont?[keyPath: keyPath] ?? false
        transformSelection { attributes in
            let resolved = attributes.font?.resolve(in: environment.fontResolutionContext)
            attributes.font = Self.font(
                size: Double(resolved?.pointSize ?? CGFloat(Self.defaultFontSize)),
                bold: keyPath == \.isBold ? !active : (resolved?.isBold ?? false),
                italic: keyPath == \.isItalic ? !active : (resolved?.isItalic ?? false)
            )
        }
    }

    private func applyColourReference(_ reference: RichTextColourReference) {
        // The reference is authoritative; the resolved light-appearance colour
        // is only the editor's WYSIWYG rendering of it.
        let display = (reference.foregroundToken.flatMap { foregroundPreviews[$0.id] }
            ?? reference.resolve(in: theme.colourPalettes, appearance: .light))
            .flatMap { Color(hex: $0) }
        popoverReference = reference
        popoverColor = display
        transformRememberedSelection { attributes in
            attributes[FoundryRichTextColourAttribute.self] = reference
            attributes.foregroundColor = display
        }
    }

    private var foregroundPreviewCSS: String {
        BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.canvas(theme: theme, appearance: .light)
            + BootstrapThemeCSS.render(theme: theme)
    }

    private func resolveForegroundPreviews() async {
        let tokens = PartColourToken.groups(for: ["foregrounds"], palettes: theme.colourPalettes).flatMap { $0.1 }
        do {
            let colours = try await BootstrapScalePreviewResolver().resolve(
                expressions: tokens.map { "var(--bs-\($0))" }, css: foregroundPreviewCSS, mode: "light")
            try Task.checkCancellation()
            foregroundPreviews = Dictionary(uniqueKeysWithValues: zip(tokens, colours))
            var updated = text
            for run in text.runs {
                guard let token = run[FoundryRichTextColourAttribute.self]?.foregroundToken else { continue }
                updated[run.range].foregroundColor = foregroundPreviews[token.id].flatMap { Color(hex: $0) }
            }
            text = updated
            if let token = popoverReference?.foregroundToken {
                popoverColor = foregroundPreviews[token.id].flatMap { Color(hex: $0) }
            }
        } catch {
            if !Task.isCancelled { foregroundPreviews = [:] }
        }
    }

    /// Applies to the selection captured when the colour popover opened —
    /// presenting the popover collapses the live selection — and keeps that
    /// capture valid across successive picks while it stays open.
    private func transformRememberedSelection(_ transform: (inout AttributeContainer) -> Void) {
        var target = rememberedSelection
        text.transformAttributes(in: &target, body: transform)
        rememberedSelection = target
        selection = target
    }

    private func transformSelection(_ transform: (inout AttributeContainer) -> Void) {
        text.transformAttributes(in: &selection, body: transform)
        editorIsFocused = true
    }

    private var hasSelectedText: Bool {
        if case .ranges(let ranges) = selection.indices(in: text) {
            return !ranges.isEmpty
        }
        return false
    }

    private func clearAllFormatting() {
        text.transform(updating: &selection) { value in
            value.setAttributes(AttributeContainer())
        }
        editorIsFocused = true
    }

    private func clearSelectedFormatting() {
        guard hasSelectedText else { return }
        transformSelection { $0 = AttributeContainer() }
    }

    private func applyLink(_ value: PartLink?) {
        var target = rememberedSelection
        text.transformAttributes(in: &target) { attributes in
            attributes.link = value.flatMap(FoundryRichTextCodec.URL(for:))
        }
        selection = target
        editorIsFocused = true
    }

    private static func font(size: Double, bold: Bool, italic: Bool) -> Font {
        var font = Font.system(size: size)
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }
}


#Preview {
    PageTextEditorView(
        value: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
        theme: .standard,
        pages: [],
        folders: [],
        assets: [],
        publicURL: "",
        cancel: {},
        save: { _ in }
    )
}

private enum RichTextHTMLCodec {
    private static let defaultFontSize = 16.0

    static func attributedString(from storedValue: String, palettes: [ColourPalette]) -> AttributedString {
        guard let fragment = FoundryRichTextCodec.htmlFragment(from: storedValue) else {
            return AttributedString(storedValue)
        }
        return HTMLFragmentParser.parse(fragment, palettes: palettes) ?? AttributedString(fragment)
    }

    static func storageValue(from attributedString: AttributedString, environment: EnvironmentValues) -> String {
        guard hasRichFormatting(attributedString, environment: environment) else {
            return String(attributedString.characters)
        }

        var result = ""
        for run in attributedString.runs {
            let source = String(attributedString[run.range].characters)
            result += html(for: source, run: run, environment: environment)
        }
        return FoundryRichTextCodec.storageValue(forHTMLFragment: result)
    }

    private static func hasRichFormatting(
        _ value: AttributedString,
        environment: EnvironmentValues
    ) -> Bool {
        value.runs.contains { run in
            let font = run.font?.resolve(in: environment.fontResolutionContext)
            return font?.isBold == true ||
                font?.isItalic == true ||
                (font.map { abs(Double($0.pointSize) - defaultFontSize) > 0.1 } ?? false) ||
                run.underlineStyle != nil ||
                run.strikethroughStyle != nil ||
                run.link != nil ||
                run.foregroundColor != nil ||
                run[FoundryRichTextColourAttribute.self] != nil
        }
    }

    private static func html(
        for source: String,
        run: AttributedString.Runs.Run,
        environment: EnvironmentValues
    ) -> String {
        let font = run.font?.resolve(in: environment.fontResolutionContext)
        var value = escape(source)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")

        if run.strikethroughStyle != nil { value = "<s>\(value)</s>" }
        if run.underlineStyle != nil { value = "<u>\(value)</u>" }
        if font?.isItalic == true { value = "<em>\(value)</em>" }
        if font?.isBold == true { value = "<strong>\(value)</strong>" }

        var styles: [String] = []
        if let font, abs(Double(font.pointSize) - defaultFontSize) > 0.1 {
            let size = Double(font.pointSize).formatted(
                .number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...1))
            )
            styles.append("font-size:\(size)px")
        }
        let reference = run[FoundryRichTextColourAttribute.self]
        // A palette reference owns the colour; a literal foregroundColor only
        // serialises when no reference exists (e.g. content pasted with one).
        if reference == nil, let color = run.foregroundColor {
            styles.append("color:\(hexColor(color.resolve(in: environment)))")
        }
        if !styles.isEmpty {
            value = "<span style=\"\(styles.joined(separator: ";"))\">\(value)</span>"
        }
        if let reference {
            value = "<span data-foundry-color=\"\(escapeAttribute(reference.marker))\">\(value)</span>"
        }

        if let link = run.link?.absoluteString, !link.isEmpty {
            value = "<a href=\"\(escapeAttribute(link))\">\(value)</a>"
        }
        return value
    }

    private static func hexColor(_ color: Color.Resolved) -> String {
        String(
            format: "#%02X%02X%02X",
            Int((color.red * 255).rounded()),
            Int((color.green * 255).rounded()),
            Int((color.blue * 255).rounded())
        )
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escape(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private final class HTMLFragmentParser: NSObject, XMLParserDelegate {
    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var fontSize = 16.0
        var color: Color?
        var colourReference: RichTextColourReference?
        var link: URL?
    }

    private let palettes: [ColourPalette]
    private var result = AttributedString()
    private var styles = [Style()]

    private init(palettes: [ColourPalette]) {
        self.palettes = palettes
    }

    static func parse(_ fragment: String, palettes: [ColourPalette]) -> AttributedString? {
        let normalized = fragment
            .replacingOccurrences(of: #"(?i)<br\s*>"#, with: "<br/>", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: "&#160;")
        guard let data = "<root>\(normalized)</root>".data(using: .utf8) else { return nil }
        let delegate = HTMLFragmentParser(palettes: palettes)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.result
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.lowercased()
        guard element != "root" else { return }

        var style = styles.last ?? Style()
        switch element {
        case "strong", "b":
            style.bold = true
        case "em", "i":
            style.italic = true
        case "u":
            style.underline = true
        case "s", "strike", "del":
            style.strikethrough = true
        case "span":
            applyInlineStyle(attributeDict["style"], to: &style)
            if let marker = attributeDict["data-foundry-color"],
               let reference = RichTextColourReference(marker: marker) {
                style.colourReference = reference
                style.color = reference.resolve(in: palettes, appearance: .light)
                    .flatMap { Color(hex: $0) }
            }
        case "a":
            style.link = attributeDict["href"].flatMap(URL.init(string:))
        case "br":
            append("\n", style: style)
        default:
            break
        }
        styles.append(style)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() != "root", styles.count > 1 else { return }
        styles.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        append(string, style: styles.last ?? Style())
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        append(string, style: styles.last ?? Style())
    }

    private func append(_ string: String, style: Style) {
        guard !string.isEmpty else { return }
        var value = AttributedString(string)
        var attributes = AttributeContainer()

        if style.bold || style.italic || abs(style.fontSize - 16) > 0.1 {
            var font = Font.system(size: style.fontSize)
            if style.bold { font = font.bold() }
            if style.italic { font = font.italic() }
            attributes.font = font
        }
        if style.underline { attributes.underlineStyle = .single }
        if style.strikethrough { attributes.strikethroughStyle = .single }
        attributes.foregroundColor = style.color
        attributes[FoundryRichTextColourAttribute.self] = style.colourReference
        attributes.link = style.link
        value.mergeAttributes(attributes)
        result.append(value)
    }

    private func applyInlineStyle(_ source: String?, to style: inout Style) {
        guard let source else { return }
        for declaration in source.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "font-size":
                let value = parts[1].lowercased().replacingOccurrences(of: "px", with: "")
                if let size = Double(value) { style.fontSize = size }
            case "color":
                style.color = color(from: parts[1])
            default:
                break
            }
        }
    }

    private func color(from source: String) -> Color? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#"), value.count == 7,
              let rgb = Int(value.dropFirst(), radix: 16) else { return nil }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
