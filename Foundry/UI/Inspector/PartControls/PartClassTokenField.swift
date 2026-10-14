import SwiftUI

/// A native macOS token field backed by the part model's space-separated CSS classes.
struct PartClassTokenField: NSViewRepresentable {
    @Binding var classes: String
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        field.suggestionsDelegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit(_:))
        field.controlSize = appKitControlSize
        field.tokenStyle = .rounded
        field.tokenizingCharacterSet = CharacterSet(charactersIn: ",")
        field.isAutomaticTextCompletionEnabled = true
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: appKitControlSize))
        field.isEditable = true
        field.isSelectable = true
        // isBordered = false also disables isBezeled; borderShape changes the
        // bezel style. Let the rounded native bezel own its appearance/insets.
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.setAccessibilityLabel("Add CSS class")

        field.cell?.isScrollable = false
        field.cell?.wraps = true
        field.cell?.usesSingleLineMode = false
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        let tokens = Self.tokens(in: classes)
        field.controlSize = appKitControlSize
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: appKitControlSize))
        field.isEnabled = isEnabled

        // Replacing objectValue while the field editor is active would erase
        // the user's unfinished completion query.
        if field.currentEditor() == nil,
           context.coordinator.tokens(in: field) != tokens {
            field.objectValue = tokens
        }

        field.placeholderString = tokens.isEmpty ? "Add class" : nil
        field.invalidateIntrinsicContentSize()
    }

    static func dismantleNSView(_ field: NSTokenField, coordinator: Coordinator) {
        field.delegate = nil
        field.suggestionsDelegate = nil
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView field: NSTokenField,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        field.preferredMaxLayoutWidth = width
        let measured = field.sizeThatFits(
            NSSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: measured.height)
    }

    private var appKitControlSize: NSControl.ControlSize {
        switch controlSize {
        case .mini: .mini
        case .small: .small
        case .regular: .regular
        case .large, .extraLarge: .large
        @unknown default: .small
        }
    }

    private static func tokens(in value: String) -> [String] {
        value.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    @MainActor
    final class Coordinator: NSObject, NSTokenFieldDelegate, NSTextSuggestionsDelegate {
        typealias SuggestionItemType = String
        var parent: PartClassTokenField
        private var pendingTokenCommits = 0

        init(parent: PartClassTokenField) {
            self.parent = parent
        }

        @objc func commit(_ sender: NSTokenField) {
            guard pendingTokenCommits == 0 else { return }
            syncClasses(from: sender)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            field.invalidateIntrinsicContentSize()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            guard pendingTokenCommits == 0 else { return }
            syncClasses(from: field)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let field = control as? NSTokenField else { return false }
            // NSTextField's default Return action selects the whole value.
            // Keep token editing active so the next class can't replace it.
            if let range = activeTokenRange(in: textView), range.length > 0 {
                textView.insertText(",", replacementRange: NSRange(
                    location: NSMaxRange(range), length: 0
                ))
            } else {
                let selection = textView.selectedRange()
                textView.setSelectedRange(NSRange(location: NSMaxRange(selection), length: 0))
            }
            field.invalidateIntrinsicContentSize()
            return true
        }

        func textField(
            _ textField: NSTextField,
            provideUpdatedSuggestions responseHandler: @escaping (ItemResponse) -> Void
        ) {
            // Token attachments delimit the active editing string. Read only
            // through the insertion point so a selected completion suffix
            // doesn't become part of the next query. Keep ':' and '-' intact.
            guard let editor = textField.currentEditor() as? NSTextView else {
                responseHandler(ItemResponse())
                return
            }
            let text = editor.string as NSString
            let insertion = editor.selectedRange().location
            guard insertion != NSNotFound, insertion <= text.length else {
                responseHandler(ItemResponse())
                return
            }
            guard let range = activeTokenRange(in: editor) else {
                responseHandler(ItemResponse())
                return
            }
            let query = text.substring(with: NSRange(
                location: range.location,
                length: insertion - range.location
            ))
            guard !query.isEmpty else {
                responseHandler(ItemResponse())
                return
            }

            let excluded = Set(PartClassTokenField.tokens(in: parent.classes))
            let foldedQuery = query.lowercased()
            let completions = BootstrapClassCatalog.shared.sortedNames.filter {
                !excluded.contains($0)
                    && $0.lowercased().hasPrefix(foldedQuery)
            }
            responseHandler(ItemResponse(items: completions.map {
                Item(representedValue: $0, title: $0)
            }))
        }

        func textField(_ textField: NSTextField, textCompletionFor item: Item) -> String? {
            // The default suggestion completion replaces the whole field,
            // including existing tokens. Selection below edits only the draft.
            nil
        }

        func textField(_ textField: NSTextField, didSelect item: Item) {
            guard let editor = textField.currentEditor() as? NSTextView,
                  let range = activeTokenRange(in: editor) else { return }
            // A comma invokes NSTokenField's native tokenization path, including
            // shouldAdd, without changing preceding/following token attachments.
            editor.insertText(item.representedValue + ",", replacementRange: range)
        }

        private func activeTokenRange(in editor: NSTextView) -> NSRange? {
            let text = editor.string as NSString
            let selection = editor.selectedRange()
            guard selection.location != NSNotFound,
                  NSMaxRange(selection) <= text.length else { return nil }
            let separators = CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: ",\u{FFFC}"))
            let before = NSRange(location: 0, length: selection.location)
            let boundary = text.rangeOfCharacter(from: separators, options: .backwards, range: before)
            let start = boundary.location == NSNotFound ? 0 : NSMaxRange(boundary)
            let after = NSRange(location: NSMaxRange(selection), length: text.length - NSMaxRange(selection))
            let nextBoundary = text.rangeOfCharacter(from: separators, options: [], range: after)
            let end = nextBoundary.location == NSNotFound ? text.length : nextBoundary.location
            return NSRange(location: start, length: end - start)
        }

        func tokenField(
            _ tokenField: NSTokenField,
            shouldAdd rawTokens: [Any],
            at index: Int
        ) -> [Any] {
            var excluded = Set(PartClassTokenField.tokens(in: parent.classes))
            var additions: [String] = []

            for rawToken in rawTokens {
                let query = String(describing: rawToken)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { continue }

                for name in PartClassTokenField.tokens(in: query)
                    where excluded.insert(name).inserted {
                    additions.append(name)
                }
            }

            // NSTokenField asks its delegate before it updates objectValue. Keep
            // the model in step with the accepted tokens immediately so the
            // Return action cannot briefly write the old, empty value back.
            var updated = PartClassTokenField.tokens(in: parent.classes)
            var insertionIndex = min(max(index, 0), updated.count)
            for addition in additions where !updated.contains(addition) {
                updated.insert(addition, at: insertionIndex)
                insertionIndex += 1
            }
            parent.classes = updated.joined(separator: " ")

            pendingTokenCommits += 1
            Task { @MainActor [weak self, weak tokenField] in
                guard let self, let tokenField else { return }
                pendingTokenCommits = max(0, pendingTokenCommits - 1)
                syncClasses(from: tokenField)
                tokenField.invalidateIntrinsicContentSize()
            }
            return additions
        }

        func tokens(in field: NSTokenField) -> [String] {
            if let values = field.objectValue as? [Any] {
                return values.compactMap { value in
                    let string = String(describing: value)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return string.isEmpty ? nil : string
                }
            }

            if let value = field.objectValue as? String {
                return PartClassTokenField.tokens(
                    in: value.replacingOccurrences(of: ",", with: " ")
                )
            }

            return []
        }

        private func syncClasses(from field: NSTokenField) {
            let fieldTokens = tokens(in: field)
            if fieldTokens.isEmpty,
               !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }

            let updated = fieldTokens.joined(separator: " ")
            if parent.classes != updated {
                parent.classes = updated
            }
        }
    }
}
