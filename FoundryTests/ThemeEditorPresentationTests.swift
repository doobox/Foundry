import AppKit
import SwiftUI
import Testing
@testable import Foundry

@MainActor
@Suite(.serialized)
struct ThemeEditorPresentationTests {
    @Test
    func previewUsesStoredPalettesAndPreservesEditingSettings() throws {
        let model = ThemeColourPreviewModel()
        let source = model.palettes.first { $0.group == .custom }!
        var edit = PreviewShadeEdit(palette: source, index: 10)
        edit.setHex("#250C42")
        edit.setSoftening(0.7)
        edit.setReversed(true)
        model.update(edit.palette, session: UUID(), undoManager: nil)
        let encoded = try JSONEncoder().encode(model.storedPalettes)
        let reloaded = ThemeColourPreviewModel(storedPalettes: try JSONDecoder().decode([ColourPalette].self, from: encoded))
        #expect(reloaded.storedPalettes == model.storedPalettes)
        let restored = reloaded.palettes.first { $0.id == source.id }!
        #expect(restored == edit.palette)
        for index in 0..<11 {
            #expect(restored.colour(at: index).hexString == edit.palette.colour(at: index).hexString)
        }
        var custom = restored
        custom.generated = false
        custom.setColour(Color(hex: "#FF0000")!, at: 3)
        reloaded.update(custom, session: UUID(), undoManager: nil)
        let record = reloaded.storedPalettes.first { $0.id == custom.id }!
        #expect(record.generation?.enabled == false)
        #expect(record.shades[3] == "#FF0000")
        #expect(PreviewColourPalette(stored: record).storedValue == record)
    }

    @Test
    func storedShadesAreNotRegeneratedOnReadOrRename() throws {
        let original = PreviewColourPalette.samples.first { $0.group == .theme }!.storedValue
        var record = original
        try record.replaceShades(Array(repeating: "#123456", count: 11))
        var adapter = PreviewColourPalette(stored: record)
        adapter.name = "Renamed"
        #expect(adapter.storedValue.shades == record.shades)
        #expect(adapter.storedValue.id == record.id)
        #expect(PreviewColourPalette.samples.first { $0.group == .theme }!.id == original.id)
    }

    @Test
    func deletedColourBindingsRemainSafe() {
        let model = ThemeColourPreviewModel()
        let custom = model.palettes.first { $0.group == .custom }!
        let binding = model.binding(for: custom)
        let other = model.palettes.last!
        let otherBinding = model.binding(for: other)
        model.delete(id: custom.id)
        #expect(binding.wrappedValue == custom)
        var lateEdit = custom
        lateEdit.name = "Late edit"
        binding.wrappedValue = lateEdit
        #expect(!model.palettes.contains { $0.id == custom.id })
        #expect(otherBinding.wrappedValue == other)
        model.delete(id: other.id)
        #expect(model.palettes.contains { $0.id == other.id })
    }

    @Test
    func softeningFirstPreservesSelectedShadeAndDefault() {
        let palette = PreviewColourPalette(name: "Test", hex: "#F97316", group: .custom)
        for index in 0..<11 {
            var edit = PreviewShadeEdit(palette: palette, index: index)
            let selectedHex = palette.colour(at: index).hexString
            #expect(edit.palette == palette)
            edit.setSoftening(0)
            #expect(edit.palette == palette)
            for amount in [0.25, 1.0, 0.5, 0.0] {
                edit.setSoftening(amount)
                #expect(edit.palette.anchor == index)
                #expect(edit.palette.colour(at: index).hexString == selectedHex)
                #expect(edit.palette.defaultShade == palette.defaultShade)
            }
        }
    }

    @Test
    func liveColourEditsCoalesceAndSupportUndoRedo() {
        let model = ThemeColourPreviewModel()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let original = model.palettes[0]
        let session = UUID()
        model.update(original, session: session, undoManager: undo)
        #expect(!undo.canUndo)
        var changed = original
        changed.hex = "#123456"
        undo.beginUndoGrouping()
        model.update(changed, session: session, undoManager: undo)
        undo.endUndoGrouping()
        changed.softening = 0.6
        model.update(changed, session: session, undoManager: undo)
        #expect(model.palettes[0] == changed)
        undo.undo()
        #expect(model.palettes[0] == original)
        #expect(!undo.canUndo)
        undo.redo()
        #expect(model.palettes[0] == changed)
    }

