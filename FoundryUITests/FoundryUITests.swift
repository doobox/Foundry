import XCTest

final class FoundryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreatesDocumentAddsPageAndPart() async throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-foundry.workspace.layout.v1", "ui-test-standard-layout"
        ]
        app.launch()
        // ⌘N opens the project chooser; ⌥⌘N is the direct blank document.
        app.typeKey("n", modifierFlags: [.command, .option])

        let pagesTab = app.buttons["Pages"]
        await assertExists(pagesTab)
        pagesTab.click()

        let addMenu = app.menuButtons["Add Page or Folder"]
        await assertExists(addMenu)
        addMenu.click()

        let newPage = app.menuItems["New Page"]
        await assertExists(newPage)
        newPage.click()

        await assertExists(app.descendants(matching: .any)["Page 2"])

        let partsTab = app.buttons["Parts"]
        await assertExists(partsTab)
        partsTab.click()

        let paragraph = app.descendants(matching: .any)["part-library-foundry.content.paragraph"]
        await assertExists(paragraph)
        paragraph.rightClick()

        let addToPageEnd = app.menuItems["Add to Page End"]
        await assertExists(addToPageEnd)
        addToPageEnd.click()

        await assertExists(app.descendants(matching: .any)["Paragraph"])
    }

    @MainActor
    private func assertExists(_ element: XCUIElement, timeout: TimeInterval = 5) async {
        let exists = expectation(
            for: NSPredicate(format: "exists == true"),
            evaluatedWith: element
        )
        await fulfillment(of: [exists], timeout: timeout)
    }

}
