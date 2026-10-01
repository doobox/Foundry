import Testing
@testable import Foundry

struct PartBackgroundInspectorContextTests {
    private let choices: [PartPropertyChoice] = [
        .init(value: "color", label: "Colour"),
        .init(value: "image", label: "Image"),
        .init(value: "gradient", label: "Gradient"),
        .init(value: "video", label: "Video")
    ]

    @Test(arguments: ["background", "heroSurface"], ["backgroundStyle", "backgroundHoverStyle"])
    func hoverNeverOffersVideo(namespace: String, localID: String) throws {
        let group = PartPackageControlGroup(type: .background, id: namespace, backgroundTypes: [.colour, .image, .gradient, .video])
        let context = try #require(PartBackgroundInspectorContext(property: group.properties.first { $0.id == namespace + "." + localID }))
        #expect(context.modeKey.rawValue == namespace + ".backgroundMode")
        #expect(context.choices(choices, mode: "hover").map(\.value) == ["color", "image", "gradient"])
        #expect(context.choices(choices, mode: "static").map(\.value) == choices.map(\.value))
    }

    @Test(arguments: ["background", "heroSurface"])
    func switchingToHoverReplacesVideoWithinTheSameGroup(namespace: String) throws {
        let group = PartPackageControlGroup(type: .background, id: namespace, backgroundTypes: [.image, .video])
        let context = try #require(PartBackgroundInspectorContext(property: group.properties.first { $0.id == namespace + ".backgroundMode" }))
        let permittedChoices = choices.filter { ["image", "video"].contains($0.value) }
        #expect(context.styleKey.rawValue == namespace + ".backgroundStyle")
        #expect(context.replacementStyle(newMode: "hover", currentStyle: "video", choices: permittedChoices) == "image")
        #expect(context.replacementStyle(newMode: "hover", currentStyle: "image", choices: permittedChoices) == nil)
        #expect(context.replacementStyle(newMode: "static", currentStyle: "video", choices: permittedChoices) == nil)
    }

    @Test func otherControlsAreNotTreatedAsBackgroundStyles() throws {
        let group = PartPackageControlGroup(type: .background, id: "surface")
        let context = try #require(PartBackgroundInspectorContext(property: group.properties.first { $0.id == "surface.backgroundMode" }))
        #expect(context.choices(choices, mode: "hover").map(\.value) == choices.map(\.value))
        #expect(PartBackgroundInspectorContext(property: nil) == nil)
    }
}
