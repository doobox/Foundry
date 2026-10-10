import Foundation
import CryptoKit

/// Resolves Bootstrap background classes, selected-layer CSS and decorative
/// video markup. An untouched background adds no classes or stylesheet.
nonisolated enum PartPackageBackgroundResolver {
    static func resolve(
        _ values: inout [String: PartPackageValue],
        properties: [PartPackageProperty],
        enablesEditorMarkup: Bool,
        instanceID: UUID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    ) {
        for members in PartPackageControlGroupCSSResolver.groups(in: properties).values {
            guard let source = members.first?.controlGroupSource, source.type == .background else { continue }
            var local = PartPackageControlGroupCSSResolver.localValues(values, members: members)
            // Each image's focal point lives under its own derived key, outside
            // the group's namespace, so hand it to the layer as a CSS position.
            for member in members {
                guard let localID = member.controlGroupSource?.localID,
                      localID == "backgroundImage" || localID == "backgroundHoverImage" else { continue }
                local[localID + "FocalPoint"] = .string(focalPosition(values[PartPackageAdapter.imageFocalPointKey(for: member.id).rawValue]))
            }
            let rawColour = string(local["backgroundColor"]) ?? ""
            let variant = string(local["backgroundColorVariant"]) ?? "bg"
            for member in members where member.control.type == .themeColor {
                guard let id = member.controlGroupSource?.localID,
                      let selected = string(local[id]), selected.hasPrefix("theme-") || PartColourToken.parse(selected) != nil else { continue }
                let role = string(local[id + "Variant"]) ?? "bg"
                local[id] = .string(BootstrapBackgroundColour.paint(selected, role: role, opacity: number(local[id + "Opacity"]) ?? 100))
            }
            resolveLayerValues(&local, enablesEditorMarkup: enablesEditorMarkup)
            let mode = string(local["backgroundMode"]) ?? "none"
            let style = string(local["backgroundStyle"]) ?? "color"
            var classes = ""
            var stylesheet = ""
            if mode != "none" {
                let name = "background--" + SHA256.hash(data: Data((instanceID.uuidString + source.namespace).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
                let selector = "." + name
                classes = name
                let css = string(local["background.css"]) ?? ""
                let opacity = number(local["backgroundColorOpacity"]) ?? 100
                if mode == "static", style == "color", rawColour.hasPrefix("theme-"),
                   rawColour != "theme-reset", opacity.isFinite, (0...100).contains(opacity), opacity.truncatingRemainder(dividingBy: 10) == 0 {
                    classes = variant == "transparent" || opacity == 0 ? "bg-transparent" : variant + "-" + rawColour.dropFirst(6)
                    if opacity > 0, opacity < 100, variant != "transparent" { classes += " bg-\(Int(opacity))" }
                } else {
                    stylesheet = selector + "{\(css)}"
                    if mode == "hover" {
                        let trigger = string(local["hoverTrigger"]) ?? "self"
                        var hover = selector + ":hover"
                        if trigger == "parent" { hover = ":where(*:hover) > " + selector }
                        if trigger == "custom", let id = PartAnchorValidator.validated(string(local["hoverTriggerID"])) { hover = "body:has(#\(id):hover) " + selector }
                        stylesheet += hover + "{\(string(local["background.hover.css"]) ?? "")}"
                    }
                    if style == "video" {
                        classes += " position-relative"
                        stylesheet += selector + "{isolation:isolate}" + selector + " > .background-layer{position:absolute;inset:0;z-index:-1;overflow:hidden;border-radius:inherit;pointer-events:none}"
                        stylesheet += selector + " > .background-layer > :is(img,video){width:100%;height:100%;object-fit:cover}"
                        stylesheet += selector + " > .background-layer::after{content:\"\";position:absolute;inset:0;background:var(--background-overlay,transparent)}"
                    }
                    stylesheet = "@layer utilities{" + stylesheet + "}"
                }
            }
            local["background.classes"] = .string(classes)
            local["background.stylesheet"] = .string(stylesheet)
            for (key, value) in local where key.hasPrefix("background.") {
                guard case .string(let output) = value else { continue }
                PartPackageControlGroupCSSResolver.insertRaw(output, at: source.namespace + key.dropFirst("background".count), into: &values)
            }
        }
    }

    static func stylesheet(_ values: [String: PartPackageValue]) -> String {
        values.keys.sorted().filter { $0.hasSuffix(".stylesheet") }.compactMap { string(values[$0]) }.joined(separator: "\n")
    }

    private static func resolveLayerValues(_ values: inout [String: PartPackageValue], enablesEditorMarkup: Bool) {
        let mode = string(values["backgroundMode"]) ?? "none"
        let normalStyle = string(values["backgroundStyle"]) ?? "color"
        let hoverStyle = string(values["backgroundHoverStyle"]) ?? "none"
        let hasMedia = ["image", "video"].contains(normalStyle)
            || (mode == "hover" && hoverStyle == "image")
        let overlay = hasMedia ? overlayColor(values: values) : nil
        let staticLayer = mode == "none"
            ? Layer.empty
            : layer(prefix: "background", style: normalStyle, overlay: overlay,
                    isHover: false, values: values, enablesEditorMarkup: enablesEditorMarkup)

        // Hover mirrors the static layer unless the part is in hover mode with
        // a hover style chosen, so `:hover` rules are safe to write blindly.
        var hoverLayer = mode == "hover" && hoverStyle != "none"
            ? layer(prefix: "backgroundHover", style: hoverStyle, overlay: overlay,
                    isHover: true, values: values, enablesEditorMarkup: enablesEditorMarkup)
            : staticLayer
        // Hover supports colour, image, and gradient only. It may mirror the
        // static layer's CSS appearance, but never its video markup.
        hoverLayer.video = ""

        staticLayer.insert(prefix: "background", into: &values)
        hoverLayer.insert(prefix: "background.hover", into: &values)
    }

    private struct Layer {
        var color = "transparent"
        var image = "none"
        var position = "center"
        var size = "cover"
        var repeatValue = "no-repeat"
        var video = ""
        var videoOverlay: String?

        static let empty = Layer()

        /// Every declaration the layer needs, ready to drop into a rule so a
        /// part can take the whole background in one interpolation.
        var css: String {
            var declarations = [
                "background-color: \(color);",
                "background-image: \(image);",
                "background-position: \(position);",
                "background-size: \(size);",
                "background-repeat: \(repeatValue);"
            ]
            if let videoOverlay {
                declarations.append("--background-overlay: \(videoOverlay);")
            }
            return declarations.joined(separator: " ")
        }

        func insert(prefix: String, into values: inout [String: PartPackageValue]) {
            values[prefix + ".css"] = .string(css)
            values[prefix + ".color"] = .string(color)
            values[prefix + ".image"] = .string(image)
            values[prefix + ".position"] = .string(position)
            values[prefix + ".size"] = .string(size)
            values[prefix + ".repeat"] = .string(repeatValue)
            values[prefix + ".video"] = .string(video)
        }
    }

    private static func layer(
        prefix: String,
        style: String,
        overlay: String?,
        isHover: Bool,
        values: [String: PartPackageValue],
        enablesEditorMarkup: Bool
    ) -> Layer {
        var layer = Layer()
        switch style {
        case "color":
            layer.color = string(values[prefix + "Color"]) ?? "transparent"
        case "image":
            let source = string(values[prefix + "Image"]) ?? ""
            layer.image = source.isEmpty ? "none" : "url(\"\(escapeCSSURL(source))\")"
            layer.position = string(values[prefix + "ImageFocalPoint"]) ?? "50% 50%"
            layer.size = string(values[prefix + "Size"]) ?? "cover"
            layer.repeatValue = string(values[prefix + "Repeat"]) ?? "no-repeat"
        case "gradient":
            layer.image = gradient(prefix: prefix, values: values)
        case "video":
            layer.videoOverlay = overlay ?? "transparent"
            layer.video = videoElement(
                prefix: prefix,
                isHover: isHover,
                values: values,
                enablesEditorMarkup: enablesEditorMarkup
            )
        default:
            break
        }
        // The overlay belongs to the whole background, not either hover state.
        // Keep its paint unchanged even when the other state is colour or gradient.
        if style != "video", let overlay {
            layer.image = "linear-gradient(\(overlay), \(overlay)), " + layer.image
            layer.position = "center, " + layer.position
            layer.size = "100% 100%, " + layer.size
            layer.repeatValue = "no-repeat, " + layer.repeatValue
        }
        return layer
    }

    private static func overlayColor(values: [String: PartPackageValue]) -> String? {
        guard boolean(values["backgroundOverlayEnabled"]) == true else { return nil }
        return string(values["backgroundOverlayColor"]) ?? BootstrapBackgroundColour.paint("token:black", opacity: 20)
    }

    private static func gradient(prefix: String, values: [String: PartPackageValue]) -> String {
        let from = string(values[prefix + "GradientFrom"]) ?? "transparent"
        let to = string(values[prefix + "GradientTo"]) ?? "transparent"
        let fromPosition = number(values[prefix + "GradientFromPosition"]) ?? 0
        let toPosition = number(values[prefix + "GradientToPosition"]) ?? 100
        let stops = "\(from) \(percentage(fromPosition)), \(to) \(percentage(toPosition))"
        switch string(values[prefix + "GradientType"]) ?? "linear" {
        case "radial": return "radial-gradient(\(stops))"
        case "conic": return "conic-gradient(\(stops))"
        default:
            let direction = string(values[prefix + "GradientDirection"]) ?? "to bottom"
            return "linear-gradient(\(direction), \(stops))"
        }
    }

    private static func videoElement(
        prefix: String,
        isHover: Bool,
        values: [String: PartPackageValue],
        enablesEditorMarkup: Bool
    ) -> String {
        let poster = string(values[prefix + "Video.poster"]) ?? ""
        let href = string(values[prefix + "Video.href"]) ?? ""
        guard !poster.isEmpty || !href.isEmpty else { return "" }
        let classes = "background-video"
        let media: String
        // The canvas never loads the movie: a poster still stands in for it.
        if enablesEditorMarkup || href.isEmpty {
            guard !poster.isEmpty else { return "" }
            media = #"<img class="\#(classes)" src="\#(escapeAttribute(poster))" alt="" aria-hidden="true">"#
        } else {
            let posterAttribute = poster.isEmpty ? "" : #" poster="\#(escapeAttribute(poster))""#
            let loops = boolean(values[prefix + "VideoLoop"]) ?? true
            let loopAttribute = loops ? " loop" : ""
            media = #"<video class="\#(classes)" src="\#(escapeAttribute(href))"\#(posterAttribute) muted\#(loopAttribute) playsinline preload="none" tabindex="-1" aria-hidden="true"></video>"#
        }
        // Only this decorative layer clips. Its positioned, isolated host is
        // an explicit part-template requirement, not a side effect of .css.
        return #"<div class="background-layer" aria-hidden="true">\#(media)</div>"#
    }

    private static func percentage(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3))) + "%"
    }

    /// A stored focal point, `[x, y]` in percent, as a CSS position. Like
    /// `object-position`, it lines the same point of image and box up.
    private static func focalPosition(_ value: PartPackageValue?) -> String {
        guard case .array(let coordinates)? = value, coordinates.count == 2,
              case .number(let x) = coordinates[0], case .number(let y) = coordinates[1] else { return "50% 50%" }
        func percent(_ number: Double) -> String {
            let clamped = min(max(number, 0), 100)
            return clamped == clamped.rounded() ? "\(Int(clamped))%" : "\(clamped)%"
        }
        return "\(percent(x)) \(percent(y))"
    }

    private static func string(_ value: PartPackageValue?) -> String? {
        guard case .string(let value)? = value else { return nil }
        return value
    }

    private static func number(_ value: PartPackageValue?) -> Double? {
        guard case .number(let value)? = value else { return nil }
        return value
    }

    private static func boolean(_ value: PartPackageValue?) -> Bool? {
        guard case .boolean(let value)? = value else { return nil }
        return value
    }

    /// The composed `url("…")` lands in a stylesheet unescaped, so angle
    /// brackets go too: nothing a path carries may close a `<style>` element.
    private static func escapeCSSURL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "<", with: "%3C")
            .replacingOccurrences(of: ">", with: "%3E")
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
