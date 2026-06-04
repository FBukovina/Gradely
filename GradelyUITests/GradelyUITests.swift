import XCTest

final class GradelyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMockLoginSubjectsDetailAndCalculatorFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI"]
        app.launch()

        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        app.textFields["schoolURLField"].tap()
        app.textFields["schoolURLField"].typeText("demo.bakalari.cz")

        app.textFields["usernameField"].tap()
        app.textFields["usernameField"].typeText("student")

        let passwordField = app.secureTextFields["passwordField"].exists
            ? app.secureTextFields["passwordField"]
            : app.textFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("secret")

        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["subjectRow-math"].exists)

        app.descendants(matching: .any)["subjectRow-math"].tap()

        XCTAssertTrue(app.textFields["theoreticalMarkField"].waitForExistence(timeout: 5))
        app.textFields["theoreticalMarkField"].tap()
        app.textFields["theoreticalMarkField"].typeText("3")

        XCTAssertTrue(app.descendants(matching: .any)["theoreticalResultPanel"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testMockLaunchWithSavedSessionShowsSubjects() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["subjectRow-math"].exists)
    }

    @MainActor
    func testTimetableTabShowsWeekAndNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        // Starts on the Marks tab.
        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))

        // Switch to the Timetable tab (second tab).
        app.tabBars.buttons.element(boundBy: 1).tap()

        XCTAssertTrue(app.scrollViews["timetableList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["weekNext"].exists)
        XCTAssertTrue(app.buttons["dayChip-1"].exists)

        // Moving off the current week reveals the "Today" shortcut; tapping it returns.
        app.buttons["weekNext"].tap()
        XCTAssertTrue(app.buttons["weekToday"].waitForExistence(timeout: 5))
        app.buttons["weekToday"].tap()
        XCTAssertTrue(app.scrollViews["timetableList"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTestingMockAPI"]
            app.launch()
        }
    }
}
