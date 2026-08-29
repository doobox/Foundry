import Testing
@testable import Foundry

struct AppPreferencesTests {
    @Test
    func previewDefaultsToTheUsersDefaultBrowser() {
        #expect(PreviewApplicationSelection.systemDefault == "defaultBrowser")
    }

    @Test
    func preferenceKeyRemainsStableAcrossThePickerUpgrade() {
        #expect(AppPreferenceKey.previewApplication == "preview.destination")
    }
}
