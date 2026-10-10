import AppKit
import SwiftUI
import Testing
@testable import Foundry

@MainActor
@Suite(.serialized)
struct ThemeEditorPresentationTests {
    @Test
    func colourSectionsMapToDistinctFamilies() {
        #expect(ThemeWindowSection.colourSections.map(\.title) == ["Theme Colours", "Foreground", "Background", "Borders", "Links"])
        #expect(ThemeWindowSection.colourSections.compactMap(\.colourKind) == [.theme, .foreground, .surface, .border, .link])
        #expect(ThemeWindowSection.settings.allSatisfy { $0.colourKind == nil })
        #expect(ThemeWindowSection(rawValue: "colors")?.colourKind == .theme)
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
    /// FOUNDRY_CAPTURE_FRAMEWORK_UI=1 (or TEST_RUNNER_FOUNDRY_CAPTURE_FRAMEWORK_UI=1 through xcodebuild).
    /// PNGs and measurement notes are written outside the repository, without changing user defaults.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FOUNDRY_CAPTURE_FRAMEWORK_UI"] == "1"))
    func captureNativeSectionsAtRepresentativeWindowSizes() async throws {
        let output = URL(fileURLWithPath: "/tmp/FoundryFrameworkEditorQA", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let sections: [ThemeWindowSection] = [
            .colors, .foreground, .background, .borders, .links, .screens, .fontFamily, .extensions
        ].filter {
            let requested = ProcessInfo.processInfo.environment["FOUNDRY_FRAMEWORK_UI_SECTION"]
            return requested == nil || $0.rawValue == requested
        }
        let sizes: [(name: String, size: CGSize)] = [
            // 962 pt outer width minus the widest supported 240 pt sidebar.
            ("minimum", CGSize(width: 722, height: 504)),
            ("default", CGSize(width: 938, height: 620)),
            ("wide", CGSize(width: 1_590, height: 620))
        ]
        var measurements: [String] = []

        for section in sections {
            let variants = section == .fontFamily ? ["", "-google", "-google-variable", "-uploaded"] : [""]
            for variant in variants {
                let document = FoundryDocument(site: fixtureSite())
                if variant.hasPrefix("-google") {
                    document.site.theme.typography.bodyFont = .init(
                        family: "ABeeZee",
                        fallbacks: ["sans-serif"],
                        source: .remote(stylesheetURL: URL(string: "https://fonts.googleapis.com/css2?family=ABeeZee&display=swap")!),
                        weights: [400],
                        styles: [.normal]
                    )
                    let variable = variant == "-google-variable"
                    let faces = [false, true].map { GoogleFontFace(italic: $0, minimum: variable ? 100 : 400, maximum: variable ? 900 : 400) }
                    if variable { document.site.theme.typography.bodyFont.family = "Roboto" }
                    document.site.theme.typography.bodyFont.applyGoogleConfiguration(.init(available: faces, included: faces))
                }
                if variant == "-uploaded" {
                    let data = try Data(contentsOf: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf"))
                    let id = document.importAsset(data: data, filename: "Arial.ttf", mediaType: "font/ttf", undoManager: nil)
                    ProjectEditor(document: document, undoManager: nil).setThemeFontResources(["foundry-asset:\(id.uuidString)"], reference: .role(.body))
                }
                let originalTheme = document.site.theme
                let session = ThemeEditorSession(document: document, undoManager: UndoManager())
                for configuration in sizes {
                    let name = "\(section.rawValue)\(variant)-\(configuration.name)"
                    let previewModel = ThemeColourPreviewModel()
                    previewModel.duplicate(PreviewColourPalette(stored: BootstrapColourCatalogue.palette(role: .primary, hue: "purple")))
                    let root = (section.colourKind != nil
                        ? AnyView(ThemeColoursPreview(model: previewModel, tokenEditor: session.editor, theme: document.site.theme, kind: section.colourKind ?? .theme, mode: .constant(.light)))
                        : AnyView(ThemeSettingsDetail(
                        section: section,
                        theme: document.site.theme,
                        assets: document.site.assets,
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

    private func fixtureSite() -> Site {
        var theme = Theme.standard
        theme.typography.customFontSizes = [
            .init(id: "user-layout-card-title", title: "Card title", size: 1.375, lineHeight: 1.25)
        ]
        theme.spacing = .standard
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
        // Prefer the main editor scroller, not the font sidebar or catalogue.
        let candidates = (view as? NSScrollView).map { [$0] } ?? []
        return (candidates + view.subviews.compactMap { firstScrollView(in: $0) })
            .max { $0.bounds.width < $1.bounds.width }
    }

    private func capture(_ view: NSView, to url: URL) throws {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        try data.write(to: url, options: .atomic)
    }
}
