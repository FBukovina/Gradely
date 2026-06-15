import XCTest

final class GradelyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMockLoginCanSelectSchoolFromDirectory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI"]
        app.launch()

        XCTAssertTrue(app.textFields["schoolSearchField"].waitForExistence(timeout: 5))
        app.textFields["schoolSearchField"].tap()
        app.textFields["schoolSearchField"].typeText("demo")

        let schoolResult = app.descendants(matching: .any)["schoolResult-demo"]
        XCTAssertTrue(schoolResult.waitForExistence(timeout: 5))
        schoolResult.tap()

        let schoolURLField = app.textFields["schoolURLField"]
        XCTAssertTrue(schoolURLField.waitForExistence(timeout: 2))
        XCTAssertEqual(schoolURLField.value as? String, "https://demo.bakalari.cz")

        app.textFields["usernameField"].tap()
        app.textFields["usernameField"].typeText("student")

        let passwordField = app.secureTextFields["passwordField"].exists
            ? app.secureTextFields["passwordField"]
            : app.textFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("secret")

        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))
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

        // Switch to the Timetable tab (third tab).
        app.tabBars.buttons.element(boundBy: 2).tap()

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
    func testSupportTipFlowUsesMockPurchase() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accountMenuButton"].waitForExistence(timeout: 5))
        app.buttons["accountMenuButton"].tap()

        let supportButton = app.buttons["supportGradelyButton"].waitForExistence(timeout: 3)
            ? app.buttons["supportGradelyButton"]
            : app.buttons["Support Gradey"]
        XCTAssertTrue(supportButton.waitForExistence(timeout: 3))
        supportButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["supportTipsList"].waitForExistence(timeout: 5))
        let smallTip = app.buttons["supportTip-tip_small"]
        let mediumTip = app.buttons["supportTip-tip_medium"]
        let largeTip = app.buttons["supportTip-tip_large"]

        XCTAssertTrue(smallTip.waitForExistence(timeout: 5))
        XCTAssertTrue(mediumTip.exists)
        XCTAssertTrue(largeTip.exists)

        smallTip.tap()

        XCTAssertTrue(app.descendants(matching: .any)["supportTipsThankYou"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStravaCZConnectOrderCancelAndGlobalLogoutClearsSession() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn"]
        app.launch()

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.descendants(matching: .any)["stravaCZConnectView"].waitForExistence(timeout: 5))

        app.textFields["stravaCZCanteenField"].tap()
        app.textFields["stravaCZCanteenField"].typeText("1234")

        app.textFields["stravaCZUsernameField"].tap()
        app.textFields["stravaCZUsernameField"].typeText("student")

        let passwordField = app.secureTextFields["stravaCZPasswordField"].exists
            ? app.secureTextFields["stravaCZPasswordField"]
            : app.textFields["stravaCZPasswordField"]
        passwordField.tap()
        passwordField.typeText("secret")

        app.buttons["stravaCZConnectButton"].tap()

        XCTAssertTrue(app.collectionViews["stravaCZMenuList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["stravaCZBalance"].waitForExistence(timeout: 5))

        let orderButton = app.descendants(matching: .any)["stravaCZOrderButton-1"]
        if !orderButton.waitForExistence(timeout: 2) {
            app.collectionViews["stravaCZMenuList"].swipeUp()
        }
        XCTAssertTrue(orderButton.waitForExistence(timeout: 5))
        orderButton.tap()

        let cancelButton = app.descendants(matching: .any)["stravaCZCancelButton-1"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["stravaCZOrderButton-1"].waitForExistence(timeout: 5))

        app.tabBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["accountMenuButton"].waitForExistence(timeout: 5))
        app.buttons["accountMenuButton"].tap()

        let logoutButton = app.buttons["logoutButton"].waitForExistence(timeout: 3)
            ? app.buttons["logoutButton"]
            : app.buttons["Log out"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 3))
        logoutButton.tap()

        XCTAssertTrue(app.textFields["schoolURLField"].waitForExistence(timeout: 5))
        app.buttons["demoAccountButton"].tap()
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.collectionViews["subjectsList"].waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.descendants(matching: .any)["stravaCZConnectView"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testVersionSupportPromptOpensSupportTips() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingShowSupportPrompt"]
        app.launch()

        let prompt = app.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))

        let supportButton = prompt.buttons["Support Gradey"].exists
            ? prompt.buttons["Support Gradey"]
            : prompt.buttons["Podpořit Gradey"]
        XCTAssertTrue(supportButton.exists)
        supportButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["supportTipsList"].waitForExistence(timeout: 5))
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
