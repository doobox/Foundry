import AppKit
import SwiftUI

/// Size preferences belong to the editor on this Mac, not to the document.
struct EditorSheetSizing: ViewModifier {
    let key: String
    let minimum: CGSize
    let defaultSize: CGSize
    @State private var available: CGSize
    @State private var initialSize: CGSize

    init(key: String, minimum: CGSize, defaultSize: CGSize) {
        self.key = key
        self.minimum = minimum
        self.defaultSize = defaultSize
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        let parent = window?.sheetParent ?? window
        var available = defaultSize
        if let screen = parent?.screen ?? NSScreen.main {
            let frame = EditorSheetSizePersistence.Coordinator.availableFrame(parent: parent?.frame, screen: screen.visibleFrame)
            if !frame.isNull {
                let parentTop = parent.map { $0.convertToScreen($0.contentLayoutRect).maxY } ?? frame.maxY
                available = CGSize(width: frame.width, height: max(1, min(frame.maxY, parentTop) - frame.minY))
            }
        }
        let remembered = UserDefaults.standard.string(forKey: key).map(NSSizeFromString) ?? defaultSize
        _available = State(initialValue: available)
        _initialSize = State(initialValue: EditorSheetSizePersistence.Coordinator.clamped(
            remembered, minimum: minimum, available: available, fallback: defaultSize
        ))
    }

    func body(content: Content) -> some View {
        content
            .frame(minWidth: min(minimum.width, available.width), idealWidth: min(initialSize.width, available.width), maxWidth: .infinity,
                   minHeight: min(minimum.height, available.height), idealHeight: min(initialSize.height, available.height), maxHeight: .infinity)
            .presentationSizing(.fitted)
            .background(EditorSheetSizePersistence(key: key, minimum: minimum, defaultSize: defaultSize) { size in
                if available != size { available = size }
            })
    }
}

extension View {
    func rememberedEditorSize(_ key: String, minimum: CGSize, defaultSize: CGSize) -> some View {
        modifier(EditorSheetSizing(key: "editorSheet.\(key).contentSize", minimum: minimum, defaultSize: defaultSize))
    }
}
