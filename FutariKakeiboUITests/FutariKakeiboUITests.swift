import XCTest

@MainActor
final class FutariKakeiboUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingAddExpenseAndPersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-data-for-ui-tests"]
        app.launch()

        let startButton = app.buttons["onboarding.start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        XCTAssertTrue(app.navigationBars["ふたりのホーム"].waitForExistence(timeout: 10))

        app.tabBars.buttons["追加"].tap()
        XCTAssertTrue(app.navigationBars["支出を追加"].waitForExistence(timeout: 5))

        let titleField = app.textFields["expense.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("スーパーで食材")

        let amountField = app.textFields["expense.amount"]
        amountField.tap()
        amountField.typeText("1234")

        let keyboardDoneButton = app.keyboards.buttons["完了"]
        if keyboardDoneButton.waitForExistence(timeout: 2) {
            keyboardDoneButton.tap()
        }

        let saveButton = app.buttons["expense.save"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(app.navigationBars["ふたりのホーム"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["スーパーで食材"].waitForExistence(timeout: 5))

        app.tabBars.buttons["履歴"].tap()
        XCTAssertTrue(app.navigationBars["支出履歴"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["スーパーで食材"].exists)

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.navigationBars["ふたりのホーム"].waitForExistence(timeout: 10))
        app.tabBars.buttons["履歴"].tap()
        XCTAssertTrue(app.staticTexts["スーパーで食材"].waitForExistence(timeout: 5))
    }
}
