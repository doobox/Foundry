import SwiftUI

/// Intercepts Tab before NSTextView turns it into a tab character or focus move.
/// Only the focused text view inside this editor's bounds receives the command.
struct SourceCodeIndentationKeys: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view] event in
            guard event.keyCode == 48,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let view, !view.isHiddenOrHasHiddenAncestor,
                  let window = view.window, event.window === window,
                  let textView = window.firstResponder as? NSTextView,
                  textView.isEditable, !textView.hasMarkedText(),
                  textView.selectedRanges.count == 1 else { return event }
            let editorBounds = view.convert(view.bounds, to: nil)
            let textBounds = textView.convert(textView.visibleRect, to: nil)
            guard editorBounds.contains(NSPoint(x: textBounds.midX, y: textBounds.midY)) else { return event }
            if let edit = SourceCodeIndentation.edit(textView.string, selection: textView.selectedRange(), unindent: event.modifierFlags.contains(.shift)) {
                textView.breakUndoCoalescing()
                textView.insertText(edit.replacement, replacementRange: edit.range)
                textView.setSelectedRange(edit.selection)
                textView.breakUndoCoalescing()
            }
            return nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    final class Coordinator {
        var monitor: Any?
    }
}
