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
    func testWideningCanvasScalesItWithoutPushingAdjacentPanels() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-foundry.workspace.layout.v1", "ui-test-canvas-scaling"
        ]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let resizeHandle = app.descendants(matching: .any)["canvas-resize-right"]
        let inspector = app.staticTexts["Inspector"]

        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        let initialHandleValue = try XCTUnwrap(resizeHandle.value as? String)
        let initialViewport = try metric("viewport", from: initialHandleValue)
        let initialScale = try metric("scale", from: initialHandleValue)
        let initialInspectorFrame = inspector.frame
        XCTAssertEqual(initialScale, 100)

        resizeHandle.click()
        for _ in 0..<12 {
            app.typeKey(.rightArrow, modifierFlags: [])
        }

        let viewportChanged = NSPredicate(format: "value != %@", initialHandleValue)
        expectation(for: viewportChanged, evaluatedWith: resizeHandle)
        waitForExpectations(timeout: 5)

        let resizedHandleValue = try XCTUnwrap(resizeHandle.value as? String)
        let resizedViewport = try metric("viewport", from: resizedHandleValue)
        let reducedScale = try metric("scale", from: resizedHandleValue)
        XCTAssertGreaterThan(resizedViewport, initialViewport)
        XCTAssertLessThan(reducedScale, initialScale)
        XCTAssertEqual(inspector.frame.minX, initialInspectorFrame.minX, accuracy: 2)
        XCTAssertEqual(inspector.frame.width, initialInspectorFrame.width, accuracy: 2)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func metric(_ name: String, from value: String) throws -> Int {
        let pair = value.split(separator: ";").first { $0.hasPrefix("\(name)=") }
        let rawValue = pair?.split(separator: "=", maxSplits: 1).last
        return try XCTUnwrap(rawValue.flatMap { Int($0) }, "Expected \(name) in \(value)")
    }
}
