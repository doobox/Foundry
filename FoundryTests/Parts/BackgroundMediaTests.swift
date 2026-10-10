import Foundation
import JavaScriptCore
import Testing
@testable import Foundry

struct BackgroundMediaTests {
    @Test(arguments: [false, true])
    func imageOnlyPartsRetainOverlayControls(hover: Bool) throws {
        let group = PartPackageControlGroup(type: .background, id: "surface", backgroundTypes: [.colour, .gradient, .image], supportsHover: hover)
        let overlay = try #require(group.properties.first { $0.id == "surface.backgroundOverlayEnabled" })
        #expect(PartPackageVisibilityEvaluator.isVisible(overlay.visibleWhen, values: [
            "surface.backgroundMode": .choice("static"), "surface.backgroundStyle": .choice("image")
        ]))
    }
    @Test(arguments: ["color", "gradient", "image"], [false, true])
    func overlayStaysConstantAcrossDifferentBackgroundStyles(otherStyle: String, imageOnHover: Bool) {
        let group = PartPackageControlGroup(type: .background, id: "surface")
        var values: [String: PartPackageValue] = [
            "surface.backgroundMode": .string("hover"),
            "surface.backgroundStyle": .string(imageOnHover ? otherStyle : "image"),
            "surface.backgroundHoverStyle": .string(imageOnHover ? "image" : otherStyle),
            "surface.backgroundOverlayEnabled": .boolean(true),
            "surface.backgroundOverlayColor": .string("#000000cc")
        ]
        PartPackageBackgroundResolver.resolve(&values, properties: group.properties, enablesEditorMarkup: false)
        let overlay = "linear-gradient(#000000cc, #000000cc), "
        #expect(values["surface.image"]?.stringValue.hasPrefix(overlay) == true)
        #expect(values["surface.hover.image"]?.stringValue.hasPrefix(overlay) == true)
    }

    @Test func overlayControlsAreSolidOnlyAndLimitedToMediaStyles() throws {
        let group = PartPackageControlGroup(type: .background, id: "surface", backgroundTypes: [.image, .video])
        let controls = group.properties
        let toggle = try #require(controls.first { $0.id == "surface.backgroundOverlayEnabled" })
        let color = try #require(controls.first { $0.id == "surface.backgroundOverlayColor" })
        #expect(toggle.defaultValue == .boolean(false))
        #expect(color.defaultValue == .string("token:black"))
        #expect(color.control.type == .themeColors)
        #expect(controls.first { $0.id == "surface.backgroundOverlayColorOpacity" }?.defaultValue == .number(20))
        #expect(controls.contains { $0.id.contains("OverlayGradient") } == false)
        #expect(controls.filter { $0.id.contains("Overlay") }.count == 3)
        #expect(controls.contains { $0.id.contains("HoverOverlay") } == false)
        for styles: [PartPackageControlGroup.BackgroundStyle] in [[.colour], [.gradient]] {
            let plain = PartPackageControlGroup(type: .background, id: "surface", backgroundTypes: styles)
            #expect(plain.properties.contains { $0.id.contains("Overlay") } == false)
            #expect(plain.javaScript.isEmpty)
        }
        let videoOnly = PartPackageControlGroup(type: .background, id: "surface", backgroundTypes: [.video])
        #expect(videoOnly.properties.contains { $0.id.contains("HoverOverlay") } == false)
        #expect(videoOnly.javaScript.contains("IntersectionObserver"))
    }

    @Test(arguments: [false, true], ["#00000033", "#ff000080"])
    func imageOverlayIsSharedAndPreservesImageSizing(enabled: Bool, color: String) {
        let group = PartPackageControlGroup(type: .background, id: "surface")
        var values: [String: PartPackageValue] = [
            "surface.backgroundMode": .string("hover"),
            "surface.backgroundStyle": .string("image"),
            "surface.backgroundImage": .string("assets/photo.jpg"),
            "surface.backgroundSize": .string("contain"),
            "surface.backgroundRepeat": .string("repeat-x"),
            "surface.backgroundOverlayEnabled": .boolean(enabled),
            "surface.backgroundOverlayColor": .string(color),
            "surface.backgroundHoverStyle": .string("image"),
            "surface.backgroundHoverImage": .string("assets/hover.jpg"),
            "surface.backgroundHoverSize": .string("auto"),
            "surface.backgroundHoverRepeat": .string("repeat-y"),
            PartPackageAdapter.imageFocalPointKey(for: "surface.backgroundHoverImage").rawValue: .array([.number(25), .number(75)])
        ]
        PartPackageBackgroundResolver.resolve(&values, properties: group.properties, enablesEditorMarkup: false)
        let tint = enabled ? "linear-gradient(\(color), \(color)), " : ""
        #expect(values["surface.image"] == .string(tint + #"url("assets/photo.jpg")"#))
        #expect(values["surface.size"] == .string(enabled ? "100% 100%, contain" : "contain"))
        #expect(values["surface.repeat"] == .string(enabled ? "no-repeat, repeat-x" : "repeat-x"))
        #expect(values["surface.hover.image"] == .string(tint + #"url("assets/hover.jpg")"#))
        #expect(values["surface.hover.size"] == .string(enabled ? "100% 100%, auto" : "auto"))
        #expect(values["surface.hover.repeat"] == .string(enabled ? "no-repeat, repeat-y" : "repeat-y"))
        #expect(values["surface.hover.position"] == .string(enabled ? "center, 25% 75%" : "25% 75%"))
    }

    @Test(arguments: [false, true], [false, true])
    func videoOverlayAppliesToMovieAndCanvasPoster(enabled: Bool, editor: Bool) {
        let group = PartPackageControlGroup(type: .background, id: "surface", backgroundTypes: [.video])
        var values: [String: PartPackageValue] = [
            "surface.backgroundMode": .string("static"),
            "surface.backgroundStyle": .string("video"),
            "surface.backgroundVideo.href": .string("assets/movie.mp4"),
            "surface.backgroundVideo.poster": .string("assets/poster.jpg"),
            "surface.backgroundOverlayEnabled": .boolean(enabled)
        ]
        PartPackageBackgroundResolver.resolve(&values, properties: group.properties, enablesEditorMarkup: editor)
        let color = enabled ? BootstrapBackgroundColour.paint("token:black", opacity: 20) : "transparent"
        #expect(values["surface.css"]?.stringValue.contains("--background-overlay: \(color);") == true)
        #expect(values["surface.video"]?.stringValue.contains(editor ? "<img " : "<video ") == true)
        #expect(values["surface.video"]?.stringValue.contains("background-layer") == true)
    }

    @Test @MainActor func playbackTracksVisibilityWithoutRestartingFinishedClips() throws {
        let context = try #require(JSContext())
        context.evaluateScript(#"""
        var window = this;
        var motionChanged;
        var motion = {matches:false, addEventListener(name, fn) {motionChanged=fn;}};
        function matchMedia() {return motion;}
        var callback, visibilityChanged, observed = 0, unobserved = 0;
        var video = {
          isConnected: true, ended: false, loop: true, currentTime: 12,
          plays: 0, pauses: 0, loads:0,
          load() { this.loads++; },
          pause() { this.pauses++; },
          play() { this.plays++; return { then(fn) { fn(); return { catch() {} }; } }; },
          closest() { return root; }
        };
        var childVideo = { closest() { return {}; } };
        var root = { querySelectorAll() { return [video, childVideo]; } };
        var document = {
          hidden: false, querySelectorAll() { return [video]; },
          addEventListener(name, fn) { visibilityChanged = fn; }
        };
        function IntersectionObserver(fn) {
          callback = fn;
          this.observe = () => observed++;
          this.unobserve = () => unobserved++;
        }
        function visibility(visible) {
          callback([{ target: video, isIntersecting: visible, intersectionRatio: visible ? 1 : 0 }]);
        }
        """#)
        context.evaluateScript(PartBackgroundVideoPlayback.javaScript)
        try #require(context.exception == nil)
        #expect(context.evaluateScript("video.pauses === 1 && video.plays === 0 && observed === 1")?.toBool() == true)
        context.evaluateScript("visibility(true)")
        #expect(context.evaluateScript("video.plays === 1")?.toBool() == true)
        context.evaluateScript("visibility(false)")
        #expect(context.evaluateScript("video.pauses === 2 && video.currentTime === 12")?.toBool() == true)
        context.evaluateScript("visibility(true); document.hidden = true; visibilityChanged()")
        #expect(context.evaluateScript("video.plays === 2 && video.pauses === 3")?.toBool() == true)
        context.evaluateScript("document.hidden = false; visibilityChanged()")
        #expect(context.evaluateScript("video.plays === 3")?.toBool() == true)
        context.evaluateScript("video.ended = true; video.loop = false; visibility(false); visibility(true)")
        #expect(context.evaluateScript("video.plays === 3")?.toBool() == true)
        context.evaluateScript(PartBackgroundVideoPlayback.javaScript)
        #expect(context.evaluateScript("observed === 1")?.toBool() == true)
        context.evaluateScript("video.isConnected = false; visibility(false)")
        #expect(context.evaluateScript("unobserved === 1")?.toBool() == true)
        context.evaluateScript(#"""
        video.isConnected = true;
        video.ended = false;
        var completePlay;
        video.play = () => ({ then(fn) { completePlay = fn; return { catch() {} }; } });
        """#)
        context.evaluateScript(PartBackgroundVideoPlayback.javaScript)
        context.evaluateScript("visibility(true); visibility(false); var beforeCompletion = video.pauses; completePlay()")
        #expect(context.evaluateScript("video.pauses === beforeCompletion + 1")?.toBool() == true)
        context.evaluateScript("motion.matches=true; motionChanged(); var playsBeforeMotion=video.plays; visibility(true)")
        #expect(context.evaluateScript("video.loads===1 && video.plays===playsBeforeMotion")?.toBool() == true)
        context.evaluateScript("delete window.IntersectionObserver")
        context.evaluateScript(PartBackgroundVideoPlayback.javaScript)
        #expect(context.evaluateScript("observed === 2")?.toBool() == true)
        #expect(context.exception == nil)
    }
}
