import AppKit
import Testing
@testable import Foundry

struct PartIconGroupTests {
    @Test @MainActor func allGroupsUseTheirAssignedPalette() throws {
        let groups: [(String, NSColor)] = [
            ("Accessibility", .systemTeal), ("Animation", .systemPink),
            ("CMS", .systemIndigo), ("Content", .systemBlue),
            ("Dynamic", .systemPurple), ("Ecommerce", .systemGreen),
            ("Forms", .systemCyan), ("Interactive", .systemOrange),
            ("Layout", .systemGray), ("Media", .systemMint),
            ("Navigation", .systemBlue), ("Security", .systemRed),
            ("SEO", .systemBrown), ("Utility", .systemPurple),
            ("Other", .systemGray), ("Unknown", .systemGray)
        ]
        for (group, expected) in groups {
            let icon = PartIconSpecification(glyph: .symbol("star.fill"), group: group)
            #expect(icon.rowImage().tint == expected, "\(group)")
            for mode in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = try #require(NSAppearance(named: mode))
                var base: NSColor?
                var background: NSColor?
                var foreground: NSColor?
                appearance.performAsCurrentDrawingAppearance {
                    base = expected.usingColorSpace(.sRGB)
                    background = icon.tileBackgroundColour.usingColorSpace(.sRGB)
                    foreground = icon.tileForegroundColour.usingColorSpace(.sRGB)
                }
                let baseRGB = try #require(base)
                let bg = try #require(background)
                let fg = try #require(foreground)
                let dark = mode == .darkAqua
                let addition: CGFloat = dark ? 0 : 0.25
                #expect(abs(bg.redComponent - (baseRGB.redComponent * 0.75 + addition)) < 0.001)
                #expect(abs(bg.greenComponent - (baseRGB.greenComponent * 0.75 + addition)) < 0.001)
                #expect(abs(bg.blueComponent - (baseRGB.blueComponent * 0.75 + addition)) < 0.001)
                #expect(fg.redComponent == 1)
                #expect(fg.greenComponent == fg.redComponent)
                #expect(fg.blueComponent == fg.redComponent)
            }
        }
    }

    @Test @MainActor func colouredSVGIsMonochromeAndKeepsPadding() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "group-icon-\(UUID()).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" fill="red"/></svg>"#.utf8).write(to: url)
        _ = await PartIconLoader.shared.icon(at: url)
        let icon = PartIconSpecification(glyph: .svg(url), group: "Media")
        let row = try #require(icon.rowImage().image)
        #expect(row.isTemplate)
        #expect(row.size == NSSize(width: 18, height: 18))
        #expect(icon.rowImage().tint == NSColor.systemMint)
        for mode in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: mode))
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            appearance.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                icon.tileImage(size: NSSize(width: 100, height: 100)).draw(in: NSRect(x: 0, y: 0, width: 100, height: 100))
                NSGraphicsContext.restoreGraphicsState()
            }
            let centre = try #require(bitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB))
            let outside = try #require(bitmap.colorAt(x: 22, y: 50)?.usingColorSpace(.sRGB))
            let inside = try #require(bitmap.colorAt(x: 27, y: 50)?.usingColorSpace(.sRGB))
            let expected: CGFloat = 1
            #expect(abs(centre.redComponent - expected) < 0.02)
            #expect(abs(centre.greenComponent - expected) < 0.02)
            #expect(abs(centre.blueComponent - expected) < 0.02)
            #expect(abs(inside.redComponent - expected) < 0.02)
            #expect(abs(outside.redComponent - expected) > 0.05)
        }
        #expect(icon.cacheKey != PartIconSpecification(glyph: .svg(url), group: "Content").cacheKey)
    }

    @Test func iconEncodingContainsOnlyGlyphFields() throws {
        let data = Data(#"{"file":"icon.svg","background":"red","foreground":"white","rendering":"original","structure":"blue"}"#.utf8)
        let icon = try JSONDecoder().decode(PartPackageIcon.self, from: data)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(icon)) as? [String: String])
        #expect(object == ["file": "icon.svg"])
    }
}
