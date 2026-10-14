struct AdaptiveColourPreview {
    let light: String
    let dark: String

    init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }

    init(solid: String) {
        light = solid
        dark = solid
    }
}
