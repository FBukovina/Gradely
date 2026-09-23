import CryptoKit
import XCTest

final class GradeySiriUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingMockAPI", "-uiTestingLoggedIn", "-uiTestingCachedMarks",
            "-uiTestingRequiresGradeyID", "-uiTestingResetGuestMode", "-settings.appLanguage", "english",
            "-onboarding.completed.v2", "YES", "-settings.siri.schoolDiscovery.v1", "NO"]
        return app
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor func testScopedSubjectURLColdLaunchAndRepeatedOpen() {
        let app = application()
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 15))
        app.terminate()
        let scope = hash("preview-gradey-user\u{1f}bakalari-demo-bakalari-cz-default")
        let url = URL(string: "gradey://siri/v1.subject.\(scope).\(hash("math"))")!
        app.open(url)
        XCTAssertTrue(app.navigationBars["Matematika"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.open(url)
        XCTAssertTrue(app.navigationBars["Matematika"].waitForExistence(timeout: 10))
        let foreign = URL(string: "gradey://siri/v1.subject.\(hash("another-account")).\(hash("math"))")!
        app.open(foreign)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor func testDiscoveryRequiresOptInAndCanBeDisabled() {
        let app = application()
        app.launch()
        XCTAssertTrue(app.scrollViews["todayScrollView"].waitForExistence(timeout: 15))
        let account = app.buttons["openAccountHubButton"].exists ? app.buttons["openAccountHubButton"] : app.buttons["accountMenuButton"]
        account.tap()
        let privacy = app.descendants(matching: .any)["settingsDestination-privacyData"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 10))
        for _ in 0..<6 where !privacy.isHittable { app.swipeUp() }
        privacy.tap()
        let toggle = app.switches["siriDiscoveryToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        let enable = app.buttons["Enable discovery"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        enable.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }
}
