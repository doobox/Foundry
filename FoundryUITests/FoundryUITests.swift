import XCTest

final class FoundryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // XCUI calls block while they talk to the app, so this stays a plain
    // synchronous test. Declaring it `@MainActor async` makes XCTest report
    // main-thread blocking and a QoS priority inversion on every run.
    func testCreatesDocumentAddsPageAndPart() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-foundry.workspace.layout.v1", "ui-test-standard-layout"
        ]
        app.launch()
        // ⌘N opens the project chooser; ⌥⌘N is the direct blank document.
        app.typeKey("n", modifierFlags: [.command, .option])

        let pagesTab = app.buttons["Pages"]
        assertExists(pagesTab)
        pagesTab.click()

        let addMenu = app.menuButtons["Add Page or Folder"]
        assertExists(addMenu)
        addMenu.click()

        let newPage = app.menuItems["New Page"]
        assertExists(newPage)
        newPage.click()

        assertExists(app.descendants(matching: .any)["Page 2"])

        let partsTab = app.buttons["Parts"]
        assertExists(partsTab)
        partsTab.click()

        let paragraph = app.descendants(matching: .any)["part-library-foundry.content.paragraph"]
        assertExists(paragraph)
        paragraph.rightClick()

        let addToPageEnd = app.menuItems["Add to Page End"]
        assertExists(addToPageEnd)
        addToPageEnd.click()

        assertExists(app.descendants(matching: .any)["Paragraph"])
    }

    private func assertExists(_ element: XCUIElement, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(element) did not appear within \(timeout)s", file: file, line: line)
    }
}
