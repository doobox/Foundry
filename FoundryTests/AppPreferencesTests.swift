import Testing
@testable import Foundry

struct AppPreferencesTests {
    @Test
    func previewDefaultsToTheUsersDefaultBrowser() {
        #expect(PreviewApplicationSelection.systemDefault == "systemDefault")
    }
}
