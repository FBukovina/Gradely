import XCTest

final class PrivacyPolicyUpdateUITests: XCTestCase {
    private var signedInArguments: [String] {
        ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-settings.appLanguage", "english"]
    }

    @MainActor
    func testPolicyUpdateBlocksTheAppUntilTheSummaryIsScrolledThrough() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = signedInArguments + ["-uiTestingShowPrivacyUpdate"]
        app.launch()

        let sheet = app.descendants(matching: .any)["privacyPolicyUpdateView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))

        // The app itself must not be reachable behind the sheet.
        XCTAssertFalse(app.tabBars.buttons.element(boundBy: 0).isHittable)

        let accept = app.buttons["privacyPolicyUpdateAcceptButton"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        XCTAssertFalse(accept.isEnabled, "Accept must stay disabled until the summary has been read")

        let scrollView = app.scrollViews["privacyPolicyUpdateScrollView"]
        XCTAssertTrue(scrollView.exists)
        for _ in 0..<12 where !accept.isEnabled {
            scrollView.swipeUp()
        }
        XCTAssertTrue(accept.isEnabled, "Reaching the end of the summary should unlock Accept")

        accept.tap()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 10))
        XCTAssertFalse(sheet.exists)
    }

    @MainActor
    func testExpandingAChangeRowRevealsItsDetail() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = signedInArguments + ["-uiTestingShowPrivacyUpdate"]
        app.launch()

        let row = app.descendants(matching: .any)["privacyPolicyUpdateRow-password"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        let detail = app.descendants(matching: .any)["privacyPolicyUpdateDetail-password"]
        XCTAssertFalse(detail.exists)

        row.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAcceptedPolicyDoesNotPromptAgain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = signedInArguments
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["privacyPolicyUpdateView"].exists)
    }

    @MainActor
    func testSettingsOffersTheChangeSummaryAfterAcceptance() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = signedInArguments
        app.launch()

        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 10))
        app.buttons["openAccountHubButton"].firstMatch.tap()

        let overview = app.descendants(matching: .any)["accountHubScroll"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        let privacyRow = app.descendants(matching: .any)["settingsDestination-privacyData"]
        for _ in 0..<8 where !privacyRow.isHittable {
            overview.swipeUp()
        }
        XCTAssertTrue(privacyRow.waitForExistence(timeout: 5))
        privacyRow.tap()

        let detail = app.descendants(matching: .any)["settingsDetail-privacyData"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))

        let changesLink = app.descendants(matching: .any)["privacyChangesLink"]
        for _ in 0..<6 where !changesLink.isHittable {
            detail.swipeUp()
        }
        XCTAssertTrue(changesLink.waitForExistence(timeout: 5))
        changesLink.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["privacyPolicyUpdateView"].waitForExistence(timeout: 5)
        )
        // Review mode is read-only: no acceptance gate.
        XCTAssertFalse(app.buttons["privacyPolicyUpdateAcceptButton"].exists)
    }
}
