import XCTest

final class FoundryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreatesDocumentAddsPageAndComponent() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-foundry.workspace.layout.v1", "ui-test-standard-layout"
        ]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let addPageButton = app.buttons["Add Page"]
        XCTAssertTrue(addPageButton.waitForExistence(timeout: 5))
        addPageButton.click()

        XCTAssertTrue(app.staticTexts["Page 2"].waitForExistence(timeout: 5))

        let componentsTab = app.buttons["Components"]
        XCTAssertTrue(componentsTab.waitForExistence(timeout: 5))
        componentsTab.click()

        let container = app.descendants(matching: .any)["component-library-foundry.layout.container"]
        XCTAssertTrue(container.waitForExistence(timeout: 5))
        container.rightClick()

        let addToPageEnd = app.menuItems["Add to Page End"]
        XCTAssertTrue(addToPageEnd.waitForExistence(timeout: 5))
        addToPageEnd.click()

        XCTAssertTrue(app.staticTexts["Container"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