    @Test
    func softenBlendsContinuouslyAndReversePreservesColours() {
        var palette = PreviewColourPalette(name: "Test", hex: "#250C42", group: .custom, anchor: 4, defaultShade: 4)
        #expect(palette.softening == 0)
        let full = PreviewPerceptualRamp.lab(NSColor(palette.colour(at: 0))).lightness
        palette.softening = 1
        let soft = PreviewPerceptualRamp.lab(NSColor(palette.colour(at: 0))).lightness
        palette.softening = 0.5
        let middle = PreviewPerceptualRamp.lab(NSColor(palette.colour(at: 0))).lightness
        #expect(abs(middle - (full + soft) / 2) < 0.00001)
        #expect(palette.colour(at: 4).hexString?.uppercased() == "#250C42")
        for custom in [false, true] {
            palette.generated = !custom
            if custom { palette.overrides[2] = "#ABCDEF" }
            let before = (0..<11).map { palette.colour(at: $0).hexString }
            let originalDefault = palette.defaultShade
            var edit = PreviewShadeEdit(palette: palette, index: palette.anchor)
            edit.setReversed(true)
            #expect(edit.index == 10 - palette.anchor)
            #expect(edit.palette.defaultShade == 10 - originalDefault)
            #expect((0..<11).map { edit.palette.colour(at: $0).hexString } == Array(before.reversed()))
            edit.setReversed(false)
            #expect((0..<11).map { edit.palette.colour(at: $0).hexString } == before)
            #expect(edit.palette.defaultShade == originalDefault)
        }
    }

    @Test
    func colourEditsKeepDefaultUntilExplicitlyChanged() {
        let palette = PreviewColourPalette(name: "Test", hex: "#6366F1", group: .custom)
        var edit = PreviewShadeEdit(palette: palette, index: 4)
        #expect(edit.palette.defaultShade == 5)
        edit.setHex("#250C42")
        #expect(edit.palette.defaultShade == 5)
        #expect(edit.palette.anchor == 4)
        edit.setUseAsDefault(true)
        #expect(edit.palette.defaultShade == 4)
        edit.setColour(Color(hex: "#450C42")!)
        #expect(edit.palette.defaultShade == 4)
        edit.setUseAsDefault(false)
        edit.setHex("#350C42")
        #expect(edit.palette.defaultShade == 5)
        var custom = palette
        custom.generated = false
        var customEdit = PreviewShadeEdit(palette: custom, index: 4)
        customEdit.setHex("#250C42")
        #expect(customEdit.palette.defaultShade == 5)
    }

