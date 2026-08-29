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

        let pagesTab = app.buttons["Pages"]
        XCTAssertTrue(pagesTab.waitForExistence(timeout: 5))
        pagesTab.click()

        let addMenu = app.menuButtons["Add"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.click()

        let newPage = app.menuItems["New Page"]
        XCTAssertTrue(newPage.waitForExistence(timeout: 5))
        newPage.click()

        XCTAssertTrue(app.staticTexts["Page 2"].waitForExistence(timeout: 5))

        let componentsTab = app.buttons["Components"]
        XCTAssertTrue(componentsTab.waitForExistence(timeout: 5))
        componentsTab.click()

        let paragraph = app.descendants(matching: .any)["component-library-foundry.content.paragraph"]
        XCTAssertTrue(paragraph.waitForExistence(timeout: 5))
        paragraph.rightClick()

        let addToPageEnd = app.menuItems["Add to Page End"]
        XCTAssertTrue(addToPageEnd.waitForExistence(timeout: 5))
        addToPageEnd.click()

        XCTAssertTrue(app.staticTexts["Paragraph"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