    @Test
    func perceptualRampPreservesAnchorAndLightnessOrder() {
        for hex in ["#250C42", "#FFFF00", "#0000FF", "#FF0000", "#00FF00", "#808080", "#FFFFFF", "#000000", "#FDFDFD"] {
            for anchor in 0..<11 {
                let palette = PreviewColourPalette(name: "Test", hex: hex, group: .custom, anchor: anchor, softening: 1)
                #expect(palette.colour(at: anchor).hexString?.uppercased() == hex)
                let levels = (0..<11).map { index in
                    PreviewPerceptualRamp.lab(NSColor(palette.colour(at: index))).lightness
                }
                #expect(levels.allSatisfy { $0.isFinite && $0 >= -0.00001 && $0 <= 1.00001 })
                for index in 0..<10 { #expect(levels[index] + 0.00001 >= levels[index + 1]) }
            }
        }
        let purple = PreviewColourPalette(name: "Test", hex: "#250C42", group: .custom, anchor: 4, softening: 1)
        let levels = (0..<11).map { PreviewPerceptualRamp.lab(NSColor(purple.colour(at: $0))).lightness }
        #expect(abs((levels[3] - levels[4]) - (levels[4] - levels[5])) < 0.02)
        #expect(levels[0] < 0.7) // Do not force this dark colour's light end almost to white.
        let red = PreviewPerceptualRamp.lab(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        #expect(abs(red.lightness - 0.627955) < 0.00001)
        #expect(abs(red.a - 0.224863) < 0.00001)
    }

    @Test
    func shadeDraftDoesNotChangeOriginalAndValidatesHex() {
        let original = PreviewColourPalette(name: "Test", hex: "#6366F1", group: .custom)
        var edit = PreviewShadeEdit(palette: original, index: 7)
        edit.setHex(edit.hex)
        #expect(edit.palette.anchor == original.anchor)
        edit.setHex(" #abc ")
        #expect(edit.palette.anchor == 7)
        #expect(edit.palette.colour(at: 7).hexString?.uppercased() == "#AABBCC")
        #expect(original.hex == "#6366F1")
        #expect(original.anchor == 5)
        edit.setHex("#nope")
        #expect(PreviewShadeEdit.normalizedHex(edit.hex) == nil)
        #expect(edit.palette.colour(at: 7).hexString?.uppercased() == "#AABBCC")
        #expect(PreviewShadeEdit.normalizedHex("12345678") == nil)
        #expect(PreviewShadeEdit.normalizedHex("#12345G") == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FOUNDRY_CAPTURE_THEME_UI"] == "1"))
    func captureShadePopover() async throws {
        let palette = PreviewColourPalette(name: "Accent", hex: "#6366F1", group: .custom)
        let root = PreviewShadeEditor(original: palette, index: 5, change: { _ in })
            .environment(\.colorScheme, .dark)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 332, height: 410),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = controller
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        defer { window.close() }
        try await settle(controller.view)
        let output = URL(fileURLWithPath: "/tmp/FoundryThemeEditorQA", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try capture(controller.view, to: output.appendingPathComponent("shade-popover.png"))
    }

    @Test
    func colourPreviewKeepsAnchorAndDuplicateIdentity() {
        let model = ThemeColourPreviewModel()
        let standard = model.palettes.first { $0.name == "Blue" }!
        model.duplicate(standard)
        #expect(model.palettes[0].id != standard.id)
        #expect(model.palettes[0].group == .custom)
        var palette = model.palettes[0]
        #expect(palette.colour(at: 2).hexString == standard.colour(at: 2).hexString)
        palette.generated = true
        palette.setColour(Color(hex: "#123456")!, at: 7)
        #expect(palette.anchor == 7)
        #expect(palette.colour(at: 7).hexString?.lowercased() == "#123456")
        #expect(palette.defaultShade == 5)
        palette.generated = false
        palette.setColour(Color(hex: "#ABCDEF")!, at: 2)
        #expect(palette.anchor == 7)
        #expect(palette.colour(at: 2).hexString?.lowercased() == "#abcdef")
        #expect(model.palettes.first { $0.id == standard.id }?.hex == standard.hex)
    }

    @Test
    func presetLabelsAreConsistentWithoutRenamingCustomStyles() {
        #expect(themeScaleTitle(id: "base", fallback: "base") == "MD")
        #expect(themeScaleTitle(id: "xs", fallback: "xs") == "XS")
        #expect(themeScaleTitle(id: "2xl", fallback: "2xl") == "2XL")
        #expect(themeScaleTitle(id: "full", fallback: "full") == "Full")
        #expect(themeScaleTitle(id: "none", fallback: "none") == "None")
        #expect(themeScaleTitle(id: "user-card-title", fallback: "Card title") == "Card title")
        #expect(themeScaleTitle(id: "custom:editorial-gap", fallback: "editorial gap") == "editorial gap")
    }

    /// Opt-in visual QA using the production views. Run with
    /// FOUNDRY_CAPTURE_THEME_UI=1 (or TEST_RUNNER_FOUNDRY_CAPTURE_THEME_UI=1 through xcodebuild).
    /// Breakpoints also captures mixed Auto, px, vw, and % containers, including a disabled custom value.
    /// PNGs and measurement notes are written outside the repository, without changing user defaults.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FOUNDRY_CAPTURE_THEME_UI"] == "1"))
    func captureNativeSectionsAtRepresentativeWindowSizes() async throws {
        let output = URL(fileURLWithPath: "/tmp/FoundryThemeEditorQA", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let sections: [ThemeWindowSection] = [
            .colors, .screens, .fontFamily, .fontSize, .spacing,
            .shadows, .borderWidth, .borderRadius
        ].filter {
            let requested = ProcessInfo.processInfo.environment["FOUNDRY_THEME_UI_SECTION"]
            return requested == nil || $0.rawValue == requested
        }
        let sizes: [(name: String, size: CGSize)] = [
            ("narrow", CGSize(width: 500, height: 620)),
            // 962 pt outer width minus the widest supported 240 pt sidebar.
            ("minimum", CGSize(width: 722, height: 504)),
            ("default", CGSize(width: 938, height: 620)),
            ("wide", CGSize(width: 1_590, height: 620))
        ]
        var measurements: [String] = []

        for section in sections {
            let variants = section == .screens ? ["", "-mixed-units"] : [""]
            for variant in variants {
                let document = FoundryDocument(site: fixtureSite(mixedContainerUnits: !variant.isEmpty))
                let originalTheme = document.site.theme
                let session = ThemeEditorSession(document: document, undoManager: UndoManager())
                for configuration in sizes {
                    let name = "\(section.rawValue)\(variant)-\(configuration.name)"
                    let previewModel = ThemeColourPreviewModel()
                    previewModel.palettes.insert(PreviewColourPalette(name: "Purple test", hex: "#250C42", group: .theme, anchor: 4, defaultShade: 4), at: 0)
                    let root = (section == .colors
                        ? AnyView(ThemeColoursPreview(model: previewModel))
                        : AnyView(ThemeSettingsDetail(
                        section: section,
                        theme: document.site.theme,
                        assets: [],
                        session: session
                    )))
                    .environment(\.colorScheme, .dark)

                    let controller = NSHostingController(rootView: root)
                    controller.sizingOptions = []
                    let window = NSWindow(
                        contentRect: CGRect(origin: .zero, size: configuration.size),
                        styleMask: [.titled, .closable, .resizable],
                        backing: .buffered,
                        defer: false
                    )
                    window.isReleasedWhenClosed = false
                    window.animationBehavior = .none
                    window.appearance = NSAppearance(named: .darkAqua)
                    window.title = "Theme Layout QA — \(name)"
                    window.contentViewController = controller
                    window.setContentSize(configuration.size)
                    // An attached backing window lets AppKit lay out native controls without taking focus.
                    window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
                    window.orderBack(nil)
                    defer { window.close() }

                    try await settle(controller.view)
                    let fitting = controller.sizeThatFits(in: configuration.size)
                    #expect(fitting.width.isFinite && fitting.height.isFinite, "\(name) returned a non-finite fitting size: \(fitting)")
                    #expect(fitting.width > 0 && fitting.height > 0, "\(name) returned an empty fitting size: \(fitting)")
                    #expect(fitting.width <= configuration.size.width + 1, "\(name) needs \(fitting.width) points at a \(configuration.size.width)-point detail width")
                    #expect(abs(controller.view.bounds.width - configuration.size.width) <= 1, "\(name) changed the requested hosting width")

                    let outerScroll = firstScrollView(in: controller.view)
                    if let outerScroll, let content = outerScroll.documentView {
                        let available = outerScroll.contentView.bounds.width
                        #expect(content.bounds.width <= available + 1, "\(name) has horizontal page overflow: \(content.bounds.width) > \(available)")
                        if section == .screens && configuration.name == "minimum" {
                            #expect(content.bounds.height <= outerScroll.contentView.bounds.height + 1,
                                    "All breakpoint rows should fit at the agreed minimum window size")
                        }
                        measurements.append("\(name): host=\(controller.view.bounds.size), fitting=\(fitting), scrollContent=\(content.bounds.size), viewport=\(outerScroll.contentView.bounds.size)")
                    } else {
                        measurements.append("\(name): host=\(controller.view.bounds.size), fitting=\(fitting); no AppKit scroll view exposed")
                    }

                    try capture(controller.view, to: output.appendingPathComponent("\(name)-top.png"))
                    if let outerScroll, let content = outerScroll.documentView,
                       content.bounds.height > outerScroll.contentView.bounds.height + 1 {
                        let bottom = max(0, content.bounds.height - outerScroll.contentView.bounds.height)
                        content.scroll(CGPoint(x: 0, y: content.isFlipped ? bottom : 0))
                        outerScroll.reflectScrolledClipView(outerScroll.contentView)
                        try await settle(controller.view)
                        try capture(controller.view, to: output.appendingPathComponent("\(name)-bottom.png"))
                    }
                }
                #expect(document.site.theme == originalTheme, "Presenting and resizing theme sections must not change stored theme values")
            }
        }

        try measurements.joined(separator: "\n").write(
            to: output.appendingPathComponent("measurements.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func fixtureSite(mixedContainerUnits: Bool = false) -> Site {
        var theme = Theme.standard
        theme.typography.customFontSizes = [
            .init(id: "user-layout-card-title", title: "Card title", size: 1.375, lineHeight: 1.25)
        ]
        theme.spacing.custom = [.init(name: "Editorial gap", value: 7.5)]
        theme.typography.customFonts = [
            .init(name: "Editorial", font: .system(family: "Georgia", weights: [400, 700]))
        ]
        theme.shadows.custom = [
            .init(id: "user-layout-floating-card", title: "Floating card", layers: [
                .init(x: 0, y: 8, blur: 24, opacity: 0.16)
            ])
        ]
        theme.screens.update(.extraLarge) { $0.isEnabled = false }
        theme.screens.update(.doubleExtraLarge) { $0.isEnabled = false }
        if mixedContainerUnits {
            theme.screens.update(.small) { $0.container = .init(value: 600, unit: .pixels) }
            theme.screens.update(.medium) { $0.container = .init(value: 92, unit: .viewportWidth) }
            theme.screens.update(.large) { $0.container = .init(value: 90, unit: .percent) }
            // Retained custom values remain visible when a breakpoint is disabled.
            theme.screens.update(.extraLarge) { $0.container = .init(value: 1_200, unit: .pixels) }
        }
        return Site(name: "Theme Layout QA", pages: [Page(title: "Home", slug: "index")], theme: theme)
    }

    private func settle(_ view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        // Yield to SwiftUI's scheduled layout and native control updates before measuring/capturing.
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = firstScrollView(in: child) { return scroll }
        }
        return nil
    }

    private func capture(_ view: NSView, to url: URL) throws {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        try data.write(to: url, options: .atomic)
    }
}
